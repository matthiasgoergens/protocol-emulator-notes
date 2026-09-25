(* Small dense linear algebra for sparse recovery: incremental least squares by modified
   Gram-Schmidt, and orthogonal matching pursuit over tones (pairs of cos/sin atoms) with
   off-grid refinement. *)

let dot a b =
  let s = ref 0.0 in
  for i = 0 to Array.length a - 1 do s := !s +. (a.(i) *. b.(i)) done;
  !s

let axpy alpha x y = Array.iteri (fun i xi -> y.(i) <- y.(i) +. (alpha *. xi)) x

(* least squares y ~ sum_j c_j a_j for the columns a_j (list), by MGS; returns coefficients *)
let lstsq (cols : float array array) (y : float array) =
  let k = Array.length cols in
  let m = Array.length y in
  let q = Array.make k [||] and r = Array.make_matrix k k 0.0 in
  for j = 0 to k - 1 do
    let v = Array.copy cols.(j) in
    for i = 0 to j - 1 do
      let c = dot q.(i) v in
      r.(i).(j) <- c;
      axpy (-.c) q.(i) v
    done;
    let n = sqrt (dot v v) in
    r.(j).(j) <- n;
    q.(j) <- (if n > 0.0 then Array.map (fun x -> x /. n) v else Array.make m 0.0)
  done;
  let qty = Array.init k (fun j -> dot q.(j) y) in
  let c = Array.make k 0.0 in
  for j = k - 1 downto 0 do
    let s = ref qty.(j) in
    for i = j + 1 to k - 1 do s := !s -. (r.(j).(i) *. c.(i)) done;
    c.(j) <- (if r.(j).(j) > 0.0 then !s /. r.(j).(j) else 0.0)
  done;
  c

type tone = { f : float; amp : float; phase : float }

(* counters of the work done, to size the host and the array *)
let corr_macs = ref 0
let other_flops = ref 0

(* OMP over tones. [atom f] returns the (cos, sin) measurement vectors of a unit tone at f;
   [grid] the candidate frequencies with their precomputed atoms; k tones are found, then each
   frequency is refined by golden-section search on the residual with the others held. *)
let omp_tones ~(atom : float -> float array * float array) ~(grid : (float * float array * float array) array)
    ~(df : float) (y : float array) k =
  let m = Array.length y in
  let chosen = ref [] in
  let fit freqs =
    let cols = List.concat_map (fun f -> let c, s = atom f in [ c; s ]) freqs |> Array.of_list in
    let c = lstsq cols y in
    other_flops := !other_flops + (Array.length cols * Array.length cols * m * 2);
    let r = Array.copy y in
    Array.iteri (fun j col -> axpy (-.c.(j)) col r) cols;
    (c, r)
  in
  let resid = ref (Array.copy y) in
  for _ = 1 to k do
    let best = ref (-1.0) and bf = ref 0.0 in
    Array.iter (fun (f, ca, sa) ->
        let a = dot ca !resid and b = dot sa !resid in
        let na = dot ca ca +. 1e-30 and nb = dot sa sa +. 1e-30 in
        let e = (a *. a /. na) +. (b *. b /. nb) in
        if e > !best then (best := e; bf := f)) grid;
    corr_macs := !corr_macs + (Array.length grid * m * 4);
    chosen := !chosen @ [ !bf ];
    let _, r = fit !chosen in
    resid := r
  done;
  (* refinement: two passes of golden-section search per tone over +-df *)
  let freqs = Array.of_list !chosen in
  for _ = 1 to 2 do
    Array.iteri (fun i f0 ->
        let others = List.filteri (fun j _ -> j <> i) (Array.to_list freqs) in
        let _, r = fit others in
        let score f =
          let ca, sa = atom f in
          let cs = lstsq [| ca; sa |] r in
          let rr = Array.copy r in
          axpy (-.cs.(0)) ca rr; axpy (-.cs.(1)) sa rr;
          -.(dot rr rr) in
        let g = (sqrt 5.0 -. 1.0) /. 2.0 in
        let a = ref (f0 -. df) and b = ref (f0 +. df) in
        let c = ref (!b -. (g *. (!b -. !a))) and d = ref (!a +. (g *. (!b -. !a))) in
        let fc = ref (score !c) and fd = ref (score !d) in
        for _ = 1 to 30 do
          if !fc > !fd then (b := !d; d := !c; fd := !fc; c := !b -. (g *. (!b -. !a)); fc := score !c)
          else (a := !c; c := !d; fc := !fd; d := !a +. (g *. (!b -. !a)); fd := score !d)
        done;
        freqs.(i) <- 0.5 *. (!a +. !b);
        other_flops := !other_flops + (60 * m * 8)) freqs
  done;
  let c, r = fit (Array.to_list freqs) in
  let tones = Array.mapi (fun i f ->
      let a = c.(2 * i) and b = c.((2 * i) + 1) in
      { f; amp = sqrt ((a *. a) +. (b *. b)); phase = atan2 (-.b) a }) freqs in
  (tones, sqrt (dot r r /. float_of_int m))
