let () =
  (try Unix.mkdir "out" 0o755 with _ -> ());
  match Array.to_list Sys.argv with
  | [ _; "pecheck" ] -> exit (if Pecheck.main () then 0 else 1)
  | [ _; "check" ] -> exit (if Check.main () then 0 else 1)
  | [ _; "latency" ] -> Latency_check.main ()
  | [ _; "rtltiming" ] -> print_string (Pins.timing ())
  | [ _; "palette" ] -> print_string (Sim.print_stats (Pins.palette ()))
  | [ _; "preview"; n; e ] -> Preview.run ~fields:(int_of_string n) ~every:(int_of_string e)
  | [ _; "game"; n ] ->
    let t0 = Unix.gettimeofday () in
    let st, lines, bad = Pins.dump ~desc:Game.desc ~fields:(int_of_string n) ~lut:Game.lut ~packet:Game.packet ~name:"game" () in
    Printf.printf "game, %s fields through the RTL (%.0f s): %d visible lines compared with the reference renderer, %d pixels differ\n"
      n (Unix.gettimeofday () -. t0) lines bad;
    print_string (Sim.print_stats st);
    List.iter print_endline (List.rev !Game.events)
  | [ _; "verilog"; name ] -> Synth_circuits.write name
  | [ _; "modelcheck" ] -> exit (if Chipmodel.main () then 0 else 1)
  | [ _; "timing" ] -> print_string (Vprog.check ())
  | _ -> prerr_endline "usage: main (pecheck | ...)"; exit 2
