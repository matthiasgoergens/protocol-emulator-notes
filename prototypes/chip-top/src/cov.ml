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

(* accumulated over every simulation of one instrumented circuit *)
type acc = { infos : reg array; mutable rose : Bits.t; mutable fell : Bits.t; mutable clocks : int }

let create_acc infos =
  let w = Array.fold_left (fun a i -> a + i.width) 0 infos in
  { infos; rose = Bits.zero w; fell = Bits.zero w; clocks = 0 }

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

(* per block: bits, bits that changed, bits that both rose and fell *)
let by_block (acc : acc) =
  let t = Hashtbl.create 16 in
  List.iter (fun b ->
      let k = block_of b.info.file in
      let n, c, f = Option.value (Hashtbl.find_opt t k) ~default:(0, 0, 0) in
      Hashtbl.replace t k (n + 1, (c + if changed b then 1 else 0), (f + if b.rose && b.fell then 1 else 0)))
    (bits acc);
  List.sort compare (Hashtbl.fold (fun k v l -> (k, v) :: l) t [])

let report ?(oc = stdout) ~title (acc : acc) =
  let all = bits acc in
  let n = List.length all and c = List.length (List.filter changed all) in
  let f = List.length (List.filter (fun b -> b.rose && b.fell) all) in
  Printf.fprintf oc "%s: %d clocks; register bits that changed %d of %d (%.1f %%), rose and fell %d\n" title acc.clocks c n
    (100. *. float c /. float (max n 1)) f;
  List.iter (fun (k, (n, c, f)) ->
      Printf.fprintf oc "  %-13s %5d of %5d changed (%5.1f %%), %5d rose and fell\n" k c n (100. *. float c /. float (max n 1)) f)
    (by_block acc)

(* never-changed bits, one line each, for classification *)
let write_never oc acc =
  List.iter (fun b -> if not (changed b) then Printf.fprintf oc "%-13s %s\n" (block_of b.info.file) (bit_name b)) (bits acc)
