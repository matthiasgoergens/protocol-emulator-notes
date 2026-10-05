(* Jitter tolerance of 10BASE-T receive at the PAL clock (12 x fsc = 53.203425 MHz, 2.66 clocks per
   half-bit), with one, two and four samples per clock; the four-sample case goes through the
   stage's input samplers (stage.ml, sub-step model). The line is generated in continuous time as in
   ../pal-ethernet/main.ml: 10 Mbit/s, transmitter offset +-100 ppm, uniform random jitter on every
   edge. A frame counts only if it comes back intact with a good CRC.

   Receivers (eth_rxn.ml unless stated):
     eth_rx h=3      the existing receiver, one sample per clock (as in pal-ethernet)
     n=1 thr=5       eth_rxn's rule at one sample: must decide exactly as eth_rx (differential check)
     n=1 thr=4       one sample, threshold moved to the ideal 75 ns
     n=2 thr=8       both clock edges
     n=4 thr=16      four phases, through the stage RTL
     n=4 skewed      the same with the sampling phases off by 0, +1, -1, +0.5 ns
     control         the four samples handed to the receiver in reverse order: must fail
   Output: results/rx-jitter.txt *)
open Hardcaml

let rx_clk = 53.203425e6

let line_of ~frame ~ppm ~jitter ~seed =
  let bits = Array.of_list (List.concat_map Eth_model.bits_of_byte (List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame)) in
  let half = 50e-9 *. (1.0 +. ppm *. 1e-6) in
  let t0 = 1e-6 in
  let st = Random.State.make [| seed |] in
  let n = 2 * Array.length bits in
  let edges = Array.init (n + 1) (fun k -> t0 +. (float k *. half) +. (if k = 0 || k = n then 0.0 else (Random.State.float st 2.0 -. 1.0) *. jitter)) in
  let tp_idl_end = edges.(n) +. (3.0 *. half *. 2.0) in
  fun t ->
    if t < edges.(0) then 0
    else if t >= edges.(n) then (if t < tp_idl_end then 1 else 0)
    else begin
      let lo = ref 0 and hi = ref n in
      while !hi - !lo > 1 do let mid = (!lo + !hi) / 2 in if edges.(mid) <= t then lo := mid else hi := mid done;
      let k = !lo in
      let b = bits.(k / 2) in
      if k mod 2 = 0 then (if b = 1 then -1 else 1) else (if b = 1 then 1 else -1)
    end

type rx = Legacy | Nrx of { n : int; thr : int; stage : bool; skew : float array; reversed : bool }

let receive rx ~frame ~ppm ~jitter ~seed =
  let line = line_of ~frame ~ppm ~jitter ~seed in
  let circuit = match rx with Legacy -> Eth_rx.circuit ~h:3 | Nrx { n; thr; _ } -> Eth_rxn.circuit ~n ~thr in
  let sim = Cyclesim.create circuit in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let stage = Stage.Sim.create ~n_out:1 ~n_in:1 () in
  let frames = ref [] and cur = ref [] and stage_mismatch = ref 0 in
  let hist = Array.make 3 0 and act_hist = Array.make 2 0 in
  let cycles = int_of_float (rx_clk *. (2e-6 +. (float (8 * (List.length frame + 12)) *. 100e-9))) in
  for c = 0 to cycles do
    let tc = float c /. rx_clk in
    (* activity (squelch) is one bit per clock; take it at the clock's last sample, so a clock in
       which the line goes idle does not count as active with its later samples already idle *)
    let n_samp, last_skew = match rx with Legacy -> 1, 0.0 | Nrx { n; skew; _ } -> n, skew.((n - 1) * 4 / n) in
    let act = if line (tc +. (float (n_samp - 1) /. float n_samp /. rx_clk) +. last_skew) <> 0 then 1 else 0 in
    (match rx with
     | Legacy -> i "rx" := Bits.of_int ~width:1 (if line tc > 0 then 1 else 0)
     | Nrx { n; stage = false; skew; _ } ->
       let v = List.fold_left (fun acc p ->
           let t = tc +. (float p /. float n /. rx_clk) +. skew.(p * 4 / n) in
           acc lor ((if line t > 0 then 1 else 0) lsl p)) 0 (List.init n Fun.id) in
       i "samples" := Bits.of_int ~width:n v
     | Nrx { n = _; stage = true; skew; reversed; _ } ->
       let direct = Array.init 4 (fun p -> if line (tc +. (float p /. 4.0 /. rx_clk) +. skew.(p)) > 0 then 1 else 0) in
       let _, samples = Stage.Sim.step stage ~sub:0 ~pads:(fun p -> direct.(p)) in
       (* the stage delivers clock c-2's samples in clock c; check them against direct sampling *)
       let want = hist.(0) in
       if c >= 2 && samples <> want then incr stage_mismatch;
       hist.(0) <- hist.(1); hist.(1) <- Array.fold_left ( lor ) 0 (Array.mapi (fun p b -> b lsl p) direct);
       (* planted fault: the four samples handed over in reverse time order *)
       let samples = if reversed then List.fold_left (fun a p -> a lor (((samples lsr p) land 1) lsl (3 - p))) 0 [ 0; 1; 2; 3 ] else samples in
       i "samples" := Bits.of_int ~width:4 samples);
    (* activity is not timing-critical; for the stage path it is delayed like the samples *)
    let act = match rx with
      | Nrx { stage = true; _ } -> let a = act_hist.(0) in act_hist.(0) <- act_hist.(1); act_hist.(1) <- act; a
      | _ -> act in
    i "rx_active" := Bits.of_int ~width:1 act;
    Cyclesim.cycle sim;
    if Bits.to_int !(o "byte_valid") = 1 then cur := Bits.to_int !(o "rx_byte") :: !cur;
    if Bits.to_int !(o "frame_end") = 1 then (frames := (List.rev !cur, Bits.to_int !(o "crc_ok") = 1) :: !frames; cur := [])
  done;
  List.rev !frames, !stage_mismatch

let () =
  if Sys.getenv_opt "RX_DEBUG" <> None then begin
    let frame = List.init 50 (fun i -> (i * 37) land 255) in
    List.iter (fun (n, thr) ->
        let got, _ = receive (Nrx { n; thr; stage = false; skew = [| 0.0; 0.0; 0.0; 0.0 |]; reversed = false }) ~frame ~ppm:0.0 ~jitter:0.0 ~seed:1 in
        Printf.printf "n=%d: %d frames\n" n (List.length got);
        List.iter (fun (bytes, ok) -> Printf.printf "  crc %b, %d bytes: %s\n" ok (List.length bytes)
                      (String.concat " " (List.map (Printf.sprintf "%02x") bytes))) got) [ (1, 5); (2, 8); (4, 16) ];
    Printf.printf "want %s\n" (String.concat " " (List.map (Printf.sprintf "%02x") (frame @ Eth_model.fcs_bytes frame)));
    exit 0
  end;
  let zero = [| 0.0; 0.0; 0.0; 0.0 |] in
  let configs =
    [ ("eth_rx h=3 (existing)", Legacy);
      ("n=1 thr=5", Nrx { n = 1; thr = 5; stage = false; skew = zero; reversed = false });
      ("n=1 thr=4", Nrx { n = 1; thr = 4; stage = false; skew = zero; reversed = false });
      ("n=2 thr=8 (both edges)", Nrx { n = 2; thr = 8; stage = false; skew = zero; reversed = false });
      ("n=4 thr=16 (stage RTL)", Nrx { n = 4; thr = 16; stage = true; skew = zero; reversed = false });
      ("n=4 thr=16, phases skewed", Nrx { n = 4; thr = 16; stage = true; skew = [| 0.0; 1e-9; -1e-9; 0.5e-9 |]; reversed = false });
      ("control: samples reversed", Nrx { n = 4; thr = 16; stage = true; skew = zero; reversed = true }) ] in
  let jitters = [ 0.0; 2.0; 3.0; 4.0; 5.0; 6.0; 8.0; 9.0; 10.0; 11.0; 12.0; 13.0 ] in
  let per = 10 in
  let ppms = [ -100.0; 100.0 ] in
  Printf.printf "10BASE-T receive at %.6f MHz; %d random frames (46-245 bytes) per ppm in {-100,+100} per cell; frames intact with good CRC\n"
    (rx_clk /. 1e6) per;
  Printf.printf "%-28s" "receiver \\ jitter +-ns";
  List.iter (fun j -> Printf.printf " %5.0f" j) jitters; print_newline ();
  let legacy_results = Hashtbl.create 64 and diff_count = ref 0 and diff_total = ref 0 and stage_bad = ref 0 in
  List.iter (fun (name, rx) ->
      Printf.printf "%-28s" name;
      List.iter (fun j ->
          let ok = ref 0 and tot = ref 0 in
          List.iter (fun ppm ->
              for k = 1 to per do
                let seed = (k * 7919) + int_of_float (j *. 1000.0) + int_of_float ppm in
                let st = Random.State.make [| seed; 17 |] in
                let len = 46 + Random.State.int st 200 in
                let frame = List.init len (fun _ -> Random.State.int st 256) in
                let got, sm = receive rx ~frame ~ppm ~jitter:(j *. 1e-9) ~seed in
                stage_bad := !stage_bad + sm;
                incr tot;
                if got = [ (frame @ Eth_model.fcs_bytes frame, true) ] then incr ok;
                (match rx with
                 | Legacy -> Hashtbl.replace legacy_results (j, ppm, k) got
                 | Nrx { n = 1; thr = 5; _ } ->
                   incr diff_total; if Hashtbl.find legacy_results (j, ppm, k) <> got then incr diff_count
                 | _ -> ())
              done) ppms;
          Printf.printf " %2d/%2d" !ok !tot; flush stdout) jitters;
      print_newline ()) configs;
  Printf.printf "differential check: eth_rxn n=1 thr=5 decoded differently from eth_rx h=3 on %d of %d lines (must be 0)\n" !diff_count !diff_total;
  Printf.printf "stage input samplers vs direct sampling of the same line: %d mismatching sample words (must be 0)\n" !stage_bad
