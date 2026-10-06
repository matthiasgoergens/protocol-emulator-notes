(* Toggle coverage of every register bit of a Hardcaml circuit, for the lockstep's stimulus.

   [instrument] taps every register of a circuit as one wide extra output, [observe] records which
   bits have risen and which have fallen, and [report] groups the bits by the block and source line
   that created them. The source line comes from Hardcaml's Caller_id (enable it with [enable]
   before the circuit is built): the deepest frame of the creating call stack that is not inside
   Hardcaml or the standard library, which is the block's own line, e.g. upe_rtl.ml:212. Where a
   circuit output shows a register directly (the core's debug outputs: pe_s0, seq_dbg_pc, ...), its
   bits are also labelled with that output's name, so a never-toggled bit can be read as "PE 2's F",
   not only as a line number.

   This measures the stimulus, not the checking: a bit that changes is reached, whether or not the
   lockstep compares it (it compares every pad and the architectural state, see lockstep.ml). *)
open Hardcaml

let enable () = Caller_id.set_mode Full_trace

type reg = {
  uid : int;
  width : int;
  offset : int;         (* bit offset in the tapped output *)
  loc : string;         (* file:line of the creating call in the design's sources, or "?" *)
  file : string;
  label : string;       (* an output name that shows this register, or its own name, or "" *)
  label_off : int;      (* bit offset of the register inside that output *)
}

let tap_name = "cov__regs"

(* Hardcaml's own and the standard library's source files: frames there are skipped *)
let skipped =
  [ "always.ml"; "signal.ml"; "signal__type.ml"; "comb.ml"; "caller_id.ml"; "reg_spec.ml"; "list.ml";
    "list0.ml"; "array.ml"; "array0.ml"; "stdlib.ml"; "fn.ml"; "option.ml"; "interface.ml"; "scope.ml";
    "hierarchy.ml"; "with_valid.ml"; "bits.ml"; "map.ml"; "camlinternalLazy.ml"; "instantiation.ml";
    "signal_graph.ml"; "circuit.ml"; "parameter.ml"; "constant.ml"; "sexp.ml"; "printexc.ml"; "fifo.ml";
    "ram.ml"; "seq.ml"; "hashtbl.ml" ]

let rec atoms (s : Sexplib0.Sexp.t) = match s with Atom a -> [ a ] | List l -> List.concat_map atoms l

(* the deepest-first list of "file:line" frames of a signal's creating stack, design files only *)
let frames s =
  match Signal.Type.caller_id s with
  | None -> []
  | Some c ->
    atoms (Caller_id.sexp_of_t c)
    |> List.filter_map (fun a ->
           match String.split_on_char ':' a with
           | f :: l :: _ ->
             let b = Filename.basename f in
             if List.mem b skipped then None else Some (b, b ^ ":" ^ l)
           | _ -> None)

let rec strip s = match s with Signal.Type.Wire { driver; _ } when not (Signal.is_empty !driver) -> strip !driver | _ -> s

(* Returns the instrumented circuit and the tapped registers, with uids of [c]. *)
let instrument (c : Circuit.t) =
  let regs = ref [] in
  Signal_graph.iter (Circuit.signal_graph c) ~f:(fun s -> match s with Signal.Type.Reg _ -> regs := s :: !regs | _ -> ());
  let regs = List.sort (fun a b -> compare ((Signal.Type.Uid.to_int (Signal.uid a))) ((Signal.Type.Uid.to_int (Signal.uid b)))) !regs in
  (* labels from outputs that show registers directly *)
  let labels = Hashtbl.create 256 in
  List.iter (fun o ->
      let name = List.hd (Signal.names o) in
      let rec walk s off =
        match strip s with
        | Signal.Type.Reg _ as r -> if not (Hashtbl.mem labels ((Signal.Type.Uid.to_int (Signal.uid r)))) then Hashtbl.replace labels ((Signal.Type.Uid.to_int (Signal.uid r))) (name, off)
        | Cat { args; _ } ->
          (* args are msb first *)
          ignore (List.fold_left (fun o a -> walk a (o - Signal.width a); o - Signal.width a) (off + Signal.width s) args)
        | _ -> ()
      in
      walk o 0)
    (Circuit.outputs c);
  let off = ref 0 in
  let infos =
    List.map (fun r ->
        let fr = frames r in
        let file, loc = match fr with (f, l) :: _ -> (f, l) | [] -> ("?", "?") in
        let label, label_off =
          match Hashtbl.find_opt labels ((Signal.Type.Uid.to_int (Signal.uid r))) with
          | Some x -> x
          | None -> ((match Signal.names r with n :: _ -> n | [] -> ""), 0) in
        let i = { uid = (Signal.Type.Uid.to_int (Signal.uid r)); width = Signal.width r; offset = !off; loc; file; label; label_off } in
        off := !off + Signal.width r;
        i)
      regs
  in
  let tap = Signal.output tap_name (Signal.concat_lsb regs) in
  (Circuit.create_exn ~name:(Circuit.name c ^ "_cov") (Circuit.outputs c @ [ tap ]), Array.of_list infos)

(* relabel registers (e.g. a register file whose entries are created in a loop) *)
let relabel (infos : reg array) f = Array.map (fun i -> match f i with Some (l, o) -> { i with label = l; label_off = o } | None -> i) infos

(* accumulated over every simulation of one instrumented circuit *)
(* [source]: the circuit the registers were found in. Circuit.create_exn renumbers the signals of
   the circuit it makes, so the instrumented circuit's uids are not these; analyses by uid
   (constant_bits) take [source]. *)
type acc = { infos : reg array; source : Circuit.t; mutable rose : Bits.t; mutable fell : Bits.t; mutable clocks : int }

let create_acc ~source infos =
  let w = Array.fold_left (fun a i -> a + i.width) 0 infos in
  { infos; source; rose = Bits.zero w; fell = Bits.zero w; clocks = 0 }

(* one simulation's view: the previous value of the tap *)
type obs = { acc : acc; mutable prev : Bits.t option }

let observer acc = { acc; prev = None }

let observe (o : obs) (v : Bits.t) =
  (match o.prev with
   | Some p ->
     o.acc.rose <- Bits.(o.acc.rose |: (v &: ~:p));
     o.acc.fell <- Bits.(o.acc.fell |: (p &: ~:v))
   | None -> ());
  o.acc.clocks <- o.acc.clocks + 1;
  o.prev <- Some v

let merge_into ~(into : acc) (a : acc) =
  into.rose <- Bits.(into.rose |: a.rose);
  into.fell <- Bits.(into.fell |: a.fell);
  into.clocks <- into.clocks + a.clocks

(* block names by source file *)
let block_of file =
  match file with
  | "chip_rtl.ml" -> "glue"
  | "sequencer2.ml" -> "sequencer"
  | "upe_rtl.ml" -> "PE array"
  | "streamer.ml" -> "streamer"
  | "sampler.ml" -> "sampler"
  | "edge_sampler.ml" -> "edge sampler"
  | "crc_unit.ml" -> "CRC"
  | "matcher_en.ml" -> "matcher"
  | "nco.ml" -> "NCO"
  | "stage.ml" -> "pin stage"
  | "tt_top.ml" -> "TT top"
  | f -> f

type bit = { info : reg; bit : int; rose : bool; fell : bool }

let bits (acc : acc) =
  Array.to_list acc.infos
  |> List.concat_map (fun i ->
         List.init i.width (fun b ->
             let k = i.offset + b in
             { info = i; bit = b; rose = Bits.to_bool (Bits.bit acc.rose k); fell = Bits.to_bool (Bits.bit acc.fell k) }))

let changed b = b.rose || b.fell

let bit_name b =
  let i = b.info in
  let base = if i.label <> "" then Printf.sprintf "%s[%d]" i.label (i.label_off + b.bit) else Printf.sprintf "r%d[%d]" i.uid b.bit in
  Printf.sprintf "%s (%s, reg %d bit %d of %d)" base i.loc i.uid b.bit i.width

(* [const]: per tapped bit, provably constant (constant_bits below); such a bit cannot change *)
let is_const const b = match const with Some c -> c.(b.info.offset + b.bit) | None -> false

(* per block: bits, bits that changed, bits that both rose and fell, provably constant bits *)
let by_block ?const (acc : acc) =
  let t = Hashtbl.create 16 in
  List.iter (fun b ->
      let k = block_of b.info.file in
      let n, c, f, z = Option.value (Hashtbl.find_opt t k) ~default:(0, 0, 0, 0) in
      Hashtbl.replace t k (n + 1, (c + if changed b then 1 else 0), (f + if b.rose && b.fell then 1 else 0),
                           (z + if is_const const b then 1 else 0)))
    (bits acc);
  List.sort compare (Hashtbl.fold (fun k v l -> (k, v) :: l) t [])

let report ?(oc = stdout) ?const ~title (acc : acc) =
  let all = bits acc in
  let n = List.length all and c = List.length (List.filter changed all) in
  let f = List.length (List.filter (fun b -> b.rose && b.fell) all) in
  let z = List.length (List.filter (is_const const) all) in
  Printf.fprintf oc "%s: %d clocks; register bits that changed %d of %d (%.1f %%), rose and fell %d" title acc.clocks c n
    (100. *. float c /. float (max n 1)) f;
  if const <> None then begin
    Printf.fprintf oc "; provably constant %d; changed of the rest %d of %d (%.1f %%)" z c (n - z)
      (100. *. float c /. float (max (n - z) 1));
    (* the analysis checked against the simulation: a bit it calls constant must never change *)
    let bad = List.filter (fun b -> changed b && is_const const b) all in
    Printf.fprintf oc "; constant yet changed (must be 0): %d" (List.length bad);
    List.iteri (fun i b -> if i < 5 then Printf.fprintf oc "\n    UNSOUND: %s" (bit_name b)) bad
  end;
  Printf.fprintf oc "\n";
  List.iter (fun (k, (n, c, f, z)) ->
      Printf.fprintf oc "  %-13s %5d of %5d changed (%5.1f %%), %5d rose and fell" k c n (100. *. float c /. float (max n 1)) f;
      if const <> None then Printf.fprintf oc ", %4d provably constant, %4d other never changed" z (n - c - z);
      Printf.fprintf oc "\n")
    (by_block ?const acc)

(* never-changed bits, one line each, for classification; provably constant ones marked *)
let write_never ?const oc acc =
  List.iter (fun b ->
      if not (changed b) then
        Printf.fprintf oc "%-13s %s%s\n" (block_of b.info.file) (bit_name b) (if is_const const b then " CONSTANT" else ""))
    (bits acc)

(* ---- which register bits can never change: a three-valued fixpoint from reset ----

   Every signal is evaluated over {0, 1, unknown} (a value and a known-mask): inputs, memory read
   data and instantiation outputs are unknown; a register starts at its clear value if it has a
   synchronous clear (the reset is applied first) and unknown otherwise; each step joins the
   register's state with its next value. At the fixpoint the known bits of a register are
   constant in every reachable state, whatever the inputs: an over-approximation of the reachable
   states, so "known" is a proof and "unknown" is not a claim. Arithmetic with an unknown bit is
   taken as wholly unknown (sound, not precise: a counter that never exceeds 15 in a 5-bit
   register is not found here). *)
module T = struct
  type v = { v : Bits.t; k : Bits.t }   (* value, known mask *)

  let known_all x = Bits.(to_int (popcount x.k)) = Bits.width x.k
  let unknown w = { v = Bits.zero w; k = Bits.zero w }
  let const c = { v = c; k = Bits.ones (Bits.width c) }

  let join a b =
    let same = Bits.(a.k &: b.k &: ~:(a.v ^: b.v)) in
    { v = Bits.(a.v &: same); k = same }

  let equal a b = Bits.equal a.k b.k && Bits.equal Bits.(a.v &: a.k) Bits.(b.v &: b.k)
end

let constant_bits (c : Circuit.t) (infos : reg array) =
  let open Signal.Type in
  let uid s = Signal.Type.Uid.to_int (Signal.uid s) in
  let state : (int, T.v) Hashtbl.t = Hashtbl.create 4096 in
  let regs = ref [] in
  Signal_graph.iter (Circuit.signal_graph c) ~f:(fun s -> match s with Reg _ -> regs := s :: !regs | _ -> ());
  let memo : (int, T.v) Hashtbl.t = Hashtbl.create 65536 in
  let rec ev (s : Signal.t) : T.v =
    if Signal.is_empty s then T.unknown 1
    else
      match Hashtbl.find_opt memo (uid s) with
      | Some x -> x
      | None ->
        let w = Signal.width s in
        let r : T.v =
          match s with
          | Empty -> T.unknown w
          | Const { constant; _ } -> T.const constant
          | Not { arg; _ } -> let a = ev arg in { v = Bits.(~:(a.v)); k = a.k }
          | Wire { driver; _ } -> if Signal.is_empty !driver then T.unknown w else ev !driver
          | Select { arg; high; low; _ } -> let a = ev arg in { v = Bits.select a.v high low; k = Bits.select a.k high low }
          | Cat { args; _ } ->
            let l = List.map ev args in
            { v = Bits.concat_msb (List.map (fun (x : T.v) -> x.v) l); k = Bits.concat_msb (List.map (fun (x : T.v) -> x.k) l) }
          | Mux { select; cases; _ } ->
            let sel = ev select in
            let cs = Array.of_list cases in
            if T.known_all sel then ev cs.(min (Bits.to_int sel.v) (Array.length cs - 1))
            else (match List.map ev cases with x :: rest -> List.fold_left T.join x rest | [] -> T.unknown w)
          | Op2 { op; arg_a; arg_b; _ } ->
            let a = ev arg_a and b = ev arg_b in
            (match op with
             | Signal_and ->
               let k = Bits.((a.k &: b.k) |: (a.k &: ~:(a.v)) |: (b.k &: ~:(b.v))) in
               { v = Bits.(a.v &: b.v &: k); k }
             | Signal_or ->
               let k = Bits.((a.k &: b.k) |: (a.k &: a.v) |: (b.k &: b.v)) in
               { v = Bits.((a.v &: a.k) |: (b.v &: b.k)); k }
             | Signal_xor -> { v = Bits.(a.v ^: b.v); k = Bits.(a.k &: b.k) }
             | Signal_eq ->
               let both = Bits.(a.k &: b.k) in
               if Bits.(to_int (reduce ~f:( |: ) (bits_lsb (both &: (a.v ^: b.v)))) ) = 1 then T.const (Bits.gnd)
               else if T.known_all a && T.known_all b then T.const Bits.(a.v ==: b.v)
               else T.unknown 1
             | _ when T.known_all a && T.known_all b ->
               T.const
                 (match op with
                  | Signal_add -> Bits.(a.v +: b.v)
                  | Signal_sub -> Bits.(a.v -: b.v)
                  | Signal_mulu -> Bits.(a.v *: b.v)
                  | Signal_muls -> Bits.(a.v *+ b.v)
                  | Signal_lt -> Bits.(a.v <: b.v)
                  | _ -> assert false)
             | _ -> T.unknown w)
          | Reg _ -> (match Hashtbl.find_opt state (uid s) with Some x -> x | None -> T.unknown w)
          | Multiport_mem _ | Mem_read_port _ | Inst _ -> T.unknown w
        in
        if Bits.width r.v <> w || Bits.width r.k <> w then
          failwith (Printf.sprintf "Cov.constant_bits: width %d for a signal of width %d: %s" (Bits.width r.v) w
                      (Sexplib0.Sexp.to_string (Signal.sexp_of_t s)));
        Hashtbl.replace memo (uid s) r;
        r
  in
  (* an empty clear value means zero *)
  let clear_value s (r : Signal.Type.register) =
    if Signal.is_empty r.reg_clear_value then T.const (Bits.zero (Signal.width s)) else ev r.reg_clear_value in
  (* the start: clear values where there is a clear, else unknown *)
  List.iter (fun s ->
      match s with
      | Reg { register = r; _ } ->
        Hashtbl.replace state (uid s)
          (if Signal.is_empty r.reg_clear then T.unknown (Signal.width s)
           else (Hashtbl.reset memo; clear_value s r))
      | _ -> ())
    !regs;
  let changed = ref true and rounds = ref 0 in
  while !changed do
    changed := false;
    incr rounds;
    Hashtbl.reset memo;
    let nexts =
      List.map (fun s ->
          match s with
          | Reg { register = r; d; _ } ->
            let cur = Hashtbl.find state (uid s) in
            let dv = ev d in
            let en = if Signal.is_empty r.reg_enable then T.const Bits.vdd else ev r.reg_enable in
            let after_en = if T.known_all en then (if Bits.to_bool en.v then dv else cur) else T.join cur dv in
            let nxt =
              if Signal.is_empty r.reg_clear then after_en
              else
                let cl = ev r.reg_clear and cv = clear_value s r in
                if T.known_all cl then (if Bits.to_bool cl.v then cv else after_en) else T.join cv after_en in
            (s, T.join cur nxt)
          | _ -> assert false)
        !regs in
    List.iter (fun (s, n) -> if not (T.equal n (Hashtbl.find state (uid s))) then (changed := true; Hashtbl.replace state (uid s) n)) nexts
  done;
  (* per tapped bit: provably constant? *)
  let w = Array.fold_left (fun a i -> a + i.width) 0 infos in
  let out = Array.make w false in
  Array.iter (fun i ->
      match Hashtbl.find_opt state i.uid with
      | Some x ->
        if Bits.width x.k <> i.width then
          failwith (Printf.sprintf "Cov.constant_bits: register %d (%s, %s) is %d wide, its state %d" i.uid i.loc i.label i.width (Bits.width x.k));
        for b = 0 to i.width - 1 do out.(i.offset + b) <- Bits.to_bool (Bits.bit x.k b) done
      | None -> ())
    infos;
  (out, !rounds)
