(* Lockstep: the model and the Hardcaml array on the same random stimulus, every state bit
   compared every clock. Generators are biased per mode, since uniform configurations rarely
   reach some of them (see the coverage table this prints). *)
open Spec

let modes =
  [ "uniform"; "arith"; "maxmin"; "logic"; "gsrc"; "window"; "gf2"; "pair"; "stream"; "lane";
    "segments"; "chains" ]

type rng = Random.State.t

let pick r l = List.nth l (Random.State.int r (List.length l))
let chance r p = Random.State.float r 1.0 < p
let rbool r = Random.State.bool r

let random_op r =
  let i n = Random.State.int r n in
  { xsel = i 4; sinsel = i 4; ysel = i 4; ymod = i 4; gsel = i 8; bitsel = i 16; pairlo = rbool r;
    alu = i 8; cin_lane = rbool r; swb = i 4; pwb = i 4; fwb = i 4; lout = i 4; lane_bc = rbool r;
    del = rbool r; stream = rbool r; tap_p = rbool r; follow = rbool r; k = i 0x10000 }

(* uniform, except that follow is rarer (with follow everywhere, most PEs never step) *)
let gen_op mode r =
  let o = random_op r in
  let o = { o with follow = chance r 0.15; stream = chance r 0.3 } in
  let k_int () = pick r [ 0; 1; 0x7fff; 0x8000; 0xffff; 0x100; Random.State.int r 0x10000 ] in
  if not (chance r 0.85) then o
  else
    match mode with
    | "arith" ->
      { o with alu = pick r [ 0; 1 ]; k = k_int (); swb = pick r [ 1; 1; 3 ]; lout = pick r [ 2; 2; 1 ];
               cin_lane = chance r 0.4; ysel = pick r [ 0; 1; 1; 2 ] }
    | "maxmin" -> { o with alu = pick r [ 2; 3 ]; pwb = pick r [ 2; 2; 1 ]; swb = pick r [ 1; 1; 3 ]; ysel = 1; xsel = 0 }
    | "logic" -> { o with alu = pick r [ 4; 5; 6; 7 ]; fwb = 2; swb = pick r [ 1; 1; 3 ]; k = k_int () }
    | "gsrc" ->
      { o with gsel = Random.State.int r 8; ymod = pick r [ 1; 2 ]; swb = pick r [ 3; 1 ]; fwb = pick r [ 1; 1; 2 ];
               alu = pick r [ 0; 1; 4 ]; pairlo = rbool r }
    | "window" -> { o with gsel = 6; pwb = 3; swb = pick r [ 0; 0; 3 ]; fwb = pick r [ 1; 0 ]; xsel = 0 }
    | "gf2" ->
      { o with xsel = pick r [ 2; 3 ]; alu = pick r [ 4; 4; 5; 6 ]; ymod = 1; gsel = pick r [ 4; 4; 1; 3; 7 ];
               swb = 1; ysel = 0; sinsel = Random.State.int r 4 }
    | "pair" ->
      { o with gsel = pick r [ 4; 7 ]; pairlo = rbool r; sinsel = pick r [ 0; 2 ]; xsel = 2; alu = 4; ymod = 1;
               swb = 1; follow = chance r 0.5 }
    | "stream" -> { o with stream = true; del = chance r 0.6; follow = chance r 0.2 }
    | "lane" ->
      { o with lout = Random.State.int r 4; gsel = pick r [ 2; 3; 3; 7 ]; cin_lane = chance r 0.5; alu = pick r [ 1; 1; 0; 4 ];
               lane_bc = chance r 0.4; ysel = 0; swb = 1 }
    | _ -> o

let interesting r ks =
  let base = [ 0; 1; 2; 0x7fff; 0x8000; 0xffff; 0x7ffe; 0x8001; 0xff00 ] in
  let near k = (k + (Random.State.int r 40 - 8) * 0x100 + Random.State.int r 256) land 0xffff in
  match Random.State.int r 4 with
  | 0 -> Random.State.int r 0x10000
  | 1 -> pick r base
  | _ -> if ks = [] then Random.State.int r 0x10000 else near (pick r ks)

(* one trial's stimulus: setup (control, configuration, init), then running traffic *)
let gen_trial mode r ~run_cycles =
  let ops = Array.init n_pe (fun _ -> gen_op mode r) in
  let ks = Array.to_list (Array.map (fun o -> o.k) ops) in
  let stim = ref [] in
  let push i = stim := i :: !stim in
  let fixed () =
    { idle with fixed_d = Array.init 4 (fun _ -> interesting r ks); fixed_v = Array.init 4 (fun _ -> chance r 0.6) }
  in
  let ctrl_byte () =
    let src = if mode = "segments" then pick r [ 0; 0; 1; 1; 2; 3; 5 ] else pick r [ 0; 1; 2; 2; 3; 3; 4 ] in
    src lor (if rbool r then 8 else 0) lor (if chance r 0.8 then 16 else 0) lor (Random.State.int r 8 lsl 5)
  in
  for sg = 0 to 3 do
    push { (fixed ()) with mbx_wr = true; mbx_seg = sg; mbx_sel = 2; mbx_byte = ctrl_byte () }
  done;
  for sg = 0 to 3 do
    for i = seg_end.(sg) downto seg_start.(sg) do
      let b = bytes_of_op ops.(i) in
      for j = 7 downto 0 do push { (fixed ()) with cfg_wr = true; cfg_seg = sg; cfg_byte = b.(j) } done
    done;
    for _ = 1 to 2 * (seg_end.(sg) - seg_start.(sg) + 1) do
      let v = interesting r ks in
      push { (fixed ()) with init_wr = true; init_seg = sg; init_byte = (if rbool r then v lsr 8 else v land 0xff) }
    done
  done;
  let p_chain = if mode = "chains" then 0.15 else 0.01 in
  for _ = 1 to run_cycles do
    let i = fixed () in
    let i =
      if chance r (if mode = "stream" then 0.7 else 0.4) then begin
        let sg = Random.State.int r 4 in
        let sel = if chance r 0.15 then 2 else pick r [ 0; 1; 1 ] in
        let v = interesting r ks in
        let byte = if sel = 2 then ctrl_byte () else if sel = 0 then v land 0xff else v lsr 8 in
        { i with mbx_wr = true; mbx_seg = sg; mbx_sel = (if chance r 0.02 then 3 else sel); mbx_byte = byte }
      end
      else i
    in
    let i =
      if chance r p_chain then { i with cfg_wr = true; cfg_seg = Random.State.int r 4; cfg_byte = Random.State.int r 256 }
      else i
    in
    let i =
      if chance r p_chain then { i with init_wr = true; init_seg = Random.State.int r 4; init_byte = Random.State.int r 256 }
      else i
    in
    push i
  done;
  List.rev !stim

(* run model and RTL side by side; return the first mismatching cycle *)
let run_trial ?(model = Model.create ()) stim =
  let rtl = Rtlsim.create () in
  let rec go n = function
    | [] -> None
    | i :: rest ->
      Model.cycle model i;
      Rtlsim.cycle rtl i;
      let d = diff (Model.state model) (Rtlsim.state rtl) in
      if d <> [] then Some (n, d) else go (n + 1) rest
  in
  go 0 stim

type result = { trials : int; cycles : int; first_fail : (int * int * string list) option }

(* run up to [trials] trials; stop at the first mismatch *)
let campaign ?(stop = true) ~mode ~seed ~trials ~run_cycles () =
  let r = Random.State.make [| seed |] in
  let cycles = ref 0 and fail = ref None and n = ref 0 in
  (try
     for t = 1 to trials do
       n := t;
       let stim = gen_trial mode r ~run_cycles in
       match run_trial stim with
       | None -> cycles := !cycles + List.length stim
       | Some (c, d) ->
         cycles := !cycles + c + 1;
         if !fail = None then fail := Some (t, !cycles, d);
         if stop then raise Exit
     done
   with Exit -> ());
  { trials = !n; cycles = !cycles; first_fail = !fail }

(* coverage of rare events, per generator, measured on the model alone *)
let coverage ~mode ~seed ~trials ~run_cycles =
  let r = Random.State.make [| seed |] in
  let m = Model.create () in
  for _ = 1 to trials do
    let stim = gen_trial mode r ~run_cycles in
    List.iter (Model.cycle m) stim
  done;
  m.cov
