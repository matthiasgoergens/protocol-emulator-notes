(* The hazard checker on multi-proto's bridge A as ported to v2 (UART <-> I2C through inboxes,
   SPI master as an unrelated neighbour), assembled exactly as ../../sequencer-v2/ports/
   multi-proto/bridge_a.ml assembles it. Declarations from bridge_a.ml's header: T0 UART RX (pin
   0 in, RTS pin 2 out) -> inbox 1; T1 I2C master (SDA 3, SCL 4, both read back for clock
   stretching and acks) <- inbox 1, -> inbox 2; T2 UART TX (pin 1) <- inbox 2; T3 SPI master on
   pins 5..7. *)
open Hazard
open Bridge_lib

let g r t ks = (r, Thread t, ks)

let () =
  let (t0, _, _), (t1, _, _), (t2, _, _) =
    uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx:1 ~own:2 () in
  let t3 = Asm.of_base ~loop:true (Compiler.spi_master { sclk = 5; mosi = 6; cs = 7; period = 12; sbytes = [ 0x96 ] }) ~plen:128 in
  let mem = [| t0; t1; t2; t3 |] in
  let fetch a = let t = a lsr 8 and pc = a land 0xFF in if pc < Array.length mem.(t) then mem.(t).(pc) else Isa2.nop in
  let d = { no_decl with grants =
                           [ g (Pin 0) 0 [ Pin_sample ]; g (Pin 2) 0 [ Pin_drive ]; g (Inbox 1) 0 [ Send_k; Space_wait ];
                             g (Pin 3) 1 [ Pin_drive; Pin_sample ]; g (Pin 4) 1 [ Pin_drive; Pin_sample ];
                             g (Inbox 1) 1 [ Recv_k; Poll ]; g (Inbox 2) 1 [ Send_k; Space_wait ];
                             g (Pin 1) 2 [ Pin_drive ]; g (Inbox 2) 2 [ Recv_k; Poll ];
                             g (Pin 5) 3 [ Pin_drive ]; g (Pin 6) 3 [ Pin_drive ]; g (Pin 7) 3 [ Pin_drive ] ] } in
  let f = report ~name:"bridge A on v2: T0 UART RX -> inbox 1 -> T1 I2C master -> inbox 2 -> T2 UART TX; T3 SPI neighbour" ~fetch d in
  Printf.printf "bridge A: %d rejected combination(s): T1's answer SENDs to inbox 2 have fail = their own address\n\n" (List.length f);
  (* the drain argument: T2's only wait that can last for ever is its RECV on inbox 2 *)
  let other = unbounded_waits ~fetch ~decl:d 2 ~except:[ Inbox 2 ] in
  Printf.printf "evidence for a waiver: T2's unbounded waits other than RECV on inbox 2: [%s]\n\n" (String.concat "; " other);
  let why = "T2 (UART TX) drains inbox 2: its only unbounded wait is that RECV (checked above), its loops are JNZ \
             countdowns, so a blocked SEND waits at most one UART byte (10 bits of 64 clocks); argued, not proved" in
  let f2 = report ~name:"bridge A with T1's inbox-2 SENDs waived by that argument" ~fetch
      { d with waivers = [ (Inbox 2, Thread 1, Send_k, why) ] } in
  Printf.printf "HAZARD BRIDGE %s (unwaived: %d rejections, the finding; waived: %d)\n"
    (if f <> [] && f2 = [] && other = [] then "PASS" else "FAIL") (List.length f) (List.length f2)

let () =
  let (_, _, _), (t1, _, _), (_, _, _) =
    uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx:1 ~own:2 () in
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "disasm" then
    Array.iteri (fun i w -> Printf.printf "T1 %3d %04x %s\n" i w (Isa2.disasm w)) t1
