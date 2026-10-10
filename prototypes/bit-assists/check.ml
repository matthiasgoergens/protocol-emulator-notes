(* Checks of the bit-path assists.

     check.exe blocks CLOCKS      the stuff tracker and the line coder: RTL against model in
                                  lockstep, every clock, with random configurations, restarts and
                                  traffic; then the RTL against independent references (USB,
                                  CAN, 10BASE-T); round trips; the planted faults
     check.exe paths CLOCKS       the transmit serialiser and the receive framer built from them:
                                  the same, with whole frames
*)
open Hardcaml

let pr = Printf.printf

(* ---------------- the stuff tracker and the line coder in lockstep ---------------- *)

(* One circuit with both stuff directions and both coder directions, every input free. *)
let blocks_circuit () =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let restart = input "restart" 1 in
  let scfg : Stuff.cfg_signals = { s_run = input "run" 4; s_either = input "either" 1; s_value = input "value" 1 } in
  let lcfg : Linecode.cfg_signals = { s_mode = input "mode" 2; s_invert = input "invert" 1; s_toggle_on = input "toggle_on" 1 } in
  let tx = Stuff.tx ~clock ~clear ~restart ~cfg:scfg ~due:(input "due" 1) ~data_bit:(input "data_bit" 1) ~data_valid:(input "data_valid" 1) in
  let rx = Stuff.rx ~clock ~clear ~restart ~cfg:scfg ~valid:(input "rx_valid" 1) ~b:(input "rx_bit" 1) () in
  let enc = Linecode.encoder ~clock ~clear ~restart ~cfg:lcfg ~tick:(input "tick" 1) ~bit:(input "enc_bit" 1) in
  let dec = Linecode.decoder ~clock ~clear ~cfg:lcfg ~valid:(input "sym_valid" 1) ~sym:(input "sym" 1) in
  Circuit.create_exn ~name:"bit_assists_blocks"
    [ output "tx_bit" tx.out_bit; output "tx_take" tx.take; output "tx_stuffed" tx.stuffed; output "tx_underrun" tx.underrun;
      output "rx_keep" rx.keep; output "rx_err" rx.err;
      output "need_bit" enc.need_bit; output "line" enc.line;
      output "dec_valid" dec.out_valid; output "dec_bit" dec.out_bit; output "dec_err" dec.err ]

let random_stuff_cfg r : Stuff.cfg =
  match Random.State.int r 5 with
  | 0 -> Stuff.usb | 1 -> Stuff.can | 2 -> Stuff.hdlc
  | 3 -> Stuff.off
  | _ ->
    (* in either mode a stuff bit starts a run of one, so a run of 1 would stuff for ever: 2 or more *)
    let either = Random.State.bool r in
    { run = (let k = Random.State.int r 16 in if either && k = 1 then 2 else k); either; value = Random.State.int r 2 }

let random_lc_cfg r : Linecode.cfg =
  { mode = Linecode.mode_of_code (Random.State.int r 4); invert = Random.State.bool r; toggle_on = Random.State.int r 2 }

(* A bit source biased towards runs, so that stuffing and long NRZI runs happen. *)
let biased_bits r =
  let cur = ref 0 and left = ref 0 in
  fun () ->
    if !left = 0 then begin
      cur := Random.State.int r 2;
      left := (match Random.State.int r 4 with 0 -> 1 + Random.State.int r 3 | 1 -> 5 + Random.State.int r 4 | _ -> 1 + Random.State.int r 8)
    end;
    decr left; !cur

(* Returns the number of mismatching clocks and the first few differences. *)
let blocks_lockstep ~clocks ~seed =
  let sim = Cyclesim.create (blocks_circuit ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port ~clock_edge:Before sim n in
  let set n v = i n := Bits.of_int ~width:(Bits.width !(i n)) v in
  let get n = Bits.to_int !(o n) in
  let r = Random.State.make [| seed |] in
  let sc = ref (random_stuff_cfg r) and lc = ref (random_lc_cfg r) in
  let txs = Stuff.init () and rxs = Stuff.init () and enc = Linecode.enc_init () and dec = Linecode.dec_init () in
  let line = ref 0 in
  let bits_tx = biased_bits r and bits_rx = biased_bits r and bits_enc = biased_bits r and bits_sym = biased_bits r in
  set "clear" 1; Cyclesim.cycle sim; set "clear" 0;
  let bad = ref 0 and diffs = ref [] in
  for c = 0 to clocks - 1 do
    if Random.State.int r 500 = 0 then sc := random_stuff_cfg r;
    if Random.State.int r 500 = 0 then lc := random_lc_cfg r;
    let restart = Random.State.int r 300 = 0 in
    let due = Random.State.int r 3 > 0 and dv = Random.State.int r 8 > 0 and db = bits_tx () in
    let rv = Random.State.int r 3 > 0 and rb = bits_rx () in
    let tick = Random.State.int r 3 > 0 and eb = bits_enc () in
    let sv = Random.State.int r 3 > 0 and sy = bits_sym () in
    let s = !sc and l = !lc in
    set "run" s.run; set "either" (Bool.to_int s.either); set "value" s.value;
    set "mode" (Linecode.mode_code l.mode); set "invert" (Bool.to_int l.invert); set "toggle_on" l.toggle_on;
    set "restart" (Bool.to_int restart);
    set "due" (Bool.to_int due); set "data_bit" db; set "data_valid" (Bool.to_int dv);
    set "rx_valid" (Bool.to_int rv); set "rx_bit" rb;
    set "tick" (Bool.to_int tick); set "enc_bit" eb;
    set "sym_valid" (Bool.to_int sv); set "sym" sy;
    Cyclesim.cycle_check sim;
    Cyclesim.cycle_before_clock_edge sim;
    (* the model, from the state at the start of the clock *)
    let d = ref [] in
    let cmp name a b = if a <> b then d := Printf.sprintf "%s: model %d rtl %d" name a b :: !d in
    (* transmit stuffer *)
    if due then begin
      let x = Stuff.tx_peek s txs ~data:(if dv then Some db else None) in
      (match x with
       | Stuff.Stuffed b -> cmp "tx bit" b (get "tx_bit"); cmp "tx stuffed" 1 (get "tx_stuffed"); cmp "tx take" 0 (get "tx_take")
       | Stuff.Data b -> cmp "tx bit" b (get "tx_bit"); cmp "tx stuffed" 0 (get "tx_stuffed"); cmp "tx take" 1 (get "tx_take")
       | Stuff.Underrun -> cmp "tx underrun" 1 (get "tx_underrun"); cmp "tx take" 0 (get "tx_take"));
      if restart then Stuff.restart txs else Stuff.tx_commit s txs x
    end
    else begin
      cmp "tx take (idle)" 0 (get "tx_take"); cmp "tx stuffed (idle)" 0 (get "tx_stuffed");
      if restart then Stuff.restart txs
    end;
    (* receive destuffer *)
    if rv then begin
      let snap = { Stuff.cnt = rxs.cnt; last = rxs.last } in
      let keep, err = Stuff.rx_step s snap rb in
      cmp "rx keep" (Bool.to_int keep) (get "rx_keep"); cmp "rx err" (Bool.to_int err) (get "rx_err");
      if restart then Stuff.restart rxs else (rxs.cnt <- snap.cnt; rxs.last <- snap.last)
    end
    else begin
      cmp "rx keep (idle)" 0 (get "rx_keep"); cmp "rx err (idle)" 0 (get "rx_err");
      if restart then Stuff.restart rxs
    end;
    (* encoder *)
    cmp "need bit" (Bool.to_int (Linecode.need_bit l enc)) (get "need_bit");
    cmp "line" !line (get "line");
    if tick then line := Linecode.enc_tick l enc ~bit:eb;
    if restart then Linecode.enc_restart enc;
    (* decoder *)
    if sv then begin
      match Linecode.dec_step l dec sy with
      | Some b, e -> cmp "dec valid" 1 (get "dec_valid"); cmp "dec bit" b (get "dec_bit"); cmp "dec err" (Bool.to_int e) (get "dec_err")
      | None, _ -> cmp "dec valid" 0 (get "dec_valid"); cmp "dec err" 0 (get "dec_err")
    end
    else cmp "dec valid (idle)" 0 (get "dec_valid");
    Cyclesim.cycle_at_clock_edge sim;
    Cyclesim.cycle_after_clock_edge sim;
    if !d <> [] then begin
      incr bad;
      if List.length !diffs < 3 then diffs := Printf.sprintf "clock %d: %s" c (String.concat "; " (List.rev !d)) :: !diffs
    end
  done;
  (!bad, List.rev !diffs)

(* ---------------- the RTL against independent references ---------------- *)

(* The RTL's transmit chain on a bit list: stuffer, then encoder, one symbol per clock; a stuff bit
   due after the last data bit is sent too. Returns the symbols. *)
let rtl_tx_chain (s : Stuff.cfg) (l : Linecode.cfg) bits =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let tick = input "tick" 1 and data_bit = input "data_bit" 1 and data_valid = input "data_valid" 1 in
  let need = wire 1 in
  let tx = Stuff.tx ~clock ~clear ~restart:gnd ~cfg:(Stuff.cfg_const s) ~due:(tick &: need) ~data_bit ~data_valid in
  let enc = Linecode.encoder ~clock ~clear ~restart:gnd ~cfg:(Linecode.cfg_const l) ~tick ~bit:tx.out_bit in
  need <== enc.need_bit;
  let c = Circuit.create_exn ~name:"tx_chain" [ output "line" enc.line; output "take" tx.take; output "underrun" tx.underrun; output "need" enc.need_bit ] in
  let sim = Cyclesim.create c in
  (* an input the circuit does not use (clear, in a configuration without state) is not a port *)
  let dummy = ref Bits.gnd in
  let i n = try Cyclesim.in_port sim n with _ -> dummy and o n = Cyclesim.out_port ~clock_edge:Before sim n in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let rest = ref bits and out = ref [] and first = ref true and fin = ref false and n = ref 0 in
  while not !fin && !n < 100_000 do
    incr n;
    (match !rest with b :: _ -> i "data_valid" := Bits.vdd; i "data_bit" := Bits.of_int ~width:1 b | [] -> i "data_valid" := Bits.gnd);
    i "tick" := Bits.vdd;
    Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim;
    if not !first then out := Bits.to_int !(o "line") :: !out;
    first := false;
    let need = Bits.to_int !(o "need") = 1 in
    if Bits.to_int !(o "take") = 1 then rest := List.tl !rest;
    if need && Bits.to_int !(o "underrun") = 1 then fin := true;
    Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim
  done;
  List.rev !out

(* The RTL's receive chain on a symbol list: decoder, then destuffer. Returns (bits, violations,
   Manchester code violations). *)
let rtl_rx_chain (s : Stuff.cfg) (l : Linecode.cfg) syms =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let valid = input "valid" 1 and sym = input "sym" 1 in
  let dec = Linecode.decoder ~clock ~clear ~cfg:(Linecode.cfg_const l) ~valid ~sym in
  let rx = Stuff.rx ~clock ~clear ~restart:gnd ~cfg:(Stuff.cfg_const s) ~valid:dec.out_valid ~b:dec.out_bit () in
  let c = Circuit.create_exn ~name:"rx_chain" [ output "keep" rx.keep; output "bit" dec.out_bit; output "err" rx.err; output "cerr" dec.err ] in
  let sim = Cyclesim.create c in
  (* an input the circuit does not use (clear, in a configuration without state) is not a port *)
  let dummy = ref Bits.gnd in
  let i n = try Cyclesim.in_port sim n with _ -> dummy and o n = Cyclesim.out_port ~clock_edge:Before sim n in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let out = ref [] and errs = ref 0 and cerrs = ref 0 in
  List.iter (fun x ->
      i "valid" := Bits.vdd; i "sym" := Bits.of_int ~width:1 x;
      Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim;
      if Bits.to_int !(o "keep") = 1 then out := Bits.to_int !(o "bit") :: !out;
      errs := !errs + Bits.to_int !(o "err"); cerrs := !cerrs + Bits.to_int !(o "cerr");
      Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim) syms;
  (List.rev !out, !errs, !cerrs)

let bits_of_bytes ?(msb = false) bytes = List.concat_map (fun b -> List.init 8 (fun i -> (b lsr (if msb then 7 - i else i)) land 1)) bytes

let random_bytes r n = List.init n (fun _ -> match Random.State.int r 4 with 0 -> 0xFF | 1 -> 0x00 | 2 -> 0x7F | _ -> Random.State.int r 256)

let ok b = if b then "ok" else "FAIL"

let references ~seed =
  let r = Random.State.make [| seed |] in
  let all_ok = ref true in
  let report name good total = if good <> total then all_ok := false; pr "  %-70s %d of %d %s\n" name good total (ok (good = total)) in
  (* USB: ../usb-ls/fw_codec.ml's device-side encoder (sync, stuffing after six 1s, NRZI, EOP),
     written for the firmware device; J = idle = level 0 here *)
  let n = 300 in
  let good = ref 0 and good_rx = ref 0 in
  for _ = 1 to n do
    let bytes = random_bytes r (1 + Random.State.int r 12) in
    let refsyms = Fw_codec.symbols bytes in
    let refsyms = List.filteri (fun i _ -> i < List.length refsyms - 3) refsyms in   (* without the EOP *)
    let ref_lv = List.map (fun s -> if s = Fw_codec.sym_j then 0 else 1) refsyms in
    let mine = rtl_tx_chain Stuff.usb Linecode.usb (bits_of_bytes (0x80 :: bytes)) in
    if mine = ref_lv then incr good;
    let bits, errs, _ = rtl_rx_chain Stuff.usb Linecode.usb ref_lv in
    if bits = bits_of_bytes (0x80 :: bytes) && errs = 0 then incr good_rx
  done;
  report "USB: RTL transmit chain = usb-ls fw_codec symbols (random packets)" !good n;
  report "USB: RTL receive chain on fw_codec symbols gives the packet back, no violation" !good_rx n;
  (* a missing stuff bit is a violation: fw_codec's stream with one stuff symbol removed *)
  let caught = ref 0 and tried = ref 0 in
  for _ = 1 to n do
    let bytes = 0xFF :: random_bytes r (Random.State.int r 8) in
    let bits = bits_of_bytes (0x80 :: bytes) in
    let stuffed = Stuff.stuff_list Stuff.usb bits in
    (* the position of the first stuff bit: where the stuffed stream first differs from the data *)
    let rec first_diff k a b = match a, b with x :: a', y :: b' when x = y -> first_diff (k + 1) a' b' | _ -> k in
    let k = first_diff 0 stuffed bits in
    if k < List.length stuffed then begin
      incr tried;
      let dropped = List.filteri (fun i _ -> i <> k) stuffed in
      let lv = Linecode.encode_list Linecode.usb dropped in
      let _, errs, _ = rtl_rx_chain Stuff.usb Linecode.usb lv in
      if errs > 0 then incr caught
    end
  done;
  report "USB: a missing stuff bit is a violation (RTL receive chain)" !caught !tried;
  (* CAN: ../sequencer-ps2-can's host stuffer (either value, five), copied in refs/can_stuff.ml *)
  let good = ref 0 and good_rx = ref 0 in
  for _ = 1 to n do
    let bits = List.init (1 + Random.State.int r 100) (fun _ -> 0) |> List.map (fun _ -> if Random.State.int r 3 = 0 then Random.State.int r 2 else 2) in
    (* runs: 2 means "repeat the previous" *)
    let bits = let p = ref 0 in List.map (fun b -> (if b <> 2 then p := b); !p) bits in
    let refst = Can_stuff.stuff bits in
    let mine = rtl_tx_chain Stuff.can Linecode.pass bits in
    if mine = refst then incr good;
    let back, errs, _ = rtl_rx_chain Stuff.can Linecode.pass refst in
    if back = bits && errs = 0 then incr good_rx
  done;
  report "CAN: RTL transmit stuffer = sequencer-ps2-can's stuffer (runs of either value)" !good n;
  report "CAN: RTL destuffer on that stream gives the bits back, no violation" !good_rx n;
  (* 10BASE-T: ../ethernet-10base-t/eth_model.ml's Manchester (a 1 low then high), half a bit per
     symbol (h = 1) *)
  let good = ref 0 and good_rx = ref 0 in
  for _ = 1 to n do
    let bytes = random_bytes r (1 + Random.State.int r 20) in
    let refsyms = Eth_model.manchester ~h:1 bytes in
    let refsyms = List.filteri (fun i _ -> i < 16 * List.length bytes) refsyms |> List.map (fun v -> if v > 0 then 1 else 0) in
    let mine = rtl_tx_chain Stuff.off Linecode.ieee_manchester (bits_of_bytes bytes) in
    if mine = refsyms then incr good;
    let back, errs, cerrs = rtl_rx_chain Stuff.off Linecode.ieee_manchester refsyms in
    if back = bits_of_bytes bytes && errs = 0 && cerrs = 0 then incr good_rx
  done;
  report "10BASE-T: RTL Manchester encoder = eth_model's Manchester" !good n;
  report "10BASE-T: RTL Manchester decoder on it gives the bits back, no code violation" !good_rx n;
  (* Manchester code violations: two equal halves *)
  let caught = ref 0 in
  for _ = 1 to n do
    let bits = bits_of_bytes (random_bytes r (1 + Random.State.int r 4)) in
    let syms = Linecode.encode_list Linecode.ieee_manchester bits in
    let k = 2 * Random.State.int r (List.length bits) in
    let syms = List.mapi (fun i s -> if i = k then 1 - s else s) syms in
    let _, _, cerrs = rtl_rx_chain Stuff.off Linecode.ieee_manchester syms in
    if cerrs > 0 then incr caught
  done;
  report "Manchester: a flipped half-bit is a code violation (RTL decoder)" !caught n;
  (* round trips through the RTL, every configuration *)
  let good = ref 0 in
  for _ = 1 to n do
    let s = random_stuff_cfg r and l = { (random_lc_cfg r) with invert = Random.State.bool r } in
    let src = biased_bits r in
    let bits = List.init (1 + Random.State.int r 80) (fun _ -> src ()) in
    let syms = rtl_tx_chain s l bits in
    let back, errs, cerrs = rtl_rx_chain s l syms in
    (* a final stuff bit is dropped by the receiver like any other *)
    if back = bits && errs = 0 && cerrs = 0 then incr good
  done;
  report "round trip, random configurations: RTL receive (RTL transmit x) = x" !good n;
  !all_ok

let run_blocks clocks =
  let t0 = Unix.gettimeofday () in
  Stuff.bug := ""; Linecode.bug := "";
  let ok_all = ref true in
  pr "== stuff tracker and line coder: RTL against model, every clock\n";
  for seed = 1 to 4 do
    let bad, diffs = blocks_lockstep ~clocks ~seed in
    pr "  seed %d: %d clocks, %d mismatching %s\n" seed clocks bad (ok (bad = 0));
    List.iter (pr "    %s\n") diffs;
    if bad > 0 then ok_all := false
  done;
  pr "== against independent references, through the RTL\n";
  if not (references ~seed:7) then ok_all := false;
  pr "== planted faults: each must be caught by the lockstep (first seed that catches it)\n";
  let caught = ref 0 and total = ref 0 in
  let try_bug set name what =
    incr total;
    set name;
    let rec go seed = if seed > 8 then None else (let bad, d = blocks_lockstep ~clocks:(min clocks 20000) ~seed in if bad > 0 then Some (seed, d) else go (seed + 1)) in
    (match go 1 with
     | Some (seed, d) -> incr caught; pr "  %-28s caught (seed %d; %s)  %s\n" name seed (List.hd d) what
     | None -> pr "  %-28s MISSED  %s\n" name what);
    set "" in
  List.iter (fun (b, w) -> try_bug (fun n -> Stuff.bug := n) b w) Stuff.bugs;
  List.iter (fun (b, w) -> try_bug (fun n -> Linecode.bug := n) b w) Linecode.bugs;
  pr "%d of %d planted faults caught\n" !caught !total;
  (* the references must be able to fail: each fault against them (quietly) *)
  let noticed = ref [] in
  let quiet f = let saved = Unix.dup Unix.stdout in let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
    flush stdout; Unix.dup2 null Unix.stdout; let v = f () in flush stdout; Unix.dup2 saved Unix.stdout; Unix.close null; v in
  List.iter (fun (set, (b, _)) -> set b; if not (quiet (fun () -> references ~seed:7)) then noticed := b :: !noticed; set "")
    (List.map (fun x -> ((fun n -> Stuff.bug := n), x)) Stuff.bugs @ List.map (fun x -> ((fun n -> Linecode.bug := n), x)) Linecode.bugs);
  pr "the independent references alone fail with %d of the %d faults: %s\n" (List.length !noticed) !total
    (String.concat ", " (List.rev !noticed));
  if !caught < !total then ok_all := false;
  pr "blocks: %s (%.0f s)\n" (if !ok_all then "PASS" else "FAIL") (Unix.gettimeofday () -. t0);
  !ok_all

(* ---------------- the transmit serialiser and the receive framer ---------------- *)

let tx_cfg_inputs prefix : Txpath.cfg_signals =
  let open Signal in
  let i n w = input (prefix ^ n) w in
  let tail k : Txpath.tail_signals = { s_len = i (Printf.sprintf "t%dlen" k) 4; s_la = i (Printf.sprintf "t%da" k) 1; s_lb = i (Printf.sprintf "t%db" k) 1 } in
  { s_period = i "period" 12; s_msb = i "msb" 1;
    s_stuff = { s_run = i "run" 4; s_either = i "either" 1; s_value = i "value" 1 };
    s_code = { s_mode = i "mode" 2; s_invert = i "invert" 1; s_toggle_on = i "toggle_on" 1 };
    s_tail1 = tail 1; s_tail2 = tail 2 }

let rx_cfg_inputs prefix : Rxpath.cfg_signals =
  let open Signal in
  let i n w = input (prefix ^ n) w in
  { s_code = { s_mode = i "mode" 2; s_invert = i "invert" 1; s_toggle_on = i "toggle_on" 1 };
    s_stuff = { s_run = i "run" 4; s_either = i "either" 1; s_value = i "value" 1 };
    s_msb = i "msb" 1; s_pattern = i "pattern" 8; s_pmask = i "pmask" 8; s_start_on_pattern = i "sop" 1;
    s_half_duplex = i "hd" 1; s_end_inactive = i "ei" 1; s_end_burst = i "eb" 1; s_skip = i "skip" 8 }

let paths_circuit () =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let t = Txpath.create ~clock ~clear ~cfg:(tx_cfg_inputs "tx_") ~push:(input "push" 1) ~push_data:(input "push_data" 8) in
  let r =
    Rxpath.create ~clock ~clear ~cfg:(rx_cfg_inputs "rx_") ~bit:(input "bit" 1) ~valid:(input "valid" 1) ~active:(input "active" 1)
      ~burst_end:(input "burst_end" 1) ~start:(input "start" 1) ~stop:(input "stop" 1) ~tx_active:t.active ~pop:(input "pop" 1) in
  Circuit.create_exn ~name:"bit_paths"
    ([ output "tx_a" t.a; output "tx_b" t.b; output "tx_busy" t.busy; output "tx_active" t.active; output "tx_count" t.count;
       output "tx_accept" t.accept;
       output "rx_head" r.head; output "rx_nonempty" r.nonempty; output "rx_count" r.count; output "rx_in_frame" r.in_frame;
       output "rx_done" r.done_; output "rx_err" r.err; output "rx_ovf" r.ovf; output "crc_bit" r.crc_bit;
       output "crc_valid" r.crc_valid; output "frame_start" r.frame_start ]
     @ List.map (fun (n, s) -> output n s) r.dbg)

let random_tail r : Txpath.tail = { len = (if Random.State.int r 3 = 0 then 0 else Random.State.int r 16); la = Random.State.int r 2; lb = Random.State.int r 2 }

let random_tx_cfg r : Txpath.cfg =
  match Random.State.int r 4 with
  | 0 -> { Txpath.usb_ls with period = 1 + Random.State.int r 6 }
  | 1 -> Txpath.eth10
  | _ ->
    { period = (match Random.State.int r 4 with 0 -> 0 | 1 -> 1 | 2 -> 2 + Random.State.int r 6 | _ -> Random.State.int r 4096);
      msb_first = Random.State.bool r; stuff = random_stuff_cfg r; code = random_lc_cfg r; tail1 = random_tail r; tail2 = random_tail r }

let random_rx_cfg r : Rxpath.cfg =
  match Random.State.int r 4 with
  | 0 -> Rxpath.usb_ls
  | 1 -> Rxpath.eth10
  | _ ->
    { code = random_lc_cfg r; stuff = random_stuff_cfg r; msb_first = Random.State.bool r;
      pattern = Random.State.int r 256; pmask = (match Random.State.int r 3 with 0 -> 0xFF | 1 -> 0x0F | _ -> Random.State.int r 256);
      start_on_pattern = Random.State.int r 4 > 0; half_duplex = Random.State.bool r; end_inactive = Random.State.bool r;
      end_burst = Random.State.bool r; skip = (if Random.State.bool r then Random.State.int r 16 else Random.State.int r 256) }

let set_tx_cfg set (c : Txpath.cfg) =
  set "tx_period" c.period; set "tx_msb" (Bool.to_int c.msb_first);
  set "tx_run" c.stuff.run; set "tx_either" (Bool.to_int c.stuff.either); set "tx_value" c.stuff.value;
  set "tx_mode" (Linecode.mode_code c.code.mode); set "tx_invert" (Bool.to_int c.code.invert); set "tx_toggle_on" c.code.toggle_on;
  List.iter (fun (k, (t : Txpath.tail)) ->
      set (Printf.sprintf "tx_t%dlen" k) t.len; set (Printf.sprintf "tx_t%da" k) t.la; set (Printf.sprintf "tx_t%db" k) t.lb)
    [ (1, c.tail1); (2, c.tail2) ]

let set_rx_cfg set (c : Rxpath.cfg) =
  set "rx_mode" (Linecode.mode_code c.code.mode); set "rx_invert" (Bool.to_int c.code.invert); set "rx_toggle_on" c.code.toggle_on;
  set "rx_run" c.stuff.run; set "rx_either" (Bool.to_int c.stuff.either); set "rx_value" c.stuff.value;
  set "rx_msb" (Bool.to_int c.msb_first); set "rx_pattern" c.pattern; set "rx_pmask" c.pmask;
  set "rx_sop" (Bool.to_int c.start_on_pattern); set "rx_hd" (Bool.to_int c.half_duplex);
  set "rx_ei" (Bool.to_int c.end_inactive); set "rx_eb" (Bool.to_int c.end_burst); set "rx_skip" c.skip

let make_sim c =
  let sim = Cyclesim.create c in
  let dummy = ref Bits.gnd in
  let i n = try Cyclesim.in_port sim n with _ -> dummy in
  let set n v = let p = i n in p := Bits.of_int ~width:(max 1 (Bits.width !p)) v in
  (sim, set)

(* Random lockstep of both paths against their models. The receive path's input is either the
   transmit path's own line (a loop, so that frames really start) or random bits. *)
let paths_lockstep ~clocks ~seed =
  let sim, set = make_sim (paths_circuit ()) in
  let o n = Cyclesim.out_port ~clock_edge:Before sim n in
  let get n = Bits.to_int !(o n) in
  let r = Random.State.make [| seed |] in
  let tc = ref (random_tx_cfg r) and rc = ref (random_rx_cfg r) in
  let tx = Txpath.init () and rx = Rxpath.init () in
  let loop = ref (Random.State.bool r) in
  set "clear" 1; Cyclesim.cycle sim; set "clear" 0;
  let bad = ref 0 and diffs = ref [] in
  let src = biased_bits r in
  for c = 0 to clocks - 1 do
    if Random.State.int r 3000 = 0 then tc := random_tx_cfg r;
    if Random.State.int r 3000 = 0 then (rc := random_rx_cfg r; loop := Random.State.bool r);
    let t = !tc and rcf = !rc in
    let push = Random.State.int r 6 = 0 in
    let pdata = match Random.State.int r 4 with 0 -> 0x80 | 1 -> 0xFF | 2 -> rcf.pattern | _ -> Random.State.int r 256 in
    let valid, bit, active =
      if !loop then (Random.State.int r (max 1 (min 8 t.period)) = 0, (if tx.busy then tx.b else 0), tx.busy || Random.State.int r 50 > 0)
      else (Random.State.int r 3 = 0, src (), Random.State.int r 40 > 0) in
    let inp : Rxpath.inputs =
      { bit; valid; active; burst_end = Random.State.int r 200 = 0; start = Random.State.int r 2000 = 0;
        stop = Random.State.int r 2000 = 0; tx_active = Txpath.active tx; pop = Random.State.int r 4 = 0 } in
    set_tx_cfg set t; set_rx_cfg set rcf;
    set "push" (Bool.to_int push); set "push_data" pdata;
    set "bit" bit; set "valid" (Bool.to_int valid); set "active" (Bool.to_int active); set "burst_end" (Bool.to_int inp.burst_end);
    set "start" (Bool.to_int inp.start); set "stop" (Bool.to_int inp.stop); set "pop" (Bool.to_int inp.pop);
    Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim;
    let d = ref [] in
    let cmp name a b = if a <> b then d := Printf.sprintf "%s: model %d rtl %d" name a b :: !d in
    (* outputs from the state at the start of the clock *)
    cmp "tx a" tx.a (get "tx_a"); cmp "tx b" tx.b (get "tx_b"); cmp "tx busy" (Bool.to_int tx.busy) (get "tx_busy");
    cmp "tx active" (Bool.to_int (Txpath.active tx)) (get "tx_active"); cmp "tx count" (Queue.length tx.fifo) (get "tx_count");
    cmp "rx count" (Queue.length rx.fifo) (get "rx_count");
    (match Queue.peek_opt rx.fifo with Some h -> cmp "rx head" h (get "rx_head") | None -> ());
    cmp "rx in frame" (Bool.to_int rx.in_frame) (get "rx_in_frame"); cmp "rx done" (Bool.to_int (Rxpath.done_ rx)) (get "rx_done");
    cmp "rx err" (Bool.to_int rx.err) (get "rx_err"); cmp "rx ovf" (Bool.to_int rx.ovf) (get "rx_ovf");
    cmp "rx chain valid" (Bool.to_int rx.cv) (get "rx_cv"); cmp "rx chain error" (Bool.to_int rx.ce) (get "rx_ce");
    if rx.cv then cmp "rx chain bit" rx.cb (get "rx_cb");
    cmp "rx history" rx.hist (get "rx_hist"); cmp "rx history count" rx.hcount (get "rx_hcount"); cmp "rx bits" (rx.nbits) (get "rx_nbits"); cmp "rx shift" rx.sh (get "rx_sh");
    cmp "rx frame bits" rx.fbits (get "rx_fbits");
    let o = Rxpath.step rcf rx inp in
    cmp "crc valid" (Bool.to_int o.crc_valid) (get "crc_valid"); if o.crc_valid then cmp "crc bit" o.crc_bit (get "crc_bit");
    cmp "frame start" (Bool.to_int o.frame_start) (get "frame_start");
    let took = Txpath.step t tx ~push:(if push then Some pdata else None) in
    cmp "tx accept" (Bool.to_int took) (get "tx_accept");
    Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim;
    if !d <> [] then begin
      incr bad;
      if List.length !diffs < 3 then diffs := Printf.sprintf "clock %d: %s" c (String.concat "; " (List.rev !d)) :: !diffs
    end
  done;
  (!bad, List.rev !diffs)

(* The transmit path's RTL on a frame: push the bytes as the FIFO takes them; returns the line pair
   sampled once per symbol (in the middle of each), from the first symbol to idle, as (a, b) *)
let rtl_tx_frame (c : Txpath.cfg) bytes =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let t = Txpath.create ~clock ~clear ~cfg:(Txpath.cfg_const c) ~push:(input "push" 1) ~push_data:(input "push_data" 8) in
  let sim, set = make_sim (Circuit.create_exn ~name:"txf" [ output "a" t.a; output "b" t.b; output "busy" t.busy; output "accept" t.accept ]) in
  let o n = Bits.to_int !(Cyclesim.out_port ~clock_edge:Before sim n) in
  set "clear" 1; Cyclesim.cycle sim; set "clear" 0;
  let rest = ref bytes and line = ref [] and started = ref false and fin = ref false and k = ref 0 and since = ref 0 in
  while not !fin && !k < 200_000 do
    incr k;
    (match !rest with x :: _ -> set "push" 1; set "push_data" x | [] -> set "push" 0);
    Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim;
    let busy = o "busy" = 1 in
    if busy && not !started then (started := true; since := 0);
    if !started then begin
      if busy then (if !since mod c.period = c.period / 2 then line := (o "a", o "b") :: !line; incr since) else fin := true
    end;
    if o "accept" = 1 then rest := List.tl !rest;
    Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim
  done;
  List.rev !line

(* The receive path's RTL on a symbol stream, one symbol every [per] clocks, sampled as an edge
   sampler would hand them over (valid for one clock); [active] per symbol. Returns the frames
   (bytes, err, crc bits fed). *)
let rtl_rx_frames (c : Rxpath.cfg) ?(per = 4) (syms : (int * bool) list) =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let r = Rxpath.create ~clock ~clear ~cfg:(Rxpath.cfg_const c) ~bit:(input "bit" 1) ~valid:(input "valid" 1) ~active:(input "active" 1)
      ~burst_end:gnd ~start:gnd ~stop:gnd ~tx_active:gnd ~pop:(input "pop" 1) in
  let sim, set = make_sim (Circuit.create_exn ~name:"rxf"
      [ output "head" r.head; output "ne" r.nonempty; output "in_frame" r.in_frame; output "err" r.err; output "cv" r.crc_valid; output "cb" r.crc_bit ]) in
  let o n = Bits.to_int !(Cyclesim.out_port ~clock_edge:Before sim n) in
  set "clear" 1; Cyclesim.cycle sim; set "clear" 0;
  let frames = ref [] and cur = ref [] and crc = ref [] and was_in = ref false and err = ref false in
  let clk sym valid active =
    set "bit" sym; set "valid" (Bool.to_int valid); set "active" (Bool.to_int active); set "pop" 1;
    Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim;
    if o "ne" = 1 then cur := o "head" :: !cur;
    if o "cv" = 1 then crc := o "cb" :: !crc;
    let inf = o "in_frame" = 1 in
    if inf then err := o "err" = 1;
    if !was_in && not inf then (frames := (List.rev !cur, !err, List.rev !crc) :: !frames; cur := []; crc := []);
    was_in := inf;
    Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim in
  List.iter (fun (s, act) -> clk s true act; for _ = 2 to per do clk s false act done) syms;
  for _ = 1 to 4 do clk 0 false false done;
  List.rev !frames

let paths_references ~seed =
  let r = Random.State.make [| seed |] in
  let all_ok = ref true in
  let report name good total = if good <> total then all_ok := false; pr "  %-78s %d of %d %s\n" name good total (ok (good = total)) in
  let n = 100 in
  (* USB low speed: the serialiser's whole frame (sync, stuffing, NRZI, EOP) against fw_codec,
     one symbol per 40 clocks; a = D-, b = D+, so the symbol is 2a + b (J 2, K 1, SE0 0) *)
  let good = ref 0 and good_rx = ref 0 in
  for _ = 1 to n do
    let bytes = random_bytes r (1 + Random.State.int r 10) in
    let refsyms = Fw_codec.symbols bytes in
    let line = rtl_tx_frame Txpath.usb_ls (0x80 :: bytes) in
    if List.map (fun (a, b) -> (2 * a) + b) line = refsyms then incr good;
    (* back through the receive path: D+ is the line the edge sampler reads, active = not SE0;
       idle J before and after *)
    let syms = List.init 4 (fun _ -> (0, true)) @ List.map (fun (a, b) -> (b, a = 1 || b = 1)) line @ List.init 4 (fun _ -> (0, true)) in
    (match rtl_rx_frames Rxpath.usb_ls syms with
     | [ (got, false, crcbits) ] when got = bytes && List.length crcbits = 8 * (List.length bytes - 1) -> incr good_rx
     | _ -> ())
  done;
  report "USB low speed: serialiser frame (sync to EOP, 40 clocks per symbol) = usb-ls fw_codec" !good n;
  report "USB low speed: framer on that line gives the bytes after the sync; CRC fed after the PID" !good_rx n;
  (* the idle line before a packet decodes as 1s, as many as the gap is long: the destuffer must
     not take the sync's first 0 for a stuff bit after six of them *)
  let good = ref 0 and tried = ref 0 in
  for idle = 0 to 14 do
    for _ = 1 to 5 do
      incr tried;
      let bytes = random_bytes r (1 + Random.State.int r 6) in
      let line = rtl_tx_frame Txpath.usb_ls (0x80 :: bytes) in
      (* a previous packet's end (SE0, J) sets the decoder's reference, then [idle] bit times of J *)
      let syms = [ (1, true); (0, false); (0, false) ] @ List.init idle (fun _ -> (0, true))
                 @ List.map (fun (a, b) -> (b, a = 1 || b = 1)) line @ [ (0, true) ] in
      match rtl_rx_frames Rxpath.usb_ls syms with
      | [ (got, false, _) ] when got = bytes -> incr good
      | _ -> ()
    done
  done;
  report "USB: a packet after 0 to 14 bit times of idle J (decoded 1s) is received whole" !good !tried;
  (* the CRC residue over a real USB data packet: the framer's CRC feed through CRC-16/USB *)
  let good = ref 0 in
  for _ = 1 to n do
    let payload = random_bytes r (Random.State.int r 9) in
    let pkt = Fw_codec.data_bytes 0xC3 payload in
    let line = rtl_tx_frame Txpath.usb_ls (0x80 :: pkt) in
    let syms = List.init 4 (fun _ -> (0, true)) @ List.map (fun (a, b) -> (b, a = 1 || b = 1)) line @ List.init 4 (fun _ -> (0, true)) in
    match rtl_rx_frames Rxpath.usb_ls syms with
    | [ (_, false, crcbits) ] ->
      let crc = List.fold_left (fun c b -> if (c land 1) lxor b = 1 then (c lsr 1) lxor 0xA001 else c lsr 1) 0xFFFF crcbits in
      if crc = 0xB001 then incr good
    | _ -> ()
  done;
  report "USB: CRC-16 over the framer's CRC feed of a data packet leaves the residue 0xB001" !good n;
  (* 10BASE-T: Manchester at 3 clocks per half-bit against eth_model, then TP_IDL 6 symbols *)
  let good = ref 0 in
  for _ = 1 to n do
    let bytes = random_bytes r (1 + Random.State.int r 20) in
    let refsyms = Eth_model.manchester ~h:1 bytes |> List.filteri (fun i _ -> i < 16 * List.length bytes) |> List.map (fun v -> if v > 0 then 1 else 0) in
    let line = rtl_tx_frame Txpath.eth10 bytes in
    let data = List.filteri (fun i _ -> i < 16 * List.length bytes) line and tail = List.filteri (fun i _ -> i >= 16 * List.length bytes) line in
    if List.map fst data = refsyms && List.for_all (fun (a, b) -> a = 1 - b) data && tail = List.init 6 (fun _ -> (1, 0)) then incr good
  done;
  report "10BASE-T: serialiser = eth_model Manchester, pair complementary, then 6 symbols TD+ high" !good n;
  (* stuffing violations are flagged: a USB frame with a stuff bit removed from the line *)
  let caught = ref 0 in
  for _ = 1 to n do
    let bytes = 0xFF :: random_bytes r (Random.State.int r 6) in
    let line = rtl_tx_frame Txpath.usb_ls (0x80 :: bytes) in
    (* the first stuff symbol: after the sync (8) and the first six 1s... find by decoding *)
    let bits = Stuff.stuff_list Stuff.usb (bits_of_bytes (0x80 :: bytes)) in
    let rec first_diff k a b = match a, b with x :: a', y :: b' when x = y -> first_diff (k + 1) a' b' | _ -> k in
    let k = first_diff 0 bits (bits_of_bytes (0x80 :: bytes)) in
    (* removing a symbol from an NRZI line removes that bit and inverts the rest's levels:
       re-encode the stream without it instead *)
    let dropped = List.filteri (fun i _ -> i <> k) bits in
    let lv = Linecode.encode_list { Linecode.usb with invert = false } dropped in
    let syms = List.init 4 (fun _ -> (0, true)) @ List.map (fun v -> (v, true)) lv @ [ (0, false); (0, false); (0, true) ] in
    ignore line;
    match rtl_rx_frames Rxpath.usb_ls syms with
    | [ (_, true, _) ] -> incr caught
    | _ -> ()
  done;
  report "USB: a frame missing a stuff bit ends with the framer's error flag set" !caught n;
  (* 10BASE-T receive behind the edge sampler (which decodes Manchester): preamble, SFD, frame and
     FCS as bits; the framer starts after the SFD, and CRC-32 over its feed leaves the residue *)
  let good = ref 0 in
  for _ = 1 to n do
    let frame = random_bytes r (14 + Random.State.int r 50) in
    let wire = List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame in
    let syms = List.init 3 (fun _ -> (0, false)) @ List.map (fun b -> (b, true)) (bits_of_bytes wire) @ [ (1, false) ] in
    match rtl_rx_frames { Rxpath.eth10 with end_inactive = true } ~per:6 syms with
    | [ (got, false, crcbits) ] ->
      let crc = List.fold_left (fun c b -> if (c land 1) lxor b = 1 then (c lsr 1) lxor 0xEDB88320 else c lsr 1) 0xFFFFFFFF crcbits in
      if got = frame @ Eth_model.fcs_bytes frame && crc = 0xDEBB20E3 then incr good
    | _ -> ()
  done;
  report "10BASE-T: framer after the SFD gives the frame and FCS; CRC-32 residue 0xDEBB20E3" !good n;
  !all_ok

let run_paths clocks =
  let t0 = Unix.gettimeofday () in
  let ok_all = ref true in
  pr "== transmit serialiser and receive framer: RTL against model, every clock\n";
  for seed = 1 to 4 do
    let bad, diffs = paths_lockstep ~clocks ~seed in
    pr "  seed %d: %d clocks, %d mismatching %s\n" seed clocks bad (ok (bad = 0));
    List.iter (pr "    %s\n") diffs;
    if bad > 0 then ok_all := false
  done;
  pr "== against independent references, through the RTL\n";
  if not (paths_references ~seed:9) then ok_all := false;
  pr "== planted faults in the two paths: each must be caught by the lockstep\n";
  let caught = ref 0 and total = ref 0 in
  let try_bug set name what =
    incr total;
    set name;
    let rec go seed = if seed > 8 then None else (let bad, d = paths_lockstep ~clocks:(min clocks 100000) ~seed in if bad > 0 then Some (seed, d) else go (seed + 1)) in
    (match go 1 with
     | Some (seed, d) -> incr caught; pr "  %-26s caught (seed %d; %s)  %s\n" name seed (List.hd d) what
     | None -> pr "  %-26s MISSED  %s\n" name what);
    set "" in
  List.iter (fun (b, w) -> try_bug (fun n -> Txpath.bug := n) b w) Txpath.bugs;
  List.iter (fun (b, w) -> try_bug (fun n -> Rxpath.bug := n) b w) Rxpath.bugs;
  pr "%d of %d planted faults caught\n" !caught !total;
  let noticed = ref [] in
  let quiet f = let saved = Unix.dup Unix.stdout in let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
    flush stdout; Unix.dup2 null Unix.stdout; let v = f () in flush stdout; Unix.dup2 saved Unix.stdout; Unix.close null; v in
  List.iter (fun (set, (b, _)) -> set b; if not (quiet (fun () -> paths_references ~seed:9)) then noticed := b :: !noticed; set "")
    (List.map (fun x -> ((fun n -> Txpath.bug := n), x)) Txpath.bugs @ List.map (fun x -> ((fun n -> Rxpath.bug := n), x)) Rxpath.bugs);
  pr "the independent references alone fail with %d of the %d faults: %s\n" (List.length !noticed) !total
    (String.concat ", " (List.rev !noticed));
  if !caught < !total then ok_all := false;
  pr "paths: %s (%.0f s)\n" (if !ok_all then "PASS" else "FAIL") (Unix.gettimeofday () -. t0);
  !ok_all

let () =
  match Array.to_list Sys.argv with
  | [ _; "blocks"; clocks ] -> exit (if run_blocks (int_of_string clocks) then 0 else 1)
  | [ _; "paths"; clocks ] -> exit (if run_paths (int_of_string clocks) then 0 else 1)
  | _ :: "usb-frame" :: l ->   (* one USB frame through the serialiser and back through the framer *)
    let bytes = List.map int_of_string l in
    let line = rtl_tx_frame Txpath.usb_ls (0x80 :: bytes) in
    pr "line: %s\n" (String.concat "" (List.map (fun (a, b) -> string_of_int ((2 * a) + b)) line));
    let syms = List.init 4 (fun _ -> (0, true)) @ List.map (fun (a, b) -> (b, a = 1 || b = 1)) line @ List.init 4 (fun _ -> (0, true)) in
    List.iter (fun (g, e, c) -> pr "frame: %s err %b crc bits %d\n" (String.concat " " (List.map (Printf.sprintf "%02x") g)) e (List.length c))
      (rtl_rx_frames Rxpath.usb_ls syms)
  | _ -> prerr_endline "usage: check.exe blocks CLOCKS | paths CLOCKS | usb-frame BYTE..."; exit 2
