(* Lockstep differential test of the mailbox variant's RTL against its interpreter, the check that
   the variant is a strict extension of the base ISA, a planted-bug control, and Verilog emission
   for the area measurement.

   Usage: lockstep.exe [runs] [cycles]   (defaults 300 x 2000, as the base core's test) *)
open Hardcaml

let rand_word ~mb_heavy =
  if mb_heavy && Random.int 2 = 0 then begin
    (* mailbox-heavy: SEND/RECV to inboxes and ports, WAITC on all conditions, short fail targets *)
    let fail = Random.int 16 in
    match Random.int 4 with
    | 0 -> Isa_mb.send ~ch:(Random.int 8) ~fail
    | 1 -> Isa_mb.recv ~ch:(Random.int 8) ~fail
    | 2 -> Isa_mb.waitc ~cond:(Random.int 16) ~value:(Random.int 2) ~fail
    | _ -> (3 lsl 12) lor Random.int 4   (* LDD 0..3: keep deadlines short so waits resolve *)
  end else Random.int 0x10000

let random_io () : Isa_mb.io =
  { pin_in = Random.int 256; host_in = Random.int 256; host_in_valid = Random.bool ();
    port_in = Array.init 4 (fun _ -> Random.int 256); port_in_valid = Array.init 4 (fun _ -> Random.bool ());
    port_out_ready = Array.init 4 (fun _ -> Random.bool ()); flags = Random.int 16 }

type cov = { mutable push : int; mutable pop : int; mutable full_cycles : int; mutable pport : int; mutable qport : int }

let lockstep ?mutant ~(c : Isa_mb.cfg) ~seed ~cycles cov =
  Random.init seed;
  let mb_heavy = seed mod 2 = 0 in
  let plen = Isa_mb.prog_len c in
  let mem = Array.init 4 (fun _ -> Array.init plen (fun _ -> rand_word ~mb_heavy)) in
  let s = Harness_mb.make ?mutant c mem in
  let st = Isa_mb.init c in
  let bad = ref 0 in
  for cyc = 0 to cycles - 1 do
    let io = random_io () in
    let e = Isa_mb.step st ~mem io in
    let o = Harness_mb.cycle s io in
    (match e.mb with `Push _ -> cov.push <- cov.push + 1 | `Pop _ -> cov.pop <- cov.pop + 1 | `None -> ());
    if e.port_push <> None then cov.pport <- cov.pport + 1;
    if e.port_pop <> None then cov.qport <- cov.qport + 1;
    if Array.exists (fun n -> n >= c.depth) (Isa_mb.counts st) then cov.full_cycles <- cov.full_cycles + 1;
    if not (Harness_mb.agrees o st e) then begin
      incr bad;
      if !bad <= 2 && mutant = None then
        Printf.printf "  mismatch seed %d cycle %d: rtl pcs=%s counts=%s | model pcs=%s counts=%s\n" seed cyc
          (String.concat "," (List.map string_of_int o.pcs)) (String.concat "," (List.map string_of_int o.counts))
          (String.concat "," (Array.to_list (Array.map string_of_int st.pcs)))
          (String.concat "," (Array.to_list (Array.map string_of_int (Isa_mb.counts st))))
    end
  done;
  !bad

(* Strict extension: with pc_bits = 6, on programmes that use no new opcode, the variant RTL must
   match the BASE interpreter (../deadline-sequencer/isa.ml) on pins, enables, host handshake and
   all four pcs, whatever the new inputs do. *)
let extension ~seed ~cycles =
  Random.init seed;
  let c = Isa_mb.cfg ~pc_bits:6 ~depth:2 () in
  let strip w = if (w lsr 12) >= 14 then w land 0x0FFF else w in
  let mem = Array.init 4 (fun _ -> Array.init 64 (fun _ -> strip (Random.int 0x10000))) in
  let s = Harness_mb.make c mem in
  let st = Isa.init () in
  let bad = ref 0 in
  for _ = 0 to cycles - 1 do
    let io = random_io () in
    let e = Isa.step st ~mem ~pin_in:io.pin_in ~host_in:io.host_in ~host_in_valid:io.host_in_valid in
    let o = Harness_mb.cycle s io in
    if not (o.pin_out = st.pin_out && o.pin_oe = st.pin_oe && o.host_out = e.host_out
            && o.host_in_ready = e.host_in_ready && o.pcs = Array.to_list st.pcs && o.port_push = None && o.port_pop = None)
    then incr bad
  done;
  !bad

let emit (c : Isa_mb.cfg) =
  let name = Printf.sprintf "rtl/seq_mb_p%d_d%d.v" c.pc_bits c.depth in
  let oc = open_out name in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer_mb.circuit c);
  close_out oc

let () =
  let runs = try int_of_string Sys.argv.(1) with _ -> 300 in
  let cycles = try int_of_string Sys.argv.(2) with _ -> 2000 in
  (try Unix.mkdir "rtl" 0o755 with _ -> ());
  List.iter emit [ Isa_mb.cfg ~pc_bits:6 ~depth:1 (); Isa_mb.cfg ~pc_bits:6 ~depth:2 (); Isa_mb.cfg ~pc_bits:6 ~depth:4 ();
                   Isa_mb.cfg ~pc_bits:7 ~depth:2 () ];
  let ok = ref true in
  List.iter (fun (pb, d) ->
    let c = Isa_mb.cfg ~pc_bits:pb ~depth:d () in
    let cov = { push = 0; pop = 0; full_cycles = 0; pport = 0; qport = 0 } in
    let total = ref 0 in
    for seed = 1 to runs do total := !total + lockstep ~c ~seed ~cycles cov done;
    Printf.printf "lockstep pc_bits=%d depth=%d: %d programmes x %d cycles, %d mismatching cycles \
                   (coverage: %d inbox pushes, %d pops, %d cycles with a full inbox, %d port pushes, %d port pops)\n%!"
      pb d runs cycles !total cov.push cov.pop cov.full_cycles cov.pport cov.qport;
    if !total <> 0 || cov.full_cycles = 0 then ok := false) [ (6, 1); (6, 2); (6, 4); (7, 2) ];
  let ext = ref 0 in
  for seed = 1 to runs do ext := !ext + extension ~seed ~cycles done;
  Printf.printf "strict extension (variant RTL, pc_bits=6, vs the BASE interpreter on programmes without E/F): %d mismatching cycles\n" !ext;
  if !ext <> 0 then ok := false;
  (* control: the planted bug must be caught *)
  let c = Isa_mb.cfg ~pc_bits:7 ~depth:2 () in
  let cov = { push = 0; pop = 0; full_cycles = 0; pport = 0; qport = 0 } in
  let caught = ref 0 and m = ref 0 in
  for seed = 1 to 50 do let b = lockstep ~mutant:`Full_never ~c ~seed ~cycles cov in if b > 0 then incr caught; m := !m + b done;
  Printf.printf "control (inbox never reports full, RTL only): caught in %d of 50 programmes, %d mismatching cycles\n" !caught !m;
  if !caught = 0 then ok := false;
  print_endline (if !ok then "LOCKSTEP PASS" else "LOCKSTEP FAIL");
  exit (if !ok then 0 else 1)
