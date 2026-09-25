let () =
  match Array.to_list Sys.argv with
  | _ :: "lockstep" :: rest -> Lockstep.main rest
  | _ -> prerr_endline "usage: main.exe lockstep [cycles]"
