(* The bench: one or more thread programmes on ISA v2's interpreter (isa2.ml) and on the core's
   RTL (sequencer2.ml, through harness2.ml) in lockstep, with an outside world on the pins.

   Every clock both run with the same inputs, and the bench compares the clock's effects (host
   byte and tag, host ready) and all architectural state of all threads (pc, page, acc, cnt, dl,
   pins, output enables, the quarter-clock view, ...), as ../sequencer-v2/lockstep2.ml does for
   random programmes. The world sees the interpreter's pins; since they must equal the RTL's
   every clock, it sees both.

   Timing at the pins: the world sees the pins after clock c and returns the levels the core reads
   in clock c + 1 (one clock of latency). The combined chip (../chip-top) has three: its pad
   stage shows the core's outputs one clock later, and the core reads samples two clocks old.
   chip_roles.ml in ../chip-top runs the same firmware there. *)

type world = clock:int -> pin_out:int -> pin_oe:int -> int   (* -> pin_in for the next clock *)

(* The host's input FIFO: bytes, each available from a given clock on (to model a slow host). *)
type host = { inq : (int * int) Queue.t; mutable outs : (int * int * int) list (* clock, tag, byte; newest first *) }

let host ?(at = 0) bytes =
  let q = Queue.create () in
  List.iter (fun b -> Queue.push (at, b) q) bytes;
  { inq = q; outs = [] }

let push_host h ~at b = Queue.push (at, b) h.inq

type result = {
  clocks : int;
  levels : Bytes.t;               (* the world's levels (pin_in) per clock, one byte each *)
  outs : (int * int * int) list;  (* host bytes: clock, tag, byte, oldest first *)
  mismatches : int;               (* clocks where interpreter and RTL differ *)
  first_mismatch : string option;
  issues : (int * int * int) list;   (* (clock, thread, word) of every instruction issued, oldest first,
                                         when [record_issues] *)
}

let diff_state (a : Isa2.state) (b : Isa2.state) =
  let d = ref [] in
  let arr n x y = if x <> y then d := n :: !d in
  arr "pc" a.pcs b.pcs; arr "page" a.pages b.pages; arr "acc" a.accs b.accs; arr "cnt" a.cnts b.cnts;
  arr "dl" a.dls b.dls; arr "bp" a.bps b.bps; arr "fine" a.fines b.fines; arr "armed" a.armed b.armed;
  arr "cfg" a.cfgs b.cfgs; arr "lsend" a.lsend b.lsend; arr "inbox" a.inbox b.inbox; arr "full" a.full b.full;
  if a.pin_out <> b.pin_out then d := "pin_out" :: !d;
  if a.pin_oe <> b.pin_oe then d := "pin_oe" :: !d;
  if a.pin_sub <> b.pin_sub then d := "pin_sub" :: !d;
  if a.thread <> b.thread then d := "thread" :: !d;
  if a.latch <> b.latch then d := "latch" :: !d;
  !d

let diff_effects (e : Isa2.effects) (o : Harness2.observed) =
  let d = ref [] in
  if e.host_out <> o.host_out then d := "host_out" :: !d;
  if e.host_in_ready <> o.host_in_ready then d := "host_in_ready" :: !d;
  if e.port_pop <> o.port_pop then d := "port_pop" :: !d;
  if e.port_push <> o.port_push then d := "port_push" :: !d;
  if e.bank_write <> o.bank_write then d := "bank_write" :: !d;
  if e.fine_out <> o.fine_out then d := "fine_out" :: !d;
  !d

(* The store: thread t's page is [pages.(t)] (None: JMP 0, a halted thread). Thread t boots at
   page t, pc 0. *)
let store (pages : int array option array) =
  let s = Array.make Isa2.store_len 0 in
  Array.iteri (fun t p ->
      for pc = 0 to Isa2.page_len - 1 do
        s.((t lsl Isa2.pc_bits) lor pc) <- (match p with Some w -> w.(pc) | None -> if pc = 0 then Isa2.halt_at 0 else 0)
      done) pages;
  s

let boot = Array.init Isa2.n_threads (fun t -> (t, 0))

(* Run for [clocks] (or until [stop ()] holds). [rtl:false] runs the interpreter alone (for
   long sweeps whose lockstep has been shown on the same programmes). *)
let run ?bug ?(rtl = true) ?(record_issues = false) ?(stop = fun () -> false) ~pages ~clocks ~(world : world) (h : host) =
  let mem = store pages in
  let st = Isa2.init ~boot () in
  let s = if rtl then Some (Harness2.make ?bug ~boot mem) else None in
  let levels = Buffer.create (clocks + 1) in
  let pin_in = ref (world ~clock:(-1) ~pin_out:0 ~pin_oe:0) in
  let mism = ref 0 and first = ref None and issues = ref [] in
  let c = ref 0 in
  while !c < clocks && not (stop ()) do
    let clock = !c in
    let host_in, host_in_valid = match Queue.peek_opt h.inq with
      | Some (at, b) when at <= clock -> b, true
      | _ -> 0, false in
    let io = Isa2.io ~host_in ~host_in_valid !pin_in in
    if record_issues then issues := (clock, st.thread, Isa2.fetch st ~mem st.thread) :: !issues;
    let e = Isa2.step st ~mem io in
    (match s with
     | Some s ->
       let o = Harness2.cycle s io in
       let d = diff_effects e o @ diff_state st (Harness2.state s o) in
       if d <> [] then (incr mism; if !first = None then first := Some (Printf.sprintf "clock %d: %s" clock (String.concat "," d)))
     | None -> ());
    if e.host_in_ready then ignore (Queue.pop h.inq);
    (match e.host_out with Some (tag, b) -> h.outs <- (clock, tag, b) :: h.outs | None -> ());
    Buffer.add_char levels (Char.chr (!pin_in land 0xFF));
    pin_in := world ~clock ~pin_out:st.pin_out ~pin_oe:st.pin_oe;
    incr c
  done;
  { clocks = !c; levels = Buffer.to_bytes levels; outs = List.rev h.outs; mismatches = !mism;
    first_mismatch = !first; issues = List.rev !issues }

let level (r : result) c p = (Char.code (Bytes.get r.levels c) lsr p) land 1

(* the transitions of pin [p]: (clock, new level) *)
let edges (r : result) p =
  let out = ref [] in
  for c = 1 to r.clocks - 1 do
    let v = level r c p in
    if v <> level r (c - 1) p then out := (c, v) :: !out
  done;
  List.rev !out

(* The default world for push-pull outputs: each pin reads what the core drives, or [idle]
   where it does not drive. *)
let driven ?(idle = 0xFF) ~pin_out ~pin_oe () = (pin_out land pin_oe) lor (idle land lnot pin_oe)

(* Write [r]'s levels as a trace for tools/sigrok-judge: one byte per clock, bit p = pin p, and
   the .expected file with [lines]. *)
let dump_trace ~dir ~stem ?(from = 0) ?upto (r : result) lines =
  let upto = Option.value upto ~default:r.clocks in
  let oc = open_out_bin (Filename.concat dir (stem ^ ".bin")) in
  output_bytes oc (Bytes.sub r.levels from (upto - from));
  close_out oc;
  let oc = open_out (Filename.concat dir (stem ^ ".expected")) in
  Printf.fprintf oc "# samplerate 60000000 (one sample per core clock at 60 MHz); from prototypes/protocol-roles\n";
  List.iter (fun (k, v) -> Printf.fprintf oc "%s %s\n" k v) lines;
  close_out oc
