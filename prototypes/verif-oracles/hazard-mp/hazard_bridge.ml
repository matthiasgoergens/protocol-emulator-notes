(* The hazard checker on multi-proto's bridge A as ported to v2 (UART <-> I2C through inboxes,
   SPI master as an unrelated neighbour), assembled exactly as ../../sequencer-v2/ports/
   multi-proto/bridge_a.ml assembles it. Declarations from bridge_a.ml's header: T0 UART RX (pin
   0 in, RTS pin 2 out) -> inbox 1; T1 I2C master (SDA 3, SCL 4, both read back for clock
   stretching and acks) <- inbox 1, -> inbox 2; T2 UART TX (pin 1) <- inbox 2; T3 SPI master on
   pins 5..7. The inboxes are declared as resource ownership (../../sequencer-v2/ownership.ml):
   T0 sends to inbox 1, T1 receives from it and sends to inbox 2, T2 receives from inbox 2; no
   thread owns any bank address or port. Bridge B (UART <-> SPI master) is checked below with its
   SPI pins moved, because v2's SHX takes the capture pin as the pin below the output pin. *)
open Hazard
open Bridge_lib

let g r t ks = (r, Thread t, ks)
let nothing = Ownership.nothing
let bridge_owns () =
  [| { nothing with inbox_send = [ 1 ] }; { nothing with inbox_recv = [ 1 ]; inbox_send = [ 2 ] };
     { nothing with inbox_recv = [ 2 ] }; nothing |]
let fetch_of mem a = let t = a lsr 8 and pc = a land 0xFF in if pc < Array.length mem.(t) then mem.(t).(pc) else Isa2.nop

let () =
  let (t0, _, _), (t1, _, _), (t2, _, _) =
    uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx:1 ~own:2 () in
  let t3 = Asm.of_base ~loop:true (Compiler.spi_master { sclk = 5; mosi = 6; cs = 7; period = 12; sbytes = [ 0x96 ] }) ~plen:128 in
  let mem = [| t0; t1; t2; t3 |] in
  let fetch a = let t = a lsr 8 and pc = a land 0xFF in if pc < Array.length mem.(t) then mem.(t).(pc) else Isa2.nop in
  let d = { no_decl with grants =
                           [ g (Pin 0) 0 [ Pin_sample ]; g (Pin 2) 0 [ Pin_drive ];
                             g (Pin 3) 1 [ Pin_drive; Pin_sample ]; g (Pin 4) 1 [ Pin_drive; Pin_sample ];
                             g (Pin 1) 2 [ Pin_drive ];
                             g (Pin 5) 3 [ Pin_drive ]; g (Pin 6) 3 [ Pin_drive ]; g (Pin 7) 3 [ Pin_drive ] ];
                         owns = bridge_owns () } in
  print_endline (Ownership.describe d.owns);
  let f = report ~name:"bridge A on v2: T0 UART RX -> inbox 1 -> T1 I2C master -> inbox 2 -> T2 UART TX; T3 SPI neighbour" ~fetch d in
  Printf.printf "bridge A: %d rejected combination(s), no waiver (bridge_lib's i2c_master now answers into inbox 2 with \
                 LDD 4095; SEND ch2 -> replylost)\n\n" (List.length f);
  (* control: T1 as it was before the fix, rebuilt by pointing every SEND to inbox 2 back at itself
     (fail = own address); the checker must reject exactly those *)
  let is_send2 w = (w lsr 12) land 15 = 13 && (w lsr 11) land 1 = 0 && (w lsr 8) land 7 = 2 in
  let t1_old = Array.mapi (fun pc w -> if is_send2 w then Isa2.send ~ch:2 ~fail:pc else w) t1 in
  let n_send2 = Array.fold_left (fun n w -> if is_send2 w then n + 1 else n) 0 t1 in
  let mem_old = [| t0; t1_old; t2; t3 |] in
  let fetch_old a = let t = a lsr 8 and pc = a land 0xFF in if pc < Array.length mem_old.(t) then mem_old.(t).(pc) else Isa2.nop in
  let f_old = report ~name:"control: the same with T1's SENDs to inbox 2 made fail = own address (the code before the fix)" ~fetch:fetch_old d in
  Printf.printf "control: %d SEND(s) to inbox 2 in T1; with fail = own address the checker rejects %d\n\n" n_send2 (List.length f_old);
  (* planted ownership violations in the real firmware: each replaces one reachable word *)
  let planted name t pc w =
    let m = Array.map Array.copy mem in
    m.(t).(pc) <- w;
    let r = report ~name:(Printf.sprintf "control: %s (must be rejected)" name) ~fetch:(fetch_of m) d in
    (name, r <> []) in
  let t3_first = 0 in
  let plants = [
    planted "T3 (the SPI neighbour) also receives from inbox 2, stealing T2's bytes" 3 t3_first (Isa2.recv ~ch:2 ~fail:t3_first);
    planted "T3 sends into inbox 1, T1's command stream" 3 t3_first (Isa2.send ~ch:1 ~fail:(t3_first + 1));
    planted "T3 reads the bank (LDB), which nobody owns" 3 t3_first Isa2.ldb;
    planted "T2 sends to out-port 0 (channel 4), which nobody owns" 2 0 (Isa2.send ~ch:4 ~fail:1);
  ] in
  List.iter (fun (n, caught) -> Printf.printf "planted: %-75s %s\n" n (if caught then "caught" else "MISSED")) plants;
  let all_caught = List.for_all snd plants in
  Printf.printf "\nHAZARD BRIDGE %s (bridge A accepted without a waiver: %d rejections; control: %d of %d sends rejected; \
                 ownership plants caught: %d of %d)\n"
    (if f = [] && n_send2 > 0 && List.length f_old = n_send2 && all_caught then "PASS" else "FAIL") (List.length f) (List.length f_old) n_send2
    (List.length (List.filter snd plants)) (List.length plants)

(* Bridge B (UART <-> SPI master, an I2C master loop as the unrelated neighbour). The v2 port
   (../../sequencer-v2/ports/multi-proto) covers bridge A only, and v2's SHX takes its capture pin
   as the pin below the output pin, so bridges.ml's layout (MOSI 3, MISO 4) does not assemble.
   The SPI master is therefore placed on SCLK 4, MOSI 3, MISO 2, CS 5; the code is otherwise the
   one bridges.ml runs. Declarations: T0 UART RX (pin 0, no RTS) -> inbox 1; T1 SPI master
   <- inbox 1, -> inbox 2; T2 UART TX (pin 1) <- inbox 2; T3 I2C master write loop on pins 6, 7. *)
let () =
  let (t0, _, _), (t1, _, _), (t2, _, _) =
    uart_rx ~rx:0 ~rts:None ~dst:1 (), spi_master ~sclk:4 ~mosi:3 ~miso:2 ~cs:5 ~own:1 ~reply:2 (), uart_tx ~tx:1 ~own:2 () in
  let t3 = Asm.of_base ~loop:true (Compiler.i2c_write { sda = 6; scl = 7; q = 4; ibytes = [ 0xA0; 0x3C ] }) ~plen:128 in
  let d = { no_decl with grants =
                           [ g (Pin 0) 0 [ Pin_sample ];
                             g (Pin 2) 1 [ Pin_sample ]; g (Pin 3) 1 [ Pin_drive ]; g (Pin 4) 1 [ Pin_drive ]; g (Pin 5) 1 [ Pin_drive ];
                             g (Pin 1) 2 [ Pin_drive ];
                             g (Pin 6) 3 [ Pin_drive; Pin_sample ]; g (Pin 7) 3 [ Pin_drive; Pin_sample ] ];
                         (* inboxes are declared as ownership, like bridge A's: T0 -> 1 -> T1 -> 2 -> T2 *)
                         owns = bridge_owns () } in
  let check name t1 =
    let mem = [| t0; t1; t2; t3 |] in
    let fetch a = let t = a lsr 8 and pc = a land 0xFF in if pc < Array.length mem.(t) then mem.(t).(pc) else Isa2.nop in
    report ~name ~fetch d in
  let f = check "bridge B on v2: T0 UART RX -> inbox 1 -> T1 SPI master -> inbox 2 -> T2 UART TX; T3 I2C neighbour" t1 in
  Printf.printf "bridge B: %d rejected combination(s), no waiver (bridge_lib's spi_master answers into inbox 2 with \
                 LDD 4095; SEND ch2 -> replylost)\n\n" (List.length f);
  (* control: T1 as it was before the fix, by pointing every SEND to inbox 2 back at itself *)
  let is_send2 w = (w lsr 12) land 15 = 13 && (w lsr 11) land 1 = 0 && (w lsr 8) land 7 = 2 in
  let t1_old = Array.mapi (fun pc w -> if is_send2 w then Isa2.send ~ch:2 ~fail:pc else w) t1 in
  let n_send2 = Array.fold_left (fun n w -> if is_send2 w then n + 1 else n) 0 t1 in
  let f_old = check "control: the same with T1's SENDs to inbox 2 made fail = own address (the code before the fix)" t1_old in
  Printf.printf "control: %d SEND(s) to inbox 2 in T1; with fail = own address the checker rejects %d\n\n" n_send2 (List.length f_old);
  Printf.printf "HAZARD BRIDGE B %s (bridge B accepted without a waiver: %d rejections; control: %d of %d sends rejected)\n"
    (if f = [] && n_send2 > 0 && List.length f_old = n_send2 then "PASS" else "FAIL") (List.length f) (List.length f_old) n_send2

let () =
  let (_, _, _), (t1, _, _), (_, _, _) =
    uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx:1 ~own:2 () in
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "disasm" then
    Array.iteri (fun i w -> Printf.printf "T1 %3d %04x %s\n" i w (Isa2.disasm w)) t1
