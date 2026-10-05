(* Stall injection on the CAN transmitter (can_fw.ml's tx on ISA v2), after
   ../../../verif-oracles/stall/eth_stall.ml: the perturbed input is the host's byte stream (IN's
   handshake), and the golden transcript is our node's txd level, clock by clock, in an
   unperturbed run.

   CAN transmission is timing-exact, so the specification checked is the Ethernet one: txd
   carries the golden transcript, or a golden prefix after which txd is recessive (released) for
   the rest of the golden frame window together with an underrun report (OUT tag_tx 5). Any other
   difference is a violation: a bit of the wrong length or a level the golden run does not have.

   Bench: node A (thread 1 TX, thread 0 holding txe) and one reference node that acknowledges, on
   the wired-AND bus of can_bench.ml. One frame, 8 data bytes. The host model: A's stream (bit
   count, then the stuffed frame bytes) is valid from the start; byte j >= 2 (the mid-frame
   refills; bytes 0 and 1 are read before the frame starts) becomes valid d clocks after byte
   j - 1 was taken, d drawn by the pattern. After an underrun report the host submits nothing
   more, so a released line must stay released. Interpreter and RTL run in lockstep. *)
open Can_bench

let frame = { Can_model.id = 0x123; rtr = false; dlc = 8; data = [ 0x00; 0xFF; 0x55; 0x0F; 0xF0; 0x81; 0x7E; 0xC3 ] }
let stream = Array.of_list (Can_fw.tx_bytes { Can_fw.id = frame.id; rtr = frame.rtr; dlc = frame.dlc; data = frame.data })
let period = Sim.period_of_hz clock_hz

type outcome = { txd : int array; reports : int list; mism : int; ref_good : int; ref_errors : int }

let run_one ~underrun_check ~delay =
  let t = !timing in
  let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 90. |] in
  let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 in
  let prog, _, _ = Can_fw.tx ~underrun_check pins_a t in
  let mem = Array.init 4 (fun i -> if i = 0 then Can_fw.rx_idle a.pins else if i = 1 then prog else Array.make 256 Isa_v.halt) in
  let m = Sim.Machine.create ~rtl:true mem in
  let pos = ref 0 and avail = ref 0 and stopped = ref false in
  let start = Sim.us 20. in
  let txd = ref [] and reports = ref [] in
  let fire now =
    let pin_in = ref m.st.pin_out in
    let lvl = Can_model.Bus.rx bus a.bus_idx ~now in
    pin_in := (!pin_in land lnot (1 lsl a.pins.rx)) lor (lvl lsl a.pins.rx);
    let th = Sim.Machine.thread m in
    let hi = if th = 1 && (not !stopped) && now >= start && now >= !avail && !pos < Array.length stream
      then Some stream.(!pos) else None in
    let eff = Sim.Machine.step m ~pin_in:!pin_in ~host_in:(Option.value hi ~default:0) ~host_in_valid:(hi <> None) in
    if eff.host_in_ready then begin
      incr pos;
      avail := now + period * (1 + (if !pos >= 2 then delay !pos else 0))
    end;
    (match eff.host_out with
     | Some (tag, v) when th = 1 && tag = Can_fw.tag_tx -> reports := v :: !reports; stopped := true
     | _ -> ());
    let o = m.st.pin_out in
    let l = ((o lsr a.pins.txd) land 1) land ((o lsr a.pins.txe) land 1) in
    Can_model.Bus.drive bus a.bus_idx ~now l;
    txd := l :: !txd in
  let r = Can_model.create ~bus ~idx:1 ~name:"ref" () in
  ignore (Sim.run ~until:(Sim.us 400.) [ Sim.agent ~name:"seq" ~hz:clock_hz fire; ref_agent r ]);
  { txd = Array.of_list (List.rev !txd); reports = List.rev !reports; mism = m.mismatches;
    ref_good = List.length (List.filter (fun (_, _, ok, own) -> ok && not own) r.received);
    ref_errors = List.length r.errors }

type verdict = Exact | Clean_abort | Violation of string

(* the golden frame window ends at the golden run's last dominant clock *)
let judge ~golden o =
  let last_dom = let r = ref 0 in Array.iteri (fun i v -> if v = 0 then r := i) golden.txd; !r in
  let n = min (Array.length golden.txd) (Array.length o.txd) in
  let first = let r = ref (-1) in (try for i = 0 to min n (last_dom + 1) - 1 do
                                     if o.txd.(i) <> golden.txd.(i) then (r := i; raise Exit) done with Exit -> ()); !r in
  if first < 0 then (if o.reports = golden.reports then Exact else Violation "same line, different report")
  else begin
    let released = ref true in
    for i = first to min n (last_dom + 1) - 1 do if o.txd.(i) <> 1 then released := false done;
    if not !released then Violation (Printf.sprintf "wrong level from clock %d" first)
    else if o.reports <> [ Can_fw.tx_underrun ] then
      Violation (Printf.sprintf "released at clock %d without the underrun report (reports [%s])" first
                   (String.concat "," (List.map string_of_int o.reports)))
    else Clean_abort
  end

let pr = Printf.printf

let () =
  let t = !timing in
  let _, l_old, _ = Can_fw.tx ~underrun_check:false pins_a t and _, l_new, _ = Can_fw.tx pins_a t in
  pr "CAN TX stall injection, %.0f kbit/s (N = %d slots per bit, SP = %d): TX thread %d words before the fix, %d after\n"
    (bit_rate () /. 1e3) t.n t.sp l_old l_new;
  pr "frame %s, %d stream bytes (byte 0 the bit count, then the stuffed frame)\n\n" (Can_model.pp_frame frame) (Array.length stream);
  let ok = ref true in
  let firmwares = [ ("before", false); ("after ", true) ] in
  let goldens = List.map (fun (name, uc) ->
      let g = run_one ~underrun_check:uc ~delay:(fun _ -> 0) in
      let good = g.ref_good = 1 && g.ref_errors = 0 && g.reports = [ 1 ] && g.mism = 0 in
      pr "%s, no stall: reference got %d good frame(s), %d error(s); A reported [%s]; lockstep mismatches %d -> %s\n"
        name g.ref_good g.ref_errors (String.concat "," (List.map string_of_int g.reports)) g.mism
        (if good then "golden" else "BAD GOLDEN");
      if not good then ok := false;
      (uc, g)) firmwares in
  let g_old = List.assoc false goldens and g_new = List.assoc true goldens in
  let same = g_old.txd = g_new.txd in
  pr "unstalled txd transcripts before and after the fix identical: %b\n\n" same;
  if not same then ok := false;
  (* slack: one byte (the fourth refill) late by d clocks; find the largest exact d *)
  let slack uc =
    let g = List.assoc uc goldens in
    let exact d = judge ~golden:g (run_one ~underrun_check:uc ~delay:(fun j -> if j = 5 then d else 0)) = Exact in
    (* bisection: exact at lo, not exact at hi (checked), assuming lateness only hurts *)
    let lo = ref 0 and hi = ref 4000 in
    if not (exact !lo) || exact !hi then failwith "slack search: not bracketed";
    while !hi - !lo > 1 do let mid = (!lo + !hi) / 2 in if exact mid then lo := mid else hi := mid done;
    !hi in
  let s_old = slack false and s_new = slack true in
  pr "slack (byte 5 late by d clocks; first d that is not exact): before %d clocks, after %d clocks (cost %d)\n\n"
    s_old s_new (s_old - s_new);
  let patterns = [
    ("one byte (5) late by slack+1..slack+200", (fun r -> let d = s_new + 1 + Random.State.int r 200 in fun j -> if j = 5 then d else 0));
    ("one random byte late by 0..2000", (fun r -> let j0 = 2 + Random.State.int r (Array.length stream - 2) and d = Random.State.int r 2001 in
                                           fun j -> if j = j0 then d else 0));
    ("random bursts: p = 0.3 per byte, 1..1500 clocks", (fun r -> fun _ -> if Random.State.float r 1.0 < 0.3 then 1 + Random.State.int r 1500 else 0));
    ("a byte that never comes (byte 6)", (fun _ -> fun j -> if j = 6 then 1_000_000 else 0)) ] in
  List.iter (fun (pname, mk) ->
      List.iter (fun (name, uc) ->
          let g = List.assoc uc goldens in
          let seeds = 20 in
          let ex = ref 0 and ab = ref 0 and vi = ref 0 and mm = ref 0 and example = ref "" in
          for seed = 1 to seeds do
            let o = run_one ~underrun_check:uc ~delay:(mk (Random.State.make [| seed |])) in
            mm := !mm + o.mism;
            match judge ~golden:g o with
            | Exact -> incr ex | Clean_abort -> incr ab
            | Violation why -> incr vi; if !example = "" then example := Printf.sprintf "seed %d: %s" seed why
          done;
          pr "%-50s %s: %2d runs: exact %2d, clean abort %2d, VIOLATION %2d; lockstep mismatches %d%s\n" pname name seeds !ex !ab !vi !mm
            (if !example = "" then "" else "\n      first violation: " ^ !example);
          if !mm > 0 then ok := false;
          if uc && !vi > 0 then ok := false;
          if (not uc) && pname <> "one random byte late by 0..2000" && !vi = 0 then
            (ok := false; pr "      ^ the firmware before the fix was expected to violate and did not\n")) firmwares) patterns;
  (* control: a golden transcript with one bit flipped must be judged a violation *)
  let flipped = { g_new with txd = Array.copy g_new.txd } in
  let i = Array.length flipped.txd / 3 in
  flipped.txd.(i) <- 1 - flipped.txd.(i);
  let c1 = match judge ~golden:g_new flipped with Violation _ -> true | _ -> false in
  pr "\ncontrol: golden with one clock's level flipped: %s\n" (if c1 then "judged a violation" else "MISSED");
  if not c1 then ok := false;
  pr "\nCAN STALL %s\n" (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
