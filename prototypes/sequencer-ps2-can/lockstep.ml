(* Lockstep of the variant RTL against the variant interpreter on random programmes, as
   ../deadline-sequencer/main.ml does for the base ISA. Random words exercise every opcode,
   including JC, CFG and the CRC / stuff flags, with random pins and host input. *)
(* biased words: half the time one of the new or changed instructions with random fields *)
let biased () =
  if Random.bool () then Random.int 0x10000
  else
    let f = Random.int 0x1000 in
    match Random.int 6 with
    | 0 -> Isa_v.enc Isa_v.SHI f | 1 -> Isa_v.enc Isa_v.SHO f | 2 -> Isa_v.enc Isa_v.CFG f
    | 3 -> Isa_v.enc Isa_v.JC f | 4 -> Isa_v.enc Isa_v.OUT f | _ -> Isa_v.enc Isa_v.JNZ f

let run ~seed ~cycles =
  Random.init seed;
  let gen = if seed mod 2 = 0 then biased else (fun () -> Random.int 0x10000) in
  let mem = Array.init Isa_v.n_threads (fun _ -> Array.init Isa_v.prog_len (fun _ -> gen ())) in
  let m = Sim.Machine.create mem in
  for _ = 1 to cycles do
    ignore (Sim.Machine.step m ~pin_in:(Random.int 256) ~host_in:(Random.int 256) ~host_in_valid:(Random.bool ()))
  done;
  (match m.first with Some s when seed <= 3 -> Printf.printf "  seed %d %s\n" seed s | _ -> ());
  m.mismatches

let () =
  if Array.length Sys.argv > 2 && Sys.argv.(2) = "shared" then Isa_v.shared_cfg := true;
  let runs = int_of_string (try Sys.argv.(1) with _ -> "300") and cycles = 2000 in
  let total = ref 0 and bad = ref 0 in
  for seed = 1 to runs do
    let n = run ~seed ~cycles in
    total := !total + n; if n > 0 then incr bad
  done;
  Printf.printf "variant lockstep (%s configuration): %d programmes x %d cycles, %d mismatching cycles in %d programmes\n"
    (if !Isa_v.shared_cfg then "shared" else "per-thread") runs cycles !total !bad;
  exit (if !total = 0 then 0 else 1)
