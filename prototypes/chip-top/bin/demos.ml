(* The existing demos, unchanged, on the combined chip through its host link.

     demos.exe ds [TRACE_DIR]   UART, SPI and I2C (../deadline-sequencer's firmware, I2C slave and
                                decoders); with TRACE_DIR, the bus trace for tools/sigrok-judge
     demos.exe dac [SAMPLES]    the one-bit DAC (../onebit-dac's pump firmware and PE
                                configuration), judged bit for bit against its fast model

   Each demo runs the chip's specification and its RTL in lockstep on the same board (Board),
   comparing every pad every clock, so the demo's verdict holds for both. The host does what a
   host would: it loads the store, the boot addresses, the pin map and the array through the
   host link, sets run, and keeps the FIFOs fed and drained. *)

open Regs
module S = Chip_spec
module D = Ds.Demo_cut

let pr = Printf.printf

type world = clock:int -> S.outputs -> int array

(* Run spec and RTL together for [clocks]; [world] gives the outside world's levels each clock,
   [on_clock] sees each clock's pad outputs after it. Returns whether they agreed throughout. *)
let run_board ?(cfg = S.default_config) (b : Board.t) ~(world : world) ~clocks ~on_clock =
  let spec = S.create ~cfg () and rtl = Chip_sim.create ~cfg () in
  let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
  let agree = ref true and first = ref None in
  for c = 0 to clocks - 1 do
    let smp = Board.samples b ~ext:(world ~clock:c b.out) in
    match Board.advance b cores ~smp ~reset:(c < 2) with
    | [ a; o ] ->
      if a.pad_nib <> o.pad_nib || a.uio_oe <> o.uio_oe then begin
        agree := false;
        if !first = None then first := Some c
      end;
      on_clock c a
    | _ -> assert false
  done;
  (match !first with Some c -> pr "  RTL and specification first differ at clock %d\n" c | None -> ());
  !agree, spec

(* ---- the programme store image of earlier-variant programmes ---- *)

(* thread t's base-ISA programme, translated to ISA v2 (../sequencer-v2/compat.ml) and moved to
   page 0, offset 64 t: the host-side loader's job *)
let store_image_base (progs : int array array) =
  List.concat
    (List.mapi
       (fun t p ->
         let words = Array.mapi (fun pc w -> Compat.relocate ~base:(64 * t) (Compat.of_base ~quarter:true ~pc_bits:6 ~addr:pc w)) p in
         [ (128 * t, List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) (Array.to_list words)) ])
       (Array.to_list progs))

(* ---- UART, SPI, I2C ---- *)

let ds ?trace_dir () =
  pr "== UART, SPI and I2C (../deadline-sequencer firmware, unchanged) on the combined chip\n";
  let mem, listings = D.build () in
  List.iter (fun (n, _, l) -> pr "  %s: %d words\n" n l) listings;
  let b = Board.create () in
  let h = b.host in
  Host.wreg h r_ctrl 2;
  List.iter (fun (a, data) -> Host.submit h (Host.Write { tgt = t_prog; addr = a; data })) (store_image_base mem);
  Host.submit h (Host.Write { tgt = t_reg; addr = r_boot_pc 0; data = [ 0; 64; 128; 192; 0 ] });
  (* logical pins: UART 0, SCLK 1, MOSI 2, CS 3 on uo_out[3:0] (undriven level 1); SDA 4 and SCL 5
     on uio[6] and uio[7], the open-drain pins, which they also read back *)
  let sel src undriven = src lor (undriven lsl 6) in
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 0; data = [ sel 0 1; sel 1 1; sel 2 1; sel 3 1 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 14; data = [ sel 4 0; sel 5 0 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_pinin 4; data = [ 14; 15 ] });
  let run_at = ref max_int in
  Host.submit h (Host.Call (fun () -> run_at := b.clock + 10));
  Host.wreg h r_ctrl 3;                         (* run; the assists stay held *)
  let demo_clocks = 6000 in
  (* after the demo, the host drains the I2C master's OUT bytes *)
  let host_bytes = ref [] in
  Host.submit h (Host.Idle demo_clocks);
  Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 8; k = (fun l ->
      let rec pairs = function t :: d :: r -> (if t land 0x80 <> 0 then [ d ] else []) @ pairs r | _ -> [] in
      host_bytes := pairs l) });
  let sl = D.new_slave () in
  let bus = ref 0xFF in
  let trace = ref [] in
  let world ~clock (o : S.outputs) =
    (* the master's outputs in logical pin numbers, then the bus with the slave on it *)
    let lv p = (o.pad_nib.(p) lsr 3) land 1 in
    let oe14 = (o.uio_oe lsr 6) land 1 and oe15 = (o.uio_oe lsr 7) land 1 in
    let pin_out = lv 0 lor (lv 1 lsl 1) lor (lv 2 lsl 2) lor (lv 3 lsl 3) lor (lv 14 lsl 4) lor (lv 15 lsl 5) in
    let pin_oe = 0xF lor (oe14 lsl 4) lor (oe15 lsl 5) in
    bus := D.resolve sl ~pin_out ~pin_oe;
    if clock >= !run_at && clock < !run_at + demo_clocks then
      trace := { Ds.Decoders.c = clock - !run_at; bus = !bus } :: !trace;
    let smp = Array.make n_pads 0 in
    smp.(14) <- Board.rep4 ((!bus lsr 4) land 1);
    smp.(15) <- Board.rep4 ((!bus lsr 5) land 1);
    smp
  in
  let total = 7000 + demo_clocks + 1500 in
  let agree, _ = run_board b ~world ~clocks:total ~on_clock:(fun _ _ -> ()) in
  let trace = List.rev !trace in
  pr "  host link: %d clocks busy loading and draining (of %d)\n" h.busy_clocks total;
  pr "  RTL and specification agree on every pad, every clock: %b\n" agree;
  let ub = Ds.Decoders.uart trace ~pin:D.uart_pin ~bit_cycles:(D.bit_slots * D.slot) in
  let sb = Ds.Decoders.spi trace ~sclk:D.sclk ~mosi:D.mosi ~cs:D.cs in
  let ib, stopped = Ds.Decoders.i2c trace ~sda:D.sda ~scl:D.scl in
  pr "  uart decoded: %s\n" (String.concat " " (List.map (fun (c, v, ok) -> Printf.sprintf "0x%02x@%d%s" v c (if ok then "" else "(framing)")) ub));
  pr "  spi decoded:  %s\n" (String.concat " " (List.map (Printf.sprintf "0x%02x") sb));
  pr "  i2c decoded:  %s stop=%b; host received: %s\n"
    (String.concat " " (List.map (fun (v, a) -> Printf.sprintf "0x%02x%s" v (if a then "+ack" else "-nak")) ib)) stopped
    (String.concat " " (List.map (Printf.sprintf "0x%02x") !host_bytes));
  (* the demo's own timing checks (main_demo in ../deadline-sequencer/demo.ml) *)
  let t1 = D.check_multiples "uart tx edge spacing" (Ds.Decoders.edges trace D.uart_pin) (D.bit_slots * D.slot) in
  let rises = List.filter (fun (_, v) -> v = 1) (Ds.Decoders.edges trace D.sclk) in
  let within = List.concat (List.mapi (fun i r -> if i mod 8 = 7 then [] else [ r ]) rises) in
  let rec pairs = function a :: (b :: _ as r) -> (a, b) :: pairs r | _ -> [] in
  let spac = pairs within |> List.filter (fun ((c1, _), (c2, _)) -> c2 - c1 < 2 * D.spi_period * D.slot) |> List.map (fun ((c1, _), (c2, _)) -> c2 - c1) in
  let t2 = spac <> [] && List.for_all (fun d -> d = D.spi_period * D.slot) spac in
  pr "  spi sclk period within bytes: %d spacings, all %d: %b\n" (List.length spac) (D.spi_period * D.slot) t2;
  let highs = let rec go = function (c1, 1) :: ((c2, 0) :: _ as r) -> (c2 - c1) :: go r | _ :: r -> go r | [] -> [] in go (Ds.Decoders.edges trace D.scl) in
  let t3 = highs <> [] && List.for_all (fun w -> w = 2 * D.q * D.slot) highs in
  pr "  i2c scl high widths: %d, all %d: %b\n" (List.length highs) (2 * D.q * D.slot) t3;
  let ok =
    agree && List.map (fun (_, v, ok) -> if ok then v else -1) ub = D.uart_bytes && sb = D.spi_bytes
    && List.map fst ib = D.i2c_bytes && List.for_all snd ib && stopped && !host_bytes = [ 0x00; 0x00 ] && t1 && t2 && t3
  in
  (match trace_dir with
   | Some dir ->
     (* one byte per clock, bit p = logical pin p, as ../deadline-sequencer's [demo.exe dump] writes *)
     let oc = open_out_bin (Filename.concat dir "deadline-sequencer.bin") in
     List.iter (fun (s : Ds.Decoders.sample) -> output_char oc (Char.chr (s.bus land 0xff))) trace;
     close_out oc;
     let bytes l = String.concat "," (List.map (Printf.sprintf "%d") l) in
     let oc = open_out (Filename.concat dir "deadline-sequencer.expected") in
     Printf.fprintf oc "# samplerate_hz_assumed 1000000 (one sample per core cycle); from prototypes/chip-top (the combined chip)\nuart_pin %d\nuart_bit_cycles %d\nspi_sclk %d\nspi_mosi %d\nspi_cs %d\ni2c_sda %d\ni2c_scl %d\nuart_bytes %s\nspi_bytes %s\ni2c_bytes %s\n"
       D.uart_pin (D.bit_slots * D.slot) D.sclk D.mosi D.cs D.sda D.scl (bytes D.uart_bytes) (bytes D.spi_bytes) (bytes D.i2c_bytes);
     close_out oc;
     pr "  trace written to %s\n" dir
   | None -> ());
  pr "UART/SPI/I2C on the combined chip: %s\n%!" (if ok then "PASS" else "FAIL");
  ok

(* ---- the one-bit DAC ---- *)

let dac ~samples =
  let order = "o2" in
  let d = Dacdemo.Dac.design_of order in
  pr "== one-bit DAC (../onebit-dac, order 2, mode A) on the combined chip, 4 PEs\n";
  (* input: 997 Hz at -6 dB of the order's full scale (5567, ../onebit-dac/README.md) *)
  let fs = 60e6 /. float Dacdemo.Dac.sample_clocks in
  let left = Array.init samples (fun i -> int_of_float (Float.round (2783. *. sin (2. *. Float.pi *. 997. *. float i /. fs)))) in
  let right = Array.make samples 0 in
  let bytes = Dacdemo.Dac.frame_bytes left right in
  let b = Board.create () in
  let h = b.host in
  Host.wreg h r_ctrl 2;
  (* the pump, as ../onebit-dac's pump_programme lays it out: thread 0 at 0, threads 1-3 parked *)
  let mem = Dacdemo.Dac.pump_programme () in
  let used = Array.to_list (Array.sub mem 0 43) in
  Host.submit h (Host.Write { tgt = t_prog; addr = 0; data = List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) used });
  let idle = Dacdemo.Dac.idle_pc in
  Host.submit h (Host.Write { tgt = t_prog; addr = 2 * idle; data = [ mem.(idle) land 0xFF; mem.(idle) lsr 8 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_boot_pc 0; data = [ 0; idle; idle; idle; 0 ] });
  (* the pin first, so that it shows F before the modulator starts: segment 3's flag, inverted
     (F = 1 means y negative), on uo_out[0] *)
  Host.wreg h (r_padsel 0) (src_tap_flag 3 lor 0x20);
  let configured = ref max_int in
  Host.submit h (Host.Call (fun () -> configured := b.clock + 20));
  (* the array: the four PEs of order 2 (FB1, I1, FB2, I2: Dac.run_ops without its pass-through
     PEs) as one run over segments 0-3; segment 0 is fed and repeats every 10 clocks, with the
     lane loop; segments 1-3 join *)
  let ops = Array.sub (Dacdemo.Dac.run_ops d) 4 4 in
  for sg = 0 to 3 do
    let bts = List.rev (Array.to_list (Upe.Spec.bytes_of_op ops.(sg))) in
    Host.submit h (Host.Write { tgt = t_pecfg; addr = sg lsl 8; data = bts })
  done;
  Host.submit h (Host.Write { tgt = t_peseg; addr = 2; data = [ 2 lor 16 lor 64 ] });
  for sg = 1 to 3 do Host.submit h (Host.Write { tgt = t_peseg; addr = (sg lsl 2) lor 2; data = [ 16 ] }) done;
  Host.submit h (Host.Write { tgt = t_peseg; addr = 3; data = [ Dacdemo.Dac.period ] });
  (* prefill four frames, then run *)
  Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init 16 (fun i -> bytes.(i)) });
  Host.wreg h r_ctrl 3;
  (* then keep the FIFO fed: read its count, top it up to 16, and collect underrun reports *)
  let next = ref 16 and underruns = ref 0 and overflow = ref false in
  let rec feed () =
    if !next < Array.length bytes then begin
      Host.submit h (Host.Read { tgt = t_reg; addr = r_hostin_count; n = 1; k = (fun l ->
          let free = 16 - List.hd l in
          let n = min (free land lnot 3) (Array.length bytes - !next) in
          if n > 0 then begin
            Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init n (fun i -> bytes.(!next + i)) });
            next := !next + n
          end;
          Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 2; k = (fun l ->
              match l with t :: _ when t land 0x80 <> 0 -> incr underruns | _ -> ()) });
          Host.submit h (Host.Read { tgt = t_reg; addr = r_status; n = 1; k = (fun l ->
              if List.hd l land 2 <> 0 then overflow := true) });
          Host.submit h (Host.Idle 1000);
          Host.submit h (Host.Call feed)) })
    end
  in
  Host.submit h (Host.Call feed);
  let total = 5000 + (samples * Dacdemo.Dac.sample_clocks) in
  let pin = Array.make total 0 in
  let agree, spec =
    run_board b ~world:(fun ~clock:_ _ -> Array.make n_pads 0) ~clocks:total
      ~on_clock:(fun c (o : S.outputs) -> pin.(c) <- (o.pad_nib.(0) lsr 3) land 1)
  in
  if Sys.getenv_opt "DAC_DEBUG" <> None then begin
    let st = Upe.Model.state spec.pe in
    Array.iteri (fun i (p : Upe.Spec.pe_state) -> pr "  PE%d %s\n" i (Upe.Spec.pe_state_to_string p)) st.pes;
    Array.iteri (fun j (g : Upe.Spec.seg_state) -> pr "  seg%d flo %02x fhi %02x ctrl %02x rep %d fw %04x\n" j g.flo g.fhi g.ctrl g.rep g.fw) st.segs;
    pr "  regs ctrl %x padsel0 %x; seq pcs %s\n" spec.regs.(r_ctrl) spec.regs.(r_padsel 0)
      (String.concat " " (Array.to_list (Array.map string_of_int spec.seq.pcs)))
  end;
  pr "  RTL and specification agree on every pad, every clock: %b\n" agree;
  pr "  host: %d of %d bytes sent, underrun reports %d, HOSTIN overflow %b\n" !next (Array.length bytes) !underruns !overflow;
  (* the pin's bitstream: one bit per 10 clocks. The pin changes only on one clock phase mod 10;
     sample half a step later. *)
  let changes = Array.make 10 0 in
  for c = 1 to total - 1 do if pin.(c) <> pin.(c - 1) then changes.(c mod 10) <- changes.(c mod 10) + 1 done;
  let phase = ref 0 in
  Array.iteri (fun k n -> if n > changes.(!phase) then phase := k) changes;
  let off = (!phase + 5) mod 10 in
  pr "  pin edges by clock phase mod 10: %s (sampled at phase %d)\n"
    (String.concat " " (Array.to_list (Array.map string_of_int changes))) off;
  let bits = Array.init ((total - off) / 10) (fun j -> 1 - pin.(off + (10 * j))) in   (* back to F *)
  (* The reference: the fast model on the same words, each held 136 steps. Before the first
     commit the feed repeats its initial word 0, so the model first takes [lead] steps on 0; that
     number is the only parameter fitted. Before the modulator starts (the host is still
     configuring it) the pin shows F = 0; the start is placed exactly, from where the pin first
     shows a 1 against where the model on zeros first outputs a 1. *)
  let steps = Dacdemo.Dac.sample_clocks / Dacdemo.Dac.period in
  let first_one a = let rec go j = if j >= Array.length a then -1 else if a.(j) = 1 then j else go (j + 1) in go 0 in
  let r1 = let f = Dacdemo.Dac.fast_create d in first_one (Array.init 1000 (fun _ -> if Dacdemo.Dac.fast_step f 0 then 1 else 0)) in
  let from = !configured / 10 + 1 in
  let start = (from + first_one (Array.sub bits from (Array.length bits - from))) - r1 in
  let reference lead =
    let f = Dacdemo.Dac.fast_create d in
    let n = Array.length bits in
    Array.init n (fun j ->
        let j = j - start in
        if j < 0 then 0
        else
          let w = if j < lead then 0 else let s = (j - lead) / steps in if s < samples then left.(s) land 0xFFFF else left.(samples - 1) land 0xFFFF in
          if Dacdemo.Dac.fast_step f w then 1 else 0)
  in
  let judged = start + ((samples - 1) * steps) in
  let best = ref (-1, max_int) in
  for lead = 0 to 2000 do
    let r = reference lead in
    let wrong = ref 0 in
    for j = from to min (Array.length bits) (lead + judged) - 1 do if r.(j) <> bits.(j) then incr wrong done;
    if !wrong < snd !best then best := (lead, !wrong)
  done;
  let lead, wrong = !best in
  let n = min (Array.length bits) (lead + judged) in
  if Sys.getenv_opt "DAC_DEBUG" <> None then begin
    let r = reference lead in
    let w = ref [] in
    for j = n - 1 downto from do if r.(j) <> bits.(j) then w := j :: !w done;
    pr "  wrong at steps: %s\n" (String.concat " " (List.map string_of_int (List.filteri (fun i _ -> i < 40) !w)))
  end;
  pr "  bitstream: %d steps compared with ../onebit-dac's fast model (pin configured by step %d, modulator started at step %d; lead-in of %d steps on word 0 fitted): %d wrong\n"
    (n - from) from start lead wrong;
  (* a second fit as a control: the same comparison against the wrong order must fail *)
  let ctrl =
    let f = Dacdemo.Dac.fast_create (Dacdemo.Dac.design_of "o3") in
    let wrong = ref 0 in
    for j = start to n - 1 do
      let k = j - start in
      let w = if k < lead then 0 else left.(min (samples - 1) ((k - lead) / steps)) land 0xFFFF in
      if (if Dacdemo.Dac.fast_step f w then 1 else 0) <> bits.(j) then incr wrong
    done;
    !wrong
  in
  pr "  control: the same bits against the order-3 model: %d of %d wrong\n" ctrl n;
  let ok = agree && start > from && wrong = 0 && n > (samples - 2) * steps && !underruns = 0 && not !overflow && ctrl > n / 10 in
  pr "one-bit DAC on the combined chip: %s\n%!" (if ok then "PASS" else "FAIL");
  ok

let () =
  match Array.to_list Sys.argv with
  | [ _; "ds" ] -> exit (if ds () then 0 else 1)
  | [ _; "ds"; dir ] -> exit (if ds ~trace_dir:dir () then 0 else 1)
  | [ _; "dac" ] -> exit (if dac ~samples:200 then 0 else 1)
  | [ _; "dac"; n ] -> exit (if dac ~samples:(int_of_string n) then 0 else 1)
  | _ -> prerr_endline "usage: demos.exe ds [TRACE_DIR] | dac [SAMPLES]"
