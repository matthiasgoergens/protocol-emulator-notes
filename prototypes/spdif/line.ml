(* The wire between a transmitter and a receiver: edge times in nanoseconds.

   A line is its level before the first edge and a sorted array of edge times. Transmitters
   produce one (a reference encoder at an exact bit rate, or the chip's pacer on its quarter grid);
   jitter is added per edge; a receiver samples it at its own clock's quarter points. *)

type t = { level0 : int; edges : float array }

(* edges of a UI-level sequence sent at [ui] ns per UI from [t0] *)
let of_levels ?(prev = 0) ?(t0 = 0.) ~ui levels =
  let l = ref [] and lv = ref prev in
  Array.iteri (fun i x -> if x <> !lv then begin l := (t0 +. (float i *. ui)) :: !l; lv := x end) levels;
  { level0 = prev; edges = Array.of_list (List.rev !l) }

(* edges of the pacer's output: (clock, quarter, transition) records at [fclk] *)
let of_bounds ~fclk (b : (int * int * int) array) =
  let tq = 1e9 /. fclk /. 4. in
  let l = Array.to_list b |> List.filter_map (fun (c, q, t) -> if t = 1 then Some (float ((4 * c) + q) *. tq) else None) in
  { level0 = 0; edges = Array.of_list l }

(* deterministic Gaussian from a seeded state *)
let gauss st = let u1 = Random.State.float st 1. and u2 = Random.State.float st 1. in
  sqrt (-2. *. log (Float.max u1 1e-300)) *. cos (2. *. Float.pi *. u2)

type jitter = { rms_ns : float; sin_pp_ns : float; sin_hz : float; sin_phase : float }

let no_jitter = { rms_ns = 0.; sin_pp_ns = 0.; sin_hz = 0.; sin_phase = 0. }

let add_jitter ~seed (j : jitter) (l : t) =
  let st = Random.State.make [| seed |] in
  let e = Array.map (fun t ->
      t +. (j.rms_ns *. gauss st) +. (j.sin_pp_ns /. 2. *. sin ((2. *. Float.pi *. j.sin_hz *. t *. 1e-9) +. j.sin_phase))) l.edges in
  Array.sort compare e;
  { l with edges = e }

(* time shift (a TX clock that starts at another moment) and scale (a TX clock offset) *)
let map_time f (l : t) = { l with edges = Array.map f l.edges }

(* the level at each quarter of each receiver clock: bit p of [samples.(k)] is the level at
   [phase + (4k + p) * tq] *)
let sample ~fclk ?(phase = 0.) ~clocks (l : t) =
  let tq = 1e9 /. fclk /. 4. in
  let out = Array.make clocks 0 in
  let i = ref 0 and lv = ref l.level0 and n = Array.length l.edges in
  for k = 0 to clocks - 1 do
    let v = ref 0 in
    for p = 0 to 3 do
      let t = phase +. (float ((4 * k) + p) *. tq) in
      while !i < n && l.edges.(!i) <= t do lv := 1 - !lv; incr i done;
      if !lv = 1 then v := !v lor (1 lsl p)
    done;
    out.(k) <- !v
  done;
  out

(* raw one-byte-per-sample capture for sigrok (-I binary), sampled every [ts] ns *)
let to_binary ~ts ~path (l : t) =
  let oc = open_out_bin path in
  let n = Array.length l.edges in
  let tend = if n = 0 then 0. else l.edges.(n - 1) +. 2000. in
  let i = ref 0 and lv = ref l.level0 in
  let k = ref 0 in
  while float !k *. ts <= tend do
    let t = float !k *. ts in
    while !i < n && l.edges.(!i) <= t do lv := 1 - !lv; incr i done;
    output_byte oc !lv; incr k
  done;
  close_out oc
