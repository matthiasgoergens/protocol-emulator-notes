(* Receiving below the naive sample budget: a locked receiver that takes ONE sample per bit, at the
   bit centre, instead of oversampling; skipping predictable fields; and reading faster than the
   clock when the line repeats.

   Line: NRZ at rate R, the transmitter's clock off by +100 ppm and wandering (sinusoidal jitter,
   0.2 UI at 100 kHz), plus random jitter per edge; 1 ns edges; threshold noise from the pad.

   4x  the four-phase sampler at 240 MS/s (architecture v0 pin stage) with an edge-tracking
       decision: the bit value is the sample nearest the estimated centre, the centre estimate a
       loop on the sampled transitions. Limit R <= 60 Mbit/s (4 samples per bit).
   1x  the fine-delay option: the pin's TDC timestamps every edge (thermometer snapshot each clock,
       Vernier, 20 ps rms here), a PI loop tracks phase and frequency, and each of the four input
       lanes places one sample per clock at a predicted bit centre through its DTC (130 ps bins,
       10 ps INL). Up to 4 bits per clock: R <= 240 Mbit/s contiguous.
   Output: ../results/rx.txt. Run from prototypes/scope/ocaml: ./_build/default/rx.exe [quick] *)

open Chain

let quick = Array.length Sys.argv > 1 && Sys.argv.(1) = "quick"
let out = Buffer.create 4096
let say fmt = Printf.ksprintf (fun s -> print_endline s; Buffer.add_string out (s ^ "\n")) fmt
let sig_v = Noise.threshold_sigma Noise.default

type line = { bits : bool array; edges : float array; (* edge time before bit i (nan if none) *) ui : float }

let make_line st ~rate ~n ~rj ~sj_ui ~sj_f =
  let ui = (1.0 /. rate) *. (1.0 -. 100e-6) in
  let bits = Array.init n (fun _ -> Random.State.bool st) in
  let edges = Array.init n (fun i ->
      let t = float_of_int i *. ui in
      t +. (sj_ui *. ui *. sin (2.0 *. Float.pi *. sj_f *. t)) +. (rj *. gauss st)) in
  { bits; edges; ui }

(* level at time t (+-1 before noise), with 1 ns erf edges; the relevant edges are near t *)
let level ln t =
  let i = max 0 (min (Array.length ln.bits - 1) (int_of_float (t /. ln.ui))) in
  let s = 1e-9 /. 2.563 in
  let v = ref (if ln.bits.(max 0 (i - 3)) then 1.0 else -1.0) in
  for j = max 1 (i - 2) to min (Array.length ln.bits - 1) (i + 3) do
    if ln.bits.(j) <> ln.bits.(j - 1) then
      v := !v +. ((if ln.bits.(j) then 2.0 else -2.0) *. phi ((t -. ln.edges.(j)) /. s))
  done;
  !v

let read ln st t = (0.3 *. level ln t) +. (sig_v *. gauss st) > 0.0     (* 300 mV of overdrive at full swing *)

(* compare a received sequence with the truth at the best alignment (the receiver does not know
   the absolute bit index); returns (errors, bits compared) *)
let align_errors truth got =
  let n = Array.length got in
  let best = ref max_int in
  for off = -3 to 3 do
    let e = ref 0 in
    for j = 8 to n - 1 do
      let i = j + off in
      if i >= 0 && i < Array.length truth && got.(j) <> truth.(i) then incr e
    done;
    best := min !best !e
  done;
  (!best, n - 8)

(* 4x oversampling receiver: samples at k * T/4; a loop on the sampled transitions tracks the bit
   boundary; each bit is the sample nearest its estimated centre *)
let rx4 ln st =
  let q = (1.0 /. 60e6) /. 4.0 in
  let n = Array.length ln.bits in
  let tend = float_of_int n *. ln.ui in
  let ns = int_of_float (tend /. q) in
  let s = Array.init ns (fun k -> read ln st ((float_of_int k *. q) +. (10e-12 *. gauss st))) in
  let ph = ref 0.0 and fr = ref (ln.ui *. (1.0 +. 100e-6)) in   (* starts at the nominal rate *)
  let got = ref [] in
  let centre = ref (0.5 *. !fr) in
  let k = ref 1 in
  while !centre < tend -. !fr do
    (* take in all transitions before the centre *)
    while !k < ns && float_of_int !k *. q < !centre do
      if s.(!k) <> s.(!k - 1) then begin
        let e = (float_of_int !k *. q) -. (q /. 2.0) in
        let m = Float.round ((e -. !ph) /. !fr) in
        let err = e -. (!ph +. (m *. !fr)) in
        ph := !ph +. (m *. !fr) +. (0.3 *. err);
        fr := !fr +. (0.002 *. err)
      end;
      incr k
    done;
    let m = Float.round ((!centre -. !ph) /. !fr -. 0.5) in
    let c = !ph +. ((m +. 0.5) *. !fr) in
    let kc = max 0 (min (ns - 1) (int_of_float (Float.round (c /. q)))) in
    got := s.(kc) :: !got;
    centre := c +. !fr
  done;
  align_errors ln.bits (Array.of_list (List.rev !got))

(* 1x locked receiver: timestamps every edge, samples each wanted bit once at its predicted centre;
   the bit count since the last edge is the receiver's own (rounded elapsed time / period);
   [want i] says whether bit i is read at all (skip predictable fields: the receiver knows the frame
   layout from its own count); lanes limit reads to 4 per clock *)
let total_slips = ref 0

let rx1 ?(want = fun _ -> true) ln st =
  let n = Array.length ln.bits in
  let per = 1.0 /. 60e6 in
  let ph = ref (ln.edges.(0) +. (20e-12 *. gauss st)) and fr = ref (ln.ui *. (1.0 +. 100e-6)) in
  let idx = ref 0 in                          (* the receiver's bit index of the edge at ph *)
  let errs = ref 0 and reads = ref 0 and missed = ref 0 and slips = ref 0 in
  let lane_use = Hashtbl.create 1024 in
  for i = 1 to n - 1 do
    if ln.bits.(i) <> ln.bits.(i - 1) then begin
      let ts = ln.edges.(i) +. (20e-12 *. gauss st) in
      let m = Float.round ((ts -. !ph) /. !fr) in
      let err = ts -. (!ph +. (m *. !fr)) in
      idx := !idx + int_of_float m;
      if !idx <> i then (incr slips; idx := i);
      ph := ts -. (0.75 *. err);
      fr := !fr +. (0.01 *. err /. Float.max 1.0 m)
    end;
    if i >= 8 && want i then begin
      let centre = !ph +. ((float_of_int (i - !idx) +. 0.5) *. !fr) in
      let c = int_of_float (centre /. per) in
      let used = try Hashtbl.find lane_use c with Not_found -> 0 in
      if used >= 4 then incr missed
      else begin
        Hashtbl.replace lane_use c (used + 1);
        let t = centre +. (sqrt ((10e-12 ** 2.0) +. (15e-12 ** 2.0)) *. gauss st) in   (* DTC INL + line noise *)
        incr reads;
        if read ln st t <> ln.bits.(i) then incr errs
      end
    end
  done;
  total_slips := !total_slips + !slips;
  (!errs + (8 * !slips), !reads, !missed)

let () =
  let st = Random.State.make [| 3 |] in
  let n = if quick then 20_000 else 200_000 in
  say "# rx.exe%s (seed 3): %d bits per cell; +100 ppm, 0.2 UI sinusoidal wander at 100 kHz, random jitter per edge" (if quick then " quick" else "") n;
  say "";
  say "1. One locked sample per bit against 4x oversampling (bit errors / bits read)";
  say "   rate        RJ rms   4x oversampling            1x locked (TDC + DTC)";
  List.iter (fun rate ->
      List.iter (fun rj_ui ->
          let ln = make_line st ~rate ~n ~rj:(rj_ui /. rate) ~sj_ui:0.2 ~sj_f:100e3 in
          let c4 = if rate <= 60e6 then (let e, b = rx4 ln st in Printf.sprintf "%7d / %-9d" e b) else "   impossible      " in
          let e1, r1, m1 = rx1 ln st in
          say "   %5.0f Mb/s  %4.2f UI  %s  %7d / %-9d%s" (rate /. 1e6) rj_ui c4 e1 r1
            (if m1 > 0 then Printf.sprintf " (%d bits beyond 4 per clock)" m1 else "")) [ 0.05; 0.11; 0.14; 0.17; 0.20 ]) [ 30e6; 60e6; 125e6; 240e6 ];
  say "   storage per bit: 4x keeps 4 samples (or a decision after a tracker); 1x keeps 1, plus the timestamps the";
  say "   tracker consumes and discards. The 4x centre is quantised to T/4 = 4.17 ns; the 1x centre to a 130 ps bin.";
  say "";
  say "2. Skip predictable fields: sample only the bits a known frame format leaves open";
  let frames = [
    ("Ethernet/IPv4/UDP, 16-byte payload, known peer",
     [ (64, false, "preamble+SFD"); (96, false, "MACs (ours, peer)"); (16, false, "ethertype");
       (32, false, "IPv4 version..flags, fixed length"); (16, true, "IPv4 identification");
       (32, false, "TTL, protocol, (checksum below)"); (16, true, "IPv4 header checksum"); (64, false, "addresses");
       (32, false, "UDP ports"); (16, false, "UDP length"); (16, true, "UDP checksum"); (128, true, "payload");
       (32, true, "FCS (read it: it is the integrity check)") ]);
    ("CAN 2.0A frame from a known ID, 8 data bytes",
     [ (19, false, "SOF, ID, RTR, IDE, r0, DLC"); (64, true, "data"); (15, true, "CRC"); (10, false, "delimiters, ACK, EOF") ]);
    ("SPI flash status poll (0x05 then 1 byte)", [ (8, false, "command"); (8, true, "status") ]) ] in
  List.iter (fun (name, fields) ->
      let tot = List.fold_left (fun s (b, _, _) -> s + b) 0 fields in
      let var = List.fold_left (fun s (b, v, _) -> if v then s + b else s) 0 fields in
      say "   %-50s %4d bits, %4d open (%3.0f %%): %s" name tot var (100.0 *. float_of_int var /. float_of_int tot)
        (String.concat ", " (List.filter_map (fun (b, v, l) -> if v then Some (Printf.sprintf "%s %d" l b) else None) fields))) frames;
  (* simulate the Ethernet case: read only the open bits at 10 Mbit/s NRZ-equivalent timing and at 125 *)
  let open_mask = Array.make 560 false in
  let pos = ref 0 in
  List.iter (fun (b, v, _) -> for i = !pos to !pos + b - 1 do open_mask.(i) <- v done; pos := !pos + b)
    (snd (List.hd frames));
  let ln = make_line st ~rate:125e6 ~n:(560 * 200) ~rj:(0.05 /. 125e6) ~sj_ui:0.2 ~sj_f:100e3 in
  let e, r, m = rx1 ~want:(fun i -> open_mask.(i mod 560)) ln st in
  say "   simulated: 200 such frames back to back at 125 Mbit/s, 0.05 UI RJ, reading only the open bits: %d reads, %d errors%s"
    r e (if m > 0 then Printf.sprintf ", %d beyond the lanes" m else "");
  say "   (tracking still uses every edge's timestamp; the saving is in samples stored, decided and shipped)";
  say "";
  say "3. Faster than the clock: a repeating frame at more than 240 Mbit/s, read over several repetitions";
  List.iter (fun rate ->
      let bits_per_frame = 256 in
      let ln = make_line st ~rate ~n:(bits_per_frame * 40) ~rj:(0.04 /. rate) ~sj_ui:0.0 ~sj_f:1.0 in
      (* the frame repeats (same content); the lanes read up to 4 bits per clock, a different subset each
         repetition, until every bit of the frame has been read once *)
      let ln = { ln with bits = Array.mapi (fun i _ -> ln.bits.(i mod bits_per_frame)) ln.bits } in
      let got = Array.make bits_per_frame false in
      let reps = ref 0 and errs = ref 0 and done_ = ref false in
      while not !done_ && !reps < 39 do
        let r = !reps in
        let e, _, _ = rx1 ~want:(fun i -> i / bits_per_frame = r && not got.(i mod bits_per_frame)
                                          && ((i mod bits_per_frame) + r) mod (int_of_float (ceil (rate /. 240e6))) = 0) ln st in
        errs := !errs + e;
        for i = 0 to bits_per_frame - 1 do
          if (i + r) mod (int_of_float (ceil (rate /. 240e6))) = 0 then got.(i) <- true
        done;
        incr reps;
        done_ := Array.for_all (fun x -> x) got
      done;
      say "   %4.0f Mbit/s: a %d-bit frame read completely in %d repetitions, %d bit errors (0.04 UI RJ)"
        (rate /. 1e6) bits_per_frame !reps !errs) [ 250e6; 400e6 ];
  say "   the pad is the limit above that: SPICE shows full-swing inputs clean at 200 MHz (IHP's own report),";
  say "   i.e. 400 Mbit/s; the kicked-sampling aperture is 0.8 GHz.";
  say "";
  say "bit-count slips of the 1x receiver over all runs: %d (the receiver's own count of bits since the last edge" !total_slips;
  say "disagreeing with the transmitted index; each is charged as 8 bit errors and re-synchronised)";
  let oc = open_out (if quick then "../results/rx-quick.txt" else "../results/rx.txt") in
  output_string oc (Buffer.contents out); close_out oc
