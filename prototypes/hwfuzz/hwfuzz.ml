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
  stream : (string -> (string * int) list array) option;
  units : (string -> (int * int) list) option;
  (* Optional structure for mutation: the (start, length) spans of the input's units, e.g. packets.
     Enables unit-level mutation: insert a unit from another entry, duplicate, delete, swap. *)
  (* Optional transducer from the fuzz input to per-cycle port changes, replacing the generic
     record decoding: the hardware fuzzer's version of an AFL++ custom post-processor, for
     inputs with framing, line coding or checksums the design checks. *)
}

type instrumented = {
  id : int;
  circuit : Circuit.t;
  resettable : bool;   (* every register has a clear and there are no memories: a simulator can be
                          reused, reset by one cycle of clear, instead of rebuilt per execution *)
  dec_widths : int array;
  reg_widths : int array;
  cmp_widths : int array;
  (* each probe family is read through outputs of at most 62 bits, so one Bits.to_int per chunk per
     cycle: (output name, (probe index, bit offset, width) array) *)
  dec_layout : (string * (int * int * int) array) array;
  reg_layout : (string * (int * int * int) array) array;
  cmp_layout : (string * (int * int * int) array) array;
  data_ports : (string * int) list;   (* inputs other than clock and clear *)
  out_ports : (string * int) list;    (* the original outputs, at most 62 bits wide *)
}

let next_id = ref 0

let instrument (t : target) =
  let c = t.circuit () in
  let g = Circuit.signal_graph c in
  let seen = Hashtbl.create 1024 in
  let decs = ref [] and regs = ref [] and cmps = ref [] and resettable = ref (t.clear <> None) in
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
    | Reg { register; _ } ->
      if Signal.is_empty register.reg_clear then resettable := false;
      regs := s :: !regs
    | Multiport_mem _ -> resettable := false
    | _ -> ());
  let trunc s = if Signal.width s > 62 then Signal.select s 61 0 else s in
  let decs = List.map trunc (List.rev !decs) and regs = List.map trunc (List.rev !regs) and cmps = List.rev !cmps in
  let chunk prefix sigs =
    let groups = ref [] and cur = ref [] and curw = ref 0 in
    List.iteri (fun j s ->
      let w = Signal.width s in
      if !curw + w > 62 then (groups := List.rev !cur :: !groups; cur := []; curw := 0);
      cur := (j, !curw, w, s) :: !cur; curw := !curw + w) sigs;
    if !cur <> [] then groups := List.rev !cur :: !groups;
    let groups = List.rev !groups in
    let name k = Printf.sprintf "%s%d" prefix k in
    List.mapi (fun k g -> Signal.output (name k) (Signal.concat_lsb (List.map (fun (_, _, _, s) -> s) g))) groups,
    Array.of_list (List.mapi (fun k g -> (name k, Array.of_list (List.map (fun (j, o, w, _) -> (j, o, w)) g))) groups) in
  let dec_outs, dec_layout = chunk "__dec" decs and reg_outs, reg_layout = chunk "__reg" regs
  and cmp_outs, cmp_layout = chunk "__cmp" cmps in
  let outs = Circuit.outputs c in
  let circuit = Circuit.create_exn ~name:(t.name ^ "_cov") (outs @ dec_outs @ reg_outs @ cmp_outs) in
  let data_ports =
    List.filter_map (fun s ->
      let n = List.hd (Signal.names s) in
      if n = t.clock || Some n = t.clear then None else Some (n, Signal.width s)) (Circuit.inputs c) in
  let out_ports = List.filter_map (fun s ->
    let n = List.hd (Signal.names s) in if Signal.width s <= 62 then Some (n, Signal.width s) else None) outs in
  incr next_id;
  { id = !next_id; circuit; resettable = !resettable; dec_widths = Array.of_list (List.map Signal.width decs);
    reg_widths = Array.of_list (List.map Signal.width regs);
    cmp_widths = Array.of_list (List.map Signal.width cmps); dec_layout; reg_layout; cmp_layout; data_ports; out_ports }

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
  cmp_pairs : (int * int * int) list;   (* width, one operand, the other: for byte-pattern input-to-state *)
  i2s : (int * int * int) list;   (* input-to-state candidates: record, port index, value to write *)
}

(* one simulator per worker domain and instrumented circuit *)
let sim_cache = Domain.DLS.new_key (fun () -> Hashtbl.create 4)

let execute (t : target) inst (input : string) =
  let sim =
    if not inst.resettable then Cyclesim.create inst.circuit
    else begin
      let tbl = Domain.DLS.get sim_cache in
      match Hashtbl.find_opt tbl inst.id with
      | Some s -> s
      | None -> let s = Cyclesim.create inst.circuit in Hashtbl.replace tbl inst.id s; s
    end in
  let inp n = Cyclesim.in_port sim n and out n = Cyclesim.out_port sim n in
  let ports = List.map (fun (n, w) -> (inp n, w)) inst.data_ports in
  let clear = Option.map inp t.clear in
  let chunks layout = Array.map (fun (n, ps) -> (out n, ps)) layout in
  let decc = chunks inst.dec_layout and regc = chunks inst.reg_layout and cmpc = chunks inst.cmp_layout in
  let vs = Array.make (Array.length inst.cmp_widths) 0 in
  let vprev = Array.make (Array.length inst.cmp_layout) (-1) and last_rec = ref (-2) in
  let oport = Hashtbl.create 8 in
  let get n = match Hashtbl.find_opt oport n with
    | Some r -> Bits.to_int !r
    | None -> let r = out n in Hashtbl.add oport n r; Bits.to_int !r in
  let outs = Array.of_list (List.map (fun (n, w) -> (n, out n, w)) inst.out_ports) in
  let nd = Array.length inst.dec_widths and nr = Array.length inst.reg_widths and no = Array.length outs in
  let dcnt = Array.make (nd * 16) 0 and dhist = Array.make nd 0 in
  let rchg = Array.make nr 0 and rprev = Array.make nr (-1) and rvals = Hashtbl.create 256 in
  let ochg = Array.make no 0 and oprev = Array.make no (-1) and oring = Array.make_matrix no 256 0 in
  let obs = Option.map (fun f -> f ()) t.observer in
  let cvals = Hashtbl.create 64 and i2s = Hashtbl.create 64 and pairs = Hashtbl.create 64 in
  let cur_rec = ref (-1) and cur_vals = ref [||] in
  let mask = if String.length input > 0 then Char.code input.[0] else 0 in
  let rb = record_bytes inst in
  let nrec = (String.length input - 1) / rb in
  let cycles = ref 0 in
  let step () =
    Cyclesim.cycle sim;
    Array.iter (fun (o, ps) ->
      let v = Bits.to_int !o in
      Array.iter (fun (j, off, w) ->
        let x = (v lsr off) land ((1 lsl w) - 1) in
        let h = if w = 1 then ((dhist.(j) lsl 1) lor x) land 15 else ((dhist.(j) * 7) + x) land 15 in
        dhist.(j) <- (if w = 1 then h else x);
        dcnt.(j * 16 + h) <- dcnt.(j * 16 + h) + 1) ps) decc;
    Array.iter (fun (o, ps) ->
      let v = Bits.to_int !o in
      Array.iter (fun (j, off, w) ->
        let x = (v lsr off) land ((1 lsl w) - 1) in
        if x <> rprev.(j) then (rchg.(j) <- rchg.(j) + 1; rprev.(j) <- x);
        if w <= 8 then Hashtbl.replace rvals (j, x) ()) ps) regc;
    if Array.length vs > 0 && Hashtbl.length cvals < 256 then begin
      (* operands rarely change from one cycle to the next: only do the logging work on a change *)
      let changed = ref false in
      Array.iteri (fun k (o, ps) ->
        let v = Bits.to_int !o in
        if v <> vprev.(k) then begin
          vprev.(k) <- v;
          Array.iter (fun (j, off, w) ->
            let x = (v lsr off) land ((1 lsl w) - 1) in
            if x <> vs.(j) || !cycles = 0 then (vs.(j) <- x; changed := true; Hashtbl.replace cvals (w, x) ())) ps
        end) cmpc;
      if !changed || !cur_rec <> !last_rec then begin
      last_rec := !cur_rec;
      for c = 0 to Array.length vs / 2 - 1 do
        let x = vs.(2 * c) and y = vs.(2 * c + 1) in
        if x <> y && Hashtbl.length pairs < 256 then Hashtbl.replace pairs (inst.cmp_widths.(2 * c), x, y) ()
      done;
      (* input-to-state: an operand equal to a value this record drives, the other operand differing *)
      if !cur_rec >= 0 && Hashtbl.length i2s < 64 then
        for c = 0 to Array.length vs / 2 - 1 do
          let x = vs.(2 * c) and y = vs.(2 * c + 1) in
          if x <> y then
            Array.iteri (fun pi pv ->
              if pv = x then Hashtbl.replace i2s (!cur_rec, pi, y) ()
              else if pv = y then Hashtbl.replace i2s (!cur_rec, pi, x) ()) !cur_vals
        done
      end
    end;
    Array.iteri (fun k (_, o, _) ->
      let v = Bits.to_int !o in
      if v <> oprev.(k) then (ochg.(k) <- ochg.(k) + 1; oprev.(k) <- v);
      oring.(k).(!cycles land 255) <- v) outs;
    (match obs with
     | None -> ()
     | Some ob -> ob.observe ~cycle:!cycles get);
    incr cycles in
  List.iter (fun (p, w) -> p := Bits.zero w) ports;
  Option.iter (fun c -> c := Bits.vdd) clear;
  step ();
  Option.iter (fun c -> c := Bits.gnd) clear;
  (match t.stream with
   | Some f ->
     let rows = f input in
     let byname = List.map2 (fun (n, _) (p, w) -> (n, (p, w))) inst.data_ports ports in
     (try
        Array.iter (fun changes ->
          if !cycles >= t.max_cycles then raise Exit;
          List.iter (fun (n, v) -> match List.assoc_opt n byname with
            | Some (p, w) -> p := Bits.of_int ~width:w (v land ((1 lsl w) - 1)) | None -> ()) changes;
          step ()) rows
      with Exit -> ())
   | None ->
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
   with Exit -> ()));
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
    i2s = Hashtbl.fold (fun k () acc -> k :: acc) i2s [];
    cmp_pairs = Hashtbl.fold (fun k () acc -> k :: acc) pairs [] }

(* ---- the fuzzing engine ---- *)

let parallel_map ~workers f xs =
  let arr = Array.of_list xs in
  let res = Array.make (Array.length arr) None in
  let doms = List.init workers (fun w -> Domain.spawn (fun () ->
    Array.iteri (fun i x -> if i mod workers = w then res.(i) <- Some (f x)) arr)) in
  List.iter Domain.join doms;
  Array.to_list (Array.map Option.get res)

let op_names = [| "flip"; "byte"; "interesting"; "arith"; "delete"; "duplicate"; "overwrite"; "splice"; "swarm"; "hold"; "dictionary"; "i2s"; "unit" |]
let op_i2s = 11 and op_unit = 12

(* unit-level mutation on the spans a target reports *)
let mutate_units st units queue (s : string) =
  let ri m = Random.State.int st (max 1 m) in
  let us = Array.of_list (units s) in
  let n = Array.length us and len = String.length s in
  let cut a b = String.sub s 0 a ^ String.sub s b (len - b) in
  let insert_at at piece = String.sub s 0 at ^ piece ^ String.sub s at (len - at) in
  let boundary () = if n = 0 then len else if ri (n + 1) = n then len else fst us.(ri n) in
  match ri 4 with
  | 0 -> (* a unit from another entry, at a unit boundary here *)
    let o = queue.(ri (Array.length queue)) in
    let uo = Array.of_list (units o) in
    if Array.length uo = 0 then s
    else let (a, l) = uo.(ri (Array.length uo)) in insert_at (boundary ()) (String.sub o a l)
  | 1 when n > 0 -> let (a, l) = us.(ri n) in insert_at (a + l) (String.sub s a l)
  | 2 when n > 0 -> let (a, l) = us.(ri n) in cut a (a + l)
  | 3 when n > 1 ->
    let k = ri (n - 1) in
    let (a, l) = us.(k) and (b, m) = us.(k + 1) in
    String.sub s 0 a ^ String.sub s b m ^ String.sub s a l ^ String.sub s (b + m) (len - b - m)
  | _ -> s
let interesting = [| 0; 1; 2; 16; 32; 64; 127; 128; 255 |]

let mutate ?(dict = [||]) ?(ports = []) ?units st rb queue (s : string) =
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
    (* the havoc operators; input-to-state is a separate stage; unit mutations when available *)
    let op = if units <> None && ri 3 = 0 then op_unit else ri op_i2s in
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
     | 12 -> (match units with Some u -> set (mutate_units st u queue s) | None -> ())
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
     | 10 when len > 1 && Array.length dict > 0 ->
       (* no port layout (a transducer target): write the value's bytes anywhere in the input *)
       let (w, v) = dict.(ri (Array.length dict)) in
       let nb = max 1 ((w + 7) / 8) in
       let p = pos () in
       for b = 0 to nb - 1 do if p + b < len then Bytes.set bs (p + b) (Char.chr ((v lsr (8 * b)) land 255)) done;
       set (Bytes.to_string bs)
     | 9 when len > 1 + rb -> (* change a record's hold *)
       let r = (len - 1) / rb in let a = 1 + ri r * rb in
       Bytes.set bs a (Char.chr (if ri 2 = 0 then ri 192 else 192 + ri 16)); set (Bytes.to_string bs)
     | _ -> ())
  done;
  let s = get () in
  let s = if String.length s = 0 then "\000" else s in
  s, !ops

type stats = { mutable uses : int array; mutable wins : int array }

(* Switches for the ablation ladder and the search strategy. *)
type config = {
  dict : bool;          (* comparison operands as a havoc dictionary *)
  i2s : bool;           (* the deterministic input-to-state stage *)
  pulses : int;         (* input-to-state variants: 0 plain, 1 + one-cycle pulse, 2 + next pulse *)
  i2s_bytes : bool;     (* input-to-state by byte pattern (AFL++ CmpLog): find one operand's bytes in
                           the input, write the other's; works through a transducer *)
  multi_i2s : bool;     (* also mutants applying several logged replacements at once *)
  shrink_budget : int;
  batch : int;
  workers : int;
}
let default_config = { dict = true; i2s = true; pulses = 2; i2s_bytes = true; multi_i2s = true; shrink_budget = 32; batch = 32;
    workers = (match Sys.getenv_opt "HWFUZZ_WORKERS" with Some w -> int_of_string w | None -> 4) }

let random_input st rb =
  let n = 1 + Random.State.int st 64 in
  String.init (1 + n * rb) (fun i -> if i = 0 then '\000' else Char.chr (Random.State.int st 256))

type result = {
  execs : int;                    (* total over all engines *)
  coverage : int;                 (* distinct features over all engines *)
  queue : (string * int list) array;
  stats : stats;
  first_hit : (int * int) list;   (* observed feature -> total executions when first seen *)
}

(* One campaign's state. Several engines can run as independent restarts or as islands that
   exchange new queue entries, as AFL's -M/-S instances do. *)
type engine = {
  t : target;
  inst : instrumented;
  cfg : config;
  fresh : bool;             (* the random baseline: every candidate a new random input *)
  rb : int;
  st : Random.State.t;
  virgin : (int, unit) Hashtbl.t;
  mutable queue : (string * int list) array;
  top : (int, int * int) Hashtbl.t;   (* feature -> (input length, queue index) *)
  stats : stats;
  mutable execs : int;
  mutable curve : (int * int) list;
  first : (int, int) Hashtbl.t;       (* observed feature -> execs of this engine when first seen *)
  pending : string Queue.t;
  dict : (int * int, unit) Hashtbl.t;
  ports : (int * int) list;           (* byte offset within a record's value bytes, and width *)
}

let exec e s = execute e.t e.inst s

let add_entry e s fs =
  let idx = Array.length e.queue in
  e.queue <- Array.append e.queue [| (s, fs) |];
  List.iter (fun f -> match Hashtbl.find_opt e.top f with
    | Some (l, _) when l <= String.length s -> () | _ -> Hashtbl.replace e.top f (String.length s, idx)) fs

let fresh_feats e fs = List.filter (fun f -> not (Hashtbl.mem e.virgin f)) fs

(* Hypothesis-style shrinking: delete blocks of records, halving the block size, while every new
   feature survives *)
let shrink e s nf =
  let rb = e.rb in
  let best = ref s and tries = ref 0 in
  let k = ref (((String.length s - 1) / rb) / 2) in
  while !k >= 1 && !tries < e.cfg.shrink_budget do
    let r = (String.length !best - 1) / rb in
    let cands = List.filter_map (fun a ->
      if a + !k > r then None
      else Some (String.sub !best 0 (1 + a * rb) ^ String.sub !best (1 + (a + !k) * rb) (String.length !best - 1 - (a + !k) * rb)))
      (List.init (max 0 (r - !k + 1)) (fun a -> a) |> List.filter (fun a -> a mod !k = 0)) in
    let cands = List.filteri (fun i _ -> i < 16) cands in
    tries := !tries + List.length cands;
    let res = parallel_map ~workers:e.cfg.workers (fun c -> (c, (exec e c).features)) cands in
    e.execs <- e.execs + List.length cands;
    (match List.find_opt (fun (_, fs) -> List.for_all (fun f -> List.mem f fs) nf) res with
     | Some (c, _) -> best := c
     | None -> k := !k / 2)
  done;
  !best

(* the deterministic input-to-state stage for a new entry, as AFL++ runs cmplog on new entries *)
let queue_i2s e s' (r : run_result) =
  let rb = e.rb in
  List.iteri (fun k (rec_, pi, v) ->
    if k < 24 then begin
      let (off, w) = List.nth e.ports pi in
      let bs = Bytes.of_string s' in
      let a = 1 + rec_ * rb + 1 + off in
      if a + (w + 7) / 8 <= Bytes.length bs then begin
        for b = 0 to (w + 7) / 8 - 1 do Bytes.set bs (a + b) (Char.chr ((v lsr (8 * b)) land 255)) done;
        Queue.push (Bytes.to_string bs) e.pending;
        if e.cfg.pulses >= 1 then begin
          (* the same, as a one-cycle pulse: strobes and valids are often read on a level *)
          Bytes.set bs (1 + rec_ * rb) '\000';
          Queue.push (Bytes.to_string bs) e.pending
        end;
        if e.cfg.pulses >= 2 then begin
          (* and as the next pulse: the original record shortened to one cycle, followed by a
             one-cycle copy driving the logged value. A value compared right after a match is
             often the next thing the design wants. *)
          let orig = Bytes.of_string s' in
          let rs = 1 + rec_ * rb in
          if rs + rb <= Bytes.length orig then begin
            Bytes.set orig rs '\000';
            let nxt = Bytes.sub bs rs rb in
            Bytes.set nxt 0 '\000';
            let o = Bytes.to_string orig in
            Queue.push (String.sub o 0 (rs + rb) ^ Bytes.to_string nxt ^ String.sub o (rs + rb) (String.length o - rs - rb)) e.pending
          end
        end
      end
    end) r.i2s

(* byte-pattern input-to-state: for a logged comparison (x, y), every place the input holds x's
   little-endian bytes gets y's instead, and the other way round *)
let queue_i2s_bytes e s (r : run_result) =
  let n = ref 0 in
  let le w v = String.init (max 1 ((w + 7) / 8)) (fun b -> Char.chr ((v lsr (8 * b)) land 255)) in
  List.iter (fun (w, x, y) ->
    if w >= 4 && w <= 32 then   (* narrow fields too: a 7-bit USB address fits one byte *)
      List.iter (fun (a, b) ->
        let pa = le w a and pb = le w b in
        let la = String.length pa in
        let i = ref 1 in
        while !n < 32 && !i + la <= String.length s do
          if String.sub s !i la = pa then begin
            Queue.push (String.sub s 0 !i ^ pb ^ String.sub s (!i + la) (String.length s - !i - la)) e.pending;
            incr n
          end;
          incr i
        done) [ (x, y); (y, x) ]) r.cmp_pairs;
  (* the next unit: a value the design compares against once the input has run out belongs in a
     new unit at the end (the unit-level form of the "next pulse" variant). Append a copy of a
     unit holding one operand, with the other substituted. USB: after SET_ADDRESS the device
     compares token addresses with its new address, and only a new IN token can use that. *)
  (match e.t.units with
   | Some units ->
     let us = Array.of_list (units s) in
     let pairs = Array.of_list (List.filter (fun (w, _, _) -> w >= 4 && w <= 16) r.cmp_pairs) in
     for _ = 1 to min 12 (Array.length pairs) do
       let (w, x, y) = pairs.(Random.State.int e.st (Array.length pairs)) in
       let (a, b) = if Random.State.bool e.st then (x, y) else (y, x) in
       let pa = le w a and pb = le w b in
       let la = String.length pa in
       let holding = List.filter (fun (st, l) ->
         let u = String.sub s st l in
         let rec f i = i + la <= l && (String.sub u i la = pa || f (i + 1)) in f 1) (Array.to_list us) in
       match List.rev holding with
       | (st, l) :: _ ->
         let u = Bytes.of_string (String.sub s st l) in
         let rec f i = if i + la <= l then (if Bytes.sub_string u i la = pa then Bytes.blit_string pb 0 u i la else f (i + 1)) in f 1;
         Queue.push (s ^ Bytes.to_string u) e.pending
       | [] -> ()
     done
   | None -> ());
  (* multi-replacement: conditions often need several comparisons true at once (a request type and
     a request code), and one replacement alone changes nothing the design reacts to. A few
     mutants apply a random, consistent subset of all logged replacements together. *)
  if e.cfg.multi_i2s then begin
    let by_src = Hashtbl.create 16 in
    List.iter (fun (w, x, y) ->
      if w >= 4 && w <= 16 then List.iter (fun (a, b) -> Hashtbl.replace by_src (w, a) (b :: Option.value ~default:[] (Hashtbl.find_opt by_src (w, a)))) [ (x, y); (y, x) ]) r.cmp_pairs;
    let srcs = Hashtbl.fold (fun k v acc -> (k, Array.of_list v) :: acc) by_src [] in
    let present = List.filter (fun ((w, a), _) ->
      let pa = le w a in let la = String.length pa in
      let rec f i = i + la <= String.length s && (String.sub s i la = pa || f (i + 1)) in f 1) srcs in
    if List.length present >= 2 then
      for _ = 1 to 16 do
        let b = Bytes.of_string s in
        (* two or three sources per mutant: replacing half of everything logged almost always
           breaks something vital as well (measured on USB: no SET_ADDRESS that way) *)
        let arr = Array.of_list present in
        let k = 2 + Random.State.int e.st 2 in
        let chosen = List.init k (fun _ -> arr.(Random.State.int e.st (Array.length arr))) in
        List.iter (fun ((w, a), targets) ->
          begin
            let pa = le w a and pb = le w targets.(Random.State.int e.st (Array.length targets)) in
            let la = String.length pa in
            for i = 1 to Bytes.length b - la do
              if Bytes.sub_string b i la = pa then Bytes.blit_string pb 0 b i la
            done
          end) chosen;
        Queue.push (Bytes.to_string b) e.pending
      done
  end

(* keep [s] if it has new features; [ops] are the operators that produced it *)
let consider e ~shrink_it (s, ops, (r : run_result)) =
  List.iter (fun f -> if not (Hashtbl.mem e.first f) then Hashtbl.replace e.first f e.execs) r.observed;
  if e.cfg.dict then List.iter (fun v -> if Hashtbl.length e.dict < 4096 then Hashtbl.replace e.dict v ()) r.cmp_values;
  List.iter (fun o -> e.stats.uses.(o) <- e.stats.uses.(o) + 1) ops;
  let nf = fresh_feats e r.features in
  if nf <> [] then begin
    List.iter (fun o -> e.stats.wins.(o) <- e.stats.wins.(o) + 1) (List.sort_uniq compare ops);
    let s' = if shrink_it then shrink e s nf else s in
    let r' = if s' == s then r else (e.execs <- e.execs + 1; exec e s') in
    if e.cfg.i2s && not e.fresh then queue_i2s e s' r';
    if e.cfg.i2s_bytes && not e.fresh then queue_i2s_bytes e s' r';
    List.iter (fun f -> Hashtbl.replace e.virgin f ()) (r.features @ r'.features);
    add_entry e s' r'.features
  end

let create ?(cfg = default_config) ?(corpus = []) ~fresh ~seed (t : target) =
  let inst = instrument t in
  let rb = record_bytes inst in
  let e = {
    t; inst; cfg; fresh; rb; st = Random.State.make [| seed |];
    virgin = Hashtbl.create 100_000; queue = [||]; top = Hashtbl.create 100_000;
    stats = { uses = Array.make (Array.length op_names) 0; wins = Array.make (Array.length op_names) 0 };
    execs = 0; curve = []; first = Hashtbl.create 16; pending = Queue.create (); dict = Hashtbl.create 1024;
    ports = (let off = ref 0 in List.map (fun (_, w) -> let o = !off in off := !off + (w + 7) / 8; (o, w)) inst.data_ports) } in
  let s0 = random_input e.st rb in
  let r0 = exec e s0 in
  e.execs <- 1;
  consider e ~shrink_it:false (s0, [], r0);
  if Array.length e.queue = 0 then add_entry e s0 r0.features;
  (* a seed corpus, as AFL campaigns start from example inputs *)
  List.iter (fun s -> e.execs <- e.execs + 1; consider e ~shrink_it:false (s, [], exec e s)) corpus;
  e

(* run [n] more executions *)
let step e n =
  let stop = e.execs + n in
  while e.execs < stop do
    let favoured = Hashtbl.fold (fun _ (_, i) acc -> i :: acc) e.top [] |> List.sort_uniq compare |> Array.of_list in
    let pick () =
      let q = e.queue in
      if Array.length favoured > 0 && Random.State.int e.st 10 < 8 then fst q.(favoured.(Random.State.int e.st (Array.length favoured)))
      else fst q.(Random.State.int e.st (Array.length q)) in
    let dict = if e.cfg.dict then Array.of_seq (Hashtbl.to_seq_keys e.dict) else [||] in
    let cands = List.init e.cfg.batch (fun _ ->
      if (not e.fresh) && not (Queue.is_empty e.pending) then (Queue.pop e.pending, [ op_i2s ])
      else if e.fresh then (random_input e.st e.rb, [])
      else mutate ~dict ~ports:e.ports ?units:e.t.units e.st e.rb (Array.map fst e.queue) (pick ())) in
    let res = parallel_map ~workers:e.cfg.workers (fun (s, ops) -> (s, ops, exec e s)) cands in
    e.execs <- e.execs + e.cfg.batch;
    List.iter (consider e ~shrink_it:(not e.fresh)) res;
    e.curve <- (e.execs, Hashtbl.length e.virgin) :: e.curve
  done

(* offer inputs found elsewhere (island sync): executed here, kept only if new to this engine *)
let import e inputs =
  let res = parallel_map ~workers:e.cfg.workers (fun s -> (s, [], exec e s)) inputs in
  e.execs <- e.execs + List.length inputs;
  List.iter (consider e ~shrink_it:false) res

(* afl-cmin: a small set of entries covering every feature the queue covers (greedy set cover) *)
let cmin (queue : (string * int list) array) =
  let uncovered = Hashtbl.create 10_000 in
  Array.iter (fun (_, fs) -> List.iter (fun f -> Hashtbl.replace uncovered f ()) fs) queue;
  let chosen = ref [] in
  while Hashtbl.length uncovered > 0 do
    let best = ref (-1) and gain = ref 0 in
    Array.iteri (fun i (s, fs) ->
      let g = List.length (List.filter (Hashtbl.mem uncovered) fs) in
      if g > !gain || (g = !gain && g > 0 && String.length s < String.length (fst queue.(!best))) then (best := i; gain := g)) queue;
    List.iter (Hashtbl.remove uncovered) (snd queue.(!best));
    chosen := !best :: !chosen
  done;
  List.rev !chosen

(* [k] engines, round-robin in slices of [slice] executions each. With [sync], each engine imports
   the entries the others found since the last round (islands); without, they are independent
   restarts merged at the end. A single campaign is k = 1. Total executions ~ budget. *)
let campaign ?(cfg = default_config) ?(corpus = []) ?(k = 1) ?(slice = 2000) ?(sync = true) ~budget ~fresh ~seed t =
  let es : engine array = Array.init k (fun i -> create ~cfg ~corpus ~fresh ~seed:(seed * 1009 + i) t) in
  let exported = Array.make k 1 in
  let total () = Array.fold_left (fun a (e : engine) -> a + e.execs) 0 es in
  let first = Hashtbl.create 16 in
  (* a hit at engine i's own count x happened when the others stood where they are now, since the
     engines run one at a time *)
  let note i =
    let others = total () - es.(i).execs in
    Hashtbl.iter (fun f x -> match Hashtbl.find_opt first f with
      | Some y when y <= x + others -> () | _ -> Hashtbl.replace first f (x + others)) es.(i).first in
  while total () < budget do
    Array.iteri (fun i e -> step e (min slice (max cfg.batch ((budget - total ()) / k))); note i) es;
    if sync && k > 1 then begin
      let fresh_entries = Array.mapi (fun i e ->
        let l = Array.to_list (Array.sub e.queue exported.(i) (Array.length e.queue - exported.(i))) in
        exported.(i) <- Array.length e.queue; List.map fst l) es in
      Array.iteri (fun i e ->
        let others = List.concat (List.filteri (fun j _ -> j <> i) (Array.to_list fresh_entries)) in
        if others <> [] then import e others;
        exported.(i) <- Array.length e.queue; note i) es
    end
  done;
  let feats = Hashtbl.create 100_000 in
  Array.iter (fun e -> Hashtbl.iter (fun f () -> Hashtbl.replace feats f ()) e.virgin) es;
  let stats = { uses = Array.make (Array.length op_names) 0; wins = Array.make (Array.length op_names) 0 } in
  Array.iter (fun e -> Array.iteri (fun i u -> stats.uses.(i) <- stats.uses.(i) + u; stats.wins.(i) <- stats.wins.(i) + e.stats.wins.(i)) e.stats.uses) es;
  ({ execs = total (); coverage = Hashtbl.length feats; queue = Array.concat (Array.to_list (Array.map (fun e -> e.queue) es));
    stats; first_hit = Hashtbl.fold (fun f e acc -> (f, e) :: acc) first [] } : result)

let fuzz ?cfg ~budget ~fresh ~seed t = campaign ?cfg ~k:1 ~budget ~fresh ~seed t
