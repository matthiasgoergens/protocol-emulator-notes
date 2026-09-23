(* Guided search over programs for the fixed network: mutate, score, keep the best.
   Score = variety x structure x smooth motion, measured on fields 1 and 2 (palette indices):
     variety   entropy of the index histogram (bits, capped at 3)
     structure fraction of pixels equal to their left or upper neighbour; best around 0.6
     smooth    mean circular index distance between consecutive fields (small = smooth)
     motion    some pixels must change, or it is a still picture *)
open Model

let to_string p =
  Printf.sprintf "p=%d tap=%d reset=%b scheme=%d ops=%s ks=%s" p.p p.tap p.reset p.scheme
    (String.concat "," (Array.to_list (Array.map string_of_int p.ops)))
    (String.concat "," (Array.to_list (Array.map string_of_int p.ks)))

let of_string s =
  let get k = let i = String.index_from s (Str.search_forward (Str.regexp_string (k ^ "=")) s 0) '=' + 1 in
    let j = try String.index_from s i ' ' with Not_found -> String.length s in String.sub s i (j - i) in
  let arr k = Array.of_list (List.map int_of_string (String.split_on_char ',' (get k))) in
  { ops = arr "ops"; ks = arr "ks"; tap = int_of_string (get "tap"); p = int_of_string (get "p");
    reset = bool_of_string (get "reset"); scheme = int_of_string (get "scheme"); pal = (random_prog 0).pal }

let metrics prog =
  match render prog ~frames:3 ~keep:(fun f -> f >= 1) with
  | [ (_, a); (_, b) ] ->
    let hist = Array.make 16 0 and same = ref 0 and dist = ref 0 and changed = ref 0 in
    for y = 0 to nvis - 1 do for x = 0 to npix - 1 do
      let v = a.(y).(x) in
      hist.(v) <- hist.(v) + 1;
      if (x > 0 && a.(y).(x - 1) = v) || (y > 0 && a.(y - 1).(x) = v) then incr same;
      let d = abs (v - b.(y).(x)) in let d = min d (16 - d) in
      dist := !dist + d; if d > 0 then incr changed
    done done;
    let tot = float (nvis * npix) in
    let ent = Array.fold_left (fun e c -> if c = 0 then e else let q = float c /. tot in e -. q *. log q /. log 2.0) 0.0 hist in
    let s = float !same /. tot and t = float !dist /. tot and m = float !changed /. tot in
    let score = (Float.min ent 3.0 /. 3.0) *. exp (-. (((s -. 0.6) /. 0.25) ** 2.0)) *. exp (-. t /. 1.5) *. Float.min 1.0 (m /. 0.05) in
    assert (score >= 0.0 && score <= 1.0);   (* every factor is in [0, 1]; catch another precedence slip *)
    (score, ent, s, t, m)
  | _ -> assert false

let mutate st p =
  let ri m = Random.State.int st m in
  let ops = Array.copy p.ops and ks = Array.copy p.ks in
  let q = ref { p with ops; ks } in
  for _ = 1 to 1 + ri 4 do
    match ri 9 with
    | 0 | 1 | 2 -> ops.(ri n) <- ri 4
    | 3 | 4 -> ks.(ri n) <- (if ri 2 = 0 then 0 else ri 256)
    | 5 -> q := { !q with tap = ri n }
    | 6 -> q := { !q with p = [| 1; 2; 5; 10 |].(ri 4) }
    | 7 -> q := { !q with reset = not !q.reset }
    | _ -> q := { !q with scheme = ri n_schemes }
  done; !q

let parallel_map f xs =
  let workers = match Sys.getenv_opt "FUZZ_WORKERS" with Some w -> int_of_string w | None -> 4 in
  let arr = Array.of_list xs in
  let res = Array.make (Array.length arr) None in
  let doms = List.init workers (fun w -> Domain.spawn (fun () ->
    Array.iteri (fun i x -> if i mod workers = w then res.(i) <- Some (f x)) arr)) in
  List.iter Domain.join doms;
  Array.to_list (Array.map Option.get res)

let run ~seed_ids ~generations ~pop =
  let st = Random.State.make [| 4242 |] in
  let init = List.map random_prog seed_ids @ List.init (max 0 (pop - List.length seed_ids)) (fun i -> random_prog (100000 + i)) in
  let scored = ref (List.combine init (parallel_map metrics init)) in
  for g = 1 to generations do
    let sorted = List.sort (fun (_, (a, _, _, _, _)) (_, (b, _, _, _, _)) -> compare b a) !scored in
    let elite = List.filteri (fun i _ -> i < pop / 4) sorted in
    let children = List.init (pop - List.length elite) (fun _ ->
      let (par, _) = List.nth elite (Random.State.int st (List.length elite)) in mutate st par) in
    scored := elite @ List.combine children (parallel_map metrics children);
    let (_, (b, e, s, t, m)) = List.hd (List.sort (fun (_, (a, _, _, _, _)) (_, (b, _, _, _, _)) -> compare b a) !scored) in
    Printf.printf "gen %2d best %.3f (entropy %.2f structure %.2f motion-dist %.2f changed %.2f)\n%!" g b e s t m
  done;
  List.sort (fun (_, (a, _, _, _, _)) (_, (b, _, _, _, _)) -> compare b a) !scored
