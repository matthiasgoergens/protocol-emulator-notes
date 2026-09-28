(* Lockstep of a row of PE-X RTL cells against the executable specification (pex_model.ml):
   random configurations and random tagged streams, every output compared every cycle. *)
open Hardcaml

let nrow = 4

let random_cfg () =
  match Random.int 4 with
  | 0 -> Array.init 5 (fun _ -> Random.int 256)
  | 1 -> Array.copy (Pex_model.tile_cfg ~kcells:(1 lsl (1 + Random.int 2)))
  | 2 -> Array.copy Pex_model.sprite_cfg
  | _ ->
    (* a video configuration with random tweaks *)
    let c = Array.copy (if Random.bool () then Pex_model.sprite_cfg else Pex_model.tile_cfg ~kcells:2) in
    c.(Random.int 5) <- c.(Random.int 5) lxor (1 lsl Random.int 8); c

let random_word () =
  let r = Random.int 100 in
  let kind = if r < 30 then 0 else if r < 70 then 1 else if r < 90 then 2 else 3 in
  let cls = if Random.int 4 = 0 then 1 else 0 in
  let data = Random.int 0x8000 lor (if kind = 1 && Random.int 40 = 0 then 0x8000 else 0) in
  (cls lsl 2) lor kind, data

let run ?(fault = 0) ~configs ~cycles () =
  let circuit = Pex.row ~fault nrow () in
  let sim = Cyclesim.create circuit in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let clear = i "clear" and cfg_in = i "cfg_in" and cfg_strobe = i "cfg_strobe" in
  let tag_in = i "tag_in" and data_in = i "data_in" in
  let tag_out = o "tag_out" and data_out = o "data_out" in
  let s_out = Array.init nrow (fun k -> o (Printf.sprintf "s%d" k)) in
  let bad = ref 0 and bad_runs = ref 0 in
  for _ = 1 to configs do
    let cfgs = Array.init nrow (fun _ -> random_cfg ()) in
    tag_in := Bits.zero 3; data_in := Bits.zero 16;
    clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
    (* shift the configuration: last PE's bytes first *)
    cfg_strobe := Bits.vdd;
    for k = nrow - 1 downto 0 do
      Array.iter (fun b -> cfg_in := Bits.of_int ~width:8 b; Cyclesim.cycle sim) cfgs.(k)
    done;
    cfg_strobe := Bits.gnd;
    let models = Array.map (fun c -> Pex_model.create (Pex_model.cfg_of_bytes c)) cfgs in
    let run_bad = ref 0 in
    for _ = 1 to cycles do
      let tag, data = random_word () in
      tag_in := Bits.of_int ~width:3 tag; data_in := Bits.of_int ~width:16 data;
      Cyclesim.cycle sim;
      (* the model: each PE sees the previous PE's registered output from before this cycle *)
      let ins = Array.init nrow (fun k -> if k = 0 then (tag, data) else (models.(k - 1).out_tag, models.(k - 1).out_data)) in
      Array.iteri (fun k m -> let t, d = ins.(k) in Pex_model.step m ~tag:t ~data:d) models;
      let last = models.(nrow - 1) in
      let ok = ref (Bits.to_int !tag_out = last.out_tag && Bits.to_int !data_out = last.out_data) in
      Array.iteri (fun k m -> if Bits.to_int !(s_out.(k)) <> m.Pex_model.s then ok := false) models;
      if not !ok then incr run_bad
    done;
    bad := !bad + !run_bad;
    if !run_bad > 0 then incr bad_runs
  done;
  !bad, !bad_runs

let main () =
  Random.init 11;
  let configs = 300 and cycles = 2000 in
  let bad, _ = run ~configs ~cycles () in
  Printf.printf "PE-X lockstep: %d rows of %d PEs x %d cycles, random configurations and streams: %d mismatching cycles\n"
    configs nrow cycles bad;
  List.iter (fun (f, name) ->
    Random.init 11;
    let bad, runs = run ~fault:f ~configs ~cycles () in
    Printf.printf "  planted fault %d (%s): %d mismatching cycles in %d of %d runs\n" f name bad runs configs)
    [ 1, "no horizontal flip"; 2, "flag block ignored"; 3, "release at window start" ];
  bad = 0
