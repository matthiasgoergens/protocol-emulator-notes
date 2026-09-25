(* I2C <-> CAN bridge: a CAN node that fronts an I2C sensor, against a frame-level CAN stand-in.

   CAN side (stand-in until the proto-ps2-can node firmware can share the core; see README):
     in-port 2   received frames as the CAN RX thread would report them, with the data made
                 byte-aligned (the interface this plan asks of that branch):
                 0xA1 c1 c2 c3 d0 .. d(n-1) 0xA2 status   (c1..c3 as its DATA packing; status 0 = ok)
     out-port 0  frames for the CAN TX thread to send: c1 c2 c3 d0 .. (it stuffs and adds the CRC
                 on chip, with that branch's stuffing and CRC assists)
   Requests: ID 0x123 (ID0 = 1) read  [addr_w, reg, addr_r] -> ID 0x223 [ack, ack, ack, data, nack]
             ID 0x124 (ID0 = 0) write [addr_w, reg, value]  -> ID 0x224 [ack, ack, ack]
   (8-bit addresses with the R/W bit, so the bridge never computes: the requester precomputes.)

   Threads:
     T0 translator: header, then the three data bytes into its own inbox (depth 4) until the
        frame's status arrives; a frame with an error is dropped before anything reaches the bus
        (a CAN node may act on a frame only after its end). Then a kind marker to T2, the I2C op
        sequence to T1, and it waits for T2's done token.
     T1 the I2C master of bridges.ml, unchanged.
     T2 response assembler: header constants, then T1's answers, to the CAN TX port; done -> T0.
     T3 unrelated SPI master loop, for isolation. *)

open Bridge_lib

let translator () =
  let b = Asm.create () in
  let open Asm in
  let r6 () = block_recv b 6 and s1 () = block_send b 1 and op v = emit b (W (Isa.lda v)); block_send b 1 in
  label b "top";
  r6 (); r6 (); r6 (); r6 ();                                (* 0xA1 c1 c2 c3 *)
  emit b (br_set 7 "rd");
  let body kind ops_between =
    r6 (); block_send b 0; r6 (); block_send b 0; r6 (); block_send b 0;   (* d0 d1 d2 -> own inbox *)
    r6 (); r6 ();                                            (* 0xA2 status *)
    emit b (br_set 0 (kind ^ "drop")); emit b (br_set 1 (kind ^ "drop"));
    emit b (W (Isa.lda (if kind = "w" then 0x57 else 0x52))); block_send b 2;
    ops_between ();
    block_recv b 0;                                          (* done token *)
    emit b (jmp "top");
    label b (kind ^ "drop");
    block_recv b 0; block_recv b 0; block_recv b 0; emit b (jmp "top") in
  let d () = block_recv b 0; s1 () in
  body "w" (fun () -> op op_start; op op_write; d (); op op_write; d (); op op_write; d (); op op_stop);
  label b "rd";
  body "r" (fun () -> op op_start; op op_write; d (); op op_write; d (); op op_start; op op_write; d ();
                      op op_read; op op_nack; op op_stop);
  assemble b

let hdr id dlc = [ (id lsr 9) land 3; (id lsr 1) land 0xFF; ((id land 1) lsl 7) lor dlc ]

let assembler () =
  let b = Asm.create () in
  let open Asm in
  let k v = emit b (W (Isa.lda v)); block_send b 4 in
  let fwd () = block_recv b 2; block_send b 4 in
  label b "top";
  block_recv b 2; emit b (br_set 0 "w");
  List.iter k (hdr 0x223 5); for _ = 1 to 5 do fwd () done;
  emit b (W (Isa.lda 0xDD)); block_send b 0; emit b (jmp "top");
  label b "w";
  List.iter k (hdr 0x224 3); for _ = 1 to 3 do fwd () done;
  emit b (W (Isa.lda 0xDD)); block_send b 0; emit b (jmp "top");
  assemble b

type req = { t : int; write : bool; addr : int; reg : int; value : int; bad : bool }

type res = { responses : int list list; expected : int list list; mism : int; starts : int; expected_starts : int;
             bus_ok : bool; regs_ok : bool; neigh_hash : int; bridge_hash : int; cycles : int }

let run ?(fault = Isa_mb.No_fault) ?(rtl = true) ?(neigh = `Compiled) ?(seed = 1) ?(n = 30) () =
  let c = Isa_mb.cfg ~pc_bits:7 ~depth:4 ~fault () in
  let (t0, _, _) = translator () and (t1, _, _) = i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 () and (t2, _, _) = assembler () in
  let t3 = match neigh with
    | `Compiled -> Asm.of_base ~loop:true (Compiler.spi_master { sclk = 5; mosi = 6; cs = 7; period = 12; sbytes = [ 0x96 ] }) ~plen:128
    | `Random s -> Random.init s; Dual.random_neighbour ~plen:128 ~pins:0xE0 ~own:[ 3 ]
    | `Off -> Array.make 128 Isa.halt in
  let d = Dual.make ~rtl c [| t0; t1; t2; t3 |] in
  let rnd = Random.State.make [| seed |] in
  let dev = 0x48 in
  (* requests, every ~6000..12000 clocks; one in eight to an absent device, one in ten corrupted *)
  let reqs = List.init n (fun i ->
    let addr = if Random.State.int rnd 8 = 0 then 0x21 else dev in
    { t = 5000 + (i * 9000) + Random.State.int rnd 3000; write = Random.State.bool rnd; addr; reg = Random.State.int rnd 256;
      value = Random.State.int rnd 256; bad = Random.State.int rnd 10 = 0 }) in
  let events = List.concat_map (fun r ->
    let id = if r.write then 0x124 else 0x123 in
    let data = if r.write then [ r.addr lsl 1; r.reg; r.value ] else [ r.addr lsl 1; r.reg; (r.addr lsl 1) lor 1 ] in
    let bytes = [ 0xA1 ] @ hdr id 3 @ data @ [ 0xA2; (if r.bad then 2 else 0) ] in
    List.mapi (fun j x -> (r.t + (j * 960), x)) bytes) reqs in
  let good = List.filter (fun r -> not r.bad) reqs in
  let txs = List.map (fun r -> if r.write then Wr (r.addr, r.reg, [ r.value ]) else Rd (r.addr, r.reg, 1)) good in
  let answers, expect_bus, ref_regs = i2c_reference ~addr:dev txs in
  (* split the flat answers into per-request responses *)
  let rec split rs ans = match rs with
    | [] -> []
    | r :: rest -> let k = if r.write then 3 else 5 in
      let h = List.filteri (fun i _ -> i < k) ans and t = List.filteri (fun i _ -> i >= k) ans in
      (hdr (if r.write then 0x224 else 0x223) k @ h) :: split rest t in
  let expected = split good answers in
  let slave = new_i2c_slave ~max_stretch:600 ~bit_stretch:0.02 ~seed:(seed + 3) dev in
  let port = Queue.create () in
  let evq = ref events in
  let out = ref [] and cur = ref [] in
  let tr = ref [] in
  let neigh_hash = ref 0 and bridge_hash = ref 0 in
  let last_t = (List.fold_left (fun m (t, _) -> max m t) 0 events) + 400_000 in
  for now = 0 to last_t do
    (match !evq with (t, x) :: r when t <= now -> Queue.push x port; evq := r | _ -> ());
    let po = Dual.pin_out d and oe = Dual.pin_oe d in
    let drv p = (oe lsr p) land 1 = 1 in
    let od_low p = drv p && (po lsr p) land 1 = 0 in
    let sda, scl = i2c_slave_step slave ~now ~m_sda_low:(od_low 3) ~m_scl_low:(od_low 4) in
    let pin_in = (sda lsl 3) lor (scl lsl 4) lor (po land oe land 0xE0) in
    tr := { Decoders.c = now; bus = pin_in } :: !tr;
    neigh_hash := Hashtbl.hash (!neigh_hash, pin_in land 0xE0);
    bridge_hash := Hashtbl.hash (!bridge_hash, pin_in land 0x18);
    let io = { Isa_mb.idle_io with pin_in; port_in = [| 0; 0; (if Queue.is_empty port then 0 else Queue.peek port); 0 |];
               port_in_valid = [| false; false; not (Queue.is_empty port); false |]; port_out_ready = [| true; true; true; true |] } in
    let e = Dual.step d io in
    (match e.port_pop with Some 2 -> ignore (Queue.pop port) | _ -> ());
    (match e.port_push with
     | Some (0, v) ->
       cur := !cur @ [ v ];
       (match !cur with _ :: _ :: c3 :: rest when List.length rest = c3 land 15 -> out := !out @ [ !cur ]; cur := [] | _ -> ())
     | _ -> ())
  done;
  let trace = List.rev !tr in
  let got_bus, _ = Decoders.i2c trace ~sda:3 ~scl:4 in
  let starts = List.length (List.filter (fun (_, _) -> true) got_bus) in
  let expected_starts = List.length expect_bus in
  { responses = !out; expected; mism = d.mismatches; starts; expected_starts; bus_ok = got_bus = expect_bus;
    regs_ok = slave.regs = ref_regs; neigh_hash = !neigh_hash; bridge_hash = !bridge_hash; cycles = last_t }

let () =
  let t0 = Unix.gettimeofday () in
  let (_, l0, _) = translator () and (_, l2, _) = assembler () in
  Printf.printf "programmes: T0 translator %d words, T1 I2C master (bridges.ml) %d, T2 assembler %d\n" l0
    (let (_, l, _) = i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 () in l) l2;
  let pr name r =
    let ok = r.responses = r.expected && r.bus_ok && r.regs_ok && r.mism = 0 in
    Printf.printf "%-44s %s: %d response frames (%d expected), I2C bus bytes as expected %b (%d bytes), device registers %s, \
                   RTL mismatches %d, %d cycles\n%!"
      name (if ok then "PASS" else "FAIL") (List.length r.responses) (List.length r.expected) r.bus_ok r.starts
      (if r.regs_ok then "ok" else "WRONG") r.mism r.cycles;
    ok in
  let a = pr "I2C<->CAN, RTL + interpreter" (run ()) in
  let ok = ref a in
  for s = 2 to 6 do if not (pr (Printf.sprintf "  random seed %d" s) (run ~rtl:false ~seed:s ())) then ok := false done;
  let base = run ~rtl:false () in
  let alone = run ~rtl:false ~neigh:`Off () in
  let rn = run ~rtl:false ~neigh:(`Random 4) () in
  Printf.printf "isolation: bridge pins identical without the neighbour %b, with a random neighbour %b\n" (alone.bridge_hash = base.bridge_hash) (rn.bridge_hash = base.bridge_hash);
  let c1 = pr "control: mailbox drops push 30 (interp)" (run ~rtl:false ~fault:(Isa_mb.Drop_push 30) ()) in
  let c2 = pr "control: two pushes swapped at 31 (interp)" (run ~rtl:false ~fault:(Isa_mb.Swap_pair 31) ()) in
  let all = !ok && a && (not c1) && (not c2) && alone.bridge_hash = base.bridge_hash && rn.bridge_hash = base.bridge_hash in
  print_endline (if all then "I2C-CAN PASS" else "I2C-CAN FAIL");
  Printf.printf "elapsed %.0f s\n" (Unix.gettimeofday () -. t0)
