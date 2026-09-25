let pr = Printf.printf

let lockstep trials run_cycles =
  Upe_rtl.bug := "";
  let total = ref 0 and bad = ref 0 in
  List.iteri
    (fun mi mode ->
      let r = Lockstep.campaign ~stop:false ~mode ~seed:(1000 + mi) ~trials ~run_cycles () in
      total := !total + r.cycles;
      (match r.first_fail with
       | None -> pr "%-9s %4d trials %8d cycles  0 mismatches\n" mode r.trials r.cycles
       | Some (t, c, d) ->
         incr bad;
         pr "%-9s MISMATCH in trial %d at cycle %d:\n  %s\n" mode t c (String.concat "\n  " d));
      flush stdout)
    Lockstep.modes;
  pr "total %d cycles compared, %d generators with mismatches\n" !total !bad

let controls trials run_cycles =
  let caught = ref 0 in
  List.iter
    (fun (b, what) ->
      Upe_rtl.bug := b;
      (* uniform alone first, to show what the biased generators add *)
      let u = Lockstep.campaign ~mode:"uniform" ~seed:7 ~trials ~run_cycles () in
      let uniform = match u.first_fail with Some (_, c, _) -> Printf.sprintf "%d" c | None -> "missed" in
      let modes = List.filter (fun m -> m <> "uniform") Lockstep.modes in
      let hits =
        List.filter_map
          (fun m ->
            let r = Lockstep.campaign ~mode:m ~seed:11 ~trials ~run_cycles () in
            Option.map (fun (_, c, d) -> (c, m, List.hd d)) r.first_fail)
          modes
      in
      (match List.sort compare hits with
       | (c, m, d) :: _ ->
         incr caught;
         pr "%-20s uniform: %-7s fastest biased: %-8s %6d cycles; %2d of %d biased generators catch it  (%s)\n    first diff: %s\n"
           b uniform m c (List.length hits) (List.length modes) what d
       | [] ->
         if u.first_fail <> None then incr caught;
         pr "%-20s uniform: %-7s biased: MISSED  (%s)\n" b uniform what);
      flush stdout)
    Upe_rtl.bugs;
  Upe_rtl.bug := "";
  pr "%d of %d planted bugs caught\n" !caught (List.length Upe_rtl.bugs)

let coverage trials run_cycles =
  let tabs = List.map (fun m -> (m, Lockstep.coverage ~mode:m ~seed:5 ~trials ~run_cycles)) Lockstep.modes in
  let events =
    List.sort_uniq compare (List.concat_map (fun (_, h) -> Hashtbl.fold (fun k _ acc -> k :: acc) h []) tabs)
  in
  pr "%-16s" "event";
  List.iter (fun (m, _) -> pr " %8s" m) tabs;
  pr "\n";
  List.iter
    (fun e ->
      pr "%-16s" e;
      List.iter (fun (_, h) -> pr " %8d" (Option.value ~default:0 (Hashtbl.find_opt h e))) tabs;
      pr "\n")
    events

let () =
  match Array.to_list Sys.argv with
  | [ _; "verilog-pe" ] -> Hardcaml.Rtl.print Verilog (Upe_rtl.pe_circuit ())
  | [ _; "verilog-array" ] -> Hardcaml.Rtl.print Verilog (Upe_rtl.array_circuit ~state_ports:false ())
  | [ _; "lockstep"; n; c ] -> lockstep (int_of_string n) (int_of_string c)
  | [ _; "controls"; n; c ] -> controls (int_of_string n) (int_of_string c)
  | [ _; "coverage"; n; c ] -> coverage (int_of_string n) (int_of_string c)
  | [ _; "cells" ] -> Cells.run_all ()
  | _ -> prerr_endline "usage: main.exe verilog-pe | verilog-array | lockstep N C | controls N C | coverage N C | cells"
