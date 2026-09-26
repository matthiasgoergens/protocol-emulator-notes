(* Differential check of the OCaml pad port against ../padmodel.py (data/padcheck.csv). *)
open Chain
let () =
  let p = Pad.load () in
  let dt = 2e-12 in
  let n = int_of_float (8e-9 /. dt) in
  let worst = ref 0.0 in
  read_lines (Filename.concat data_dir "padcheck.csv")
  |> List.iter (fun l ->
         match split_csv l with
         | [ d; tpy ] ->
           let d = float_of_string d and tpy = float_of_string tpy in
           let v = Array.init n (fun i ->
               let t = float_of_int i *. dt in
               p.Pad.vt -. 0.25 +. d +. (0.5 *. Float.min 1.0 (Float.max 0.0 ((t -. 3e-9) /. 500e-12)))) in
           let core = Pad.run p dt v in
           let k = ref 0 in
           while !k < n - 1 && not core.(!k) do incr k done;
           let t = float_of_int !k *. dt in
           worst := Float.max !worst (Float.abs (t -. tpy));
           Printf.printf "level %+.3f V: python %.1f ps, ocaml %.1f ps\n" d (tpy *. 1e12) (t *. 1e12)
         | _ -> ());
  Printf.printf "worst difference %.1f ps (%s)\n" (!worst *. 1e12) (if !worst <= 2.01e-12 then "PASS: within one step" else "FAIL")
