(* Block-independent behavioural round trip: any Hardcaml circuit against
   the netlist extracted from its layout, with random values on every input
   port on every cycle and every output bit compared on every cycle.

   This needs nothing from the block but its Circuit.t, so it is the version
   to run for every block in the regular flow.  It is weaker than a block's
   own harness (the sequencer's lockstep feeds it a coherent instruction
   memory, which reaches deeper states), and a reset or clear input driven
   at random spends half the time in reset, so [hold_low] names inputs that
   are high on the first cycle and then high on one cycle in 64 at random.
   Pulsing them mid-run matters: a block harness that clears only at the
   start cannot see a wire carrying "not clear" crossed with a tie-high,
   which is exactly the crossed-wire fault this was added for. *)

open Hardcaml

let bit_name name width i = if width = 1 then name else Printf.sprintf "%s[%d]" name i

let run ?(hold_low = [ "clear"; "reset"; "rst" ]) ?(clock = "clock") ~(circuit : Circuit.t)
    ~(sim : Sim.t) ~seed ~cycles () =
  Random.init seed;
  let rtl = Cyclesim.create circuit in
  let inputs =
    List.filter (fun (n, _) -> n <> clock) (Cyclesim.inputs rtl) in
  List.iter (fun (n, b) -> if Bits.width !b > 62 then failwith (n ^ ": ports wider than 62 bits not supported"))
    (inputs @ Cyclesim.outputs rtl);
  let outputs = Cyclesim.outputs rtl in
  if outputs = [] then failwith "the circuit has no outputs: a lockstep would compare nothing";
  let set name (b : Bits.t ref) v =
    let w = Bits.width !b in
    b := Bits.of_int ~width:w v;
    for i = 0 to w - 1 do Sim.set_input sim (bit_name name w i) ((v lsr i) land 1) done
  in
  let get name w =
    let r = ref 0 in
    for i = w - 1 downto 0 do r := (!r lsl 1) lor Sim.get sim (bit_name name w i) done;
    !r
  in
  Sim.reset sim;
  let mismatches = ref 0 and first = ref None in
  for c = 0 to cycles - 1 do
    List.iter (fun (name, b) ->
      let w = Bits.width !b in
      let v =
        if List.mem name hold_low then (if c = 0 || Random.int 64 = 0 then 1 else 0)
        else if w <= 30 then Random.bits () land ((1 lsl w) - 1)
        else (Random.bits () lor (Random.bits () lsl 30)) land ((1 lsl w) - 1) in
      set name b v) inputs;
    Cyclesim.cycle rtl;
    Sim.cycle sim;
    if c > 0 then begin
      let bad = List.filter (fun (n, b) -> Bits.to_int !b <> get n (Bits.width !b)) outputs in
      if bad <> [] then begin
        incr mismatches;
        if !first = None then
          first := Some (c, List.map (fun (n, b) ->
              Printf.sprintf "%s rtl=%x gate=%x" n (Bits.to_int !b) (get n (Bits.width !b))) bad)
      end
    end
  done;
  (!mismatches, !first)
