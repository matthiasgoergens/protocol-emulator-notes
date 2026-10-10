(* The example programmes, each checked end to end.

   For every example under examples/:
   - it assembles; where it is a port of the repository's compiler output, its words equal the
     compiler's (prototypes/deadline-sequencer/compiler.ml translated to ISA v2 by
     prototypes/sequencer-v2/compat.ml, or prototypes/onebit-dac/sim/dac.ml's pump programme and
     PE configuration);
   - its .timing block, where it has one, is the verifier's own specification of that programme
     (prototypes/verifier/programmes.ml), compared as automata up to the numbering of states, and
     asm --verify proves it; the certificates go to results/certs/;
   - it runs on the ISA v2 interpreter and on the chip's specification and RTL in lockstep, with
     its peers, and the interpreter's nets and OUTs must equal the chip's clock for clock;
   - an independent decoder judges the pins (the repository's decoders,
     prototypes/deadline-sequencer/decoders.ml, which "sample where a receiver would sample"; an
     I2C target and UART peers written from the protocol; for the DAC the modulator's bit-exact
     model and a low-pass filter), and the host's bytes are compared with what was sent;
   - controls: a planted RTL bug (prototypes/chip-top/src/chip_rtl.ml) on the example's pins must
     make the lockstep fail, and a wrong peer must make the decoder fail.
   Traces for tools/sigrok-judge go to results/traces/<example>/ (test/judge_examples.py).
   Usage: examples.exe [NAME...]. Run from tools/asm. Exit 1 on any failure. *)

module D = Ds.Decoders

let failures = ref 0
let check name ok = Printf.printf "  %-66s %s\n%!" name (if ok then "ok" else "FAIL"); if not ok then incr failures

let mkdir_p d = ignore (Sys.command (Printf.sprintf "mkdir --parents %s" (Filename.quote d)))

let assemble file = Assembler.assemble_file ~include_dirs:[ "lib" ] (Filename.concat "examples" file)

let read_file path = let ic = open_in_bin path in let s = really_input_string ic (in_channel_length ic) in close_in ic; s

let page_words (r : Assembler.result) page = Image.page_words r.image page

(* ---- automata up to state numbering ---- *)

let canonical (s : Verif.Spec.t) =
  let ids = Hashtbl.create 64 and q = Queue.create () and n = ref 0 in
  let id x = match Hashtbl.find_opt ids x with Some i -> i | None -> let i = !n in incr n; Hashtbl.replace ids x i; Queue.push x q; i in
  ignore (id s.start);
  let out = ref [] in
  while not (Queue.is_empty q) do
    let a = Queue.pop q in
    let trs = List.sort compare (List.map (fun (tr : Verif.Spec.transition) ->
        (List.sort compare tr.pats, tr.gap, tr.data, tr.dst)) (Verif.Spec.outgoing s a)) in
    List.iter (fun (pats, gap, data, dst) -> out := (id a, pats, gap, data, id dst) :: !out) trs
  done;
  (!n, List.sort compare !out, Array.to_list s.bytes, List.sort compare s.pins)

let same_spec a b = canonical a = canonical b

(* ---- runs ---- *)

let opts ?(hostin = []) clocks peers = { Runner.clocks; peers; hostin; prog_words = 1024 }

(* run on the interpreter and on the chip (specification + RTL); they must agree *)
let both name (img : Image.t) ~clocks ~peers ?hostin () =
  let a = Runner.run Runner.Isa img (opts ?hostin clocks (peers ())) in
  let c = Runner.run (Runner.Chip { rtl = true }) img (opts ?hostin clocks (peers ())) in
  check (name ^ ": chip specification and RTL equal on every pad, every clock") (c.agree = Some true);
  check (name ^ ": interpreter and chip: equal nets on every clock") (Runner.compare a c = None);
  check (name ^ ": interpreter and chip: the same OUTs at the same clocks") (a.trace.outs = c.trace.outs);
  let sent = List.map (fun (_, t, b) -> (t, b)) c.trace.outs in
  let rec prefix x y = match x, y with [], _ -> true | p :: x', q :: y' -> p = q && prefix x' y' | _ -> false in
  check (name ^ ": the host link delivered every OUT, in order") (prefix sent c.received);
  a, c

(* a planted RTL bug must break the lockstep *)
let control_rtl name (img : Image.t) ~clocks ~peers bug =
  Chip_rtl.bug := bug;
  let c = Runner.run (Runner.Chip { rtl = true }) img (opts clocks (peers ())) in
  Chip_rtl.bug := "";
  check (Printf.sprintf "%s: control, RTL bug %s caught by the lockstep" name bug) (c.agree = Some false)

let write_trace ex (r : Runner.result) expected =
  let dir = Filename.concat "results/traces" ex in
  mkdir_p dir;
  Wave.sigrok_bin (Filename.concat dir "deadline-sequencer.bin") r.trace;
  Wave.sigrok_session (Filename.concat dir (ex ^ ".sr")) r.trace;
  Wave.vcd (Filename.concat dir (ex ^ ".vcd")) r.trace;
  let oc = open_out (Filename.concat dir "deadline-sequencer.expected") in
  Printf.fprintf oc "# samplerate 60000000 (one sample per chip clock); from tools/asm/examples/%s.s on the chip's RTL\n" ex;
  List.iter (fun (k, v) -> Printf.fprintf oc "%s %s\n" k v) expected;
  close_out oc

let bytes_csv l = String.concat "," (List.map string_of_int l)
let hex l = String.concat " " (List.map (Printf.sprintf "%02x") l)

(* ---- verification ---- *)

let verify ex (r : Assembler.result) =
  let vs = Verify.verify ~name:ex r in
  List.iter (fun (v : Verify.verdict) ->
      print_string ("  " ^ String.concat "\n  " (String.split_on_char '\n' (String.trim v.text)) ^ "\n");
      check (Printf.sprintf "%s: thread %d's .timing PROVED by the verifier" ex v.thread) v.ok;
      match v.cert with
      | Some c -> mkdir_p "results/certs";
        let oc = open_out (Printf.sprintf "results/certs/%s.cert" v.name) in output_string oc c; close_out oc
      | None -> ()) vs

(* the words of the compiler's programme, translated to ISA v2, against page [page] from pc 0 *)
let same_as_compiler name (r : Assembler.result) ~page (prog, len) =
  let mine = page_words r page in
  let theirs = Array.init len (fun pc -> Compat.of_base ~pc_bits:Verif.Isa.pc_bits ~addr:pc prog.(pc)) in
  let diff = List.filter (fun pc -> mine.(pc) <> theirs.(pc)) (List.init len Fun.id) in
  List.iter (fun pc -> Printf.printf "    pc %d: assembled %04x (%s), compiler %04x (%s)\n" pc mine.(pc) (Isa2.disasm mine.(pc)) theirs.(pc) (Isa2.disasm theirs.(pc))) diff;
  check (Printf.sprintf "%s: the %d words equal the compiler's, translated to ISA v2" name len) (diff = []);
  let extra = List.filter (fun (a, _) -> a lsr 8 = page && a land 0xFF >= len) r.image.prog in
  check (Printf.sprintf "%s: nothing else on the page (the compiler pads its 64 words with HALT)" name) (extra = [])

(* ---- the examples ---- *)

let uart_tx () =
  print_endline "== uart_tx: UART transmitter, 8N1, 64 clocks a bit, \"OK!\"";
  let r = assemble "uart_tx.s" in
  same_as_compiler "uart_tx" r ~page:0 (Verif.Compiler.uart_tx { upin = 0; bit_slots = 16; ubytes = [ 0x4F; 0x4B; 0x21 ]; stretch = None });
  let reference = Verif.Programmes.uart_spec ~bytes:[| 0x4F; 0x4B; 0x21 |] ~u:0 ~b:16 ~nbytes:3 ~stretch:None () in
  check "uart_tx: its .timing is the verifier's uart_spec" (same_spec (snd (List.hd r.timings)) reference);
  verify "uart_tx" r;
  let _, c = both "uart_tx" r.image ~clocks:2500 ~peers:(fun () -> []) () in
  let s = Runner.samples c in
  let got = D.uart s ~pin:0 ~bit_cycles:64 in
  Printf.printf "  decoded: %s\n" (String.concat " " (List.map (fun (t, b, ok) -> Printf.sprintf "%02x@%d%s" b t (if ok then "" else "(framing)")) got));
  check "uart_tx: decoder reads 4f 4b 21 with good stop bits" (List.map (fun (_, b, ok) -> (b, ok)) got = [ (0x4F, true); (0x4B, true); (0x21, true) ]);
  let edges = D.edges s 0 in
  let rec spacing = function (a, _) :: ((b, _) :: _ as r) -> (b - a) mod 64 = 0 && spacing r | _ -> true in
  check (Printf.sprintf "uart_tx: all %d edges a multiple of 64 clocks apart" (List.length edges)) (spacing edges);
  write_trace "uart_tx" c [ ("uart_pin", "0"); ("uart_bit_cycles", "64"); ("uart_bytes", bytes_csv [ 0x4F; 0x4B; 0x21 ]) ];
  control_rtl "uart_tx" r.image ~clocks:2500 ~peers:(fun () -> []) "pin_lane_swap"

let spi () =
  print_endline "== spi: SPI controller, mode 0, period 64 clocks, A5 3C";
  let r = assemble "spi.s" in
  same_as_compiler "spi" r ~page:0 (Verif.Compiler.spi_master { sclk = 1; mosi = 2; cs = 3; period = 16; sbytes = [ 0xA5; 0x3C ] });
  let reference = Verif.Programmes.spi_spec ~bytes:[| 0xA5; 0x3C |] ~sclk:1 ~mosi:2 ~cs:3 ~p:16 ~nbytes:2 () in
  check "spi: its .timing is the verifier's spi_spec" (same_spec (snd (List.hd r.timings)) reference);
  verify "spi" r;
  let _, c = both "spi" r.image ~clocks:1500 ~peers:(fun () -> []) () in
  let got = D.spi (Runner.samples c) ~sclk:1 ~mosi:2 ~cs:3 in
  Printf.printf "  decoded: %s\n" (hex got);
  check "spi: decoder reads a5 3c" (got = [ 0xA5; 0x3C ]);
  let rises = List.filter (fun (_, v) -> v = 1) (D.edges (Runner.samples c) 1) in
  (* within a byte: rises 1-8 of each group of eight *)
  let within = List.concat (List.mapi (fun i r -> if i mod 8 = 7 then [] else [ (r, List.nth rises (i + 1)) ]) rises) in
  check (Printf.sprintf "spi: SCLK rises 64 clocks apart within a byte (%d spacings)" (List.length within))
    (List.length rises = 16 && List.for_all (fun ((a, _), (b, _)) -> b - a = 64) within);
  write_trace "spi" c [ ("spi_sclk", "1"); ("spi_mosi", "2"); ("spi_cs", "3"); ("spi_bytes", bytes_csv [ 0xA5; 0x3C ]) ];
  control_rtl "spi" r.image ~clocks:1500 ~peers:(fun () -> []) "pin_lane_swap"

let i2c_peer ?(stretch = 0) ?(mem = Array.make 256 0) () = Peers.i2c_target ~sda:4 ~scl:5 ~addr:0x50 ~stretch mem

let i2c_write () =
  print_endline "== i2c_write: I2C controller, write A0 5A, SCL period 64 clocks, clock stretching";
  let r = assemble "i2c_write.s" in
  same_as_compiler "i2c_write" r ~page:0 (Verif.Compiler.i2c_write ~stretch_limit:4095 { sda = 4; scl = 5; q = 4; ibytes = [ 0xA0; 0x5A ] });
  let reference = Verif.Programmes.i2c_spec ~sda:4 ~scl:5 ~q:4 ~nbytes:2 ~lm:4095 in
  check "i2c_write: its .timing is the verifier's i2c_spec" (same_spec (snd (List.hd r.timings)) reference);
  verify "i2c_write" r;
  List.iter (fun stretch ->
      let name = Printf.sprintf "i2c_write (target stretches SCL by %d clocks)" stretch in
      let mem = Array.make 256 0 in
      let peer = ref None in
      let peers () = let p = i2c_peer ~stretch ~mem () in peer := Some p; [ p ] in
      let _, c = both name r.image ~clocks:3000 ~peers () in
      let got, stopped = D.i2c (Runner.samples c) ~sda:4 ~scl:5 in
      Printf.printf "  decoded: %s stop=%b; host received %s\n"
        (String.concat " " (List.map (fun (b, a) -> Printf.sprintf "%02x%s" b (if a then "+ack" else "-nak")) got)) stopped
        (hex (List.map snd c.received));
      List.iter (Printf.printf "    target: %s\n") ((Option.get !peer).report ());
      check (name ^ ": decoder reads a0+ack 5a+ack, then STOP") (got = [ (0xA0, true); (0x5A, true) ] && stopped);
      check (name ^ ": the host received the two acknowledge bits, 00 00") (c.received = [ (0, 0); (0, 0) ]);
      if stretch = 0 then
        write_trace "i2c_write" c [ ("i2c_sda", "4"); ("i2c_scl", "5"); ("i2c_bytes", bytes_csv [ 0xA0; 0x5A ]) ]) [ 0; 7 ];
  (* control: no target on the bus, so nothing acknowledges *)
  let _, c = both "i2c_write (control: no target)" r.image ~clocks:3000 ~peers:(fun () -> []) () in
  let got, _ = D.i2c (Runner.samples c) ~sda:4 ~scl:5 in
  check "i2c_write: control, without a target the decoder sees no acknowledge" (List.for_all (fun (_, a) -> not a) got && got <> []);
  control_rtl "i2c_write" r.image ~clocks:3000 ~peers:(fun () -> [ i2c_peer () ]) "uio_oe_swap"

let i2c_read () =
  print_endline "== i2c_read: I2C controller, write pointer 0x10, repeated START, read two bytes";
  let r = assemble "i2c_read.s" in
  let mem () = let m = Array.init 256 (fun i -> (i * 37 + 11) land 0xFF) in m.(0x10) <- 0x12; m.(0x11) <- 0x7A; m in
  List.iter (fun stretch ->
      let name = Printf.sprintf "i2c_read (target stretches SCL by %d clocks)" stretch in
      let peer = ref None in
      let peers () = let p = i2c_peer ~stretch ~mem:(mem ()) () in peer := Some p; [ p ] in
      let _, c = both name r.image ~clocks:4000 ~peers () in
      let got, stopped = D.i2c (Runner.samples c) ~sda:4 ~scl:5 in
      Printf.printf "  decoded: %s stop=%b; host received %s\n"
        (String.concat " " (List.map (fun (b, a) -> Printf.sprintf "%02x%s" b (if a then "+ack" else "-nak")) got)) stopped
        (String.concat " " (List.map (fun (t, b) -> Printf.sprintf "%02x/%d" b t) c.received));
      List.iter (Printf.printf "    target: %s\n") ((Option.get !peer).report ());
      check (name ^ ": decoder reads a0+ack 10+ack a1+ack 12+ack 7a-nak, STOP")
        (got = [ (0xA0, true); (0x10, true); (0xA1, true); (0x12, true); (0x7A, false) ] && stopped);
      check (name ^ ": the host received acks 00 00 00 and bytes 12 7a (tag 1)")
        (c.received = [ (0, 0); (0, 0); (0, 0); (1, 0x12); (1, 0x7A) ]);
      if stretch = 0 then
        write_trace "i2c_read" c [ ("i2c_sda", "4"); ("i2c_scl", "5"); ("i2c_frames", "w:50:10 r:50:12,7a") ]) [ 0; 5 ];
  (* control: the target holds other data; the host must see it *)
  let m = mem () in
  m.(0x10) <- 0x99;
  let _, c = both "i2c_read (control: other data)" r.image ~clocks:4000 ~peers:(fun () -> [ i2c_peer ~mem:m () ]) () in
  check "i2c_read: control, other data in the target gives other bytes" (List.mem (1, 0x99) c.received)

let uart_rx () =
  print_endline "== uart_rx: UART receiver, 64 clocks a bit, from Forencich's uart_tx and from the runner's peer";
  let r = assemble "uart_rx.s" in
  let sent = [ 0x48; 0x69; 0x21; 0x0A; 0x00; 0xFF; 0x55; 0xA5 ] in
  let _, c = both "uart_rx (stimulus: Forencich uart_tx)" r.image ~clocks:6500
      ~peers:(fun () -> [ Peers.stimulus_file "examples/uart_rx.stim" ]) () in
  Printf.printf "  host received: %s\n" (hex (List.map snd c.received));
  check "uart_rx: the host received 48 69 21 0a 00 ff 55 a5, all tag 0" (c.received = List.map (fun b -> (0, b)) sent);
  (* the runner's own transmitter, with gaps and a start at every clock phase *)
  let rng = Random.State.make [| 7 |] in
  let all_ok = ref true in
  for start = 300 to 315 do
    let bytes = List.init 6 (fun _ -> Random.State.int rng 256) in
    let gap = Random.State.int rng 40 in
    let c = Runner.run (Runner.Chip { rtl = false }) r.image (opts 5500 [ Peers.uart_tx ~net:0 ~bit:64 ~start ~gap bytes ]) in
    if c.received <> List.map (fun b -> (0, b)) bytes then begin
      all_ok := false;
      Printf.printf "    start %d gap %d: sent %s, received %s\n" start gap (hex bytes) (hex (List.map snd c.received))
    end
  done;
  check "uart_rx: runner's UART peer, 16 start phases x 6 random bytes, all received" !all_ok;
  (* control: a transmitter 12 % slow must be noticed (wrong bytes or a framing error) *)
  let c = Runner.run (Runner.Chip { rtl = false }) r.image (opts 6500 [ Peers.uart_tx ~net:0 ~bit:72 ~start:300 sent ]) in
  check "uart_rx: control, a transmitter at 72 clocks a bit is not received correctly" (c.received <> List.map (fun b -> (0, b)) sent);
  control_rtl "uart_rx" r.image ~clocks:6500 ~peers:(fun () -> [ Peers.stimulus_file "examples/uart_rx.stim" ]) "prog_byte_order"

let bridge () =
  print_endline "== bridge: UART in (thread 0) -> mailbox -> SPI out (thread 1)";
  let r = assemble "bridge.s" in
  let sent = [ 0x48; 0x69; 0x21; 0x0A; 0x00; 0xFF; 0x55; 0xA5 ] in
  let _, c = both "bridge" r.image ~clocks:7000 ~peers:(fun () -> [ Peers.stimulus_file "examples/uart_rx.stim" ]) () in
  let got = D.spi (Runner.samples c) ~sclk:1 ~mosi:2 ~cs:3 in
  Printf.printf "  SPI decoded: %s\n" (hex got);
  check "bridge: the SPI decoder reads the 8 bytes the UART received" (got = sent);
  write_trace "bridge" c [ ("spi_sclk", "1"); ("spi_mosi", "2"); ("spi_cs", "3"); ("spi_bytes", bytes_csv sent) ];
  (* control: the UART bytes from the runner's peer instead: the SPI must follow them *)
  let other = [ 0x01; 0x80; 0x7E ] in
  let c = Runner.run (Runner.Chip { rtl = false }) r.image (opts 4000 [ Peers.uart_tx ~net:0 ~bit:64 ~start:200 other ]) in
  check "bridge: control, other UART bytes give the same other SPI bytes" (D.spi (Runner.samples c) ~sclk:1 ~mosi:2 ~cs:3 = other)

(* ---- the one-bit DAC ---- *)

let dac () =
  print_endline "== dac: one-bit DAC, order 2, on 4 PEs, a 997 Hz tone from the host";
  let r = assemble "dac.s" in
  let mem = Dacdemo.Dac.pump_programme () in
  let used = List.init 43 Fun.id @ [ Dacdemo.Dac.idle_pc ] in
  let mine = page_words r 0 in
  check "dac: pump words 0-42 and the idle word equal onebit-dac's pump_programme"
    (List.for_all (fun a -> mine.(a) = mem.(a)) used);
  check "dac: nothing else in the store (pump_programme fills it with jmp 0, which demos.ml does not load either)"
    (List.length r.image.prog = List.length used);
  let d = Dacdemo.Dac.design_of "o2" in
  let ops = Array.sub (Dacdemo.Dac.run_ops d) 4 4 in
  let want = Array.to_list (Array.map (fun op -> List.rev (Array.to_list (Upe.Spec.bytes_of_op op))) ops) in
  check "dac: each segment's configuration chain equals Upe.Spec.bytes_of_op of run_ops (FB1 I1 FB2 I2)"
    (Array.to_list r.image.pecfg = want);
  check "dac: segment registers as chip-top's demo writes them (feed with lane loop and repeat 10; joins)"
    (r.image.peseg = [| [ (2, 2 lor 16 lor 64); (3, Dacdemo.Dac.period) ]; [ (2, 16) ]; [ (2, 16) ]; [ (2, 16) ] |]);
  (* the tone, and the host's stream after the four frames in the image *)
  let samples = 200 in
  let fs = 60e6 /. float Dacdemo.Dac.sample_clocks in
  let left = Array.init samples (fun i -> int_of_float (Float.round (2783. *. sin (2. *. Float.pi *. 997. *. float i /. fs)))) in
  let bytes = Dacdemo.Dac.frame_bytes left (Array.make samples 0) in
  check "dac: the image's four HOSTIN frames are the tone's first four" (r.image.hostin = Array.to_list (Array.sub bytes 0 16));
  let hostin = Array.to_list (Array.sub bytes 16 (Array.length bytes - 16)) in
  let clocks = 3000 + (samples * Dacdemo.Dac.sample_clocks) in
  let c = Runner.run (Runner.Chip { rtl = true }) r.image (opts ~hostin clocks []) in
  check "dac: chip specification and RTL equal on every pad, every clock" (c.agree = Some true);
  (* underruns may come only after the host has sent its last sample *)
  let last = samples * Dacdemo.Dac.sample_clocks in
  let under = List.filter (fun (_, t, _) -> t = 1) c.trace.outs in
  Printf.printf "  underrun reports at run clocks: %s (the stream ends near %d)\n"
    (String.concat " " (List.map (fun (k, _, b) -> Printf.sprintf "%d(byte %d)" k b) under)) last;
  check "dac: no underrun while the host has samples" (List.for_all (fun (k, _, _) -> k > last - Dacdemo.Dac.sample_clocks) under);
  check "dac: no HOSTIN or HOSTOUT overflow" (c.log = []);
  (* the pin: uo_out[0], quarter 3; F = 1 - pin. One bit every 10 clocks, at a phase found from
     where the pin changes *)
  let pin = Array.map (fun pads -> (pads.(0) lsr 3) land 1) c.trace.pads in
  let n = Array.length pin in
  let changes = Array.make 10 0 in
  for k = 1 to n - 1 do if pin.(k) <> pin.(k - 1) then changes.(k mod 10) <- changes.(k mod 10) + 1 done;
  let phase = ref 0 in
  Array.iteri (fun k x -> if x > changes.(!phase) then phase := k) changes;
  let off = (!phase + 5) mod 10 in
  let f = Array.init ((n - off) / 10) (fun j -> 1 - pin.(off + (10 * j))) in
  (* bit-exact: onebit-dac's fast model. The array runs from the moment the image sets the
     segments' run bits, before the sequencer starts, on the feed's initial word 0; so the model
     takes [pre] steps on 0 before the trace's first bit, then [lead] more on 0 until the pump's
     first word commits, then each input word for 136 steps. [pre] and [lead] are fitted (the
     first by replaying the model's states on zero input); every other bit is a prediction. *)
  let steps = Dacdemo.Dac.sample_clocks / Dacdemo.Dac.period in
  let zero_states =
    let fm = Dacdemo.Dac.fast_create d in
    Array.init 6000 (fun _ -> let st = (Array.copy fm.s, fm.g) in ignore (Dacdemo.Dac.fast_step fm 0); st) in
  let judged = min (Array.length f) ((samples - 4) * steps) in
  let wrong_of ~pre ~lead ~limit =
    let fm = Dacdemo.Dac.fast_create d in
    let s0, g0 = zero_states.(pre) in
    Array.blit s0 0 fm.s 0 (Array.length s0); fm.g <- g0;
    let wrong = ref 0 and j = ref 0 in
    while !j < judged && !wrong <= limit do
      let w = if !j < lead then 0 else left.(min (samples - 1) ((!j - lead) / steps)) land 0xFFFF in
      if (if Dacdemo.Dac.fast_step fm w then 1 else 0) <> f.(!j) then incr wrong;
      incr j
    done;
    !wrong in
  let fits = ref [] in
  for pre = 0 to Array.length zero_states - 1 do
    for lead = 0 to 80 do
      if wrong_of ~pre ~lead ~limit:0 = 0 then fits := (pre, lead) :: !fits
    done
  done;
  if Sys.getenv_opt "DAC_DEBUG" <> None then begin
    let best = ref (max_int, 0, 0) in
    for pre = 0 to Array.length zero_states - 1 do
      for lead = 0 to 80 do
        let w = wrong_of ~pre ~lead ~limit:300 in
        let b, _, _ = !best in if w < b then best := (w, pre, lead)
      done
    done;
    let w, pre, lead = !best in
    Printf.printf "  debug: best (pre %d, lead %d): %d wrong (counting stops at 301)\n" pre lead w;
    (* where the errors are *)
    let fm = Dacdemo.Dac.fast_create d in
    let s0, g0 = zero_states.(pre) in
    Array.blit s0 0 fm.s 0 (Array.length s0); fm.g <- g0;
    let errs = ref [] in
    for j = 0 to judged - 1 do
      let x = if j < lead then 0 else left.(min (samples - 1) ((j - lead) / steps)) land 0xFFFF in
      if (if Dacdemo.Dac.fast_step fm x then 1 else 0) <> f.(j) then errs := j :: !errs
    done;
    for pre = 0 to 40 do
      let bestlen = ref (0, 0) in
      for lead = 0 to 80 do
        let fm = Dacdemo.Dac.fast_create d in
        let s0, g0 = zero_states.(pre) in
        Array.blit s0 0 fm.s 0 (Array.length s0); fm.g <- g0;
        let j = ref 0 and ok = ref true in
        while !ok && !j < judged do
          let x = if !j < lead then 0 else left.(min (samples - 1) ((!j - lead) / steps)) land 0xFFFF in
          if (if Dacdemo.Dac.fast_step fm x then 1 else 0) <> f.(!j) then ok := false else incr j
        done;
        if !j > fst !bestlen then bestlen := (!j, lead)
      done;
      Printf.printf "  debug: pre %d: longest matching prefix %d (lead %d)\n" pre (fst !bestlen) (snd !bestlen)
    done;
    Printf.printf "  debug: pin changes by clock mod 10: %s\n" (String.concat " " (Array.to_list (Array.map string_of_int changes)));
    Printf.printf "  debug: f[0..99] = %s\n" (String.concat "" (List.init 100 (fun j -> string_of_int f.(j))));
    let fz = Dacdemo.Dac.fast_create d in
    Printf.printf "  debug: zero    = %s\n" (String.concat "" (List.init 100 (fun _ -> if Dacdemo.Dac.fast_step fz 0 then "1" else "0")));
    Printf.printf "  debug: first errors at steps %s\n" (String.concat " " (List.map string_of_int (List.filteri (fun i _ -> i < 30) (List.rev !errs))))
  end;
  (match !fits with
   | (pre, lead) :: _ ->
     Printf.printf "  bit stream: %d steps judged; %d (pre-run zero steps, lead-in) pairs of the %d tried give 0 wrong bits, e.g. (%d, %d)\n"
       judged (List.length !fits) (6000 * 81) pre lead
   | [] -> Printf.printf "  bit stream: %d steps judged; no fit gives 0 wrong bits\n" judged);
  let distinct_leads = List.sort_uniq compare (List.map snd !fits) in
  check "dac: the pin's bits equal the modulator's bit-exact model (0 wrong bits, one lead-in fits)"
    (!fits <> [] && List.length distinct_leads = 1);
  let start, lead = match !fits with (_, l) :: _ -> (0, l) | [] -> (0, 0) in
  (* control: the order-3 model must not fit *)
  let d3 = Dacdemo.Dac.design_of "o3" in
  let fm = Dacdemo.Dac.fast_create d3 in
  let wrong3 = ref 0 in
  for j = 0 to judged - 1 do
    let w = if j < lead then 0 else left.(min (samples - 1) ((j - lead) / steps)) land 0xFFFF in
    if (if Dacdemo.Dac.fast_step fm w then 1 else 0) <> f.(j) then incr wrong3
  done;
  Printf.printf "  control: the order-3 model gets %d of %d bits wrong\n" !wrong3 judged;
  check "dac: control, the order-3 model does not fit (over 10 % wrong)" (!wrong3 * 10 > judged);
  (* independent of the model: low-pass the +-1 stream (a mean over each sample's 136 steps) and
     correlate it with the input samples *)
  let y = Array.map (fun b -> 1. -. (2. *. float b)) f in
  let nsamp = (Array.length y - start - lead) / steps in
  let mean s = let a = ref 0. in for j = 0 to steps - 1 do a := !a +. y.(start + lead + (s * steps) + j) done; !a /. float steps in
  let m = Array.init (min nsamp samples) mean in
  let corr lag =
    let xs = Array.init (Array.length m - 4) (fun s -> float left.(s)) and ys = Array.init (Array.length m - 4) (fun s -> m.(s + lag)) in
    let k = float (Array.length xs) in
    let mx = Array.fold_left ( +. ) 0. xs /. k and my = Array.fold_left ( +. ) 0. ys /. k in
    let sxy = ref 0. and sxx = ref 0. and syy = ref 0. in
    Array.iteri (fun i x -> let a = x -. mx and b = ys.(i) -. my in sxy := !sxy +. (a *. b); sxx := !sxx +. (a *. a); syy := !syy +. (b *. b)) xs;
    !sxy /. sqrt (!sxx *. !syy), !sxy /. !sxx in
  let r0, gain = corr 0 in
  let r1, _ = corr 1 in
  Printf.printf "  low-pass decode: correlation with the input %.4f (lag 0), %.4f (lag 1); gain %.3g per LSB\n" r0 r1 gain;
  check "dac: low-passed pin correlates with the input tone (r > 0.99)" (max r0 r1 > 0.99);
  (* control: the same comparison against a tone of another frequency must fail *)
  let other = Array.init samples (fun i -> sin (2. *. Float.pi *. 1500. *. float i /. fs)) in
  let k = Array.length m - 4 in
  let rc =
    let xs = Array.sub other 0 k and ys = Array.sub m 0 k in
    let mx = Array.fold_left ( +. ) 0. xs /. float k and my = Array.fold_left ( +. ) 0. ys /. float k in
    let sxy = ref 0. and sxx = ref 0. and syy = ref 0. in
    Array.iteri (fun i x -> let a = x -. mx and b = ys.(i) -. my in sxy := !sxy +. (a *. b); sxx := !sxx +. (a *. a); syy := !syy +. (b *. b)) xs;
    !sxy /. sqrt (!sxx *. !syy) in
  Printf.printf "  control: correlation with a 1500 Hz tone %.4f\n" rc;
  check "dac: control, a 1500 Hz tone does not correlate (|r| < 0.5)" (Float.abs rc < 0.5);
  control_rtl "dac" r.image ~clocks:20000 ~peers:(fun () -> []) "pecfg_seg";
  mkdir_p "results/traces/dac";
  Wave.vcd "results/traces/dac/dac.vcd" { c.trace with nets = Array.sub c.trace.nets 0 20000; pcs = Array.sub c.trace.pcs 0 20000; pads = Array.sub c.trace.pads 0 20000 }

(* ---- WS2812 (docs/tutorial.md) ---- *)

(* A WS2812 receiver written from the WS2812B datasheet: a high pulse of 0.40 us is a 0 and of
   0.80 us a 1 (each +-150 ns); the low after it is 0.85 us after a 0 and 0.45 us after a 1 (each
   +-150 ns); a low of 50 us or more ends the frame. Times are clocks at 60 MHz. Returns the frames
   as byte lists, and the timing violations seen. *)
let ws2812_decode (s : D.sample list) ~pin =
  let ns clocks = float clocks *. 1000. /. 60. in
  let edges = D.edges s pin in
  let frames = ref [] and bits = ref [] and errors = ref [] in
  let flush () =
    if !bits <> [] then begin
      let b = List.rev !bits in
      if List.length b mod 8 <> 0 then errors := Printf.sprintf "frame of %d bits" (List.length b) :: !errors;
      let rec bytes = function
        | b0 :: b1 :: b2 :: b3 :: b4 :: b5 :: b6 :: b7 :: r ->
          ((b0 lsl 7) lor (b1 lsl 6) lor (b2 lsl 5) lor (b3 lsl 4) lor (b4 lsl 3) lor (b5 lsl 2) lor (b6 lsl 1) lor b7) :: bytes r
        | _ -> [] in
      frames := bytes b :: !frames; bits := []
    end in
  let rec go = function
    | (r, 1) :: (f, 0) :: rest ->
      let th = ns (f - r) in
      let bit = if th >= 250. && th <= 550. then Some 0 else if th >= 650. && th <= 950. then Some 1 else None in
      (match bit with
       | None -> errors := Printf.sprintf "high of %.0f ns at clock %d" th r :: !errors
       | Some b ->
         bits := b :: !bits;
         (match rest with
          | (r', 1) :: _ ->
            let tl = ns (r' - f) in
            if tl >= 50_000. then flush ()
            else if (b = 0 && (tl < 700. || tl > 1000.)) || (b = 1 && (tl < 300. || tl > 600.)) then
              errors := Printf.sprintf "low of %.0f ns after a %d at clock %d" tl b f :: !errors
          | _ -> flush ()));
      go rest
    | _ :: rest -> go rest
    | [] -> flush () in
  go edges;
  (List.rev !frames, List.rev !errors)

let ws2812 () =
  print_endline "== ws2812: WS2812 LED string, two LEDs (docs/tutorial.md)";
  let r = assemble "ws2812.s" in
  verify "ws2812" r;
  let clocks = 40000 in
  let _, c = both "ws2812" r.image ~clocks ~peers:(fun () -> []) () in
  let frames, errors = ws2812_decode (Runner.samples c) ~pin:0 in
  Printf.printf "  decoded: %s; timing violations: %d\n" (String.concat " | " (List.map hex frames)) (List.length errors);
  List.iter (Printf.printf "    %s\n") errors;
  check "ws2812: datasheet decoder reads one frame 12 34 56 9a bc de, every pulse in tolerance"
    (frames = [ [ 0x12; 0x34; 0x56; 0x9A; 0xBC; 0xDE ] ] && errors = []);
  write_trace "ws2812" c [ ("ws2812_pin", "0"); ("ws2812_rgb", "#341256,#bc9ade") ];
  (* controls: a high part one slot short is rejected by the verifier and by the decoder *)
  let src = read_file "examples/ws2812.s" in
  let bad = Str.replace_first (Str.regexp_string "    delay HIGH - 1          ; s+1 .. s+5") "    delay HIGH - 2" src in
  let rb = Assembler.assemble_string ~include_dirs:[ "lib"; "examples" ] ~name:"ws2812 (high part one slot short)" bad in
  let vs = Verify.verify ~name:"ws2812-short" rb in
  check "ws2812: control, high part one slot short: the verifier rejects it" (List.exists (fun (v : Verify.verdict) -> not v.ok) vs);
  let short = Str.replace_first (Str.regexp_string "    delay HIGH - 1          ; s+1 .. s+5") "    nop" src in
  let rs = Assembler.assemble_string ~include_dirs:[ "lib"; "examples" ] ~name:"ws2812 (high part 2 slots)" short in
  let cs = Runner.run (Runner.Chip { rtl = false }) rs.image (opts clocks []) in
  let _, errs = ws2812_decode (Runner.samples cs) ~pin:0 in
  check "ws2812: control, a 133 ns high part: the decoder reports timing violations" (errs <> []);
  let other = Str.replace_first (Str.regexp_string "0x12, 0x34") "0x13, 0x34" src in
  let ro = Assembler.assemble_string ~include_dirs:[ "lib"; "examples" ] ~name:"ws2812 (other colour)" other in
  let co = Runner.run (Runner.Chip { rtl = false }) ro.image (opts clocks []) in
  check "ws2812: control, another colour in the bank is decoded as that colour"
    (fst (ws2812_decode (Runner.samples co) ~pin:0) = [ [ 0x13; 0x34; 0x56; 0x9A; 0xBC; 0xDE ] ])

let all = [ ("uart_tx", uart_tx); ("spi", spi); ("i2c_write", i2c_write); ("i2c_read", i2c_read); ("uart_rx", uart_rx);
            ("bridge", bridge); ("ws2812", ws2812); ("dac", dac) ]

let () =
  let names = List.tl (Array.to_list Sys.argv) in
  List.iter (fun (n, f) ->
      if names = [] || List.mem n names then
        (try f () with Loc.Error (l, m) -> check (n ^ ": " ^ Loc.message l m) false)) all;
  if !failures = 0 then print_endline "EXAMPLES: ALL PASS"
  else (Printf.printf "EXAMPLES: %d FAILURES\n" !failures; exit 1)
