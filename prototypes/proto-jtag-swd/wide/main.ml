(* The WIDE variant (8-bit pc): lockstep of its RTL against its interpreter on random programmes,
   then JTAG and SWD. Arguments select parts: lockstep, jtag, swd (default: all). *)
open Hardcaml

let emit () =
  let oc = open_out "deadline_sequencer_wide.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog Harness.circuit;
  close_out oc

(* As ../../deadline-sequencer/main.ml, on the variant. *)
let lockstep ~seed ~cycles =
  Random.init seed;
  let mem = Array.init Isa.n_threads (fun _ -> Array.init Isa.prog_len (fun _ -> Random.int 0x10000)) in
  let s = Harness.make mem in
  let st = Isa.init () in
  let mismatches = ref 0 in
  for _ = 0 to cycles - 1 do
    let pin_in = Random.int 256 and host_in = Random.int 256 and host_in_valid = Random.bool () in
    let eff = Isa.step st ~mem ~pin_in ~host_in ~host_in_valid in
    let o = Harness.cycle s ~pin_in ~host_in ~host_in_valid in
    if not (o.pin_out = st.pin_out && o.pin_oe = st.pin_oe && o.host_out = eff.host_out
            && o.host_in_ready = eff.host_in_ready && o.pcs = Array.to_list st.pcs) then incr mismatches
  done;
  !mismatches

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let want p = args = [] || List.mem p args in
  let ok = ref true in
  if want "lockstep" then begin
    emit ();
    let runs = 300 and cycles = 2000 in
    let total = ref 0 in
    for seed = 1 to runs do total := !total + lockstep ~seed ~cycles done;
    Printf.printf "wide variant lockstep: %d programmes x %d cycles, %d mismatching cycles\n%!" runs cycles !total;
    if !total <> 0 then ok := false
  end;
  if want "jtag" then (if not (Jtag_suite.main ()) then ok := false);
  if List.mem "swddbg" args then begin
    let mem, len = Swd_host.programmes Swd_host.fastest in
    for i = 0 to len - 1 do Printf.printf "%3d %s\n" i (Asm.disassemble mem.(0).(i)) done;
    let r = Swd_test.run ~debug:2600 ~mk:Asm.interp ~mem ~cfg:(Swd_suite.cfg ~seed:1 ()) (List.filteri (fun i _ -> i < 3) Swd_test.bring_up) in
    Printf.printf "cycles %d complete %b contention %d outcomes %d\n" r.cycles r.complete r.contention (List.length r.outcomes);
    List.iter print_endline (Swd_target.log r.target)
  end;
  if want "swd" && not (List.mem "swddbg" args) then (if not (Swd_suite.main ()) then ok := false);
  print_endline (if !ok then "ALL PASS" else "FAILURES");
  exit (if !ok then 0 else 1)
