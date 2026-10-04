(* Gergo Erdi's TMDS encoder (as transliterated in GergoTMDS.hs; table in gergo-table.txt, one line
   per (accumulator, pixel): "acc d word acc'") against the independent DVI model.
   Usage: gergo_check.exe gergo-table.txt *)
module I = Tmds_indep

let () =
  let tbl = Hashtbl.create 4096 in
  let ic = open_in Sys.argv.(1) in
  (try
     while true do
       Scanf.sscanf (input_line ic) "%d %d %d %d" (fun a d w a' -> Hashtbl.replace tbl (a, d) (w, a'))
     done
   with End_of_file -> close_in ic);
  (* Exhaustive over Gergo's own reachable accumulator values (closure from 0). *)
  let reach = Hashtbl.create 16 in
  let rec close a =
    if not (Hashtbl.mem reach a) then begin
      Hashtbl.replace reach a ();
      for d = 0 to 255 do close (snd (Hashtbl.find tbl (a, d))) done
    end
  in
  close 0;
  let accs = List.sort compare (Hashtbl.fold (fun a () l -> a :: l) reach []) in
  Printf.printf "reachable accumulator values: %s\n" (String.concat " " (List.map string_of_int accs));
  let pairs = ref 0 and roundtrip = ref 0 and invalid = ref 0 and acc_vs_disp = ref 0 in
  List.iter (fun a ->
      for d = 0 to 255 do
        incr pairs;
        let w, a' = Hashtbl.find tbl (a, d) in
        (match I.decode w with I.Data x when x = d -> () | _ -> incr roundtrip);
        if not (I.is_valid_data w) then incr invalid;
        if a' - a <> I.ones_minus_zeros w then incr acc_vs_disp
      done) accs;
  Printf.printf "pairs %d: decode(encode x) <> x: %d; words outside the 460 valid data words: %d; \
                 accumulator step <> word disparity: %d\n" !pairs !roundtrip !invalid !acc_vs_disp;
  (* Same random stream shape as test_tmds.ml: running disparity measured from the words. *)
  let rng = Random.State.make [| 42 |] in
  let acc = ref 0 and running = ref 0 and maxrd = ref 0 and prev_de = ref false in
  for k = 0 to 999_999 do
    let de = if !prev_de then Random.State.int rng 800 <> 0 else Random.State.int rng 20 = 0 in
    let de = de && k > 0 in
    let d = Random.State.int rng 256 in
    ignore (Random.State.int rng 2); ignore (Random.State.int rng 2);
    if de then begin
      let w, a' = Hashtbl.find tbl (!acc, d) in
      acc := a'; running := !running + I.ones_minus_zeros w
    end else begin acc := 0; running := 0 end;
    maxrd := max !maxrd (abs !running);
    prev_de := de
  done;
  Printf.printf "1,000,000-word random stream: max |running disparity| = %d (spec encoder: 8)\n" !maxrd
