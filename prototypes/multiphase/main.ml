(* Checks of the four-phase stage (stage.ml) against its reference model, with planted faults; the
   stage behind the sequencer (random programmes and 10BASE-T transmit firmware); and emission of
   the real-clock Verilog for iverilog and static timing. Output: results/main.txt *)
open Hardcaml

(* Reference model. Output: after the core clock in which nibble N_j is presented, the pins over
   the four quarters are N_(j-1) (bit p of each pin's nibble). Input: the samples word the core sees
   in clock j holds the pads at the four quarters of clock j - 2. *)
let nib_of word i = (word lsr (4 * i)) land 0xF
let pins_of_quarter ~n word p = List.fold_left (fun acc i -> acc lor (((nib_of word i lsr p) land 1) lsl i)) 0 (List.init n Fun.id)
let pack_samples ~n (pads : int array) = (* pads.(p): pad word at quarter p *)
  List.fold_left (fun acc i -> List.fold_left (fun acc p -> acc lor (((pads.(p) lsr i) land 1) lsl (4 * i + p))) acc [ 0; 1; 2; 3 ]) 0 (List.init n Fun.id)

let random_stage_test ?fault ~seed ~clocks () =
  Random.init seed;
  let n_out = 4 and n_in = 4 in
  let s = Stage.Sim.create ?fault ~n_out ~n_in () in
  let prev_sub = ref 0 in
  let pad_hist = Array.make 3 [| 0; 0; 0; 0 |] in
  let bad_out = ref 0 and bad_in = ref 0 in
  for j = 0 to clocks - 1 do
    (* mix dense random nibbles with sparse edges, so both runs and single-quarter pulses occur *)
    let sub = if Random.int 3 = 0 then Random.int (1 lsl (4 * n_out)) else
        if Random.bool () then !prev_sub else
          List.fold_left (fun acc i -> let q = Random.int 4 and v = Random.int 2 in
                           let old = (nib_of !prev_sub i lsr 3) land 1 in
                           let nb = List.fold_left (fun a p -> a lor ((if p < q then old else v) lsl p)) 0 [ 0; 1; 2; 3 ] in
                           acc lor (nb lsl (4 * i))) 0 (List.init n_out Fun.id) in
    let pads = Array.init 4 (fun _ -> Random.int (1 lsl n_in)) in
    let pins, samples = Stage.Sim.step s ~sub ~pads:(fun p -> pads.(p)) in
    for p = 0 to 3 do
      if pins.(p) <> pins_of_quarter ~n:n_out !prev_sub p then incr bad_out
    done;
    if j >= 2 && samples <> pack_samples ~n:n_in pad_hist.(0) then incr bad_in;
    pad_hist.(0) <- pad_hist.(1); pad_hist.(1) <- pads;
    prev_sub := sub
  done;
  !bad_out, !bad_in

(* the stage behind the sequencer RTL, all 8 pins: random programmes as in the lockstep test; the
   stage's pins at quarter resolution must equal the interpreter's pin_sub one clock later *)
let sequencer_through_stage ~seed ~cycles =
  Random.init seed;
  let mem = Array.init Isa.n_threads (fun _ -> Array.init Isa.prog_len (fun _ -> Random.int 0x10000)) in
  let h = Harness.make mem in
  let st = Isa.init () in
  let s = Stage.Sim.create ~n_out:8 ~n_in:1 () in
  let prev = ref 0 and bad = ref 0 and edges = ref 0 and fine_edges = ref 0 in
  let last_level = ref 0 in
  for _ = 0 to cycles - 1 do
    let pin_in = Random.int 256 and host_in = Random.int 256 and host_in_valid = Random.bool () in
    let _ = Isa.step st ~mem ~pin_in ~host_in ~host_in_valid in
    let o = Harness.cycle h ~pin_in ~host_in ~host_in_valid in
    let pins, _ = Stage.Sim.step s ~sub:o.pin_sub ~pads:(fun _ -> 0) in
    for p = 0 to 3 do
      let want = pins_of_quarter ~n:8 !prev p in
      if pins.(p) <> want then incr bad;
      if pins.(p) <> !last_level then begin incr edges; if p <> 0 then incr fine_edges end;
      last_level := pins.(p)
    done;
    prev := st.pin_sub
  done;
  !bad, !edges, !fine_edges

(* 10BASE-T transmit firmware (the generator from ../sequencer-ethernet/main.ml, copied: that file
   is an executable) through the stage: the pin at quarter resolution against the model encoder *)
module Eth_fw = struct
  let h = 3
  let s = 16
  let frame =
    Eth_model.udp_frame ~dst_mac:[ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ] ~src_mac:[ 0x02; 0x00; 0x00; 0x12; 0x34; 0x56 ]
      ~src_ip:[ 192; 168; 1; 200 ] ~dst_ip:[ 192; 168; 1; 255 ] ~src_port:4096 ~dst_port:4096
      ~payload:(List.map Char.code [ 'm'; 'u'; 'l'; 't'; 'i'; 'p'; 'h'; 'a'; 's'; 'e' ])
  let wire = List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame
  let model_samples = Array.of_list (Eth_model.encode_frame ~h frame)
  let nhalf = 16 * List.length wire
  let owner k = (s + h * k) mod Isa.n_threads
  let streams ?(flip = -1) () =
    let bits = Array.of_list (List.concat_map Eth_model.bits_of_byte wire) in
    let per = Array.make Isa.n_threads [] in
    for k = 0 to nhalf - 1 do
      let b = bits.(k / 2) in
      let v = if k mod 2 = 0 then 1 - b else b in
      let v = if k = flip then 1 - v else v in
      per.(owner k) <- v :: per.(owner k)
    done;
    Array.map (fun l ->
        let vs = Array.of_list (List.rev l) in
        Array.init ((Array.length vs + 7) / 8) (fun j ->
            let byte = ref 0 in
            for i = 0 to 7 do let idx = 8 * j + i in if idx < Array.length vs && vs.(idx) = 1 then byte := !byte lor (1 lsl i) done;
            !byte)) per
  let program t =
    let k0 = let rec f k = if owner k = t then k else f (k + 1) in f 0 in
    let first_sho_slot = (s + h * k0 - t) / Isa.n_threads in
    let pro = (if t = 0 then [ Isa.setp ~mask:1 ~value:0 ~oe:1 ] else []) @ [ Isa.in_ ] in
    let pad = first_sho_slot - List.length pro in
    let body_start = List.length pro + pad in
    let sho = Isa.sho ~pin:0 ~msb:0 () in
    let body = List.concat (List.init 7 (fun _ -> [ sho; Isa.nop; Isa.nop ])) @ [ sho; Isa.in_; Isa.jmp body_start ] in
    let code = Array.of_list (pro @ List.init pad (fun _ -> Isa.nop) @ body) in
    Array.init Isa.prog_len (fun i -> if i < Array.length code then code.(i) else Isa.halt)

  (* returns quarters where the stage's pin differs from the model (model sample i = clock s + i of
     the core's pin_out; through the stage it appears one clock later, at quarters 4(s+i+1)+p) *)
  let run ?flip () =
    let streams = streams ?flip () in
    let mem = Array.init Isa.n_threads program in
    let hs = Harness.make mem in
    let st = Isa.init () in
    let stage = Stage.Sim.create ~n_out:8 ~n_in:1 () in
    let next = Array.make Isa.n_threads 0 in
    let out = Array.make (4 * (s + h * nhalf + 8)) 0 in
    for c = 0 to s + h * nhalf + 4 do
      let t = st.thread in
      let valid = mem.(t).(st.pcs.(t)) = Isa.in_ && next.(t) < Array.length streams.(t) in
      let byte = if valid then streams.(t).(next.(t)) else 0 in
      let eff = Isa.step st ~mem ~pin_in:0 ~host_in:byte ~host_in_valid:valid in
      let o = Harness.cycle hs ~pin_in:0 ~host_in:byte ~host_in_valid:valid in
      if eff.host_in_ready then next.(t) <- next.(t) + 1;
      (* Harness.cycle c returns the registers after edge E_(c+1), i.e. N_(c+1); the stage's step
         for N_(c+1) returns the quarters of N_c *)
      let pins, _ = Stage.Sim.step stage ~sub:o.pin_sub ~pads:(fun _ -> 0) in
      Array.iteri (fun p v -> out.(4 * c + p) <- v land 1) pins
    done;
    (* pin_out after interpreter step c is N_(c+1) in the Harness numbering; the model's sample i is
       the pin during clock s + i of sequencer-ethernet's trace, i.e. after step s + i; its quarters
       come out of the stage in the step for N_(s+i+2), loop index s + i + 1 *)
    let bad = ref 0 in
    for i = 0 to h * nhalf - 1 do
      let want = if model_samples.(i) > 0 then 1 else 0 in
      for p = 0 to 3 do if out.(4 * (s + i + 1) + p) <> want then incr bad done
    done;
    !bad
end

(* A firmware edge train with sub-clock placement: pin 1 toggles every 4.25 clocks (17 quarters),
   a period the clock grid cannot make. Edge n lands at quarter 17n, which is clock 4n + n div 4 and
   sub-slot n mod 4; that clock belongs to thread (n div 4) mod 4. So each thread writes four
   consecutive edges on four consecutive slots (q = 0, 1, 2, 3) and then idles 13 slots: the
   rotation through the barrel is what makes the period. Returns the edge spacings in quarters. *)
let fine_edge_train () =
  let open Isa in
  let program u =
    let body = [ setpq ~q:0 ~mask:2 ~value:1 ~oe:1; setpq ~q:1 ~mask:2 ~value:0 ~oe:1;
                 setpq ~q:2 ~mask:2 ~value:1 ~oe:1; setpq ~q:3 ~mask:2 ~value:0 ~oe:1 ]
               @ List.init 12 (fun _ -> nop) @ [ jmp (4 * u) ] in
    let code = Array.of_list (List.init (4 * u) (fun _ -> nop) @ body) in
    Array.init prog_len (fun i -> if i < Array.length code then code.(i) else halt) in
  let mem = Array.init n_threads program in
  let hs = Harness.make mem in
  let stage = Stage.Sim.create ~n_out:8 ~n_in:1 () in
  let edges = ref [] and last = ref 0 in
  for c = 0 to 600 do
    let o = Harness.cycle hs ~pin_in:0 ~host_in:0 ~host_in_valid:false in
    let pins, _ = Stage.Sim.step stage ~sub:o.pin_sub ~pads:(fun _ -> 0) in
    Array.iteri (fun p v -> let b = (v lsr 1) land 1 in if b <> !last then (edges := (4 * c + p) :: !edges; last := b)) pins
  done;
  let e = Array.of_list (List.rev !edges) in
  Array.init (Array.length e - 1) (fun i -> e.(i + 1) - e.(i))

let () =
  let oc = open_out "multiphase_stage.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Stage.circuit_phases ());
  close_out oc;
  let oc = open_out "multiphase_stage_fault_lane.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Stage.circuit_phases ~fault:Stage.Lane_on_wrong_phase ());
  close_out oc;
  let ok = ref true in
  let check name cond = Printf.printf "%-72s %s\n" name (if cond then "PASS" else "FAIL"); if not cond then ok := false in
  let clocks = 50_000 in
  let bo, bi = random_stage_test ~seed:1 ~clocks () in
  Printf.printf "stage vs model, 4 out + 4 in pins, %d random clocks: %d wrong output quarters, %d wrong sample words\n" clocks bo bi;
  check "stage matches the model" (bo = 0 && bi = 0);
  List.iter (fun (name, fault) ->
      let bo, bi = random_stage_test ~fault ~seed:1 ~clocks () in
      Printf.printf "  control %-28s %6d wrong output quarters, %6d wrong sample words -> %s\n" name bo bi
        (if bo + bi > 0 then "caught" else "MISSED");
      if bo + bi = 0 then ok := false)
    [ ("lane 2 on phase 3", Stage.Lane_on_wrong_phase); ("no previous-quarter register", Stage.No_prev3);
      ("OR instead of XOR", Stage.Or_combiner); ("sampler 1 on phase 2", Stage.Sampler_wrong_phase) ];
  let total = ref 0 and edges = ref 0 and fine = ref 0 in
  for seed = 1 to 100 do
    let b, e, f = sequencer_through_stage ~seed ~cycles:2000 in
    total := !total + b; edges := !edges + e; fine := !fine + f
  done;
  Printf.printf "sequencer RTL -> stage, 100 random programmes x 2000 clocks: %d wrong quarters; %d pin-vector changes, %d of them off quarter 0\n"
    !total !edges !fine;
  check "stage output equals the interpreter's pin_sub" (!total = 0 && !fine > 0);
  let bad = Eth_fw.run () in
  Printf.printf "10BASE-T transmit firmware through the stage: %d of %d quarters differ from the model encoder\n" bad (4 * Eth_fw.h * Eth_fw.nhalf);
  check "10BASE-T transmit through the stage" (bad = 0);
  let bad_c = Eth_fw.run ~flip:300 () in
  Printf.printf "  control: one half-bit flipped in the host stream: %d quarters differ -> %s\n" bad_c (if bad_c > 0 then "caught" else "MISSED");
  if bad_c = 0 then ok := false;
  let sp = fine_edge_train () in
  let hist = Hashtbl.create 4 in
  Array.iter (fun d -> Hashtbl.replace hist d (1 + Option.value ~default:0 (Hashtbl.find_opt hist d))) sp;
  Printf.printf "fine edge train (SETP with q = 0,1,2,3 on thread 0): spacings in quarters:%s\n"
    (String.concat "" (List.map (fun (d, n) -> Printf.sprintf " %d x%d" d n) (List.sort compare (Hashtbl.fold (fun d n l -> (d, n) :: l) hist []))));
  check "every edge 17 quarters after the previous one" (Array.length sp > 100 && Array.for_all (( = ) 17) sp);
  print_endline (if !ok then "ALL PASS" else "FAILURES");
  exit (if !ok then 0 else 1)
