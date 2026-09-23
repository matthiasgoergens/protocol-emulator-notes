let () =
  match Array.to_list Sys.argv with
  | [ _; "check"; frames ] ->
    (* forward-differenced ring model against direct evaluation, every pixel *)
    let bad = ref 0 and tot = ref 0 in
    for t = 0 to int_of_string frames - 1 do
      let c = Model.cfg_at t in
      let img = Model.render c ~inits:(Model.inits_at t) and ref_ = Model.reference t in
      Array.iteri (fun y row -> Array.iteri (fun x v -> incr tot; if v <> ref_.(y).(x) then begin
        if !bad < 5 then Printf.printf "frame %d (%d,%d): ring %d reference %d\n" t x y v ref_.(y).(x);
        incr bad end) row) img
    done;
    Printf.printf "%d of %d pixels differ; %d saturating results\n" !bad !tot (Atomic.get Model.saturations)
  | [ _; "controls" ] ->
    (* planted faults must be caught; and the picture must actually contain all three shapes *)
    let diff mutate =
      let d = ref 0 in
      for t = 0 to 9 do
        let c = Model.cfg_at t in mutate c;
        let img = Model.render c ~inits:(Model.inits_at t) and r = Model.reference t in
        Array.iteri (fun y row -> Array.iteri (fun x v -> if v <> r.(y).(x) then incr d) row) img
      done; !d in
    List.iter (fun (name, f) -> Printf.printf "%-40s %7d pixels differ\n" name (diff f))
      [ "no fault", (fun _ -> ());
        "G = max instead of min", (fun c -> c.op.(7) <- 2);
        "Q3 reads D1 instead of D3", (fun c -> c.ys.(8) <- 2);
        "ellipse second difference 3", (fun c -> c.k.(1) <- 3);
        "wiggle third difference + 1", (fun c -> c.k.(5) <- c.k.(5) + 1);
        "Fb reads D2 instead of D1", (fun c -> c.ys.(3) <- 1) ];
    let h = Array.make 16 0 in
    for t = 0 to 59 do
      Array.iter (Array.iter (fun v -> h.(v) <- h.(v) + 1)) (Model.reference t) done;
    Printf.printf "palette index histogram over 60 frames: %s\n"
      (String.concat " " (Array.to_list (Array.map string_of_int h)))
  | [ _; "rtlcheck"; fields ] ->
    let f = int_of_string fields in
    let bad, tot = Tb.lockstep f in
    Printf.printf "RTL vs model: %d of %d samples differ\n%!" bad tot;
    let bad, tot = Tb.lockstep ~fault:true 1 in
    Printf.printf "planted fault (cell 7 min -> max): %d of %d samples differ\n" bad tot
  | [ _; "dump"; fields; prefix ] -> Tb.dump ~fields:(int_of_string fields) ~prefix
  | [ _; "verilog" ] ->
    Hardcaml.Rtl.print Verilog (Ring_rtl.circuit ())
  | _ -> prerr_endline "usage: main check FRAMES"
