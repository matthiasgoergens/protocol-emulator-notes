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
  | _ -> prerr_endline "usage: main (topology | search A B | anim ID FRAMES DIR)"; exit 2
