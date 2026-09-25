(* A 10BASE-T line in continuous time, written from the standard: Manchester (a 1 is low then
   high), each byte LSB first, preamble (possibly truncated, as after a repeater) and SFD, the frame
   with its FCS, TP_IDL (300 ns positive), then silence. The transmitter's bit clock may be off by
   [ppm] and every edge moves by a uniform random amount in [-jitter, +jitter].

   The receiver's front end is modelled as a comparator whose output is the sign of the line and
   a squelch flag that is high while the line is not idle; while squelched the comparator reads 0.
   Sampling at [clock_hz] with n samples per clock (sample p of clock c at (c + p/n) / clock_hz). *)

type burst = { start_ns : float; edges : float array; levels : int array; stop_ns : float }
(* edges.(k) is the start of half-bit k; levels.(k) its level; after the last half-bit the line is
   high (TP_IDL) until stop_ns *)

let make_burst ?(preamble_bits = 56) ?(ppm = 0.0) ?(jitter_ns = 0.0) ~start_ns frame_with_fcs =
  let pre_all = List.concat_map Eth_model.bits_of_byte (List.init 7 (fun _ -> 0x55)) in
  let pre = List.filteri (fun i _ -> i >= 56 - preamble_bits) pre_all in
  let bits = Array.of_list (pre @ Eth_model.bits_of_byte 0xD5 @ List.concat_map Eth_model.bits_of_byte frame_with_fcs) in
  let half = 50.0 *. (1.0 +. (ppm *. 1e-6)) in
  let n = 2 * Array.length bits in
  let edges = Array.init (n + 1) (fun k ->
      start_ns +. (float k *. half) +. (if k = 0 then 0.0 else (Random.float 2.0 -. 1.0) *. jitter_ns)) in
  let levels = Array.init n (fun k -> let b = bits.(k / 2) in if k mod 2 = 0 then (if b = 1 then -1 else 1) else (if b = 1 then 1 else -1)) in
  { start_ns; edges; levels; stop_ns = edges.(n) +. 300.0 }

let level_at (b : burst) t =
  if t < b.start_ns || t >= b.stop_ns then 0
  else if t >= b.edges.(Array.length b.levels) then 1
  else begin
    let lo = ref 0 and hi = ref (Array.length b.levels) in
    while !hi - !lo > 1 do let mid = (!lo + !hi) / 2 in if b.edges.(mid) <= t then lo := mid else hi := mid done;
    b.levels.(!lo)
  end

(* samples for clocks [0, cycles): per clock (n-bit sample word, bit p = sample p; active) *)
let sample ~clock_hz ~n ~cycles (bursts : burst list) =
  let bursts = Array.of_list (List.sort (fun a b -> compare a.start_ns b.start_ns) bursts) in
  let bi = ref 0 in
  Array.init cycles (fun c ->
      let word = ref 0 and act = ref false in
      for p = 0 to n - 1 do
        let t = (float c +. (float p /. float n)) *. 1e9 /. clock_hz in
        while !bi < Array.length bursts - 1 && t >= bursts.(!bi).stop_ns do incr bi done;
        let v = level_at bursts.(!bi) t in
        if v <> 0 then act := true;
        if v > 0 then word := !word lor (1 lsl p)
      done;
      (!word, !act))

let end_ns (b : burst) = b.stop_ns
