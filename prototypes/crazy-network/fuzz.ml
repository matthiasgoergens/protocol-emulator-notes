(* Coverage-guided fuzzing of the crazy network, our own version.

   AFL++'s coverage is control flow: which edges the instruction pointer took. The network has no
   control flow, so coverage has to be defined on data. What plays the role of branches here are
   the data-dependent decisions every cell makes on every step:
     max cells  which operand won (a > b)
     add/sub/xor cells  whether the 8-bit result wrapped (carry or borrow, including the constant)
   Feature families, each hashed into a slot, with log2 hit-count buckets as in AFL:
     D  per cell, the last four decision bits (AFL++'s n-gram coverage, n = 4)   64 x 16 slots
     P  horizontal 3-grams of 4-pixel symbols in field 1 (what a TV can resolve)  17^3 slots
     M  fraction of pixels that change between fields 0 and 1, 16 buckets        16 slots
   An input (a program) is kept when it produces a (slot, bucket) pair never seen before.

   Borrowed heuristics: AFL's favoured entries (the smallest program covering each feature) and
   havoc stacks with splicing; Hypothesis's swarm testing (a mutant may be restricted to a random
   subset of operations) and shrinking (a new entry is simplified by zeroing constants while its new
   features survive). *)
open Model

let d_slots = n * 16 and p_slots = 17 * 17 * 17 and m_slots = 16
let slots = d_slots + p_slots + m_slots
let buckets = 4
(* Relative-frequency buckets within a feature family, not AFL's raw hit counts: the network
   produces millions of hits, and fine count buckets made every noisy program look new. *)
let rel_bucket c total = if c = 0 || total = 0 then -1 else
  let f = float c /. float total in if f < 0.01 then 0 else if f < 0.1 then 1 else if f < 0.25 then 2 else 3

(* run fields 0 and 1; instrumented copy of Model.run_field; returns counters and field 1 image *)
let execute prog =
  let cnt = Array.make slots 0 in
  let s = Array.make n 0 and t = Array.make n 0 and hist = Array.make n 0 in
  let img0 = Array.make_matrix nvis npix 0 and img1 = Array.make_matrix nvis npix 0 in
  for frame = 0 to 1 do
    let img = if frame = 0 then img0 else img1 in
    for line = 0 to lpf - 1 do
      for h = 0 to cpl - 1 do
        let visible = line >= first_vis && line < first_vis + nvis && h >= vis_start && h < vis_start + npix * pixc
                      && (h - vis_start) mod pixc = 5 in
        if visible then img.(line - first_vis).((h - vis_start) / pixc) <- s.(prog.tap) lsr 4;
        if h = 0 then begin
          if prog.reset then Array.fill s 0 n 0;
          let sd = seeds prog ~line ~frame in
          for j = 0 to 3 do s.(j) <- s.(j) lxor sd.(j) done
        end else if h mod prog.p = 0 then begin
          for i = 0 to n - 1 do
            let a = s.(left.(i)) and b = s.(partner.(i)) in
            let v = match prog.ops.(i) with 0 -> a + b | 1 -> a lxor b | 2 -> a - b | _ -> if a > b then a else b in
            let r = v + prog.ks.(i) in
            let d = if prog.ops.(i) = 3 then (if a > b then 1 else 0) else (if r < 0 || r > 255 then 1 else 0) in
            t.(i) <- r land 255;
            if frame = 1 then begin
              let hh = ((hist.(i) lsl 1) lor d) land 15 in
              hist.(i) <- hh;
              let k = i * 16 + hh in cnt.(k) <- cnt.(k) + 1
            end
          done;
          Array.blit t 0 s 0 n
        end
      done
    done
  done;
  (* pixel motifs on what a TV can show: composite colour cannot resolve single pixels, so each run
     of 4 pixels becomes one symbol, its majority colour if at least 3 of 4 agree, else 16 ("mush");
     then horizontal 3-grams of symbols *)
  let sym y bx =
    let c = Array.make 16 0 in
    for x = 4 * bx to 4 * bx + 3 do let v = img1.(y).(x) in c.(v) <- c.(v) + 1 done;
    let best = ref 0 in Array.iteri (fun v k -> if k > c.(!best) then best := v) c;
    if c.(!best) >= 3 then !best else 16 in
  for y = 0 to nvis - 1 do
    let s = Array.init (npix / 4) (sym y) in
    for bx = 2 to npix / 4 - 1 do
      let k = d_slots + (s.(bx - 2) * 17 + s.(bx - 1)) * 17 + s.(bx) in
      cnt.(k) <- cnt.(k) + 1
    done
  done;
  let changed = ref 0 in
  Array.iteri (fun y row -> Array.iteri (fun x v -> if v <> img0.(y).(x) then incr changed) row) img1;
  let m = min 15 (!changed * 16 / (nvis * npix)) in
  cnt.(d_slots + p_slots + m) <- 1;
  cnt, img1

let features cnt =
  let fs = ref [] in
  let family lo hi ~min_bucket =
    let total = ref 0 in
    for k = lo to hi - 1 do total := !total + cnt.(k) done;
    for k = lo to hi - 1 do
      let b = rel_bucket cnt.(k) !total in
      if b >= min_bucket then fs := (k * buckets + b) :: !fs
    done in
  family 0 d_slots ~min_bucket:0;
  (* pixel motifs count only when they recur: at least 1 % of the picture *)
  family d_slots (d_slots + p_slots) ~min_bucket:1;
  for k = d_slots + p_slots to slots - 1 do if cnt.(k) > 0 then fs := (k * buckets) :: !fs done;
  !fs

let size prog = Array.fold_left (fun a k -> if k <> 0 then a + 1 else a) 0 prog.ks

let copy p = { p with ops = Array.copy p.ops; ks = Array.copy p.ks }

let interesting_values = [| 0; 1; 2; 127; 128; 254; 255 |]

let mutate st queue p0 =
  let p = copy p0 in
  let hdr = ref p in
  let ri m = Random.State.int st m in
  let stack = 1 lsl (ri 4) in
  for _ = 1 to stack do
    match ri 9 with
    | 0 | 1 -> p.ops.(ri n) <- ri 4
    | 2 -> p.ks.(ri n) <- ri 256
    | 3 -> p.ks.(ri n) <- interesting_values.(ri (Array.length interesting_values))
    | 4 -> let i = ri n in p.ks.(i) <- (p.ks.(i) + ri 9 - 4) land 255
    | 5 -> let i = ri n in p.ks.(i) <- p.ks.(i) lxor (1 lsl ri 8)
    | 6 -> (match ri 4 with
            | 0 -> hdr := { !hdr with tap = ri n } | 1 -> hdr := { !hdr with p = [| 1; 2; 5; 10 |].(ri 4) }
            | 2 -> hdr := { !hdr with reset = not !hdr.reset } | _ -> hdr := { !hdr with scheme = ri n_schemes })
    | 7 -> (* splice a block of cells from another queue entry *)
      let (q, _) = queue.(ri (Array.length queue)) in
      let a = ri n in let len = 1 + ri 16 in
      for j = a to min (n - 1) (a + len) do p.ops.(j) <- q.ops.(j); p.ks.(j) <- q.ks.(j) done
    | _ -> p.ks.(ri n) <- 0
  done;
  (* swarm testing: sometimes restrict the whole program to a random subset of operations *)
  if ri 5 = 0 then begin
    let allowed = List.filter (fun _ -> ri 2 = 0) [ 0; 1; 2; 3 ] in
    let allowed = if allowed = [] then [ ri 4 ] else allowed in
    let arr = Array.of_list allowed in
    Array.iteri (fun i o -> if not (List.mem o allowed) then p.ops.(i) <- arr.(ri (Array.length arr))) p.ops
  end;
  !hdr   (* shares p's arrays *)

type result = { execs : int; coverage : int; queue : (prog * int list) array; curve : (int * int) list }

(* [fresh = true] is the baseline: same coverage accounting, but every candidate is a new random
   program instead of a mutant. *)
let run ~budget ~fresh ~seed =
  let st = Random.State.make [| seed |] in
  let virgin = Hashtbl.create 100_000 in
  let queue = ref [||] in
  let execs = ref 0 and curve = ref [] in
  let picked = Hashtbl.create 1000 in
  let top_rated = Hashtbl.create 100_000 in   (* feature -> (size, queue index) *)
  let add_entry p fs =
    let idx = Array.length !queue in
    queue := Array.append !queue [| (p, fs) |];
    List.iter (fun f -> match Hashtbl.find_opt top_rated f with
      | Some (sz, _) when sz <= size p -> () | _ -> Hashtbl.replace top_rated f (size p, idx)) fs in
  let new_features fs = List.filter (fun f -> not (Hashtbl.mem virgin f)) fs in
  let record fs = List.iter (fun f -> Hashtbl.replace virgin f ()) fs in
  (* shrinking: test zeroing each non-zero constant in parallel, combine the zeros that keep every
     new feature, verify the combination once, fall back to the unshrunk program if it fails *)
  let shrink p nf =
    let idx = List.filter (fun i -> p.ks.(i) <> 0) (List.init n Fun.id) in
    let ok = Evolve.parallel_map (fun i ->
      let q = copy p in q.ks.(i) <- 0;
      let fs = features (fst (execute q)) in
      (i, List.for_all (fun f -> List.mem f fs) nf)) idx in
    execs := !execs + List.length idx;
    let q = copy p in
    List.iter (fun (i, good) -> if good then q.ks.(i) <- 0) ok;
    let fs = features (fst (execute q)) in incr execs;
    if List.for_all (fun f -> List.mem f fs) nf then q else p in
  let seedp = random_prog (seed * 1000) in
  let fs = features (fst (execute seedp)) in incr execs; record fs; add_entry seedp fs;
  let batch = 32 in
  let id = ref 0 in
  while !execs < budget do
    let favoured = Hashtbl.fold (fun _ (_, i) acc -> i :: acc) top_rated [] |> List.sort_uniq compare |> Array.of_list in
    let pick () =
      let q = !queue in
      let i = if Array.length favoured > 0 && Random.State.int st 10 < 9 then favoured.(Random.State.int st (Array.length favoured))
              else Random.State.int st (Array.length q) in
      let times = Option.value ~default:0 (Hashtbl.find_opt picked i) in
      (* AFLFast-like: entries picked often get their turn given away with rising probability *)
      if Random.State.int st (1 + times / 8) = 0 then (Hashtbl.replace picked i (times + 1); fst q.(i)) else fst q.(Random.State.int st (Array.length q)) in
    let cands = List.init batch (fun _ ->
      incr id;
      if fresh then random_prog (seed * 1_000_000 + !id) else mutate st !queue (pick ())) in
    let res = Evolve.parallel_map (fun p -> (p, features (fst (execute p)))) cands in
    execs := !execs + batch;
    List.iter (fun (p, fs) ->
      let nf = new_features fs in
      if nf <> [] then begin
        let p = if fresh then p else shrink p nf in
        let fs = if fresh then fs else features (fst (execute p)) in
        record fs; add_entry p fs
      end) res;
    curve := (!execs, Hashtbl.length virgin) :: !curve
  done;
  { execs = !execs; coverage = Hashtbl.length virgin; queue = !queue; curve = List.rev !curve }
