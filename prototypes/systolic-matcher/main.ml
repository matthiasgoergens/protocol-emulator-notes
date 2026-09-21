open Hardcaml

let circuit = Matcher.circuit ()

let emit () =
  let oc = open_out "systolic_matcher.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog circuit; close_out oc

(* Configure, reset the datapath, stream xs; return (y, hit) observed after each cycle. After the
   cycle that presents x(n) the outputs show the register state at the start of cycle n+1, so they
   are compared with Model.y_at / hit_at at time n+1. *)
let run_stream ~(cfg : Model.cfg) ~(xs : int array) =
  let sim = Cyclesim.create circuit in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let clear = i "clear" and x = i "x" and cfg_in = i "cfg_in" and cfg_shift = i "cfg_shift" in
  let y = o "y" and hit = o "hit" in
  List.iter (fun b -> cfg_in := Bits.of_int ~width:1 b; cfg_shift := Bits.vdd; Cyclesim.cycle sim) (Model.cfg_bits cfg);
  cfg_shift := Bits.gnd;
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  Array.map (fun b -> x := Bits.of_int ~width:1 b; Cyclesim.cycle sim; (Bits.to_int !y, Bits.to_int !hit = 1)) xs

let check ~cfg ~xs =
  let obs = run_stream ~cfg ~xs in
  let xf k = xs.(k) in
  let bad = ref 0 in
  Array.iteri (fun n (yo, ho) ->
    let ye = Model.y_at cfg xf (n + 1) and he = Model.hit_at cfg xf (n + 1) in
    if yo <> ye || ho <> he then begin
      incr bad;
      if !bad <= 3 then Printf.printf "  cycle %d: rtl y=%d hit=%b, model y=%d hit=%b\n" n yo ho ye he
    end) obs;
  !bad, obs

let random_cfg () =
  { Model.t = Array.init Model.n (fun _ -> Random.int 2); m = Array.init Model.n (fun _ -> Random.int 2); thr = Random.int 18 }

let lockstep ~seed ~cycles =
  Random.init seed;
  let cfg = random_cfg () in
  let xs = Array.init cycles (fun _ -> Random.int 2) in
  fst (check ~cfg ~xs)

(* Directed: find the 16-bit word 0xB5A3 (bit 0 = newest sample) in a random stream, exact match. *)
let directed_exact () =
  Random.init 4242;
  let word = 0xB5A3 in
  let cfg = { Model.t = Array.init Model.n (fun j -> (word lsr j) land 1); m = Array.make Model.n 1; thr = 16 } in
  let xs = Array.init 3000 (fun _ -> Random.int 2) in
  (* plant the word twice: samples k..k+15 with bit j at position k+15-j (bit 0 newest) *)
  List.iter (fun k -> for j = 0 to 15 do xs.(k + 15 - j) <- (word lsr j) land 1 done) [ 700; 2100 ];
  let bad, obs = check ~cfg ~xs in
  let hits = Array.to_list obs |> List.mapi (fun n (_, h) -> (n, h)) |> List.filter snd |> List.map fst in
  (* hit observed after cycle n is hit_at (n+1) = [y_at n >= thr], and y_at n covers the window
     whose newest sample is x(n - N - 1). Planted windows have newest samples at 715 and 2115, so
     the hits appear after cycles 715 + N + 1 = 732 and 2132. *)
  let expected = [ 715 + Model.n + 1; 2115 + Model.n + 1 ] in
  Printf.printf "exact match: mismatches=%d hits at %s (expected %s)\n" bad
    (String.concat "," (List.map string_of_int hits)) (String.concat "," (List.map string_of_int expected));
  bad = 0 && hits = expected

(* Directed: the same word with two bits corrupted still hits at threshold 14, and a random stream
   with threshold 14 gives some false hits, which the model predicts exactly. *)
let directed_tolerant () =
  Random.init 99;
  let word = 0xB5A3 in
  let cfg = { Model.t = Array.init Model.n (fun j -> (word lsr j) land 1); m = Array.make Model.n 1; thr = 14 } in
  let xs = Array.init 1500 (fun _ -> Random.int 2) in
  for j = 0 to 15 do xs.(400 + 15 - j) <- (word lsr j) land 1 done;
  xs.(400 + 15 - 3) <- 1 - xs.(400 + 15 - 3); xs.(400 + 15 - 9) <- 1 - xs.(400 + 15 - 9);
  let bad, obs = check ~cfg ~xs in
  let planted_hit = snd obs.(415 + Model.n + 1) in
  Printf.printf "tolerant match: mismatches=%d planted-with-2-errors hit=%b\n" bad planted_hit;
  bad = 0 && planted_hit

let () =
  emit ();
  let total = ref 0 in
  let runs = 300 and cycles = 500 in
  for seed = 1 to runs do total := !total + lockstep ~seed ~cycles done;
  Printf.printf "lockstep: %d random configurations x %d cycles, %d mismatching cycles\n" runs cycles !total;
  let a = directed_exact () and b = directed_tolerant () in
  let ok = !total = 0 && a && b in
  print_endline (if ok then "ALL PASS" else "FAILURES");
  exit (if ok then 0 else 1)
