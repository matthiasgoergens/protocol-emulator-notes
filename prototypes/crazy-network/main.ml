let prog_from src key =
  let lines = In_channel.with_open_text src In_channel.input_all |> String.split_on_char '\n' in
  let l = List.find (fun l -> String.length l > String.length key && String.sub l 0 (String.length key + 1) = key ^ " ") lines in
  let i = Str.search_forward (Str.regexp_string "p=") l 0 in
  Evolve.of_string (String.sub l i (String.length l - i))

let () =
  match Array.to_list Sys.argv with
  | [ _; "topology" ] ->
    Array.iteri (fun i p -> if p <> i then Printf.printf "%d->%d " i p) Model.partner; print_newline ()
  | [ _; "search"; a; b ] ->
    for id = int_of_string a to int_of_string b - 1 do
      let prog = Model.random_prog id in
      List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "out/search/%05d_f%d.pgm" id fr) img)
        (Model.render prog ~frames:3 ~keep:(fun fr -> fr = 0 || fr = 2))
    done
  | [ _; "anim"; id; frames; dir ] ->
    let prog = Model.random_prog (int_of_string id) in
    (try Unix.mkdir dir 0o755 with _ -> ());
    List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "%s/f%04d.pgm" dir fr) img)
      (Model.render prog ~frames:(int_of_string frames) ~keep:(fun _ -> true))
  | [ _; "evolve"; gens; pop; seeds ] ->
    let seed_ids = if seeds = "-" then [] else List.map int_of_string (String.split_on_char ',' seeds) in
    let best = Evolve.run ~seed_ids ~generations:(int_of_string gens) ~pop:(int_of_string pop) in
    let oc = open_out "out/evolved.txt" in
    List.iteri (fun i (prog, (s, e, st, t, m)) ->
      Printf.fprintf oc "%d score=%.3f entropy=%.2f structure=%.2f dist=%.2f changed=%.2f %s\n" i s e st t m (Evolve.to_string prog);
      if i < 48 then List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "out/evo/%02d_f%d.pgm" i fr) img)
          (Model.render prog ~frames:3 ~keep:(fun f -> f >= 1))) best;
    close_out oc
  | [ _; "animp"; line_no; frames; dir ] ->
    let lines = In_channel.with_open_text "out/evolved.txt" In_channel.input_all |> String.split_on_char '\n' in
    let l = List.nth lines (int_of_string line_no) in
    let i = Str.search_forward (Str.regexp_string "p=") l 0 in
    let prog = Evolve.of_string (String.sub l i (String.length l - i)) in
    (try Unix.mkdir dir 0o755 with _ -> ());
    List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "%s/f%04d.pgm" dir fr) img)
      (Model.render prog ~frames:(int_of_string frames) ~keep:(fun _ -> true))
  | [ _; "mapelites"; iters; batch; seeds ] ->
    let seed_ids = if seeds = "-" then [] else List.map int_of_string (String.split_on_char ',' seeds) in
    let grid = Mapelites.run ~iters:(int_of_string iters) ~batch:(int_of_string batch) ~seed_ids in
    (try Unix.mkdir "out/map" 0o755 with _ -> ());
    let oc = open_out "out/map.txt" in
    Hashtbl.iter (fun (o, m, c) (prog, q) ->
      Printf.fprintf oc "%d %d %d q=%.3f %s\n" o m c q (Evolve.to_string prog);
      List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "out/map/%d%d%d_f%d.pgm" o m c fr) img)
        (Model.render prog ~frames:3 ~keep:(fun f -> f >= 1))) grid;
    close_out oc
  | [ _; "mutants"; src; keys; count ] ->
    (* judged evolution: for each chosen program (by its key in [src]), write [count] mutants *)
    let lines = In_channel.with_open_text src In_channel.input_all |> String.split_on_char '\n' in
    let prog_of key =
      (* map.txt lines start "o m c q=..."; key "321" means orientation 3, motion 2, coarseness 1 *)
      let spaced = String.concat " " (List.init (String.length key) (fun i -> String.make 1 key.[i])) ^ " " in
      let l = List.find (fun l -> String.length l >= String.length spaced && String.sub l 0 (String.length spaced) = spaced) lines in
      let i = Str.search_forward (Str.regexp_string "p=") l 0 in Evolve.of_string (String.sub l i (String.length l - i)) in
    (try Unix.mkdir "out/judge" 0o755 with _ -> ());
    let oc = open_out "out/judge.txt" in
    let st = Random.State.make [| 7 |] in
    let jobs = List.concat_map (fun key ->
      let base = prog_of key in
      (key, 0, base) :: List.init (int_of_string count - 1) (fun i -> (key, i + 1, Evolve.mutate st base))) (String.split_on_char ',' keys) in
    List.iter (fun (key, i, prog) -> Printf.fprintf oc "%s.%d %s\n" key i (Evolve.to_string prog)) jobs;
    close_out oc;
    ignore (Evolve.parallel_map (fun (key, i, prog) ->
      List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "out/judge/%s.%d_f%d.pgm" key i fr) img)
        (Model.render prog ~frames:3 ~keep:(fun f -> f >= 1))) jobs)
  | [ _; "animk"; src; key; frames; dir ] ->
    let lines = In_channel.with_open_text src In_channel.input_all |> String.split_on_char '\n' in
    let l = List.find (fun l -> String.length l > String.length key && String.sub l 0 (String.length key + 1) = key ^ " ") lines in
    let i = Str.search_forward (Str.regexp_string "p=") l 0 in
    let prog = Evolve.of_string (String.sub l i (String.length l - i)) in
    (try Unix.mkdir dir 0o755 with _ -> ());
    List.iter (fun (fr, img) -> Model.write_pgm (Printf.sprintf "%s/f%04d.pgm" dir fr) img)
      (Model.render prog ~frames:(int_of_string frames) ~keep:(fun _ -> true))
  | [ _; "rtlcheck"; src; keys; fields ] ->
    let ok = ref true in
    List.iter (fun key ->
      let checked, bad = Tb.lockstep (prog_from src key) ~fields:(int_of_string fields) in
      Printf.printf "%s: %d pixel samples compared with the model, %d mismatches\n%!" key checked bad;
      if bad <> 0 then ok := false) (String.split_on_char ',' keys);
    exit (if !ok then 0 else 1)
  | [ _; "rtldump"; src; key; fields; name ] -> Tb.dump (prog_from src key) ~fields:(int_of_string fields) ~name
  | [ _; "verilog" ] ->
    let oc = open_out "crazy_network.v" in Hardcaml.Rtl.output ~output_mode:(To_channel oc) Verilog (Crazy_rtl.circuit ()); close_out oc
  | [ _; "progstats"; a; b ] ->
    (* dump per-program features for the lambda-style predictor experiment *)
    for id = int_of_string a to int_of_string b - 1 do
      let p = Model.random_prog id in
      let cnt o = Array.fold_left (fun c x -> if x = o then c + 1 else c) 0 p.ops in
      let linked = Array.to_list (Array.mapi (fun i q -> q <> i) Model.partner) in
      let lk o = List.length (List.filter (fun x -> x) (List.mapi (fun i l -> l && p.ops.(i) = o) linked)) in
      let kz = Array.fold_left (fun c x -> if x = 0 then c + 1 else c) 0 p.ks in
      Printf.printf "%d %d %d %d %d %d %d %d %d %b %d %d\n" id (cnt 0) (cnt 1) (cnt 2) (cnt 3) (lk 0) (lk 1) (lk 2) (lk 3) p.reset p.p kz
    done
  | [ _; "fbdiff"; id; k; g ] ->
    (* pixels that differ between the program with and without feedback, per field *)
    let prog = Model.random_prog (int_of_string id) in
    let go ctl = Model.set_feedback ctl; Model.render prog ~frames:3 ~keep:(fun _ -> true) in
    let a = go None and b = go (Some (int_of_string k, int_of_string g)) in
    List.iter2 (fun (fr, x) (_, y) ->
      let d = ref 0 in
      Array.iteri (fun r row -> Array.iteri (fun c v -> if v <> y.(r).(c) then incr d) row) x;
      Printf.printf "field %d: %d pixels differ\n" fr !d) a b
  | [ _; "fuzzcheck" ] ->
    (* the instrumented copy must draw exactly what the model draws *)
    List.iter (fun id ->
      let p = Model.random_prog id in
      let _, img = Fuzz.execute p in
      let r = match Model.render p ~frames:2 ~keep:(fun f -> f = 1) with [ (_, i) ] -> i | _ -> assert false in
      Printf.printf "program %d: %s\n%!" id (if img = r then "same" else "DIFFERENT")) [ 0; 1; 2; 3; 40; 141 ]
  | [ _; "fuzz"; budget; mode; seed ] ->
    let fresh = mode = "random" in
    let r = Fuzz.run ~budget:(int_of_string budget) ~fresh ~seed:(int_of_string seed) in
    let dir = Printf.sprintf "out/fuzz_%s_%s" mode seed in
    (try Sys.mkdir dir 0o755 with Sys_error _ -> ());
    let oc = open_out (dir ^ "/curve.txt") in
    List.iter (fun (e, c) -> Printf.fprintf oc "%d %d\n" e c) r.curve; close_out oc;
    let oc = open_out (dir ^ "/queue.txt") in
    Array.iteri (fun i (p, fs) -> Printf.fprintf oc "%05d features=%d size=%d %s\n" i (List.length fs) (Fuzz.size p) (Evolve.to_string p)) r.queue;
    close_out oc;
    ignore (Evolve.parallel_map (fun (i, (p, _)) ->
      List.iter (fun (f, img) -> Model.write_pgm (Printf.sprintf "%s/%05d_f%d.pgm" dir i f) img)
        (Model.render p ~frames:3 ~keep:(fun f -> f = 0 || f = 2))) (List.mapi (fun i e -> (i, e)) (Array.to_list r.queue)));
    Printf.printf "%s: %d execs, coverage %d, queue %d\n" mode r.execs r.coverage (Array.length r.queue)
  | [ _; "pyragas"; ids ] ->
    (* For each program, with its own seeds and autonomously (seeds all zero), and each (k, gain):
       fraction of pixels equal to the pixel k rows above (fields 1 and 2), and the entropy of the
       palette indices, so that collapsing to a flat field does not count as locking. *)
    let ids = List.map int_of_string (String.split_on_char ',' ids) in
    let settings = List.concat_map (fun k -> List.map (fun g -> (k, g)) [ 0; 1; 2; 4; 8; 32; 128 ]) [ 4; 8; 16 ] in
    let jobs = List.concat_map (fun id -> List.concat_map (fun auto -> List.map (fun s -> (id, auto, s)) settings) [ false; true ]) ids in
    let res = Evolve.parallel_map (fun (id, auto, (k, g)) ->
      Model.set_feedback (if g = 0 then None else Some (k, g));
      let prog = Model.random_prog id in
      let prog = if auto then { prog with scheme = 3 } else prog in
      let imgs = Model.render prog ~frames:3 ~keep:(fun f -> f >= 1) in
      let same = ref 0 and tot = ref 0 and hist = Array.make 16 0 in
      List.iter (fun (_, img) ->
        Array.iter (Array.iter (fun v -> hist.(v) <- hist.(v) + 1)) img;
        for y = k to Model.nvis - 1 do for x = 0 to Model.npix - 1 do
          incr tot; if img.(y).(x) = img.(y - k).(x) then incr same done done) imgs;
      let npx = float (Array.fold_left ( + ) 0 hist) in
      let ent = Array.fold_left (fun acc c -> if c = 0 then acc else
        let q = float c /. npx in acc -. q *. Float.log2 q) 0. hist in
      (id, auto, k, g, float !same /. float !tot, ent)) jobs in
    List.iter (fun (id, auto, k, g, per, ent) ->
      Printf.printf "%d %s %d %d %.3f %.2f\n" id (if auto then "auto" else "seeded") k g per ent) res
  | _ -> prerr_endline "usage: main (topology | search A B | anim ID FRAMES DIR)"; exit 2
