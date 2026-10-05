(* The 10BASE-T transmitter as it runs on ISA v2: eth_fixed.ml, the original 24-slot loop of
   ../../../sequencer-ethernet/main.ml with WAITC 9 (host byte valid) two slots before each IN and
   an underrun handler that releases the line and reports (OUT tag 7). The fix was found and
   measured by ../../../verif-oracles/stall/eth_stall.ml; this is the port's own test of the
   firmware it now runs, with main.ml's checks:
   - the pin against the Ethernet model's encoder, clock for clock, on the interpreter;
   - the same on the v2 RTL, which must also agree with the interpreter on every clock;
   - main.ml's controls (a flipped stream bit, rotated streams), which must be caught;
   - and one the original cannot pass: a thread's stream cut short must end in a released line
     and an underrun report, never a wrong level.
   The host is a FIFO per thread holding the whole stream (valid whenever a byte is left), so
   unlike main.ml's bench it does not need to know when each thread executes IN. *)
open Eth_fw

let n_threads = Isa2.n_threads

let fetch_of mem a =
  let t = a lsr Isa2.pc_bits and pc = a land (Isa2.page_len - 1) in
  if pc < Array.length mem.(t) then mem.(t).(pc) else Isa2.nop

(* run for the frame window; returns the line per clock of the window (0, 1, or 2 = released),
   the host reports and the clocks where the RTL differs from the interpreter *)
let run ?(rtl = false) ~streams () =
  let mem = Array.init n_threads (fun t -> Eth_fixed.program_fixed t) in
  let fetch = fetch_of mem in
  let st = Isa2.init ~boot:Compat.boot_by_thread () in
  let hs = if rtl then Some (Harness2.make_f ~boot:Compat.boot_by_thread ~fetch ()) else None in
  let next = Array.make n_threads 0 in
  let window = Array.make (h * nhalf) 2 and reports = ref [] and diverged = ref 0 in
  for c = 0 to s + (h * nhalf) - 1 do
    let t = st.thread in
    let valid = next.(t) < Array.length streams.(t) in
    let io = Isa2.io ~host_in:(if valid then streams.(t).(next.(t)) else 0) ~host_in_valid:valid 0 in
    let eff = Isa2.step_f st ~fetch io in
    (match hs with
     | Some hs ->
       let o = Harness2.cycle hs io in
       if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe || o.host_out <> eff.host_out then incr diverged
     | None -> ());
    if eff.host_in_ready then next.(t) <- next.(t) + 1;
    (match eff.host_out with Some r -> reports := r :: !reports | None -> ());
    if c >= s then window.(c - s) <- (if st.pin_oe land 1 = 0 then 2 else st.pin_out land 1)
  done;
  window, List.rev !reports, !diverged

let golden = Array.init (h * nhalf) (fun i -> if model_samples.(i) > 0 then 1 else 0)
let mismatches w = let n = ref 0 in Array.iteri (fun i v -> if v <> golden.(i) then incr n) w; !n

let () =
  let ok = ref true in
  Printf.printf "10BASE-T TX on v2 with the underrun check: %d bytes on the wire, %d half-bits; words per thread %s\n"
    (List.length wire) nhalf (String.concat "," (List.init n_threads (fun t -> string_of_int (Array.length (Eth_fixed.program_fixed t)))));
  let w, reports, _ = run ~streams () in
  let m = mismatches w in
  Printf.printf "pin vs Ethernet model encoder: %d mismatching clocks of %d, %d host reports -> %s\n" m (h * nhalf)
    (List.length reports) (if m = 0 && reports = [] then "PASS" else "FAIL");
  if m <> 0 || reports <> [] then ok := false;
  let w, _, diverged = run ~rtl:true ~streams () in
  let m = mismatches w in
  Printf.printf "RTL: %d clocks where the line differs from the Ethernet model, %d where the RTL differs from the interpreter -> %s\n"
    m diverged (if m = 0 && diverged = 0 then "PASS" else "FAIL");
  if m <> 0 || diverged <> 0 then ok := false;
  let flip_byte t j = Array.mapi (fun u a -> if u = t then Array.mapi (fun i b -> if i = j then b lxor 1 else b) a else a) streams in
  let rotated = Array.init n_threads (fun t -> streams.((t + 2) mod n_threads)) in
  List.iter (fun (name, st) ->
      let w, _, _ = run ~streams:st () in
      let m = mismatches w in
      Printf.printf "control %-40s %5d mismatching clocks -> %s\n" name m (if m > 0 then "caught" else "MISSED");
      if m = 0 then ok := false)
    [ ("one bit flipped in thread 2's 10th byte", flip_byte 2 9); ("threads' streams rotated by two", rotated) ];
  (* a stream cut short: thread 1 gets only its first 20 bytes *)
  let cut = Array.mapi (fun t a -> if t = 1 then Array.sub a 0 20 else a) streams in
  let w, reports, diverged = run ~rtl:true ~streams:cut () in
  let first = let r = ref (-1) in (try Array.iteri (fun i v -> if v <> golden.(i) then (r := i; raise Exit)) w with Exit -> ()); !r in
  let released = first >= 0 && (let ok = ref true in for k = first to Array.length w - 1 do if w.(k) <> 2 then ok := false done; !ok) in
  let reported = List.exists (fun (tag, v) -> tag = 7 && v = 1) reports in
  Printf.printf "underrun: thread 1's stream cut after 20 bytes: line correct up to half-bit %d, released from there to the end %b, \
                 underrun reported by thread 1 %b, RTL differs %d clocks -> %s\n"
    (first / h) released reported diverged (if released && reported && diverged = 0 then "PASS" else "FAIL");
  if not (released && reported && diverged = 0) then ok := false;
  print_endline (if !ok then "ETH V2 FIXED: ALL PASS" else "ETH V2 FIXED: FAIL");
  exit (if !ok then 0 else 1)
