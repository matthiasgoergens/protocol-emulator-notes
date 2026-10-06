(* Where every signal of the chip comes from, for reading timing reports.
   [origins.exe VERILOG MAP [macros|regs] [SIZES] [PROG_WORDS]] writes the same Verilog as emit.exe
   and MAP, one line per signal: its Verilog name (a given name, or "_UID" for an anonymous one, as
   Hardcaml prints it), the kind (reg, mem, inst, comb), its width, and the OCaml call sites that
   built it, innermost first, outside Hardcaml and the standard library.  A netlist net such as
   chip._1673 is then the signal _1673 of this map. *)
open Hardcaml

let ours (f : string) =
  let skip = [ "hardcaml"; "stdlib"; "base/"; "camlinternal"; "list.ml"; "array.ml"; "comb.ml"; "signal.ml";
               "always.ml"; "interface.ml"; "scope.ml"; "caller_id.ml"; "signal__type.ml"; "bits.ml"; "with_valid.ml" ] in
  not (List.exists (fun s -> let n = String.length s in
                     let rec go i = i + n <= String.length f && (String.sub f i n = s || go (i + 1)) in go 0) skip)

let () =
  Caller_id.set_mode Full_trace;
  let arg i d = if Array.length Sys.argv > i then Sys.argv.(i) else d in
  let vfile = arg 1 "chip_tt.v" and mfile = arg 2 "chip_tt.map" in
  let memories = match arg 3 "macros" with "macros" -> `Macros | "regs" -> `Behavioural | m -> failwith ("memories: " ^ m) in
  let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' (arg 4 "1,1,1,1"))) in
  let prog_words = int_of_string (arg 5 "512") in
  let cfg = { Chip_spec.layout = Upe.Spec.layout_of_sizes sizes; prog_words } in
  Chip_rtl.bug := "";
  let c = Tt_top.create ~cfg ~memories ~name:"chip_tt" () in
  let oc = open_out vfile in
  Rtl.output ~output_mode:(To_channel oc) Verilog c;
  close_out oc;
  let oc = open_out mfile in
  let frames s =
    match Signal.Type.caller_id s with
    | None -> []
    | Some id ->
      let rec atoms (x : Sexplib0.Sexp.t) = match x with Atom a -> [ a ] | List l -> List.concat_map atoms l in
      atoms (Caller_id.sexp_of_t id) |> List.filter ours
      |> List.fold_left (fun acc f -> if List.mem f acc then acc else f :: acc) [] |> List.rev
  in
  Signal_graph.iter (Circuit.signal_graph c) ~f:(fun s ->
      let kind = match s with
        | Signal.Type.Reg _ -> "reg" | Multiport_mem _ -> "mem" | Inst _ -> "inst" | Mem_read_port _ -> "memrd"
        | Wire _ -> "wire" | Const _ -> "const" | _ -> "comb" in
      if kind <> "const" && not (Signal.is_empty s) then
        let name = match Signal.names s with n :: _ -> n | [] -> "_" ^ Signal.Type.Uid.to_string (Signal.uid s) in
        Printf.fprintf oc "%s\t%s\t%d\t%s\n" name kind (Signal.width s) (String.concat " " (frames s)));
  close_out oc
