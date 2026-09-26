(* Lockstep of the OCaml upe_v0 model (upe.ml) against ../unified-pe/rtl/upe.v under Icarus.

   Stimulus: random throughout, so every mode is reached, including op encodings no demo uses:
   - configuration bursts of 8 random bytes shifted through the chain (the PE keeps stepping
     while its configuration changes, as it would on the chip);
   - occasional clear and init-chain strobes;
   - random A, valid, lane, broadcast, pair and carry-back inputs, and random enable.
   Every output is compared on every cycle. With UPE_FAULT=negate the model drops the
   "negate Y by g" mode, and the check must then fail. *)

let run ~cycles ~seed ~dir =
  Random.init seed;
  ignore (Sys.command ("mkdir --parents " ^ Filename.quote dir));
  let stim = Filename.concat dir (Printf.sprintf "stim_%d.txt" seed) in
  let oc = open_out stim in
  let ins = Array.make cycles Upe.idle in
  let burst = ref 0 in
  for t = 0 to cycles - 1 do
    if t = 0 || (!burst = 0 && Random.int 40 = 0) then burst := 8;
    let strobe = if !burst > 0 then (decr burst; 1) else 0 in
    let rb n = Random.int n in
    let i : Upe.inputs = {
      clear = (if t <= 8 || rb 300 = 0 then 1 else 0);
      cfg_in = rb 256; cfg_strobe = strobe;
      init_in = rb 256; init_strobe = (if rb 50 = 0 then 1 else 0);
      en = (if rb 10 = 0 then 0 else 1);
      a = rb 65536; a_valid = (if rb 4 = 0 then 0 else 1);
      b_in = rb 2; bc_in = rb 2; cb_in = rb 2; s15_in = rb 2; g_in = rb 2 } in
    ins.(t) <- i;
    Printf.fprintf oc "%x %x %x %x %x %x %x %x %x %x %x %x %x\n" i.clear i.cfg_in i.cfg_strobe
      i.init_in i.init_strobe i.en i.a i.a_valid i.b_in i.bc_in i.cb_in i.s15_in i.g_in
  done;
  close_out oc;
  let vvp = Filename.concat dir "tb.vvp" and out = Filename.concat dir (Printf.sprintf "rtl_%d.txt" seed) in
  let compile =
    Printf.sprintf
      "nice ionice iverilog -g2012 -DNO_POP -DNO_LUT -DBITSEL '-DSTIM=\"%s\"' -o %s rtl/tb_upe.v \
       ../unified-pe/rtl/upe.v" stim (Filename.quote vvp) in
  if Sys.command compile <> 0 then failwith "iverilog failed";
  let simulate = Printf.sprintf "nice ionice vvp -n %s > %s" (Filename.quote vvp) (Filename.quote out) in
  if Sys.command simulate <> 0 then failwith "vvp failed";
  let ic = open_in out in
  let st = Upe.create () in
  let unknown = ref 0 in
  let mism = ref 0 and first = ref None and rows = ref 0 in
  (try
     while true do
       let line = input_line ic in
       match String.split_on_char ' ' line with
       | c :: _ when String.contains line 'x' ->
         incr unknown; Upe.clock st ins.(int_of_string c)
       | [ c; co; io; po; pv; bo; cbo; s15o; go; fl; so ] ->
         let t = int_of_string c in
         let h x = int_of_string ("0x" ^ x) in
         let o = Upe.outputs st ins.(t) in
         let got = [ o.cfg_out; o.init_out; o.p_out; o.p_valid; o.b_out; o.cb_out; o.s15_out;
                     o.g_out; o.flag; o.s_out ] in
         let want = List.map h [ co; io; po; pv; bo; cbo; s15o; go; fl; so ] in
         incr rows;
         if got <> want then begin
           incr mism;
           if !first = None then first := Some (t, line)
         end;
         Upe.clock st ins.(t)
       | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  Printf.printf "  %d rows skipped: RTL outputs unknown (x) while the first configuration shifts in\n" !unknown;
  (!rows, !mism, !first)

let main args =
  let cycles, dir =
    match args with
    | [] -> 20000, Filename.concat (Filename.get_temp_dir_name ()) "array-uses-lockstep"
    | [ n ] -> int_of_string n, Filename.concat (Filename.get_temp_dir_name ()) "array-uses-lockstep"
    | n :: dir :: _ -> int_of_string n, dir in
  let seeds = [ 1; 2; 3 ] in
  let total = ref 0 and bad = ref 0 in
  List.iter (fun seed ->
      let rows, mism, first = run ~cycles ~seed ~dir in
      total := !total + rows; bad := !bad + mism;
      Printf.printf "seed %d: %d cycles compared, %d with a differing output%s\n" seed rows mism
        (match first with Some (t, l) -> Printf.sprintf " (first at cycle %d: rtl %s)" t l | None -> ""))
    seeds;
  Printf.printf "fault=%s: %d of %d cycles differ\n"
    (match !Upe.fault with Some f -> f | None -> "none") !bad !total
