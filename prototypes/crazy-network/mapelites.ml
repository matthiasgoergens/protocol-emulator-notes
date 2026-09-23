(* Quality-diversity search (MAP-Elites): keep the best program per cell of a descriptor grid.
   Descriptors, from fields 1 and 2 (palette indices):
     orientation  hsame - vsame, from vertical structure (-1) to horizontal (+1), 5 bins
     motion       fraction of pixels whose index changes between fields, 5 bins
     coarseness   mean horizontal run length, log scale, 4 bins
   Quality inside a cell: variety (entropy, capped) times a broad "neither flat nor noise" window
   on neighbour agreement. Deliberately weak: the grid does the selecting, judgement comes later. *)
open Model

let describe prog =
  match render prog ~frames:3 ~keep:(fun f -> f >= 1) with
  | [ (_, a); (_, b) ] ->
    let hist = Array.make 16 0 and hs = ref 0 and vs = ref 0 and ch = ref 0 and runs = ref 0 in
    for y = 0 to nvis - 1 do for x = 0 to npix - 1 do
      let v = a.(y).(x) in
      hist.(v) <- hist.(v) + 1;
      if x > 0 && a.(y).(x - 1) = v then incr hs else incr runs;
      if y > 0 && a.(y - 1).(x) = v then incr vs;
      if b.(y).(x) <> v then incr ch
    done done;
    let tot = float (nvis * npix) in
    let ent = Array.fold_left (fun e c -> if c = 0 then e else let q = float c /. tot in e -. q *. log q /. log 2.0) 0.0 hist in
    let h = float !hs /. tot and v = float !vs /. tot and m = float !ch /. tot in
    let run = tot /. float (max 1 !runs) in
    let s = (h +. v) /. 2.0 in
    let q = (Float.min ent 3.0 /. 3.0) *. (if s < 0.1 || s > 0.97 then 0.05 else 1.0) in
    let orient = min 4 (int_of_float ((h -. v +. 1.0) /. 2.0 *. 5.0)) in
    let motion = min 4 (int_of_float (m *. 5.0)) in
    let coarse = min 3 (max 0 (int_of_float (log (Float.max 1.0 run) /. log 2.0))) in
    (q, (orient, motion, coarse))
  | _ -> assert false

let run ~iters ~batch ~seed_ids =
  let st = Random.State.make [| 99 |] in
  let grid = Hashtbl.create 128 in
  let place (prog, (q, cell)) =
    match Hashtbl.find_opt grid cell with
    | Some (_, q') when q' >= q -> ()
    | _ -> Hashtbl.replace grid cell (prog, q) in
  let init = List.map random_prog seed_ids @ List.init batch (fun i -> random_prog (200000 + i)) in
  List.iter place (List.combine init (Evolve.parallel_map describe init));
  for it = 1 to iters do
    let elites = Array.of_seq (Hashtbl.to_seq_values grid) in
    let kids = List.init batch (fun _ ->
      let (p, _) = elites.(Random.State.int st (Array.length elites)) in
      if Random.State.int st 10 = 0 then random_prog (300000 + Random.State.int st 1_000_000) else Evolve.mutate st p) in
    List.iter place (List.combine kids (Evolve.parallel_map describe kids));
    if it mod 10 = 0 then Printf.printf "iter %3d: %d cells filled\n%!" it (Hashtbl.length grid)
  done;
  grid
