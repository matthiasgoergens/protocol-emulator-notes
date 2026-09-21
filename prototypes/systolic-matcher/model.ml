(* Systolic pattern correlator: the specification.

   N identical cells in a line. Cell i holds two configuration bits, a template bit t_i and a
   mask bit m_i, loaded through a serial chain. Input samples x enter cell 0 and move right one
   cell every two clocks (two registers per cell); partial sums y move right one cell per clock.
   Cell i adds m_i * [x = t_i] to the sum passing through it, using the sample in its first
   register. At the array's end the sum is compared with a threshold; the hit flag is registered.

   Derivation of what the array computes. With xa_i(n) the first x register of cell i at time n,
   xa_i(n) = x(n - 1 - 2i). With y_i(n) = y_{i-1}(n-1) + w_i(xa_i(n-1)), where w_i(v) = m_i * [v = t_i]:
     y_i(n) = sum_{j<=i} w_j(x(n - 2 - i - j)),
   so the last cell's sum at time n is
     y(n) = sum_{j<N} w_j(x(n - N - 1 - j)):
   a correlation with latency N+1, template bit 0 aligned with the newest sample of the window.
   Samples before time 0 are 0 (reset state). hit(n) = [y(n-1) >= threshold]. *)

let n = 16

type cfg = { t : int array; m : int array; thr : int }

(* Serial configuration sequence, first bit shifted first: thr[4] .. thr[0], then for cell N-1
   down to cell 0 the pair t_i, m_i. Shifting it into the RTL's chain leaves each bit in place. *)
let cfg_bits c =
  List.init 5 (fun k -> (c.thr lsr (4 - k)) land 1)
  @ List.concat (List.init n (fun k -> let i = n - 1 - k in [ c.t.(i); c.m.(i) ]))

(* y(n) and hit(n) from the whole input history x.(0..n). *)
(* After a reset every partial-sum register is 0, so the term contributed by cell j at time n
   exists only if it entered the pipeline at or after time 0: n - N + j >= 0. Samples before time 0
   are 0 (the sample registers are reset too). *)
let y_at c (x : int -> int) time =
  let s = ref 0 in
  for j = 0 to n - 1 do
    if time - n + j >= 0 then begin
      let k = time - n - 1 - j in
      let v = if k < 0 then 0 else x k in
      if c.m.(j) = 1 && v = c.t.(j) then incr s
    end
  done; !s

let hit_at c x time = if time = 0 then false else y_at c x (time - 1) >= c.thr
