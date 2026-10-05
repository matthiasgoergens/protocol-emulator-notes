(* Structural checks on an extracted netlist, run before any simulation.

   The lesson from the puzzle chip: it shipped with a floating net, which a
   SAT solver treats as a free variable and a simulator reads as 0, so both
   kinds of tool quietly agree with a broken chip.  Hence every net must have
   exactly one driver, and every cell input and output port must sit on a
   driven net, and that is checked here, explicitly, first. *)

type dir = In | Out

(* Port names and directions from the RTL's Verilog module header, expanded
   to one entry per bit, named the way the layout labels them: "pin_in[3]". *)
let rtl_ports (path : string) : (string * dir) list =
  let ic = open_in path in
  let acc = ref [] in
  (try
     while true do
       let line = String.trim (input_line ic) in
       let words = String.split_on_char ' ' line |> List.filter (( <> ) "") in
       let strip s = if String.ends_with ~suffix:";" s then String.sub s 0 (String.length s - 1) else s in
       let add dir width name =
         if width = 1 then acc := (name, dir) :: !acc
         else for i = 0 to width - 1 do acc := (Printf.sprintf "%s[%d]" name i, dir) :: !acc done
       in
       let width_of r = Scanf.sscanf r "[%d:%d]" (fun hi lo -> hi - lo + 1) in
       match words with
       | [ ("input" | "output") as d; r; n ] when r.[0] = '[' ->
         add (if d = "input" then In else Out) (width_of r) (strip n)
       | [ ("input" | "output") as d; n ] -> add (if d = "input" then In else Out) 1 (strip n)
       | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  List.rev !acc

let power_ports = [ "VPWR"; "VGND"; "VDD"; "VSS" ]

type report = {
  errors : string list;
  warnings : string list;
  stats : (string * int) list;
}

let run ~(lib : (string, Cells.cell) Hashtbl.t) ~(ports : (string * dir) list)
    ~(clock : string) (nl : Extract.netlist) : report =
  let errors = ref [] and warnings = ref [] in
  let err fmt = Printf.ksprintf (fun s -> errors := s :: !errors) fmt in
  let warn fmt = Printf.ksprintf (fun s -> warnings := s :: !warnings) fmt in
  let n = nl.nnets in
  let drivers = Array.make n [] and sinks = Array.make n [] in
  let power_net = Array.make n None in
  List.iter (fun u -> err "unresolved label: %s" u) nl.unresolved;
  List.iter (fun (l, d, c) -> err "%d shapes in the top cell on layer %d/%d, which the extractor does not follow" c l d)
    nl.foreign_layers;
  (* ports: every RTL port bit must be a label in the layout, and back *)
  let layout_ports = Hashtbl.create 64 in
  List.iter (fun (p, net) -> Hashtbl.replace layout_ports p net) nl.ports;
  List.iter (fun (p, d) ->
    match Hashtbl.find_opt layout_ports p with
    | None -> err "port %s: in the RTL, no label in the layout" p
    | Some None -> ()
    | Some (Some net) ->
      (match d with
       | In -> drivers.(net) <- ("port " ^ p) :: drivers.(net)
       | Out -> sinks.(net) <- ("port " ^ p) :: sinks.(net)))
    ports;
  List.iter (fun (p, net) ->
    if List.mem p power_ports then Option.iter (fun x -> power_net.(x) <- Some p) net
    else if not (List.mem_assoc p ports) then err "port %s: labelled in the layout, not in the RTL" p)
    nl.ports;
  (* cell pins *)
  let ncells = Hashtbl.create 32 in
  Array.iter (fun (inst : Extract.inst) ->
    Hashtbl.replace ncells inst.icell (1 + Option.value ~default:0 (Hashtbl.find_opt ncells inst.icell));
    match Hashtbl.find_opt lib inst.icell with
    | None -> err "%s: cell %s has no functional model" inst.iname inst.icell
    | Some cell ->
      Option.iter (fun why -> err "%s: %s not supported (%s)" inst.iname inst.icell why) cell.unsupported;
      let pins = cell.inputs @ cell.outputs in
      List.iter (fun p ->
        if not (List.mem_assoc p inst.nets) then err "%s/%s: pin %s has no label in the cell layout" inst.iname inst.icell p)
        pins;
      List.iter (fun (p, net) ->
        let who = Printf.sprintf "%s/%s.%s" inst.iname inst.icell p in
        if not (List.mem p pins) then warn "%s: labelled pin not in the model" who
        else match net with
          | None -> if List.mem p cell.inputs then err "floating input (no metal under the pin): %s" who
          | Some x ->
            if List.mem p cell.outputs then drivers.(x) <- who :: drivers.(x)
            else sinks.(x) <- who :: sinks.(x))
        inst.nets)
    nl.instances;
  let undriven = ref 0 and multi = ref 0 and dangling = ref 0 and floating_in = ref 0 in
  for x = 0 to n - 1 do
    match power_net.(x) with
    | Some p ->
      List.iter (fun w -> err "signal pin on the %s supply net: %s" p w) (drivers.(x) @ sinks.(x))
    | None ->
      (match drivers.(x), sinks.(x) with
       | [], [] -> ()
       | [], ss ->
         incr undriven;
         floating_in := !floating_in + List.length ss;
         err "undriven net n%d, read by %d: %s" x (List.length ss)
           (String.concat ", " (List.filteri (fun i _ -> i < 4) ss))
       | [ _ ], [] -> incr dangling
       | [ _ ], _ -> ()
       | ds, _ ->
         incr multi;
         err "net n%d has %d drivers: %s" x (List.length ds) (String.concat ", " ds))
  done;
  (* clock: every flip-flop's clock pin must lead back to the clock port
     through buffers and inverters only, with an even number of inversions *)
  let clock_net = Option.join (List.assoc_opt clock nl.ports) in
  let driver_inst = Hashtbl.create 1024 in
  Array.iter (fun (inst : Extract.inst) ->
    match Hashtbl.find_opt lib inst.icell with
    | Some cell ->
      List.iter (fun (p, net) ->
        match net with
        | Some x when List.mem p cell.outputs -> Hashtbl.replace driver_inst x (inst, cell)
        | _ -> ()) inst.nets
    | None -> ()) nl.instances;
  let rec trace net depth inversions =
    if Some net = clock_net then Ok inversions
    else if depth > 64 then Error "clock path longer than 64 cells"
    else match Hashtbl.find_opt driver_inst net with
      | None -> Error (Printf.sprintf "n%d is not driven" net)
      | Some (inst, cell) ->
        (match cell.ffs, Array.to_list cell.gates, cell.inputs with
         | [], [ { gprim = (Buf | Not) as g; _ } ], [ a ] ->
           (match List.assoc_opt a inst.nets with
            | Some (Some up) -> trace up (depth + 1) (inversions + if g = Not then 1 else 0)
            | _ -> Error (inst.iname ^ ": input unconnected"))
         | [], [ { gprim = Not; _ }; { gprim = Buf; _ } ], [ a ] | [], [ { gprim = Buf; _ }; { gprim = Not; _ } ], [ a ] ->
           (match List.assoc_opt a inst.nets with
            | Some (Some up) -> trace up (depth + 1) (inversions + 1)
            | _ -> Error (inst.iname ^ ": input unconnected"))
         | _ -> Error (Printf.sprintf "clock passes through %s (%s), not a buffer" inst.iname inst.icell))
  in
  let nff = ref 0 and clock_buffers = Hashtbl.create 64 in
  Array.iter (fun (inst : Extract.inst) ->
    match Hashtbl.find_opt lib inst.icell with
    | Some cell when cell.ffs <> [] ->
      List.iter (fun (f : Cells.ff) ->
        incr nff;
        (* the simulator clocks every flip-flop on the rising edge of the
           clock port: that needs the model's flip-flop clock to be the
           cell's clock input itself (rising edge, ihp_dff_* table), and
           the path from the port to have no net inversion (below) *)
        if not (List.mem f.clk cell.inputs) then
          err "%s: %s clocks its flip-flop from an internal wire %s" inst.iname inst.icell f.clk;
        match List.assoc_opt f.clk inst.nets with
        | Some (Some net) ->
          Hashtbl.replace clock_buffers net ();
          (match trace net 0 0 with
           | Ok inv when inv mod 2 = 0 -> ()
           | Ok _ -> err "%s: clock arrives inverted" inst.iname
           | Error e -> err "%s: clock pin %s: %s" inst.iname f.clk e)
        | _ -> err "%s: clock pin %s unconnected" inst.iname f.clk) cell.ffs
    | _ -> ()) nl.instances;
  if clock_net = None then err "no clock port %s" clock;
  let stats =
    [ ("instances", Array.length nl.instances); ("nets", n); ("flip-flops", !nff);
      ("undriven nets", !undriven); ("pins on undriven nets", !floating_in);
      ("multiply driven nets", !multi); ("driven nets nobody reads", !dangling);
      ("unresolved labels", List.length nl.unresolved) ]
    @ (Hashtbl.fold (fun c k acc -> ("cell " ^ c, k) :: acc) ncells [] |> List.sort compare)
  in
  { errors = List.rev !errors; warnings = List.rev !warnings; stats }
