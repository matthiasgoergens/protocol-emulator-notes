(* Option (b): two threads exchanging bytes over looped-back pins, on the UNMODIFIED base ISA and
   RTL (../deadline-sequencer isa.ml, sequencer.ml, harness.ml), against option (c), the mailbox.

   The pin link uses three pins wired back to themselves: V (sender: a byte follows), R (receiver:
   ready), D (data). The barrel schedule fixes the phase between thread 0 and thread 1, so after
   one rendezvous the data needs no per-bit handshake: the sender's SHO on slot k is visible to
   the receiver's SHI on slot k, eight in a row. Both threads are fully occupied during a
   transfer and nothing is buffered: the sender waits until the receiver is at its poll.

   Both directions are checked the same way: 256 random bytes from the host into thread 0, through
   the link, out of thread 1 to the host, compared in order; RTL and interpreter in lockstep. *)

let d_pin = 4 and v_pin = 5 and r_pin = 6

let pin_link ?(aligned = true) () =
  let s = Array.make 64 Isa.halt and r = Array.make 64 Isa.halt in
  let m p = 1 lsl p in
  (* sender, thread 0 *)
  let sw = [ Isa.setp ~mask:(m v_pin lor m d_pin) ~value:0 ~oe:1;                     (* 0 *)
             Isa.in_;                                                                 (* 1: top *)
             Isa.waitp ~pin:r_pin ~value:1 ~fail:2;                                  (* 2: receiver ready *)
             Isa.setp ~mask:(m v_pin) ~value:1 ~oe:1 ]                                (* 3 *)
           @ (if aligned then [ Isa.nop ] else [])                                    (* 4: the receiver's SETP R=0 *)
           @ List.init 8 (fun _ -> Isa.sho ~pin:d_pin ~msb:1 ())                      (* 5..12 *)
           @ [ Isa.setp ~mask:(m v_pin) ~value:0 ~oe:1; Isa.jmp 1 ] in
  List.iteri (fun i w -> s.(i) <- w) sw;
  (* receiver, thread 1 *)
  let rw = [ Isa.setp ~mask:(m r_pin) ~value:1 ~oe:1;                                 (* 0: top, ready *)
             Isa.waitp ~pin:v_pin ~value:1 ~fail:1;                                   (* 1 *)
             Isa.setp ~mask:(m r_pin) ~value:0 ~oe:1 ]                                (* 2 *)
           @ List.init 8 (fun _ -> Isa.shi ~pin:d_pin ~msb:1)                         (* 3..10 *)
           @ [ Isa.out; Isa.jmp 0 ] in
  List.iteri (fun i w -> r.(i) <- w) rw;
  s, r, List.length sw, List.length rw

let run_pins ?aligned bytes =
  let s, r, _, _ = pin_link ?aligned () in
  let halt = Array.make 64 Isa.halt in
  let mem = [| s; r; halt; halt |] in
  let h = Harness.make mem in
  let st = Isa.init () in
  let q = ref bytes and got = ref [] and mism = ref 0 and n = ref 0 and first_in = ref (-1) in
  let loop_mask = (1 lsl d_pin) lor (1 lsl v_pin) lor (1 lsl r_pin) in
  while List.length !got < List.length bytes && !n < 200_000 do
    let pin_in = st.pin_out land loop_mask in
    let host_in, valid = match !q with x :: _ -> x, true | [] -> 0, false in
    let e = Isa.step st ~mem ~pin_in ~host_in ~host_in_valid:valid in
    let o = Harness.cycle h ~pin_in ~host_in ~host_in_valid:valid in
    if o.pin_out <> st.pin_out || o.host_out <> e.host_out || o.host_in_ready <> e.host_in_ready then incr mism;
    if e.host_in_ready then (if !first_in < 0 then first_in := !n; q := List.tl !q);
    (match e.host_out with Some v -> got := v :: !got | None -> ());
    incr n
  done;
  List.rev !got, !n, !mism

let run_mailbox bytes =
  let c = Isa_mb.cfg ~pc_bits:7 ~depth:2 () in
  let b0 = Asm.create () and b1 = Asm.create () in
  Asm.label b0 "top"; Asm.emit b0 (Asm.W Isa.in_); Asm.block_send b0 1; Asm.emit b0 (Asm.jmp "top");
  Asm.label b1 "top"; Asm.block_recv b1 1; Asm.emit b1 (Asm.W Isa.out); Asm.emit b1 (Asm.jmp "top");
  let (p0, _, _) = Asm.assemble b0 and (p1, _, _) = Asm.assemble b1 in
  let halt = Array.make 128 Isa.halt in
  let d = Dual.make c [| p0; p1; halt; halt |] in
  let q = ref bytes and got = ref [] and n = ref 0 in
  while List.length !got < List.length bytes && !n < 200_000 do
    let host_in, valid = match !q with x :: _ -> x, true | [] -> 0, false in
    let e = Dual.step d { Isa_mb.idle_io with host_in; host_in_valid = valid } in
    if e.host_in_ready then q := List.tl !q;
    (match e.host_out with Some v -> got := v :: !got | None -> ());
    incr n
  done;
  List.rev !got, !n, d.mismatches

let () =
  Random.init 11;
  let bytes = List.init 256 (fun _ -> Random.int 256) in
  let _, _, ls, lr = pin_link () in
  let gp, np, mp = run_pins bytes in
  let gm, nm, mm = run_mailbox bytes in
  let gx, _, _ = run_pins ~aligned:false bytes in
  let f = 60e6 in
  Printf.printf "pin loopback (base ISA and RTL, 3 pins, %d + %d words): %d bytes in order %b, %d cycles, %.1f cycles/byte = %.2f MB/s at 60 MHz; \
                 RTL mismatches %d; both threads busy for the whole transfer, no buffering\n"
    ls lr (List.length gp) (gp = bytes) np (float np /. 256.) (256. *. f /. float np /. 1e6) mp;
  Printf.printf "mailbox (variant, 0 pins, 3 + 3 words): %d bytes in order %b, %d cycles, %.1f cycles/byte = %.2f MB/s at 60 MHz; \
                 RTL mismatches %d; each side spends 2 of every 3 of its slots and the inbox buffers 2 bytes\n"
    (List.length gm) (gm = bytes) nm (float nm /. 256.) (256. *. f /. float nm /. 1e6) mm;
  Printf.printf "control: pin loopback with the sender one slot early (the NOP removed): %d of 256 bytes correct\n"
    (List.fold_left2 (fun n a b -> if a = b then n + 1 else n) 0 (List.filteri (fun i _ -> i < List.length gx) bytes) gx)
