let () =
  (try Unix.mkdir "out" 0o755 with _ -> ());
  match Array.to_list Sys.argv with
  | [ _; "pecheck" ] -> exit (if Pecheck.main () then 0 else 1)
  | _ -> prerr_endline "usage: main (pecheck | ...)"; exit 2
