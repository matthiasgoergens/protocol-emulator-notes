(* Could the systolic matcher recognise the tokens? An experiment on its closed-form
   specification (../systolic-matcher/model.ml, 16 cells), fed one sample per decoded bit, i.e.
   with the bit layer's strobe as a clock enable, which the matcher as built does not have.
   Template: the 16 bits that follow an IN token's PID for (address 42, endpoint 1), address,
   endpoint and CRC5 included; threshold 16 (exact match).
   Measured: hits on that token in a stream of random tokens; hits anywhere else, including
   inside random data packets, where a 16-bit pattern also occurs by chance. *)
let bits_of_bytes bs = List.concat_map (fun b -> List.init 8 (fun i -> (b lsr i) land 1)) bs

let () =
  let rng = Random.State.make [| 5 |] in
  let tail = List.tl (Ls_host.token Ls_host.pid_in ~addr:42 ~ep:1) in
  let tb = Array.of_list (bits_of_bytes tail) in
  (* template bit j is compared with x(n - N - 1 - j): bit 0 with the newest sample *)
  let cfg = { Matcher_model.t = Array.init 16 (fun j -> tb.(15 - j)); m = Array.make 16 1; thr = 16 } in
  (* a stream of packets' bits (after sync): 2,000 random tokens and 2,000 random data packets *)
  let stream = ref [] and target_ends = ref [] and same_tail = ref [] and pos = ref 0 in
  for _ = 1 to 4000 do
    let pkt =
      if Random.State.bool rng then begin
        let addr = if Random.State.int rng 20 = 0 then 42 else Random.State.int rng 128 in
        let ep = Random.State.int rng 2 in
        let pid = [| Ls_host.pid_in; Ls_host.pid_out; Ls_host.pid_setup |].(Random.State.int rng 3) in
        let t = Ls_host.token pid ~addr ~ep in
        if pid = Ls_host.pid_in && addr = 42 && ep = 1 then target_ends := (!pos + 24) :: !target_ends
        else if addr = 42 && ep = 1 then same_tail := (!pos + 24) :: !same_tail;
        t
      end else Ls_host.data_packet Ls_host.pid_data0 (List.init (Random.State.int rng 9) (fun _ -> Random.State.int rng 256)) in
    let b = bits_of_bytes pkt in
    stream := List.rev_append b !stream; pos := !pos + List.length b
  done;
  let x = Array.of_list (List.rev !stream) in
  let xf k = if k < Array.length x then x.(k) else 0 in
  (* the match of the window ending with sample k shows as hit at time k + N + 2 *)
  let hits = ref [] in
  for time = 1 to Array.length x + 20 do
    if Matcher_model.hit_at cfg xf time then hits := (time - Matcher_model.n - 2 + 1) :: !hits
  done;
  let hits = List.rev !hits and targets = List.rev !target_ends in
  let true_hits = List.filter (fun h -> List.mem h targets) hits in
  let false_hits = List.filter (fun h -> not (List.mem h targets)) hits in
  let other_pid = List.filter (fun h -> List.mem h !same_tail) false_hits in
  Printf.printf "matcher on decoded bits: %d bits, %d target tokens, %d found; %d other hits: %d are OUT/SETUP tokens with the same address and endpoint (the PID is outside the template), %d are chance matches elsewhere (expected about %.1f: one per 65,536 positions)\n"
    (Array.length x) (List.length targets) (List.length true_hits) (List.length false_hits)
    (List.length other_pid) (List.length false_hits - List.length other_pid) (float_of_int (Array.length x) /. 65536.0);
  (* a false hit is where the 16 bits after some other PID, or 16 bits inside data, equal the
     template; gating the matcher to the two bytes after a token PID removes them *)
  ()
