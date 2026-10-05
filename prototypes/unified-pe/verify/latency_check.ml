(* The latency lint as a regression test ([main.exe latency], run by [dune test]; stdout must
   match latency.expected, accept a reviewed change with [dune promote]).

   The video configurations (sprites, tiles: see README.md) are configurations of this array,
   loaded through its chains at run time, so the lint sees only the hardware they run on.  With
   [hold_registers] it has no findings; with default settings it reports 183 (array) and 2 (one
   PE), all measured from the configuration and initialisation chains and the mailbox-loaded
   feed registers, which hold their values while a configuration runs.  How a configuration
   aligns a pixel with its valid flag is data in the chains, which a structural lint cannot see.

   There is no planted control: the array has no fixed sync or blank path to remove a register
   from; a configuration decides which lanes carry pixels and valids. *)
let main () =
  let config = Latency_ci.hold in
  List.iter
    (fun (title, c) -> Latency_ci.print ~title ~config (Latency_ci.lint ~config c))
    [ "upe_array", Upe_rtl.array_circuit ~state_ports:false ()
    ; "upe_v1 (one PE)", Upe_rtl.pe_circuit () ];
  Latency_ci.exit ()
