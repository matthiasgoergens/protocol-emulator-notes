(* The hazard checker (../hazard/hazard.ml) on the base-ISA programmes run on v2: the
   deadline-sequencer demo's UART, SPI and I2C threads, and the 10BASE-T transmitter (original
   and the fixed one of eth_fixed.ml). Declarations are written from the prototypes' own pin
   assignments (demo.ml: uart 0, sclk 1, mosi 2, cs 3, sda 4, scl 5; sequencer-ethernet: TD on
   pin 0, all four threads), not from what the checker infers. *)
open Hazard

let fetch_base mem = Compat.fetch_threads ~translate:Variant.translate mem
let g r t ks = (r, Thread t, ks)

let () =
  let bad = ref 0 in
  let expect_ok n = if n <> [] then incr bad in
  let mem, _ = Demo_lib.build () in
  let demo_decl = { no_decl with grants =
                                   [ g (Pin 0) 0 [ Pin_drive ]; g (Pin 1) 1 [ Pin_drive ]; g (Pin 2) 1 [ Pin_drive ]; g (Pin 3) 1 [ Pin_drive ];
                                     g (Pin 4) 2 [ Pin_drive; Pin_sample ]; g (Pin 5) 2 [ Pin_drive ] ] } in
  expect_ok (report ~name:"deadline-sequencer demo: T0 UART TX, T1 SPI master, T2 I2C master write" ~fetch:(fetch_base mem) demo_decl);
  let eth_decl = { no_decl with grants = List.init 4 (fun t -> g (Pin 0) t [ Pin_drive ]);
                                shared = [ (Pin 0, List.init 4 (fun t -> Thread t)) ] } in
  let eth_mem = Array.init 4 Eth_fw.program in
  expect_ok (report ~name:"10BASE-T TX (original), pin 0 declared a four-thread time-division group" ~fetch:(fetch_base eth_mem) eth_decl);
  let fixed = Array.init 4 (fun t -> Eth_fixed.program_fixed t) in
  let fetch_fixed a = let t = a lsr 8 and pc = a land 0xFF in if pc < Array.length fixed.(t) then fixed.(t).(pc) else Isa2.nop in
  expect_ok (report ~name:"10BASE-T TX (fixed, with the underrun path)" ~fetch:fetch_fixed eth_decl);
  (* load-bearing entries: without the time-division entry, or without the declaration, the
     Ethernet transmitter must be rejected *)
  let no_tdm = without_pairs (fun (a, b, _, s) -> a = Pin_drive && b = Pin_drive && s) default_tables in
  let r1 = report ~tables:no_tdm ~name:"control: 10BASE-T TX with the time-division table entry removed (must be rejected)" ~fetch:(fetch_base eth_mem) eth_decl in
  if r1 = [] then incr bad;
  let r2 = report ~name:"control: 10BASE-T TX without the sharing declaration (must be rejected)" ~fetch:(fetch_base eth_mem) { eth_decl with shared = [] } in
  if r2 = [] then incr bad;
  let r3 = report ~name:"control: the demo with SPI's cs (pin 3) granted to T0 instead (must be rejected)"
      ~fetch:(fetch_base mem) { demo_decl with grants = List.map (fun (r, a, k) -> if r = Pin 3 then (r, Thread 0, k) else (r, a, k)) demo_decl.grants } in
  if r3 = [] then incr bad;
  Printf.printf "HAZARD BASE %s\n" (if !bad = 0 then "PASS" else "FAIL")
