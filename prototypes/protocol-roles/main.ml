(* main.exe uart | ... : the checks of README.md, one command per task. *)
let () =
  let ok = match Array.to_list Sys.argv |> List.tl with
    | [ "uart" ] -> T_uart.run ()
    | [ "dump"; dir ] -> T_uart.dump dir
    | _ -> prerr_endline "usage: main.exe uart"; exit 2 in
  exit (if ok then 0 else 1)
