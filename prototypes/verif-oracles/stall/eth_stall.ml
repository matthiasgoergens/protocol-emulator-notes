(* Stall injection on the 10BASE-T transmitter firmware (../../sequencer-ethernet), on ISA v2.

   Idea credited to Gergo Erdi's clash-intel8080 test-sim.hs, which perturbs the "memory ready"
   input of a CPU with a random pattern and requires the identical golden output. Here the
   perturbed input is host byte availability (IN's handshake), and the golden transcript is the
   Ethernet model's own line encoding of the frame (Eth_model.encode_frame), clock for clock.

   Ethernet transmission is timing-exact: a half-bit late is a wrong frame. So "identical
   transcript" cannot hold for every stall pattern, and the specification we check is:

     the line carries the golden frame exactly; or it carries a prefix of the golden frame,
     after which the line is released (high impedance) for the rest of the frame window and
     the host receives an underrun report (OUT tag 7). A wrong level on the line is a violation
     ("silent corruption").

   The host model: four per-thread FIFOs multiplexed onto the one host port by the executing
   thread, as the original bench does. When a thread consumes its head byte at clock c, the next
   byte becomes valid at clock c + 1 + d, d chosen by the stall pattern; once valid it stays
   valid until consumed (the valid/ready rule). The golden run has d = 0 always.

   Two firmwares:
   - original: ../../sequencer-ethernet/main.ml's generator, unchanged (eth_fw.ml is that file
     up to its first test, cut by a dune rule), translated word by word into v2 (compat.ml);
   - fixed: the same 24-slot loop, with one NOP replaced by WAITC 9 ("host byte valid") at
     dl = 0, two slots before IN, branching to an underrun handler that still emits the byte's
     last bit on time, then tells the end of the stream (cnt = 0, loaded with the thread's bit
     count in the prologue) from an underrun, and on an underrun releases the line and reports. *)

open Eth_fw
open Eth_fixed   (* the fixed firmware, program_fixed, and n_threads *)

(* ---- the host ---- *)
type pattern = {
  pname : string;
  mk : Random.State.t -> t:int -> j:int -> int;   (* per run: extra clocks before byte j of thread t is valid *)
}

let none = { pname = "none (golden)"; mk = (fun _ ~t:_ ~j:_ -> 0) }
let uniform d = { pname = Printf.sprintf "every byte %d clocks late" d; mk = (fun _ ~t:_ ~j -> if j = 0 then 0 else d) }
let bursts p maxb = { pname = Printf.sprintf "random: p = %.3f per byte, 1..%d clocks" p maxb;
                      mk = (fun r ~t:_ ~j:_ -> if Random.State.float r 1.0 < p then 1 + Random.State.int r maxb else 0) }
(* one byte, chosen per seed, late by 97..200 clocks: beyond the loop's slack *)
let one_late = { pname = "one random byte 97..200 clocks late";
                 mk = (fun r ->
                     let ct = Random.State.int r n_threads and cj = 1 + Random.State.int r 30 and d = 97 + Random.State.int r 104 in
                     fun ~t ~j -> if (t, j) = (ct, cj) then d else 0) }

(* ---- one run ---- *)
type core = Interp | Rtl_lockstep

type result = {
  window : int array;          (* per clock of the frame window: 0, 1, or 2 = released *)
  reports : (int * int) list;  (* host_out (tag, byte) *)
  rtl_diff : int;              (* clocks where the RTL's pins differ from the interpreter's *)
}

let run ?(core = Interp) ~fetch ~(pattern : pattern) ~seed () =
  let rnd = Random.State.make [| seed |] in
  let delay = pattern.mk rnd in
  let st = Isa2.init ~boot:Compat.boot_by_thread () in
  let hs = match core with Rtl_lockstep -> Some (Harness2.make_f ~boot:Compat.boot_by_thread ~fetch ()) | Interp -> None in
  let next = Array.make n_threads 0 in
  let avail = Array.init n_threads (fun t -> delay ~t ~j:0) in
  let cycles = s + h * nhalf in
  let window = Array.make (h * nhalf) 2 and reports = ref [] and rtl_diff = ref 0 in
  for c = 0 to cycles - 1 do
    let t = st.thread in
    let valid = next.(t) < Array.length streams.(t) && c >= avail.(t) in
    let byte = if valid then streams.(t).(next.(t)) else 0 in
    let io = Isa2.io ~host_in:byte ~host_in_valid:valid 0 in
    let eff = Isa2.step_f st ~fetch io in
    (match hs with
     | Some hs ->
       let o = Harness2.cycle hs io in
       if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe || o.host_out <> eff.host_out
          || o.host_in_ready <> eff.host_in_ready then incr rtl_diff
     | None -> ());
    if eff.host_in_ready then begin
      next.(t) <- next.(t) + 1;
      avail.(t) <- c + 1 + delay ~t ~j:next.(t)
    end;
    (match eff.host_out with Some r -> reports := r :: !reports | None -> ());
    if c >= s then window.(c - s) <- (if st.pin_oe land 1 = 0 then 2 else st.pin_out land 1)
  done;
  { window; reports = List.rev !reports; rtl_diff = !rtl_diff }

let golden = Array.init (h * nhalf) (fun i -> if model_samples.(i) > 0 then 1 else 0)   (* the frame window, as main.ml compares it *)

type verdict = Exact | Cut_reported of int | Violation of string

let judge ?(golden = golden) r =
  let n = Array.length golden in
  let rec first i = if i >= n then None else if r.window.(i) <> golden.(i) then Some i else first (i + 1) in
  match first 0 with
  | None -> if r.reports = [] then Exact else Violation "exact frame but an underrun was reported"
  | Some i ->
    let released_after = let ok = ref true in for k = i to n - 1 do if r.window.(k) <> 2 then ok := false done; !ok in
    let reported = List.exists (fun (tag, _) -> tag = 7) r.reports in
    if not released_after then
      Violation (Printf.sprintf "wrong level on the line at half-bit %d (clock %d)" (i / h) (s + i))
    else if not reported then Violation (Printf.sprintf "line released at half-bit %d without an underrun report" (i / h))
    else Cut_reported (i / h)

(* ---- fetch functions over the per-thread arrays ---- *)
let fetch_original = Compat.fetch_threads ~translate:Variant.translate (Array.init n_threads program)
let fetch_fixed ?plant () =
  let mem = Array.init n_threads (fun t -> program_fixed ?plant t) in
  fun a ->
    let t = a lsr Isa2.pc_bits and pc = a land (Isa2.page_len - 1) in
    if pc < Array.length mem.(t) then mem.(t).(pc) else Isa2.nop

let pr = Printf.printf

let campaign ?core ~name ~fetch ~pattern ~seeds () =
  let exact = ref 0 and cut = ref 0 and viol = ref 0 and first_viol = ref "" and cut_at = ref [] and rtl = ref 0 in
  for seed = 1 to seeds do
    let r = run ?core ~fetch ~pattern ~seed () in
    rtl := !rtl + r.rtl_diff;
    match judge r with
    | Exact -> incr exact
    | Cut_reported k -> incr cut; cut_at := k :: !cut_at
    | Violation m -> incr viol; if !first_viol = "" then first_viol := Printf.sprintf " (seed %d: %s)" seed m
  done;
  pr "  %-9s %-44s %3d runs: exact %3d, cut and reported %3d, VIOLATIONS %3d%s%s\n%!" name pattern.pname seeds !exact !cut !viol
    (match core with Some Rtl_lockstep -> Printf.sprintf ", RTL vs interpreter %d clocks differ" !rtl | _ -> "")
    !first_viol;
  (!exact, !cut, !viol, !rtl)

let () =
  pr "10BASE-T TX firmware under host stalls: %d bytes on the wire, %d half-bits, frame window %d clocks\n" (List.length wire) nhalf (h * nhalf);
  pr "fixed firmware sizes (words per thread): %s; original: %s\n"
    (String.concat "," (List.init n_threads (fun t -> string_of_int (Array.length (program_fixed t)))))
    (String.concat "," (List.init n_threads (fun t -> string_of_int (List.length (List.filter (( <> ) Isa.halt) (Array.to_list (program t)))))));
  let ok = ref true in
  let need cond msg = if not cond then (ok := false; pr "  ** expectation failed: %s\n" msg) in
  pr "\n== golden: no stalls\n";
  let e, _, _, _ = campaign ~name:"original" ~fetch:fetch_original ~pattern:none ~seeds:1 () in
  need (e = 1) "original exact without stalls";
  let e, _, _, rd = campaign ~core:Rtl_lockstep ~name:"fixed" ~fetch:(fetch_fixed ()) ~pattern:none ~seeds:1 () in
  need (e = 1 && rd = 0) "fixed exact without stalls, RTL agrees";
  pr "\n== latency sweep: every byte after the first d clocks late (the slack of the 24-slot loop)\n";
  let last_exact name fetch =
    let best = ref (-1) in
    List.iter (fun d ->
        let r = run ~fetch ~pattern:(uniform d) ~seed:1 () in
        let v = judge r in
        pr "  %-9s d = %3d: %s\n" name d
          (match v with Exact -> "exact" | Cut_reported k -> Printf.sprintf "cut at half-bit %d, reported" k | Violation m -> "VIOLATION: " ^ m);
        if v = Exact && d > !best then best := d) [ 0; 40; 80; 82; 83; 84; 85; 87; 88; 92; 94; 95; 96; 120 ];
    !best in
  let bo = last_exact "original" fetch_original and bf = last_exact "fixed" (fetch_fixed ()) in
  pr "  largest exact delay: original %d clocks, fixed %d clocks\n" bo bf;
  pr "\n== random stall patterns (seeds 1..N)\n";
  List.iter (fun pattern ->
      let _, _, vo, _ = campaign ~name:"original" ~fetch:fetch_original ~pattern ~seeds:50 () in
      let _, _, vf, rd = campaign ~core:Rtl_lockstep ~name:"fixed" ~fetch:(fetch_fixed ()) ~pattern ~seeds:50 () in
      need (vf = 0 && rd = 0) ("fixed firmware meets the specification under " ^ pattern.pname);
      ignore vo)
    [ bursts 0.01 40; bursts 0.05 120; bursts 0.3 200; one_late ];
  pr "\n== controls (each must be flagged)\n";
  let p = bursts 0.05 120 in
  let _, _, v, _ = campaign ~name:"original" ~fetch:fetch_original ~pattern:p ~seeds:50 () in
  pr "  control original firmware (no underrun path): %s\n" (if v > 0 then "flagged" else "MISSED"); need (v > 0) "control: original flagged";
  let _, _, v, _ = campaign ~name:"no-rel" ~fetch:(fetch_fixed ~plant:No_release ()) ~pattern:p ~seeds:50 () in
  pr "  control fixed firmware without the line release: %s\n" (if v > 0 then "flagged" else "MISSED"); need (v > 0) "control: no release flagged";
  let _, _, v, _ = campaign ~name:"no-rep" ~fetch:(fetch_fixed ~plant:No_report ()) ~pattern:p ~seeds:50 () in
  pr "  control fixed firmware without the underrun report: %s\n" (if v > 0 then "flagged" else "MISSED"); need (v > 0) "control: no report flagged";
  let bad_golden = Array.copy golden in
  bad_golden.(h * 500) <- 1 - bad_golden.(h * 500);
  let v = judge ~golden:bad_golden (run ~fetch:(fetch_fixed ()) ~pattern:none ~seed:1 ()) in
  let flagged = match v with Violation _ -> true | _ -> false in
  pr "  control golden transcript with half-bit 500 flipped, no stalls: %s\n" (if flagged then "flagged" else "MISSED");
  need flagged "control: wrong golden flagged";
  pr "\nETH STALL %s\n" (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
