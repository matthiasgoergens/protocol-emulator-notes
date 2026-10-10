(* main.exe uart | ... : the checks of README.md, one command per task. *)
let () =
  let ok = match Array.to_list Sys.argv |> List.tl with
    | [ "uart" ] -> T_uart.run ()
    | [ "spi" ] -> T_spi.run_all ()
    | [ "dump"; dir ] -> T_uart.dump dir && T_spi.dump dir
    | _ -> prerr_endline "usage: main.exe uart | spi | dump DIR"; exit 2 in
  exit (if ok then 0 else 1)
