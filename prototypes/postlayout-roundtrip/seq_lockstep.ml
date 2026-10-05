(* Post-layout round trip, block-specific half, for the deadline sequencer:
   the gate-level netlist extracted from the GDS runs in lockstep with the
   Hardcaml RTL simulation, every output bit compared on every cycle, on the
   same random programmes and inputs as the RTL-against-interpreter test in
   ../deadline-sequencer/main.ml (seeds 1..runs, random 16-bit instruction
   words, random pins and host traffic).

   seq_lockstep.exe GDS MODELS.v RUNS CYCLES [GDS ...]

   Each further GDS is checked the same way, so the planted-fault copies
   from roundtrip_check.exe controls can be passed in; "--swaps N SEED"
   instead plants N crossed-wire faults in the extracted netlist. *)

open Hardcaml

let top = "deadline_sequencer"

type gate_harness = {
  g : Sim.t;
  mutable pending : int;
  mutable current : int;
}

let set_bus (g : Sim.t) name width value =
  if width = 1 then Sim.set_input g name (value land 1)
  else for i = 0 to width - 1 do Sim.set_input g (Printf.sprintf "%s[%d]" name i) ((value lsr i) land 1) done

let get_bus (g : Sim.t) name width =
  if width = 1 then Sim.get g name
  else begin
    let r = ref 0 in
    for i = width - 1 downto 0 do r := (!r lsl 1) lor Sim.get g (Printf.sprintf "%s[%d]" name i) done;
    !r
  end

let toggles = ref 0

let popcount x = let r = ref 0 and x = ref x in while !x <> 0 do incr r; x := !x land (!x - 1) done; !r

let lockstep_one ~(sim : Sim.t) ~seed ~cycles =
  Random.init seed;
  let mem = Array.init Isa.n_threads (fun _ -> Array.init Isa.prog_len (fun _ -> Random.int 0x10000)) in
  let h = Harness.make mem in
  (* the gate-level side gets the same clear cycle as Harness.make *)
  Sim.reset sim;
  set_bus sim "clear" 1 1;
  Sim.cycle sim;
  set_bus sim "clear" 1 0;
  let gh = { g = sim; current = 0; pending = get_bus sim "imem_addr" 8 } in
  let outs = Cyclesim.outputs h.sim in
  let mismatches = ref 0 and first = ref None in
  let prev = Hashtbl.create 16 in
  for c = 0 to cycles - 1 do
    let pin_in = Random.int 256 and host_in = Random.int 256 and host_in_valid = Random.bool () in
    let pin_in4 = (Random.bits () lor (Random.bits () lsl 30)) land 0xFFFFFFFF in
    ignore (Harness.cycle h ~pin_in ~pin_in4 ~host_in ~host_in_valid);
    set_bus sim "imem_data" 16 (Harness.fetch mem gh.current);
    set_bus sim "pin_in" 8 pin_in;
    set_bus sim "pin_in4" 32 pin_in4;
    set_bus sim "host_in" 8 host_in;
    set_bus sim "host_in_valid" 1 (if host_in_valid then 1 else 0);
    Sim.cycle sim;
    gh.current <- gh.pending;
    gh.pending <- get_bus sim "imem_addr" 8;
    (* non-vacuity: count output bits that change on the gate-level side *)
    List.iter (fun (name, b) ->
      let v = get_bus sim name (Bits.width !b) in
      (match Hashtbl.find_opt prev name with
       | Some p -> toggles := !toggles + popcount (p lxor v)
       | None -> ());
      Hashtbl.replace prev name v) outs;
    let bad =
      List.filter (fun (name, b) ->
        let w = Bits.width !b in
        let rtl = Bits.to_int !b and gate = get_bus sim name w in
        rtl <> gate) outs in
    if bad <> [] then begin
      incr mismatches;
      if !first = None then
        first := Some (c, List.map (fun (n, b) ->
            Printf.sprintf "%s rtl=%x gate=%x" n (Bits.to_int !b) (get_bus sim n (Bits.width !b))) bad)
    end
  done;
  (!mismatches, !first)

(* the RTL's ports, bit by bit, for the structural check *)
let rtl_ports () =
  let sim = Cyclesim.create Harness.circuit in
  let bits dir (n, b) =
    let w = Bits.width !b in
    List.init w (fun i -> (Generic_lockstep.bit_name n w i, dir)) in
  List.concat_map (bits Check.In) (Cyclesim.inputs sim)
  @ List.concat_map (bits Check.Out) (Cyclesim.outputs sim)

let run_netlist ~lib ~runs ~cycles ~label (nl : Extract.netlist) =
  let structural = Check.run ~lib ~ports:(rtl_ports ()) ~clock:"clock" nl in
  Printf.printf "%s: structural check: %d errors%s\n" label (List.length structural.errors)
    (match structural.errors with e :: _ -> " (first: " ^ e ^ ")" | [] -> "");
  let t1 = Unix.gettimeofday () in
  match Sim.create lib nl with
  | exception Failure e ->
    Printf.printf "%s: cannot build the gate-level model: %s\n%!" label e;
    `Unsimulable
  | sim ->
    let total = ref 0 and failing = ref 0 and shown = ref 0 in
    toggles := 0;
    for seed = 1 to runs do
      let m, first = lockstep_one ~sim ~seed ~cycles in
      total := !total + m;
      if m > 0 then incr failing;
      match first with
      | Some (c, what) when !shown < 1 ->
        incr shown;
        Printf.printf "  seed %d: first mismatch at cycle %d: %s\n" seed c
          (String.concat "; " (List.filteri (fun i _ -> i < 3) what))
      | _ -> ()
    done;
    let t2 = Unix.gettimeofday () in
    Printf.printf "%s: %d programmes x %d cycles, %d mismatching cycles in %d programmes, %d output-bit toggles (lockstep %.1f s)\n%!"
      label runs cycles !total !failing !toggles (t2 -. t1);
    (* a comparison of outputs that never change would prove nothing *)
    if !toggles = 0 then failwith "no output bit ever changed: the comparison is vacuous";
    if !total = 0 then (if structural.errors = [] then `Agrees else `Structural) else `Differs

let extract gds =
  let t0 = Unix.gettimeofday () in
  let nl, _ = Extract.extract ~gds_path:gds ~top_name:top () in
  Printf.printf "%s: extracted in %.2f s\n%!" (Filename.basename gds) (Unix.gettimeofday () -. t0);
  nl

(* A fault no structural check can see: two input pins of different cells
   exchange nets (crossed wires).  Every net keeps exactly one driver and its
   readers, so only behaviour can tell. *)
let swap_inputs (lib : (string, Cells.cell) Hashtbl.t) (nl : Extract.netlist) =
  let inputs =
    Array.to_list nl.instances
    |> List.mapi (fun i (inst : Extract.inst) ->
        let cell = Hashtbl.find lib inst.icell in
        List.filter_map (fun (p, n) ->
          match n with Some n when List.mem p cell.inputs -> Some (i, p, n) | _ -> None) inst.nets)
    |> List.concat |> Array.of_list in
  let rec pick () =
    let (i, p, n) = inputs.(Random.int (Array.length inputs)) in
    let (j, q, m) = inputs.(Random.int (Array.length inputs)) in
    if i = j || n = m then pick () else ((i, p, n), (j, q, m))
  in
  let (i, p, n), (j, q, m) = pick () in
  let set k pin net =
    let inst = nl.instances.(k) in
    { inst with nets = List.map (fun (p', n') -> if p' = pin then (p', Some net) else (p', n')) inst.nets } in
  let insts = Array.copy nl.instances in
  insts.(i) <- set i p m;
  insts.(j) <- set j q n;
  (Printf.sprintf "swap %s.%s (n%d) with %s.%s (n%d)" insts.(i).iname p n insts.(j).iname q m,
   { nl with instances = insts })

let () =
  match Array.to_list Sys.argv |> List.tl with
  | gds :: models :: runs :: cycles :: more ->
    let lib = Cells.parse_library models in
    let runs = int_of_string runs and cycles = int_of_string cycles in
    let nl = extract gds in
    let base = run_netlist ~lib ~runs ~cycles ~label:(Filename.basename gds) nl in
    if more = [ "--generic" ] then begin
      (* the block-independent check: random values on every input port *)
      let sim = Sim.create lib nl in
      let t0 = Unix.gettimeofday () in
      let total = ref 0 in
      for seed = 1 to runs do
        let m, first = Generic_lockstep.run ~circuit:Harness.circuit ~sim ~seed ~cycles () in
        total := !total + m;
        Option.iter (fun (c, what) ->
          Printf.printf "  seed %d: first mismatch at cycle %d: %s\n" seed c (String.concat "; " what)) first
      done;
      Printf.printf "generic random-input lockstep: %d runs x %d cycles, %d mismatching cycles (%.1f s)\n"
        runs cycles !total (Unix.gettimeofday () -. t0);
      exit (if !total = 0 && base = `Agrees then 0 else 1)
    end;
    let controls =
      match more with
      | [ "--swaps"; n; seed ] ->
        Random.init (int_of_string seed);
        List.init (int_of_string n) (fun _ ->
          let label, nl' = swap_inputs lib nl in
          (label, nl'))
      | gdss -> List.map (fun g -> (Filename.basename g, extract g)) gdss
    in
    let results = List.map (fun (label, nl') -> run_netlist ~lib ~runs ~cycles ~label nl') controls in
    if controls <> [] then begin
      let count p = List.length (List.filter p results) in
      Printf.printf "planted faults: %d; behaviour differs or cannot be simulated: %d; \
                     caught only by the structural check: %d; caught by neither: %d\n"
        (List.length results) (count (fun r -> r = `Differs || r = `Unsimulable))
        (count (( = ) `Structural)) (count (( = ) `Agrees))
    end;
    exit (if base = `Agrees then 0 else 1)
  | _ -> prerr_endline "usage: seq_lockstep.exe GDS MODELS.v RUNS CYCLES [GDS ... | --swaps N SEED]"; exit 2
