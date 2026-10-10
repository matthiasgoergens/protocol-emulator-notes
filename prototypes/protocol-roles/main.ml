(* main.exe uart | ... : the checks of README.md, one command per task. *)
let () =
  let ok = match Array.to_list Sys.argv |> List.tl with
    | [ "uart" ] -> T_uart.run ()
    | [ "spi" ] -> T_spi.run_all ()
    | [ "i2c" ] -> T_i2c.run_all ()
    | [ "i2c-target" ] -> T_i2c_target.run_all ()
    | [ "spi-target" ] -> T_spi_target.run_all ()
    | [ "dump"; dir ] -> T_uart.dump dir && T_spi.dump dir && T_i2c.dump dir && T_i2c_target.dump dir && T_spi_target.dump dir
    | _ -> prerr_endline "usage: main.exe uart | spi | i2c | i2c-target | spi-target | dump DIR"; exit 2 in
  exit (if ok then 0 else 1)
