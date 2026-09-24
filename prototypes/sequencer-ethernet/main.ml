(* 10BASE-T transmit as firmware on the deadline sequencer, with no new instructions.

   At 60 MHz a Manchester half-bit is 3 clocks and each hardware thread issues once every 4 clocks,
   so no single thread can keep up. But the four threads together issue every clock, and half-bit k
   starts on clock S + 3k, which (S a multiple of 4) is thread (3k) mod 4's slot. So each thread owns
   every fourth half-bit, 12 clocks apart, with two spare slots in between.

   Heavy precomputation does the rest: the host sorts the frame's half-bits by owning thread, inverts
   the first halves (Manchester: a 1 is low then high), and packs 8 per byte, LSB first. Each thread
   then runs the same 24-slot loop: (SHO; NOP; NOP) x 7, SHO, IN, JMP, emitting its accumulator one
   bit per 12 clocks and loading its next byte with IN.

   Assumption, stated rather than hidden: the host presents each thread's next byte in the slot where
   that thread executes IN (the schedule is deterministic, so a host running from the same clock can;
   a per-thread input FIFO would be the hardware alternative).

   The check: the interpreter's pin trace against the Ethernet model's own encoder, clock for clock. *)

let h = 3
let s = 16   (* first half-bit clock, a multiple of 4 *)

let frame =
  Eth_model.udp_frame ~dst_mac:[ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ] ~src_mac:[ 0x02; 0x00; 0x00; 0x12; 0x34; 0x56 ]
    ~src_ip:[ 192; 168; 1; 200 ] ~dst_ip:[ 192; 168; 1; 255 ] ~src_port:4096 ~dst_port:4096
    ~payload:(List.map Char.code [ 'h'; 'e'; 'l'; 'l'; 'o'; ' '; 'f'; 'r'; 'o'; 'm'; ' '; 'f'; 'i'; 'r'; 'm'; 'w'; 'a'; 'r'; 'e' ])

(* the bytes on the wire: preamble, SFD, frame, FCS; and the model's line samples for them *)
let wire = List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame
let model_samples = Array.of_list (Eth_model.encode_frame ~h frame)
let nbits = 8 * List.length wire
let nhalf = 2 * nbits

(* precomputation: per-thread byte streams *)
let owner k = (s + h * k) mod Isa.n_threads
let streams =
  let bits = Array.of_list (List.concat_map Eth_model.bits_of_byte wire) in
  let per = Array.make Isa.n_threads [] in
  for k = 0 to nhalf - 1 do
    let b = bits.(k / 2) in
    let v = if k mod 2 = 0 then 1 - b else b in   (* pin level: 1 = positive *)
    per.(owner k) <- v :: per.(owner k)
  done;
  Array.map (fun l ->
    let vs = Array.of_list (List.rev l) in
    let nbytes = (Array.length vs + 7) / 8 in
    Array.init nbytes (fun j ->
      let byte = ref 0 in
      for i = 0 to 7 do
        let idx = 8 * j + i in
        if idx < Array.length vs && vs.(idx) = 1 then byte := !byte lor (1 lsl i)
      done; !byte)) per

(* the firmware, generated: a prologue that loads the first byte and pads so that the first SHO lands
   exactly on the thread's first half-bit, then the 24-slot loop *)
let program t =
  let k0 = let rec f k = if owner k = t then k else f (k + 1) in f 0 in
  let first_sho_slot = (s + h * k0 - t) / Isa.n_threads in
  let pro = (if t = 0 then [ Isa.setp ~mask:1 ~value:0 ~oe:1 ] else []) @ [ Isa.in_ ] in
  let pad = first_sho_slot - List.length pro in
  assert (pad >= 0);
  let body_start = List.length pro + pad in
  let sho = Isa.sho ~pin:0 ~msb:0 () in
  let body = List.concat (List.init 7 (fun _ -> [ sho; Isa.nop; Isa.nop ])) @ [ sho; Isa.in_; Isa.jmp body_start ] in
  let code = Array.of_list (pro @ List.init pad (fun _ -> Isa.nop) @ body) in
  assert (Array.length code <= Isa.prog_len);
  Array.init Isa.prog_len (fun i -> if i < Array.length code then code.(i) else Isa.halt)

let run ~mem ~streams =
  let st = Isa.init () in
  let next = Array.make Isa.n_threads 0 in
  let cycles = s + h * nhalf + 8 in
  let trace = Array.make cycles 0 and oe = Array.make cycles 0 in
  for c = 0 to cycles - 1 do
    let t = st.thread in
    (* the host: this thread's next byte, presented in the slot where it executes IN *)
    let at_in = mem.(t).(st.pcs.(t)) = Isa.in_ in
    let valid = at_in && next.(t) < Array.length streams.(t) in
    let byte = if valid then streams.(t).(next.(t)) else 0 in
    let eff = Isa.step st ~mem ~pin_in:0 ~host_in:byte ~host_in_valid:valid in
    if eff.host_in_ready then next.(t) <- next.(t) + 1;
    trace.(c) <- st.pin_out land 1; oe.(c) <- st.pin_oe land 1
  done;
  (* compare: model sample i (the bit part: +1 / -1) against the pin during clock s + i *)
  let mismatches = ref 0 and first_bad = ref (-1) in
  for i = 0 to h * nhalf - 1 do
    let want = if model_samples.(i) > 0 then 1 else 0 in
    if model_samples.(i) = 0 || oe.(s + i) = 0 || trace.(s + i) <> want then begin
      incr mismatches; if !first_bad < 0 then first_bad := i end
  done;
  !mismatches, !first_bad

let () =
  let mem = Array.init Isa.n_threads program in
  let mismatches, first_bad = run ~mem ~streams in
  let mismatches = ref mismatches and first_bad = ref first_bad in
  Printf.printf "frame %d bytes on the wire (%d half-bits, %d clocks); program sizes %s of %d; host bytes per thread %s\n"
    (List.length wire) nhalf (h * nhalf)
    (String.concat "," (List.init Isa.n_threads (fun t -> string_of_int (Array.length (Array.of_list (List.filter (fun i -> i <> Isa.halt) (Array.to_list mem.(t))))))))
    Isa.prog_len (String.concat "," (Array.to_list (Array.map (fun a -> string_of_int (Array.length a)) streams)));
  Printf.printf "pin vs Ethernet model encoder: %d mismatching clocks of %d%s -> %s\n" !mismatches (h * nhalf)
    (if !first_bad >= 0 then Printf.sprintf " (first at clock %d, half-bit %d)" (s + !first_bad) (!first_bad / h) else "")
    (if !mismatches = 0 then "PASS" else "FAIL")

(* controls: each of these must fail *)
let () =
  let mem = Array.init Isa.n_threads program in
  let flip_byte t j = Array.mapi (fun u a -> if u = t then Array.mapi (fun i b -> if i = j then b lxor 1 else b) a else a) streams in
  let swap_threads = Array.init Isa.n_threads (fun t -> streams.((t + 2) mod Isa.n_threads)) in
  let late = Array.init Isa.n_threads (fun t ->
    if t = 1 then Array.of_list (Array.to_list (program t) |> fun l -> Isa.nop :: List.filteri (fun i _ -> i < Isa.prog_len - 1) l)
    else program t) in
  List.iter (fun (name, mem, streams) ->
    let m, first = run ~mem ~streams in
    Printf.printf "control %-40s %5d mismatching clocks (first at %d) -> %s\n" name m (s + first) (if m > 0 then "caught" else "MISSED"))
    [ ("one bit flipped in thread 2's 10th byte", mem, flip_byte 2 9);
      ("threads' streams rotated by two", mem, swap_threads);
      ("thread 1 one slot late (extra NOP)", late, streams) ]

(* the same firmware on the RTL (sequencer.ml through the prototype's own Harness), with the
   interpreter alongside to drive the host; the RTL's pin is checked against the model directly *)
let () =
  let mem = Array.init Isa.n_threads program in
  let hs = Harness.make mem in
  let st = Isa.init () in
  let next = Array.make Isa.n_threads 0 in
  let bad = ref 0 and diverged = ref 0 in
  for c = 0 to s + h * nhalf - 1 do
    let t = st.thread in
    let valid = mem.(t).(st.pcs.(t)) = Isa.in_ && next.(t) < Array.length streams.(t) in
    let byte = if valid then streams.(t).(next.(t)) else 0 in
    let eff = Isa.step st ~mem ~pin_in:0 ~host_in:byte ~host_in_valid:valid in
    let o = Harness.cycle hs ~pin_in:0 ~host_in:byte ~host_in_valid:valid in
    if eff.host_in_ready then next.(t) <- next.(t) + 1;
    if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe then incr diverged;
    if c >= s then begin
      let i = c - s in
      let want = if model_samples.(i) > 0 then 1 else 0 in
      if o.pin_oe land 1 = 0 || o.pin_out land 1 <> want then incr bad
    end
  done;
  Printf.printf "RTL: %d clocks where its pin differs from the Ethernet model, %d where it differs from the interpreter -> %s\n"
    !bad !diverged (if !bad = 0 && !diverged = 0 then "PASS" else "FAIL")
