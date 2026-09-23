(* hwfuzz: coverage-guided fuzzing for any Hardcaml circuit.

   Hardware has no instruction pointer, so coverage cannot be control-flow edges as in AFL. The
   closest things to branches are data-dependent choices, and a Hardcaml circuit exposes them all
   in its signal graph. [instrument] walks the graph and taps, as extra outputs:
     - every multiplexer select and every comparison (lt, eq): the "decisions"
     - every register
   (RFUZZ, ICCAD 2018, used multiplexer selects as RTL coverage for the same reason.)

   Generic coverage, needing nothing but the circuit:
     D  per decision signal, 4-grams of its values, bucketed by relative frequency
     R  per register, how often it changes (log buckets); for registers of at most 8 bits, which
        values it takes (state machines: the state-aware coverage of AFLNet and SGFuzz)
     O  per output, how often it changes, and the period of its last 256 values
   Application-specific coverage comes from an optional observer (in the spirit of Hypothesis's
   target()), which sees the outputs every cycle and returns features at the end.

   Relative-frequency buckets, not AFL's raw hit counts: hardware produces millions of hits, and
   fine count buckets made every noisy run look new (measured on the crazy network).

   Input: a byte string. Byte 0 is a swarm mask (Hypothesis's swarm testing: port i is held at 0
   for the whole run if bit i is set). Then records: one hold byte, then the value bytes for every
   data input port. A record is applied for [hold] cycles: 1..4 for a hold byte below 192 (dense),
   2^(b land 15) otherwise (sparse, up to 32768). The run ends when the records do. *)
open Hardcaml

type observer = { observe : cycle:int -> (string -> int) -> unit; finish : unit -> int list }

type target = {
  name : string;
  circuit : unit -> Circuit.t;
  clock : string;
  clear : string option;
  max_cycles : int;
  observer : (unit -> observer) option;
}

type instrumented = {
  circuit : Circuit.t;
  dec_widths : int array;
  reg_widths : int array;
  cmp_widths : int array;
  data_ports : (string * int) list;   (* inputs other than clock and clear *)
  out_ports : (string * int) list;    (* the original outputs, at most 62 bits wide *)
}

let instrument (t : target) =
  let c = t.circuit () in
  let g = Circuit.signal_graph c in
  let seen = Hashtbl.create 1024 in
  let decs = ref [] and regs = ref [] and cmps = ref [] in
  let add_dec s =
    let u = Signal.uid s in
    let is_const = match s with Signal.Type.Const _ -> true | _ -> false in
    if not is_const && not (Hashtbl.mem seen u) then (Hashtbl.add seen u (); decs := s :: !decs) in
  Signal_graph.iter g ~f:(fun s ->
    match s with
    | Signal.Type.Mux { select; _ } -> add_dec select
    | Op2 { op = Signal_lt | Signal_eq; arg_a; arg_b; _ } ->
      add_dec s;
      (* CmpLog, as in AFL++: the operands of comparisons are the magic values inputs need *)
      if Signal.width arg_a <= 32 then cmps := arg_b :: arg_a :: !cmps
    | Reg _ -> regs := s :: !regs
    | _ -> ());
  let decs = List.rev !decs and regs = List.rev !regs and cmps = List.rev !cmps in
  let outs = Circuit.outputs c in
  let extra =
    (if decs = [] then [] else [ Signal.output "__dec" (Signal.concat_lsb decs) ])
    @ (if regs = [] then [] else [ Signal.output "__reg" (Signal.concat_lsb regs) ])
    @ if cmps = [] then [] else [ Signal.output "__cmp" (Signal.concat_lsb cmps) ] in
  let circuit = Circuit.create_exn ~name:(t.name ^ "_cov") (outs @ extra) in
  let data_ports =
    List.filter_map (fun s ->
      let n = List.hd (Signal.names s) in
      if n = t.clock || Some n = t.clear then None else Some (n, Signal.width s)) (Circuit.inputs c) in
  let out_ports = List.filter_map (fun s ->
    let n = List.hd (Signal.names s) in if Signal.width s <= 62 then Some (n, Signal.width s) else None) outs in
  { circuit; dec_widths = Array.of_list (List.map Signal.width decs);
    reg_widths = Array.of_list (List.map Signal.width regs);
    cmp_widths = Array.of_list (List.map Signal.width cmps); data_ports; out_ports }

(* read a field of [w] bits at [off] from an int64 array *)
let field (a : int64 array) off w =
  let v = ref 0 in
  for b = 0 to w - 1 do
    let i = off + b in
    if Int64.logand (Int64.shift_right_logical a.(i / 64) (i mod 64)) 1L = 1L then v := !v lor (1 lsl b)
  done; !v

let rel_bucket c total =
  let f = float c /. float (max 1 total) in if f < 0.01 then 0 else if f < 0.1 then 1 else if f < 0.25 then 2 else 3
let rate_bucket changes cycles =
  if changes = 0 then 0 else 1 + min 7 (int_of_float (Float.log2 (float cycles /. float changes)) / 2)

let record_bytes inst = 1 + List.fold_left (fun a (_, w) -> a + (w + 7) / 8) 0 inst.data_ports

type run_result = {
  features : int list; cycles : int; observed : int list;
  cmp_values : (int * int) list;
  i2s : (int * int * int) list;   (* input-to-state candidates: record, port index, value to write *)
}

let execute (t : target) inst (input : string) =
  let sim = Cyclesim.create inst.circuit in
  let inp n = Cyclesim.in_port sim n and out n = Cyclesim.out_port sim n in
  let ports = List.map (fun (n, w) -> (inp n, w)) inst.data_ports in
  let clear = Option.map inp t.clear in
  let dec = if Array.length inst.dec_widths > 0 then Some (out "__dec") else None in
  let reg = if Array.length inst.reg_widths > 0 then Some (out "__reg") else None in
  let outs = Array.of_list (List.map (fun (n, w) -> (n, out n, w)) inst.out_ports) in
  let nd = Array.length inst.dec_widths and nr = Array.length inst.reg_widths and no = Array.length outs in
  let dcnt = Array.make (nd * 16) 0 and dhist = Array.make nd 0 in
  let rchg = Array.make nr 0 and rprev = Array.make nr (-1) and rvals = Hashtbl.create 256 in
  let ochg = Array.make no 0 and oprev = Array.make no (-1) and oring = Array.make_matrix no 256 0 in
  let obs = Option.map (fun f -> f ()) t.observer in
  let cmp = if Array.length inst.cmp_widths > 0 then Some (out "__cmp") else None in
  let cvals = Hashtbl.create 64 and i2s = Hashtbl.create 64 in
  let cur_rec = ref (-1) and cur_vals = ref [||] in
  let mask = if String.length input > 0 then Char.code input.[0] else 0 in
  let rb = record_bytes inst in
  let nrec = (String.length input - 1) / rb in
  let cycles = ref 0 in
  let step () =
    Cyclesim.cycle sim;
    (match dec with
     | None -> ()
     | Some d ->
       let a = Constant.to_int64_array (Bits.to_constant !d) in
       let off = ref 0 in
       Array.iteri (fun j w ->
         let v = field a !off w in off := !off + w;
         let h = if w = 1 then ((dhist.(j) lsl 1) lor v) land 15 else ((dhist.(j) * 7) + v) land 15 in
         dhist.(j) <- (if w = 1 then h else v);
         dcnt.(j * 16 + h) <- dcnt.(j * 16 + h) + 1) inst.dec_widths);
    (match reg with
     | None -> ()
     | Some r ->
       let a = Constant.to_int64_array (Bits.to_constant !r) in
       let off = ref 0 in
       Array.iteri (fun j w ->
         let v = if w <= 62 then field a !off w else (* wide: hash of its words *) Hashtbl.hash (field a !off 62, w) in
         off := !off + w;
         if v <> rprev.(j) then (rchg.(j) <- rchg.(j) + 1; rprev.(j) <- v);
         if w <= 8 then Hashtbl.replace rvals (j, v) ()) inst.reg_widths);
    (match cmp with
     | Some c when Hashtbl.length cvals < 256 ->
       let a = Constant.to_int64_array (Bits.to_constant !c) in
       let off = ref 0 in
       let vs = Array.map (fun w -> let v = field a !off w in off := !off + w; Hashtbl.replace cvals (w, v) (); v) inst.cmp_widths in
       (* input-to-state: an operand equal to a value this record drives, the other operand differing *)
       if !cur_rec >= 0 && Hashtbl.length i2s < 64 then
         for c = 0 to Array.length vs / 2 - 1 do
           let x = vs.(2 * c) and y = vs.(2 * c + 1) in
           if x <> y then
             Array.iteri (fun pi pv ->
               if pv = x then Hashtbl.replace i2s (!cur_rec, pi, y) ()
               else if pv = y then Hashtbl.replace i2s (!cur_rec, pi, x) ()) !cur_vals
         done
     | _ -> ());
    Array.iteri (fun k (_, o, _) ->
      let v = Bits.to_int !o in
      if v <> oprev.(k) then (ochg.(k) <- ochg.(k) + 1; oprev.(k) <- v);
      oring.(k).(!cycles land 255) <- v) outs;
    (match obs with
     | None -> ()
     | Some ob -> ob.observe ~cycle:!cycles (fun n -> Bits.to_int !(Cyclesim.out_port sim n)));
    incr cycles in
  Option.iter (fun c -> c := Bits.vdd) clear;
  step ();
  Option.iter (fun c -> c := Bits.gnd) clear;
  (try
     for r = 0 to nrec - 1 do
       let base = 1 + r * rb in
       let hb = Char.code input.[base] in
       let hold = if hb < 192 then 1 + (hb land 3) else 1 lsl (hb land 15) in
       let pos = ref (base + 1) in
       List.iteri (fun i (p, w) ->
         let nb = (w + 7) / 8 in
         let v = ref 0 in
         for b = 0 to nb - 1 do v := !v lor (Char.code input.[!pos + b] lsl (8 * b)) done;
         pos := !pos + nb;
         let v = if i < 8 && mask land (1 lsl i) <> 0 then 0 else !v land ((1 lsl w) - 1) in
         p := Bits.of_int ~width:w v) ports;
       cur_rec := r;
       cur_vals := Array.of_list (List.map (fun (p, _) -> Bits.to_int !p) ports);
       for _ = 1 to hold do
         if !cycles >= t.max_cycles then raise Exit;
         step ()
       done
     done
   with Exit -> ());
  let n = !cycles in
  let fs = ref [] in
  let add x = fs := Hashtbl.hash x :: !fs in
  Array.iteri (fun i c -> if c > 0 then add ('D', i / 16, i mod 16, rel_bucket c n)) dcnt;
  Array.iteri (fun j c -> add ('R', j, rate_bucket c n)) rchg;
  Hashtbl.iter (fun (j, v) () -> add ('V', j, v)) rvals;
  Array.iteri (fun k c ->
    add ('O', k, rate_bucket c n);
    (* smallest period of the last 256 values, 0 if none up to 64 *)
    if n >= 256 then begin
      let ring = oring.(k) and last = (n - 1) land 255 in
      let at d = ring.((last - d + 512) land 255) in
      let per = ref 0 in
      (try for p = 1 to 64 do
          let ok = ref true in
          for d = 0 to 255 - p do if !ok && at d <> at (d + p) then ok := false done;
          if !ok then (per := p; raise Exit) done with Exit -> ());
      add ('P', k, !per)
    end) ochg;
  let observed = match obs with None -> [] | Some ob -> ob.finish () in
  List.iter (fun f -> add ('X', f)) observed;
  { features = !fs; cycles = n; observed; cmp_values = Hashtbl.fold (fun k () acc -> k :: acc) cvals [];
    i2s = Hashtbl.fold (fun k () acc -> k :: acc) i2s [] }

(* ---- the fuzzing engine ---- *)

let parallel_map ~workers f xs =
  let arr = Array.of_list xs in
  let res = Array.make (Array.length arr) None in
  let doms = List.init workers (fun w -> Domain.spawn (fun () ->
    Array.iteri (fun i x -> if i mod workers = w then res.(i) <- Some (f x)) arr)) in
  List.iter Domain.join doms;
  Array.to_list (Array.map Option.get res)

let op_names = [| "flip"; "byte"; "interesting"; "arith"; "delete"; "duplicate"; "overwrite"; "splice"; "swarm"; "hold"; "dictionary"; "i2s" |]
let op_i2s = 11
let interesting = [| 0; 1; 2; 16; 32; 64; 127; 128; 255 |]

let mutate ?(dict = [||]) ?(ports = []) st rb queue (s : string) =
  let b = Buffer.create (String.length s + 64) in
  Buffer.add_string b s;
  let get () = Buffer.contents b in
  let set s' = Buffer.clear b; Buffer.add_string b s' in
  let ri m = Random.State.int st (max 1 m) in
  let ops = ref [] in
  let stack = 1 lsl ri 4 in
  for _ = 1 to stack do
    let s = get () in
    let len = String.length s in
    let op = ri op_i2s in   (* the havoc operators; input-to-state is a separate stage *)
    ops := op :: !ops;
    let bs = Bytes.of_string s in
    let pos () = 1 + ri (len - 1) in
    (match op with
     | 0 when len > 1 -> let p = pos () in Bytes.set bs p (Char.chr (Char.code s.[p] lxor (1 lsl ri 8))); set (Bytes.to_string bs)
     | 1 when len > 1 -> Bytes.set bs (pos ()) (Char.chr (ri 256)); set (Bytes.to_string bs)
     | 2 when len > 1 -> Bytes.set bs (pos ()) (Char.chr interesting.(ri (Array.length interesting))); set (Bytes.to_string bs)
     | 3 when len > 1 -> let p = pos () in Bytes.set bs p (Char.chr ((Char.code s.[p] + ri 71 - 35) land 255)); set (Bytes.to_string bs)
     | 4 when len > 1 + rb -> (* delete whole records *)
       let r = (len - 1) / rb in
       let a = 1 + ri r * rb and kr = 1 + ri (max 1 (r / 4)) in
       let k = min (kr * rb) (len - a) in
       set (String.sub s 0 a ^ String.sub s (a + k) (len - a - k))
     | 5 when len > 1 + rb -> (* duplicate a block of records in place *)
       let r = (len - 1) / rb in let a = 1 + ri r * rb and k = (1 + ri 4) * rb in
       let k = min k (len - a) in set (String.sub s 0 a ^ String.sub s a k ^ String.sub s a (len - a))
     | 6 when len > 1 -> let p = pos () in for i = p to min (len - 1) (p + ri 8) do Bytes.set bs i (Char.chr (ri 256)) done; set (Bytes.to_string bs)
     | 7 -> (* splice: insert records from another queue entry *)
       let o = queue.(ri (Array.length queue)) in
       let ol = String.length o in
       if ol > 1 + rb then begin
         let r = (ol - 1) / rb in let a = 1 + ri r * rb and k = (1 + ri 8) * rb in
         let k = min k (ol - a) in
         let at = if len > 1 then 1 + ri ((len - 1) / rb + 1) * rb else 1 in
         let at = min at len in
         set (String.sub s 0 at ^ String.sub o a k ^ String.sub s at (len - at))
       end
     | 8 when len > 0 -> Bytes.set bs 0 (Char.chr (ri 256)); set (Bytes.to_string bs)
     | 10 when len > 1 + rb && Array.length dict > 0 && ports <> [] ->
       (* write a logged comparison operand into one port field of one record *)
       let (w, v) = dict.(ri (Array.length dict)) in
       let r = (len - 1) / rb in let a = 1 + ri r * rb in
       let fields = List.filter (fun (_, pw) -> pw >= w || pw >= 8) ports |> Array.of_list in
       if Array.length fields > 0 then begin
         let (off, pw) = fields.(ri (Array.length fields)) in
         for b = 0 to (pw + 7) / 8 - 1 do Bytes.set bs (a + 1 + off + b) (Char.chr ((v lsr (8 * b)) land 255)) done;
         set (Bytes.to_string bs)
       end
     | 9 when len > 1 + rb -> (* change a record's hold *)
       let r = (len - 1) / rb in let a = 1 + ri r * rb in
       Bytes.set bs a (Char.chr (if ri 2 = 0 then ri 192 else 192 + ri 16)); set (Bytes.to_string bs)
     | _ -> ())
  done;
  let s = get () in
  let s = if String.length s = 0 then "\000" else s in
  s, !ops

type stats = { mutable uses : int array; mutable wins : int array }

type result = {
  execs : int;
  coverage : int;
  queue : (string * int list) array;
  curve : (int * int) list;
  stats : stats;
  first_hit : (int * int) list;   (* observed feature -> execs when first seen *)
}

let random_input st rb =
  let n = 1 + Random.State.int st 64 in
  String.init (1 + n * rb) (fun i -> if i = 0 then '\000' else Char.chr (Random.State.int st 256))

let fuzz ?(workers = 16) ?(batch = 32) ?(shrink_budget = 32) ~budget ~fresh ~seed (t : target) =
  let inst = instrument t in
  let rb = record_bytes inst in
  let st = Random.State.make [| seed |] in
  let virgin = Hashtbl.create 100_000 in
  let queue = ref [||] and top = Hashtbl.create 100_000 in
  let stats = { uses = Array.make (Array.length op_names) 0; wins = Array.make (Array.length op_names) 0 } in
  let execs = ref 0 and curve = ref [] and first = Hashtbl.create 16 in
  let exec s = execute t inst s in
  let dict = Hashtbl.create 1024 in
  let ports = (* byte offset within a record's value bytes, and width *)
    let off = ref 0 in List.map (fun (_, w) -> let o = !off in off := !off + (w + 7) / 8; (o, w)) inst.data_ports in
  let note_observed (r : run_result) =
    List.iter (fun f -> if not (Hashtbl.mem first f) then Hashtbl.replace first f !execs) r.observed in
  let pending = Queue.create () in
  let add_entry s fs =
    let idx = Array.length !queue in
    queue := Array.append !queue [| (s, fs) |];
    List.iter (fun f -> match Hashtbl.find_opt top f with
      | Some (l, _) when l <= String.length s -> () | _ -> Hashtbl.replace top f (String.length s, idx)) fs in
  let fresh_feats fs = List.filter (fun f -> not (Hashtbl.mem virgin f)) fs in
  (* Hypothesis-style shrinking: delete blocks of records, halving the block size, while every
     new feature survives *)
  let shrink s nf =
    let best = ref s and tries = ref 0 in
    let k = ref (((String.length s - 1) / rb) / 2) in
    while !k >= 1 && !tries < shrink_budget do
      let r = (String.length !best - 1) / rb in
      let cands = List.filter_map (fun a ->
        if a + !k > r then None
        else Some (String.sub !best 0 (1 + a * rb) ^ String.sub !best (1 + (a + !k) * rb) (String.length !best - 1 - (a + !k) * rb)))
        (List.init (max 0 (r - !k + 1)) (fun a -> a) |> List.filter (fun a -> a mod !k = 0)) in
      let cands = List.filteri (fun i _ -> i < 16) cands in
      tries := !tries + List.length cands;
      let res = parallel_map ~workers (fun c -> (c, (exec c).features)) cands in
      execs := !execs + List.length cands;
      (match List.find_opt (fun (_, fs) -> List.for_all (fun f -> List.mem f fs) nf) res with
       | Some (c, _) -> best := c
       | None -> k := !k / 2)
    done;
    !best in
  let s0 = random_input st rb in
  let r0 = exec s0 in
  incr execs;
  List.iter (fun f -> Hashtbl.replace virgin f ()) r0.features;
  add_entry s0 r0.features;
  while !execs < budget do
    let favoured = Hashtbl.fold (fun _ (_, i) acc -> i :: acc) top [] |> List.sort_uniq compare |> Array.of_list in
    let pick () =
      let q = !queue in
      if Array.length favoured > 0 && Random.State.int st 10 < 8 then fst q.(favoured.(Random.State.int st (Array.length favoured)))
      else fst q.(Random.State.int st (Array.length q)) in
    let cands = List.init batch (fun _ ->
      if (not fresh) && not (Queue.is_empty pending) then (Queue.pop pending, [ op_i2s ])
      else if fresh then (random_input st rb, [])
      else mutate ~dict:(Array.of_seq (Hashtbl.to_seq_keys dict)) ~ports st rb (Array.map fst !queue) (pick ())) in
    let res = parallel_map ~workers (fun (s, ops) -> (s, ops, exec s)) cands in
    execs := !execs + batch;
    List.iter (fun (s, ops, r) ->
      note_observed r;
      List.iter (fun v -> if Hashtbl.length dict < 4096 then Hashtbl.replace dict v ()) r.cmp_values;
      List.iter (fun o -> stats.uses.(o) <- stats.uses.(o) + 1) ops;
      let nf = fresh_feats r.features in
      if nf <> [] then begin
        List.iter (fun o -> stats.wins.(o) <- stats.wins.(o) + 1) (List.sort_uniq compare ops);
        let s' = if fresh then s else shrink s nf in
        let r' = if s' == s then r else exec s' in
        let fs = r'.features in
        (* the deterministic input-to-state stage for the new entry, as AFL++ runs cmplog on new entries *)
        if not fresh then
          List.iteri (fun k (rec_, pi, v) ->
            if k < 24 then begin
              let (off, w) = List.nth ports pi in
              let bs = Bytes.of_string s' in
              let a = 1 + rec_ * rb + 1 + off in
              if a + (w + 7) / 8 <= Bytes.length bs then begin
                for b = 0 to (w + 7) / 8 - 1 do Bytes.set bs (a + b) (Char.chr ((v lsr (8 * b)) land 255)) done;
                Queue.push (Bytes.to_string bs) pending;
                (* the same, as a one-cycle pulse: strobes and valids are often read on a level *)
                Bytes.set bs (1 + rec_ * rb) '\000';
                Queue.push (Bytes.to_string bs) pending;
                (* and as the next pulse: the original record shortened to one cycle, followed by a
                   one-cycle copy driving the logged value. A value compared right after a match is
                   often the next thing the design wants. *)
                let orig = Bytes.of_string s' in
                let rs = 1 + rec_ * rb in
                if rs + rb <= Bytes.length orig then begin
                  Bytes.set orig rs '\000';
                  let nxt = Bytes.sub bs rs rb in
                  let o = Bytes.to_string orig in
                  Queue.push (String.sub o 0 (rs + rb) ^ Bytes.to_string nxt ^ String.sub o (rs + rb) (String.length o - rs - rb)) pending
                end
              end
            end) r'.i2s;
        List.iter (fun f -> Hashtbl.replace virgin f ()) (r.features @ fs);
        add_entry s' fs
      end) res;
    curve := (!execs, Hashtbl.length virgin) :: !curve
  done;
  { execs = !execs; coverage = Hashtbl.length virgin; queue = !queue; curve = List.rev !curve; stats;
    first_hit = Hashtbl.fold (fun f e acc -> (f, e) :: acc) first [] }
