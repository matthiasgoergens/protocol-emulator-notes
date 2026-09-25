(* An independent judge of a 10BASE-T transmitter's differential output, written from the
   standard's timing rules and knowing nothing about how the waveform was generated.

   Input: the differential level (+1, -1, 0) as runs of equal level, each run a whole number of
   ticks of [tick_ns]. The judge splits the line into bursts separated by at least [burst_gap_ns]
   of zero, and classifies each burst as a link pulse (only positive) or a frame.

   Limits encoded (clause 14 of IEEE 802.3, as I know them; see the README for which ones I could
   check against a source):
   - NLP: a single positive pulse, nominal 100 ns, at most 200 ns wide [nlp_width];
     no negative part.
   - NLP spacing: every link pulse follows the end of the previous activity (pulse or frame) by
     16 ms +- 8 ms, i.e. [8, 24] ms [nlp_gap]; and no idle stretch longer than 24 ms.
   - Frame: every interval between consecutive zero crossings is 50 or 100 ns, to within
     [edge_tol_ns]; the bits decode (Manchester, a 1 is low then high) to 56 preamble bits,
     the SFD, and a frame whose FCS is right.
   - TP_IDL: the last zero crossing is positive-going and the line stays positive for at least
     250 ns after it [tp_idl_min]; we also bound it above by [tp_idl_max] (400 ns: a sanity bound
     of ours, not a number from the standard), then it returns to zero.
   - Inter-packet gap: at least 9.6 us from the end of one frame's last bit cell to the next
     frame's first transition [ipg]. *)

type limits = {
  nlp_width : float * float;   (* ns *)
  nlp_gap : float * float;     (* ms *)
  edge_tol_ns : float;
  tp_idl_min : float;          (* ns after the last positive-going crossing *)
  tp_idl_max : float;
  ipg_us : float;
  burst_gap_ns : float;
}

let clause14 = { nlp_width = (60.0, 200.0); nlp_gap = (8.0, 24.0); edge_tol_ns = 2.5;
                 tp_idl_min = 250.0; tp_idl_max = 400.0; ipg_us = 9.6; burst_gap_ns = 500.0 }

type event =
  | Nlp of { t_ns : float; width_ns : float }
  | Frame of { t_ns : float; end_ns : float; bytes : int list option; fcs_ok : bool; preamble_bits : int;
               max_dev_ns : float; tp_idl_ns : float }

type report = { events : event list; violations : string list; nlp_gaps_ms : float list; nlp_widths : float list;
                tp_idls : float list; max_edge_dev : float }

let crc_ok bytes =
  (* FCS check by residual, from the Ethernet model's CRC (written from the standard) *)
  List.length bytes >= 5 && Eth_model.crc32_reg bytes = Eth_model.residual

(* decode a frame burst: list of (start tick, level, length) runs *)
let decode_frame ~tick_ns runs =
  (* zero crossings: between a + run and a - run (or vice versa), possibly separated by a short
     zero run; the crossing time is the middle of the zero run, or the boundary *)
  let crossings = ref [] in
  let rec go prev_sign prev_end pending_zero = function
    | [] -> ()
    | (s, l, n) :: rest ->
      if l = 0 then go prev_sign prev_end (Some (s, n)) rest
      else begin
        (if prev_sign <> 0 && l <> prev_sign then
           let t = match pending_zero with Some (zs, zn) -> float zs +. (float zn /. 2.0) | None -> float s in
           crossings := (t *. tick_ns, l) :: !crossings);
        go l (s + n) None rest
      end in
  go 0 0 None runs;
  let xs = Array.of_list (List.rev !crossings) in
  (* intervals must be 50 or 100 ns *)
  let max_dev = ref 0.0 and bad = ref 0 in
  for i = 1 to Array.length xs - 1 do
    let d = fst xs.(i) -. fst xs.(i - 1) in
    let dev = Float.min (Float.abs (d -. 50.0)) (Float.abs (d -. 100.0)) in
    if dev > !max_dev then max_dev := dev
  done;
  ignore bad;
  (* Manchester decode: the first crossing is mid-bit (the preamble alternates, so every crossing
     in it is mid-bit); after a mid-bit crossing, a crossing 50 ns later is a boundary and one
     100 ns later is the next mid-bit. Bit = 1 on a positive-going mid-bit crossing. *)
  let bits = ref [] and last_mid = ref neg_infinity in
  Array.iter (fun (t, l) ->
      if t -. !last_mid > 75.0 then begin bits := (if l > 0 then 1 else 0) :: !bits; last_mid := t end) xs;
  let bits = List.rev !bits in
  (* preamble: count alternating 1,0 bits before the SFD's 1,1 *)
  let rec find n = function
    | 1 :: 1 :: rest -> Some (n, rest)
    | _ :: rest -> find (n + 1) rest
    | [] -> None in
  let bytes, pre =
    match find 0 bits with
    | Some (n, rest) ->
      let nb = List.length rest / 8 in
      let a = Array.of_list rest in
      (Some (List.init nb (fun k -> List.fold_left (fun acc j -> acc lor (a.((8 * k) + j) lsl j)) 0 (List.init 8 Fun.id))), n + 2)
    | None -> (None, 0) in
  (* TP_IDL: time from the last positive-going crossing to the end of the burst's positive level *)
  let last_pos = Array.fold_left (fun acc (t, l) -> if l > 0 then t else acc) neg_infinity xs in
  let last_neg = Array.fold_left (fun acc (t, l) -> if l < 0 then t else acc) neg_infinity xs in
  let burst_end = match List.rev runs with (s, _, n) :: _ -> float (s + n) *. tick_ns | [] -> 0.0 in
  let tp_idl = if last_pos > last_neg then burst_end -. last_pos else -1.0 in
  (* the end of the last bit cell: the last mid-bit crossing plus 50 ns *)
  (bytes, pre, !max_dev, tp_idl, !last_mid +. 50.0, xs)

let check ?(lim = clause14) ~tick_ns (runs : (int * int) list) =
  (* annotate runs with start ticks *)
  let t = ref 0 in
  let runs = List.map (fun (l, n) -> let s = !t in t := !t + n; (s, l, n)) runs in
  let total = !t in
  let gap_ticks = int_of_float (lim.burst_gap_ns /. tick_ns) in
  (* split into bursts *)
  let bursts = ref [] and cur = ref [] in
  List.iter (fun ((_, l, n) as r) ->
      if l = 0 && n >= gap_ticks then begin
        if !cur <> [] then bursts := List.rev !cur :: !bursts; cur := [] end
      else if l <> 0 || !cur <> [] then cur := r :: !cur) runs;
  if !cur <> [] then bursts := List.rev !cur :: !bursts;
  let bursts = List.rev !bursts in
  let viol = ref [] in
  let v fmt = Printf.ksprintf (fun s -> viol := s :: !viol) fmt in
  let events = List.map (fun b ->
      let (s0, _, _) = List.hd b in
      let has_neg = List.exists (fun (_, l, _) -> l < 0) b in
      if not has_neg then begin
        let width = List.fold_left (fun acc (_, l, n) -> if l > 0 then acc + n else acc) 0 b in
        let zeros = List.exists (fun (_, l, _) -> l = 0) b in
        if zeros then v "link pulse at %.3f ms has a gap inside" (float s0 *. tick_ns /. 1e6);
        Nlp { t_ns = float s0 *. tick_ns; width_ns = float width *. tick_ns }
      end else begin
        let bytes, pre, dev, tp, end_ns, _ = decode_frame ~tick_ns b in
        Frame { t_ns = float s0 *. tick_ns; end_ns; bytes; fcs_ok = (match bytes with Some bs -> crc_ok bs | None -> false);
                preamble_bits = pre; max_dev_ns = dev; tp_idl_ns = tp }
      end) bursts in
  (* per-event checks *)
  (* the start of the trace counts as activity, so the first link pulse is held to the same
     8..24 ms window (review finding: it was unchecked) *)
  let last_activity_end = ref 0.0 and have_prev = ref true in
  let gaps = ref [] and widths = ref [] and tps = ref [] and maxdev = ref 0.0 in
  let prev_frame_end = ref neg_infinity in
  List.iter (function
      | Nlp { t_ns; width_ns } ->
        widths := width_ns :: !widths;
        let lo, hi = lim.nlp_width in
        if width_ns < lo || width_ns > hi then v "link pulse at %.3f ms is %.1f ns wide" (t_ns /. 1e6) width_ns;
        let gap = (t_ns -. !last_activity_end) /. 1e6 in
        if !have_prev then begin
          gaps := gap :: !gaps;
          let lo, hi = lim.nlp_gap in
          if gap < lo || gap > hi then v "link pulse at %.3f ms follows activity by %.3f ms" (t_ns /. 1e6) gap
        end;
        have_prev := true;
        last_activity_end := t_ns +. width_ns
      | Frame { t_ns; end_ns; bytes; fcs_ok; preamble_bits; max_dev_ns; tp_idl_ns } ->
        maxdev := Float.max !maxdev max_dev_ns;
        tps := tp_idl_ns :: !tps;
        if max_dev_ns > lim.edge_tol_ns then v "frame at %.3f ms: a crossing interval is %.2f ns off 50/100 ns" (t_ns /. 1e6) max_dev_ns;
        if bytes = None then v "frame at %.3f ms: no SFD" (t_ns /. 1e6);
        if not fcs_ok then v "frame at %.3f ms: FCS wrong" (t_ns /. 1e6);
        if preamble_bits <> 64 then v "frame at %.3f ms: preamble+SFD is %d bits, not 64" (t_ns /. 1e6) preamble_bits;
        if tp_idl_ns < lim.tp_idl_min || tp_idl_ns > lim.tp_idl_max then
          v "frame at %.3f ms: TP_IDL %.1f ns after the last positive crossing" (t_ns /. 1e6) tp_idl_ns;
        if (t_ns -. !prev_frame_end) /. 1e3 < lim.ipg_us then
          v "frame at %.3f ms: gap %.2f us after the previous frame" (t_ns /. 1e6) ((t_ns -. !prev_frame_end) /. 1e3);
        if (t_ns -. !last_activity_end) /. 1e6 > snd lim.nlp_gap then
          v "frame at %.3f ms follows %.3f ms of silence without a link pulse" (t_ns /. 1e6) ((t_ns -. !last_activity_end) /. 1e6);
        prev_frame_end := end_ns;
        have_prev := true;
        last_activity_end := end_ns +. tp_idl_ns) events;
  let tail = (float total *. tick_ns -. !last_activity_end) /. 1e6 in
  if tail > snd lim.nlp_gap then v "idle for %.3f ms at the end without a link pulse" tail;
  { events; violations = List.rev !viol; nlp_gaps_ms = List.rev !gaps; nlp_widths = List.rev !widths;
    tp_idls = List.rev !tps; max_edge_dev = !maxdev }

let frames_of r = List.filter_map (function Frame { bytes = Some b; _ } -> Some b | _ -> None) r.events
