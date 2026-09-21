(* Emit Verilog, then run: (a) lockstep differential test of the RTL against the interpreter on
   random programmes and inputs; (b) a UART transmitter programme; (c) a deadline-timeout programme. *)
open Hardcaml

let circuit = Harness.circuit

let emit () =
  let oc = open_out "deadline_sequencer.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog circuit;
  close_out oc

(* Combinational outputs computed from the new state must be compared with the interpreter's
   state after the same step: host_in_ready is combinational within the cycle, so it is compared
   against the interpreter's effect of that step. *)
let lockstep ~seed ~cycles =
  Random.init seed;
  let mem = Array.init Isa.n_threads (fun _ -> Array.init Isa.prog_len (fun _ -> Random.int 0x10000)) in
  let s = Harness.make mem in
  let st = Isa.init () in
  let mismatches = ref 0 in
  for c = 0 to cycles - 1 do
    let pin_in = Random.int 256 and host_in = Random.int 256 and host_in_valid = Random.bool () in
    let eff = Isa.step st ~mem ~pin_in ~host_in ~host_in_valid in
    let o = Harness.cycle s ~pin_in ~host_in ~host_in_valid in
    let (po, poe, ho, hir, pcs) = (o.pin_out, o.pin_oe, o.host_out, o.host_in_ready, o.pcs) in
    let ok = po = st.pin_out && poe = st.pin_oe && ho = eff.host_out && hir = eff.host_in_ready
             && pcs = Array.to_list st.pcs in
    if not ok then begin
      incr mismatches;
      if !mismatches <= 3 then
        Printf.printf "  seed %d cycle %d: rtl out=%02x oe=%02x pcs=%s | model out=%02x oe=%02x pcs=%s hir rtl=%b model=%b\n"
          seed c po poe (String.concat "," (List.map string_of_int pcs)) st.pin_out st.pin_oe
          (String.concat "," (Array.to_list (Array.map string_of_int st.pcs))) hir eff.host_in_ready
    end
  done;
  !mismatches

(* UART transmitter on thread 0, pin 0, 16 slots per bit (one slot = 4 cycles), bytes from the host. *)
let uart_program =
  let open Isa in
  let p = Array.make prog_len nop in
  let set i w = p.(i) <- w in
  set 0 (setp ~mask:0x01 ~value:1 ~oe:1);   (* idle high *)
  set 1 in_;                                 (* acc <- byte *)
  set 2 (setp ~mask:0x01 ~value:0 ~oe:1);   (* start bit *)
  set 3 (ldd 12);
  set 4 waitd;
  set 5 (ldc 8);
  set 6 (sho ~pin:0 ~msb:0 ());                 (* loop: data bit, lsb first *)
  set 7 (ldd 12);
  set 8 waitd;
  set 9 (jnz 6);
  set 10 (setp ~mask:0x01 ~value:1 ~oe:1);  (* stop bit *)
  set 11 (ldd 12);
  set 12 waitd;
  set 13 (jmp 1);
  p

let uart_test () =
  let mem = Array.init Isa.n_threads (fun t -> if t = 0 then uart_program else Array.make Isa.prog_len Isa.halt) in
  let s = Harness.make mem in
  let byte = 0x4B in
  (* feed one byte, then record pin 0 for 11 bit periods, sampling mid-bit *)
  let trace = Buffer.create 64 in
  let fed = ref false in
  let start_seen = ref None in
  let samples = Buffer.create 16 in
  for c = 0 to 4 * 16 * 14 do
    let o = Harness.cycle s ~pin_in:0 ~host_in:byte ~host_in_valid:(not !fed) in
    let po = o.pin_out and hir = o.host_in_ready in
    if hir then fed := true;
    let tx = po land 1 in
    Buffer.add_char trace (if tx = 1 then '1' else '0');
    (match !start_seen with
     | None -> if !fed && tx = 0 then start_seen := Some c
     | Some c0 -> let d = c - c0 in
       if d mod 64 = 32 && Buffer.length samples < 10 then Buffer.add_char samples (if tx = 1 then '1' else '0'))
  done;
  let expect = "0" ^ String.init 8 (fun i -> if (byte lsr i) land 1 = 1 then '1' else '0') ^ "1" in
  let got = Buffer.contents samples in
  Printf.printf "uart: sampled %s expected %s -> %s\n" got expect (if got = expect then "PASS" else "FAIL");
  got = expect

(* Thread 1 waits for pin 1 to rise with a 20-slot deadline; on timeout it raises pin 7. *)
let deadline_program =
  let open Isa in
  let p = Array.make prog_len nop in
  p.(0) <- setp ~mask:0x80 ~value:0 ~oe:1;
  p.(1) <- ldd 20;
  p.(2) <- waitp ~pin:1 ~value:1 ~fail:5;
  p.(3) <- setp ~mask:0x40 ~value:1 ~oe:1;   (* pin 6: event seen in time *)
  p.(4) <- halt;
  p.(5) <- setp ~mask:0x80 ~value:1 ~oe:1;   (* pin 7: timed out *)
  p.(6) <- halt;
  p

let deadline_test ~rise_at =
  let mem = Array.init Isa.n_threads (fun t -> if t = 1 then deadline_program else Array.make Isa.prog_len Isa.halt) in
  let s = Harness.make mem in
  let final = ref 0 in
  for c = 0 to 200 do
    let pin_in = match rise_at with Some r when c >= r -> 2 | _ -> 0 in
    let o = Harness.cycle s ~pin_in ~host_in:0 ~host_in_valid:false in
    final := o.pin_out
  done;
  let seen = !final land 0x40 <> 0 and timeout = !final land 0x80 <> 0 in
  Printf.printf "deadline: rise_at=%s -> seen=%b timeout=%b\n"
    (match rise_at with Some r -> string_of_int r | None -> "never") seen timeout;
  (seen, timeout)

let () =
  emit ();
  let total = ref 0 in
  let runs = 300 and cycles = 2000 in
  for seed = 1 to runs do total := !total + lockstep ~seed ~cycles done;
  Printf.printf "lockstep: %d programmes x %d cycles, %d mismatching cycles\n" runs cycles !total;
  let u = uart_test () in
  let (a, b) = deadline_test ~rise_at:(Some 30) and (c, d) = deadline_test ~rise_at:None in
  let ok = !total = 0 && u && a && (not b) && (not c) && d in
  print_endline (if ok then "ALL PASS" else "FAILURES");
  exit (if ok then 0 else 1)
