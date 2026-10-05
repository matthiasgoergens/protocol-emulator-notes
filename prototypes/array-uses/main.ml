let () =
  match Array.to_list Sys.argv with
  | _ :: "lockstep" :: rest -> Lockstep.main rest
  | _ :: "synth" :: rest -> Synth.main rest
  | _ :: "evaluate" :: rest -> Evaluate.main rest
  | _ :: "ddc" :: rest -> Ddc.main rest
  | _ -> prerr_endline "usage: main.exe (lockstep [cycles] | synth [seconds [dir]])"
