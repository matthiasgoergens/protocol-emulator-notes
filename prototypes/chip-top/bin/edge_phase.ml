(* The edge-phase test: in which half of the clock each input pad is sampled, and on which edge
   each general output pad's quarter-2 lane toggles, observed through the chip's own functions
   rather than read off the netlist's clock tree.

   Why it is needed. The hardened chip runs the four-phase stage on both clock edges (README,
   "Phases"): per input pad, the quarter-0/1 samples are taken on the rising edge E_j and the
   quarter-2/3 samples on the falling edge F_j, each through a two-flop synchroniser and a
   retiming flop on the rising edge. The random host traffic of gate_lockstep.ml does not notice
   a quarter-2 sampler moved to the rising edge: the host link's two-clock margins absorb the
   half-clock shift, and random programmes do not look at quarters.

   How it observes the sampling instant. Each pad under test toggles at most once per clock, at
   random either in the first half (+T/4: between E_j and F_j) or in the second half (+3T/4: between
   F_j and E_j+1), or not at all. Four threads loop on SHI quad, which shifts a logical pin's four
   quarter samples into the accumulator, two pins per thread, and store a byte per 16 clocks in
   the data bank (stopped, the host reads the bank back). The nibble a thread stores for a pad is
   rev4 (q0 q1 q2 q3). For each pad the test then asks, of the sample instants
   - q0/q1 at E_j (the rising edge), F_j-1 or F_j, and
   - q2/q3 at E_j, F_j (the falling edge) or E_j+1,
   which combinations reproduce every stored nibble for some alignment between the threads'
   clocks and the pad log. The design must fit (E_j, F_j) and nothing else. A first-stage sampler
   moved to the rising edge samples quarter 2 at E_j+1 and fits (E_j, E_j+1) instead. This check
   is absolute: it reads the stored bytes against the pad schedule, not against a reference.

   Outputs: every general output pad (0-7, uio 6, 7) is then switched to the pin NCO's quarter or
   half grid, whose edges fall on quarter 2, and the test counts the pin changes seen after
   falling edges. Lane 2 is the only lane on the falling edge, so each pin must change after
   falling edges as well as after rising ones; a lane-2 toggle moved to the rising edge leaves
   its pin with no falling-edge changes.

   Every half clock the outputs are also compared with a second simulator (differential).

   The host-link pads are tested too: the data lines while the strobe is still, and the strobe
   and read request with the data lines held at 0, so that a strobe change moves a 0 nibble,
   which the parser ignores (op 0), and a change of the read request resets the nibble phase; a
   pulse on the read request at the end resynchronises the link.

     edge_phase.exe rtl SIZES [STIM]          the two-part Hardcaml reference (Twoedge.Ref2); STIM:
                                              also write the per-half-clock stimulus for iverilog
     edge_phase.exe replay SIZES STIM TRACE   the outputs of an iverilog run of STIM (TRACE), with
                                              the reference compared
     edge_phase.exe gates GDS MODELS SIZES [fall2rise:K ...|all]
                                              the extracted gates, the reference compared (with
                                              EDGE_PHASE_FFS=FILE, every flip-flop's number of
                                              output changes for sim/gate_cov.py); "all"
                                              plants every falling-edge flip-flop on the rising
                                              edge in turn
     edge_phase.exe structure GDS MODELS [K ...|all]
                                              the structural rule for the input synchronisers
                                              ([structure]), with falling-edge flop K moved
     edge_phase.exe prove                     exhaustive check of the input synchroniser with each
                                              of its falling-edge flops moved (see [prove]) *)

open Twoedge

let n_pads = Regs.n_pads
let pr = Printf.printf

(* ---- the devices under test ---- *)

type dut = {
  name : string;
  rise : rst_n:int -> pads:int -> unit;
  fall : pads:int -> unit;
  outputs : unit -> int;   (* uo_out | uio_out << 8 | uio_oe << 16 *)
}

let ref2_dut cfg =
  let rf = Ref2.create cfg in
  { name = "RTL"; rise = (fun ~rst_n ~pads -> Ref2.rise rf ~rst_n ~pads ~en:0b0011);
    fall = (fun ~pads -> Ref2.fall rf ~pads); outputs = (fun () -> Ref2.outputs rf) }

(* [changes]: per flip-flop, how often its output changed (for gate_cov.py) *)
let gates_dut ?changes (g : Gates.t) =
  Gates.reset g;
  let rst = ref 0 in
  let prev = Array.make (Array.length g.sim.ffs) 0 in
  let count () =
    Option.iter (fun ch ->
        Array.iteri (fun i (f : Sim.ff) -> let q = g.sim.v.(f.q) in if q <> prev.(i) then (ch.(i) <- ch.(i) + 1; prev.(i) <- q)) g.sim.ffs)
      changes in
  { name = "gates";
    rise = (fun ~rst_n ~pads -> rst := rst_n; Gates.set g ~rst_n ~pads; Sim.edge g.sim ~fall:false; count ());
    fall = (fun ~pads -> Gates.set g ~rst_n:!rst ~pads; Sim.edge g.sim ~fall:true; count ());
    outputs = (fun () -> Gates.outputs g) }

(* the outputs an event-driven simulation wrote, one hexadecimal word per half clock *)
(* An event-driven simulation starts with unknown (x) flip-flops; the reset synchroniser makes the
   outputs known after two clocks. Unknown digits read as 0 (what the other simulators start
   with) and are counted, with the last half clock that had one, which must lie in the reset. *)
let x_halves = ref 0 and x_last = ref (-1)

let replay_dut trace =
  let ic = open_in trace in
  let cur = ref 0 and halves = ref 0 in
  let next () =
    match input_line ic with
    | l ->
      let l = String.trim l in
      if String.exists (fun c -> c = 'x' || c = 'z' || c = 'X' || c = 'Z') l then (incr x_halves; x_last := !halves);
      cur := int_of_string ("0x" ^ String.map (fun c -> match c with 'x' | 'z' | 'X' | 'Z' -> '0' | c -> c) l);
      incr halves
    | exception End_of_file -> failwith "replay: trace too short" in
  { name = "iverilog"; rise = (fun ~rst_n:_ ~pads:_ -> next ()); fall = (fun ~pads:_ -> next ()); outputs = (fun () -> !cur) }

(* ---- the test ---- *)

let n_bytes = 24                 (* bytes per thread and run: 24 SHI quad samples per pin *)
let window = (16 * n_bytes) + 160
let prog_page_words = 8

(* The runs: the eight pads the logical pins 0-7 read; thread t samples pins 2t and 2t+1. *)
let runs = [| [| 0; 1; 2; 3; 4; 5; 6; 7 |]; [| 8; 9; 10; 11; 14; 15; 0; 1 |]; [| 12; 13; 2; 3; 4; 5; 6; 7 |] |]
let strobe_run = 2

let thread_code ~run t =
  let base = prog_page_words * t in
  [ Isa2.lda (64 * run); Isa2.bank t; Isa2.ldc (2 * n_bytes);
    Isa2.shi ~quad:1 ~pin:(2 * t) ~msb:1 (); Isa2.shi ~quad:1 ~pin:((2 * t) + 1) ~msb:1 (); Isa2.stb;
    Isa2.jnz (base + 3); Isa2.jmp (base + 7) ]

let words_bytes ws = List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) ws

type result = {
  mutable mism : int;                 (* half clocks where the compared simulator differed *)
  mutable first_mism : string list;
  fits : (int * string list * int) list;   (* pad, fitting hypotheses, alignments of the design's *)
  pin_edges : (int * int * int) list;      (* output pad, changes after rising, after falling edges *)
  input_ok : bool;
  output_ok : bool;
}

let q0_hyps = [| "E"; "F-1"; "F" |]
let q2_hyps = [| "E"; "F"; "E+1" |]

(* [primary] drives the host's reads and the chip-driven data lines; [others] are compared with
   it every half clock. [stim]: write the per-half-clock stimulus. *)
let run_test ?stim ~seed (primary : dut) (others : dut list) =
  let host = Host.create () in
  let nclk = 60_000 in
  let log_r = Array.make nclk 0 and log_f = Array.make nclk 0 in
  let clock = ref 0 in
  let read_bytes = Hashtbl.create 16 in
  let window_run = ref (-1) and window_left = ref 0 and cleanup = ref 0 in
  let sched_rng = ref (Random.State.make [| seed |]) in
  let level = Array.make n_pads 0 in   (* the test's levels of the pads under test *)
  let out_mode = ref false in
  let pin_rise = Array.make n_pads 0 and pin_fall = Array.make n_pads 0 in
  let w a d = Host.submit host (Host.Write { tgt = Regs.t_reg; addr = a; data = d }) in
  (* the transactions *)
  let prog = List.concat (List.init 4 (fun t -> thread_code ~run:0 t)) in
  w Regs.r_ctrl [ 2 ];
  Host.submit host (Host.Write { tgt = Regs.t_prog; addr = 0; data = words_bytes prog });
  w (Regs.r_boot_pc 0) (List.init 4 (fun t -> prog_page_words * t) @ [ 0 ]);
  Array.iteri (fun run pads ->
      if run > 0 then
        for t = 0 to 3 do
          Host.submit host (Host.Write { tgt = Regs.t_prog; addr = 2 * prog_page_words * t; data = words_bytes [ Isa2.lda (64 * run) ] })
        done;
      w (Regs.r_pinin 0) (Array.to_list pads);
      w Regs.r_ctrl [ 1 ];
      Host.submit host (Host.Call (fun () ->
          window_run := run; window_left := window;
          sched_rng := Random.State.make [| seed; run |];
          Array.iter (fun p -> level.(p) <- (match p with 12 -> host.s | 13 -> host.r | p when p >= 8 && p < 12 -> 0 | _ -> level.(p))) pads));
      Host.submit host (Host.Idle (window + 24));
      w Regs.r_ctrl [ 0 ])
    runs;
  (* read the bank back *)
  Array.iteri (fun run _ ->
      for t = 0 to 3 do
        Host.submit host (Host.Read { tgt = Regs.t_bank; addr = (256 * t) + (64 * run); n = n_bytes;
                                      k = (fun l -> Hashtbl.replace read_bytes (run, t) l) })
      done)
    runs;
  (* the outputs: every general output pad on the NCO's quarter or half grid *)
  Host.wreg32 host Regs.r_nco_inc 0x2B3C4D5F;
  List.iteri (fun i p -> w (Regs.r_padsel p) [ (if i mod 2 = 0 then Regs.src_nco_quarter else Regs.src_nco_half) ]) Regs.general_out_pads;
  w Regs.r_ctrl [ 0 ];
  Host.submit host (Host.Call (fun () -> out_mode := true));
  Host.submit host (Host.Idle 400);
  Host.submit host (Host.Call (fun () -> out_mode := false));
  (* the clocks *)
  let mism = ref 0 and first = ref [] in
  let prev_out = ref 0 in
  let soc = Option.map open_out stim in
  (* Not compared: the first two clocks, before the reset synchroniser has been clocked twice;
     an event-driven simulation starts with unknown flip-flops there (Cyclesim and the gate
     simulator start at 0). *)
  let compare half =
    let want = primary.outputs () in
    if !clock >= 2 then List.iter (fun d ->
        let got = d.outputs () in
        if got <> want then begin
          incr mism;
          if List.length !first < 8 then
            first := Printf.sprintf "clock %d %s: %s %06x, %s %06x" !clock half d.name got primary.name want :: !first
        end) others;
    if !out_mode then
      List.iter (fun p ->
          if ((want lxor !prev_out) lsr p) land 1 = 1 then
            if half = "rise" then pin_rise.(p) <- pin_rise.(p) + 1 else pin_fall.(p) <- pin_fall.(p) + 1)
        Regs.general_out_pads;
    prev_out := want in
  let emit edge rst_n pads dchip =
    Option.iter (fun oc -> Printf.fprintf oc "%d %d %04x %d\n" (if edge = 'r' then 1 else 0) rst_n pads (if dchip then 1 else 0)) soc in
  let finished () = Host.idle host in
  let ui = ref 0x5A in
  while not (finished ()) || !clock < 8 do
    if !clock >= nclk then failwith "edge_phase: out of clocks";
    let rst_n = if !clock < 4 then 0 else 1 in
    let s, r, d = if rst_n = 0 then (0, 0, None) else Host.clock host ~d_in:((!prev_out lsr 8) land 15) in
    (* this clock's toggle choices for the pads under test: 0 none, 1 first half, 2 second half *)
    let in_window = !window_run >= 0 && !window_left > 0 in
    let pads_under = if in_window then runs.(!window_run) else [||] in
    let choice = Array.make n_pads 0 in
    if in_window then begin
      Array.iter (fun p -> choice.(p) <- Random.State.int !sched_rng 3) pads_under;
      decr window_left;
      if !window_left = 0 && !window_run = strobe_run then cleanup := 16
    end;
    let strobe_test = (in_window && !window_run = strobe_run) || !cleanup > 0 in
    let dval_host = match d with Some v -> Some v | None -> None in
    (* pads as the host and the outside world drive them; the test's levels override *)
    let pads_now () =
      let p = ref (!ui lor ((s lsl 4) lor (r lsl 5)) lsl 8) in
      let dchip = ref false in
      (match dval_host with
       | Some v -> p := !p lor (v lsl 8)
       | None -> dchip := true; p := !p lor (((!prev_out lsr 8) land 15) lsl 8));
      if strobe_test then begin
        (* data lines held at 0 by the test; strobe and read request from the test's levels *)
        p := !p land lnot (0x3F lsl 8);
        dchip := false;
        if !cleanup > 0 then p := !p lor (host.s lsl 12) lor ((if !cleanup > 12 then 1 else 0) lsl 13)
        else p := !p lor (level.(12) lsl 12) lor (level.(13) lsl 13)
      end;
      Array.iter (fun q ->
          if not (strobe_test && (q = 12 || q = 13)) then begin
            if q >= 8 && q < 12 then dchip := false;
            p := (!p land lnot (1 lsl q)) lor (level.(q) lsl q)
          end) pads_under;
      (!p, !dchip) in
    (* the outside world: ui_in pads not under test change now and then, between the edges too *)
    let wiggle () = if Random.State.int !sched_rng 8 = 0 then ui := !ui lxor (1 lsl Random.State.int !sched_rng 8) in
    let pads_r, dchip_r = pads_now () in
    emit 'r' rst_n pads_r dchip_r;
    log_r.(!clock) <- pads_r;
    primary.rise ~rst_n ~pads:pads_r;
    List.iter (fun d -> d.rise ~rst_n ~pads:pads_r) others;
    compare "rise";
    Array.iter (fun q -> if choice.(q) = 1 then level.(q) <- 1 - level.(q)) pads_under;
    if not in_window then wiggle ();
    let pads_f, dchip_f = pads_now () in
    emit 'f' rst_n pads_f dchip_f;
    log_f.(!clock) <- pads_f;
    primary.fall ~pads:pads_f;
    List.iter (fun d -> d.fall ~pads:pads_f) others;
    compare "fall";
    Array.iter (fun q -> if choice.(q) = 2 then level.(q) <- 1 - level.(q)) pads_under;
    if !cleanup > 0 then decr cleanup;
    incr clock
  done;
  Option.iter close_out soc;
  let total = !clock in
  (* ---- the absolute check of the inputs ---- *)
  let bitp v p = (v lsr p) land 1 in
  let q0_at h m p = match h with 0 -> bitp log_r.(m) p | 1 -> bitp log_f.(m - 1) p | _ -> bitp log_f.(m) p in
  let q2_at h m p = match h with 0 -> bitp log_r.(m) p | 1 -> bitp log_f.(m) p | _ -> bitp log_r.(m + 1) p in
  let fits = ref [] and input_ok = ref true in
  Array.iteri (fun run pads ->
      for t = 0 to 3 do
        let bytes = Array.of_list (Option.value (Hashtbl.find_opt read_bytes (run, t)) ~default:[]) in
        if Array.length bytes <> n_bytes then (input_ok := false; pr "  run %d thread %d: %d bytes read\n" run t (Array.length bytes))
        else
          List.iter (fun (pin, shift, off) ->
              let pad = pads.(pin) in
              let nib k = (bytes.(k) lsr shift) land 15 in
              let fit_bases h0 h2 =
                let l = ref [] in
                for base = 1 to total - (16 * n_bytes) - 8 do
                  let ok = ref true and k = ref 0 in
                  while !ok && !k < n_bytes do
                    let m = base + (16 * !k) + off in
                    if nib !k <> (12 * q0_at h0 m pad) + (3 * q2_at h2 m pad) then ok := false;
                    incr k
                  done;
                  if !ok then l := base :: !l
                done;
                !l in
              let hyps = ref [] and design = ref 0 in
              for h0 = 0 to 2 do
                for h2 = 0 to 2 do
                  let b = fit_bases h0 h2 in
                  if b <> [] then hyps := Printf.sprintf "(q0 at %s, q2 at %s)" q0_hyps.(h0) q2_hyps.(h2) :: !hyps;
                  if h0 = 0 && h2 = 1 then design := List.length b
                done
              done;
              let hyps = List.rev !hyps in
              if hyps <> [ "(q0 at E, q2 at F)" ] then input_ok := false;
              fits := (pad, hyps, !design) :: !fits)
            [ (2 * t, 4, 0); ((2 * t) + 1, 0, 4) ]
      done)
    runs;
  let pin_edges = List.map (fun p -> (p, pin_rise.(p), pin_fall.(p))) Regs.general_out_pads in
  let output_ok = List.for_all (fun (_, r, f) -> r > 0 && f > 0) pin_edges in
  ({ mism = !mism; first_mism = List.rev !first; fits = List.rev !fits; pin_edges; input_ok = !input_ok; output_ok }, total)

let print_result ~verbose (r, total) =
  pr "%d clocks; compared simulator: %d half clocks differ\n" total r.mism;
  List.iter (pr "  %s\n") r.first_mism;
  if verbose then begin
    pr "inputs: for each pad and run, the sample instants that reproduce every stored nibble (alignments of the design's)\n";
    List.iter (fun (pad, hyps, n) ->
        pr "  pad %2d: %s  [%d]\n" pad (if hyps = [] then "none" else String.concat " " hyps) n) r.fits;
    pr "outputs: pin changes after rising / falling edges with the NCO grids on every general pad\n";
    List.iter (fun (p, a, b) -> pr "  pad %2d: %d / %d\n" p a b) r.pin_edges
  end;
  pr "inputs: %s; outputs: %s\n%!"
    (if r.input_ok then "every pad sampled at (E, F) and only there" else "FAIL")
    (if r.output_ok then "every general pin changes after falling edges" else "FAIL")

(* ---- the exhaustive check of the input synchroniser ----

   One pad's quarter-2 path: s on F (samples the pad), r on F (samples s), t on E (samples r),
   each with the synchronous clear (D gated by the reset, which changes on E only). The core
   reads t after E. Variants: s on E, r on E. The product of the design and a variant, from every
   common start state, under every input sequence (pad level at E, pad level at F, reset), is
   explored to a fixed point; a variant is equivalent iff t agrees in every reachable state. *)
let prove () =
  let step ~s_rise ~r_rise (s, r, _t) (pe, pf, rst) =
    let clr x = if rst = 1 then 0 else x in
    (* the rising edge: flops on E sample, all at once *)
    let s1 = if s_rise then clr pe else s and r1 = if r_rise then clr s else r and t1 = clr r in
    (* the falling edge *)
    let s2 = if s_rise then s1 else clr pf and r2 = if r_rise then r1 else clr s1 in
    (s2, r2, t1) in
  let variant ~s_rise ~r_rise name =
    let seen = Hashtbl.create 64 and q = Queue.create () and bad = ref None in
    for x = 0 to 7 do
      let st = ((x lsr 2) land 1, (x lsr 1) land 1, x land 1) in
      Hashtbl.replace seen (st, st) (); Queue.push (st, st) q
    done;
    while not (Queue.is_empty q) do
      let a, b = Queue.pop q in
      for i = 0 to 7 do
        let inp = ((i lsr 2) land 1, (i lsr 1) land 1, i land 1) in
        let a' = step ~s_rise:false ~r_rise:false a inp and b' = step ~s_rise ~r_rise b inp in
        let (_, _, ta), (_, _, tb) = (a', b') in
        if ta <> tb && !bad = None then bad := Some i;
        if not (Hashtbl.mem seen (a', b')) then (Hashtbl.replace seen (a', b') (); Queue.push (a', b') q)
      done
    done;
    pr "%-40s %3d reachable product states: %s\n" name (Hashtbl.length seen)
      (match !bad with None -> "equivalent (t agrees in every reachable state)" | Some _ -> "DIFFERS (distinguishable by some input sequence)") in
  variant ~s_rise:false ~r_rise:true "second stage (r) on the rising edge";
  variant ~s_rise:true ~r_rise:false "first stage (s) on the rising edge";
  variant ~s_rise:true ~r_rise:true "both on the rising edge"

(* ---- the structural rule for the input synchronisers ----

   The second synchroniser stage's edge cannot be observed (see [prove]): moving it is a
   functionally equivalent change. So this rule pins it from the netlist: for every input pad,
   the flip-flops whose D depends on the pad within 12 gates (buffers and hold-fixing delay cells included; the first stage) include a
   rising-edge one (quarters 0-1) and a falling-edge one (quarters 2-3); every flip-flop fed by a
   falling first-stage flop is on the falling edge (the second stage), and every flip-flop fed by
   one of those, or by a rising first-stage flop, is on the rising edge (the retiming flop and
   the rising path's second stage). Returns the violations and the counts. *)
let structure (g : Gates.t) =
  let sim = g.sim in
  let driver = Hashtbl.create 65536 in
  Array.iter (fun (gt : Sim.gate) -> Hashtbl.replace driver gt.out gt) sim.gates;
  let q_of = Hashtbl.create 4096 in
  Array.iteri (fun i (f : Sim.ff) -> Hashtbl.replace q_of f.q i) sim.ffs;
  let pad_of = Hashtbl.create 16 in
  Array.iteri (fun p s -> Hashtbl.replace pad_of s p) g.ins;
  (* the pads and flip-flops a signal depends on within [depth] gates *)
  let rec support s depth acc =
    match Hashtbl.find_opt q_of s, Hashtbl.find_opt pad_of s with
    | Some i, _ -> `Ff i :: acc
    | None, Some p -> `Pad p :: acc
    | None, None ->
      if depth = 0 then acc
      else match Hashtbl.find_opt driver s with
        | Some gt -> Array.fold_left (fun a x -> support x (depth - 1) a) acc gt.ins
        | None -> acc in
  let n = Array.length sim.ffs in
  let sup = Array.init n (fun i -> support sim.ffs.(i).d 12 []) in
  let fed_by i = List.filter (fun j -> List.mem (`Ff i) sup.(j)) (List.init n Fun.id) in
  let fall i = sim.ff_fall.(i) in
  let bad = ref [] and n1 = ref 0 and n2 = ref 0 in
  let name i = sim.ffs.(i).owner in
  for p = 0 to n_pads - 1 do
    let first = List.filter (fun i -> List.mem (`Pad p) sup.(i)) (List.init n Fun.id) in
    let f1 = List.filter fall first and r1 = List.filter (fun i -> not (fall i)) first in
    n1 := !n1 + List.length f1;
    if f1 = [] then bad := Printf.sprintf "pad %d: no falling-edge first-stage flip-flop" p :: !bad;
    if r1 = [] then bad := Printf.sprintf "pad %d: no rising-edge first-stage flip-flop" p :: !bad;
    List.iter (fun i ->
        let second = fed_by i in
        if second = [] then bad := Printf.sprintf "pad %d: %s feeds no flip-flop" p (name i) :: !bad;
        List.iter (fun j ->
            if fall j then incr n2 else bad := Printf.sprintf "pad %d: second stage %s (after %s) is on the rising edge" p (name j) (name i) :: !bad;
            List.iter (fun k -> if fall k then bad := Printf.sprintf "pad %d: retiming %s is on the falling edge" p (name k) :: !bad) (fed_by j))
          second)
      f1;
    List.iter (fun i -> List.iter (fun j -> if fall j then bad := Printf.sprintf "pad %d: %s, after the rising first stage, is on the falling edge" p (name j) :: !bad) (fed_by i)) r1
  done;
  (List.rev !bad, !n1, !n2)

let print_structure (bad, n1, n2) =
  pr "structure: %d falling first-stage and %d falling second-stage input flip-flops; %s\n%!" n1 n2
    (if bad = [] then "the rule holds" else Printf.sprintf "%d violations: %s" (List.length bad) (String.concat "; " bad))

(* ---- main ---- *)

let cfg_of sizes =
  let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' sizes)) in
  { Chip_spec.layout = Upe.Spec.layout_of_sizes sizes; prog_words = 512 }

let () =
  Chip_rtl.bug := "";
  let seed = 11 in
  match List.tl (Array.to_list Sys.argv) with
  | [ "prove" ] -> prove ()
  | "rtl" :: sizes :: stim ->
    let cfg = cfg_of sizes in
    let res = run_test ?stim:(match stim with [ f ] -> Some f | _ -> None) ~seed (ref2_dut cfg) [] in
    print_result ~verbose:true res;
    exit (if (fst res).input_ok && (fst res).output_ok then 0 else 1)
  | [ "replay"; sizes; _stim; trace ] ->
    let cfg = cfg_of sizes in
    let res = run_test ~seed (replay_dut trace) [ ref2_dut cfg ] in
    print_result ~verbose:true res;
    (* the reset is held for the first 4 clocks, 8 half clocks *)
    pr "half clocks with unknown outputs: %d, the last at half clock %d (%s)\n" !x_halves !x_last
      (if !x_last < 8 then "inside the reset" else "AFTER THE RESET");
    exit (if (fst res).input_ok && (fst res).output_ok && (fst res).mism = 0 && !x_last < 8 then 0 else 1)
  | "structure" :: gds :: models :: plants ->
    (* the structural rule alone, on the design and with each falling-edge flip-flop moved *)
    let g = Gates.create ~gds ~models in
    print_structure (structure g);
    let falls = List.filter (fun i -> g.sim.ff_fall.(i)) (List.init (Array.length g.sim.ffs) Fun.id) in
    let ks = if plants = [ "all" ] then List.init (List.length falls) Fun.id else List.map int_of_string plants in
    let caught = ref 0 in
    List.iter (fun k ->
        let i = List.nth falls k in
        g.sim.ff_fall.(i) <- false;
        let (sb, _, _) = structure g in
        g.sim.ff_fall.(i) <- true;
        if sb <> [] then incr caught;
        pr "plant fall2rise:%d %s: %s\n%!" k g.sim.ffs.(i).owner (if sb = [] then "rule holds" else "rule violated: " ^ String.concat "; " sb))
      ks;
    if ks <> [] then pr "%d of %d plants violate the structural rule\n" !caught (List.length ks)
  | "gates" :: gds :: models :: sizes :: plants ->
    let cfg = cfg_of sizes in
    let g = Gates.create ~gds ~models in
    let falls = List.filter (fun i -> g.sim.ff_fall.(i)) (List.init (Array.length g.sim.ffs) Fun.id) in
    let ks = match plants with
      | [ "all" ] -> List.init (List.length falls) Fun.id
      | l -> List.map (fun p -> match String.split_on_char ':' p with [ "fall2rise"; k ] -> int_of_string k | _ -> failwith p) l in
    let st = structure g in
    print_structure st;
    let (sbad, _, _) = st in
    if ks = [] then begin
      let changes = Array.make (Array.length g.sim.ffs) 0 in
      let res = run_test ~seed (gates_dut ~changes g) [ ref2_dut cfg ] in
      print_result ~verbose:true res;
      Option.iter (fun file ->
          let oc = open_out file in
          Array.iteri (fun i (f : Sim.ff) -> Printf.fprintf oc "%s %s %d\n" f.owner (if g.sim.ff_fall.(i) then "falling" else "rising") changes.(i)) g.sim.ffs;
          close_out oc)
        (Sys.getenv_opt "EDGE_PHASE_FFS");
      exit (if (fst res).input_ok && (fst res).output_ok && (fst res).mism = 0 && sbad = [] then 0 else 1)
    end else begin
      let caught = ref 0 and caught_any = ref 0 in
      List.iter (fun k ->
          let i = List.nth falls k in
          g.sim.ff_fall.(i) <- false;
          let r, _ = run_test ~seed (gates_dut g) [ ref2_dut cfg ] in
          let (sb, _, _) = structure g in
          g.sim.ff_fall.(i) <- true;
          let bad_pads = List.filter_map (fun (pad, h, _) -> if h <> [ "(q0 at E, q2 at F)" ] then Some (Printf.sprintf "%d:%s" pad (String.concat "" h)) else None) r.fits in
          let bad_pins = List.filter_map (fun (p, _, f) -> if f = 0 then Some (string_of_int p) else None) r.pin_edges in
          let c = r.mism > 0 || not r.input_ok || not r.output_ok in
          if c then incr caught;
          if c || sb <> [] then incr caught_any;
          pr "plant fall2rise:%d %s: %s by behaviour; differential %d half clocks; absolute: inputs %s, outputs %s; structural rule: %s\n%!" k g.sim.ffs.(i).owner
            (if c then "caught" else "MISSED") r.mism
            (if r.input_ok then "ok" else "pads " ^ String.concat " " bad_pads)
            (if r.output_ok then "ok" else "no falling-edge changes on pads " ^ String.concat " " bad_pins)
            (if sb = [] then "holds" else "violated (" ^ String.concat "; " sb ^ ")"))
        ks;
      pr "%d of %d plants caught by behaviour, %d by behaviour or the structural rule\n" !caught (List.length ks) !caught_any
    end
  | _ ->
    prerr_endline "usage: edge_phase.exe rtl SIZES [STIM] | replay SIZES STIM TRACE | gates GDS MODELS SIZES [fall2rise:K ...|all] | prove";
    exit 2
