(* The runner: an image on the ISA v2 interpreter, and on the chip (its executable specification
   and its RTL in lockstep), with the outside world on the pins.

   The board, in both modes, is the chip-top board (../../prototypes/chip-top/src/board.ml): a
   level the core puts out in clock k is on the pin during clock k + 1 and the core sees a pin
   sampled in clock k in clock k + 2. The ISA mode builds the same pipeline around the
   interpreter, so for the same peers the two modes put the same levels on the nets clock for
   clock from the start of the run, which [compare] checks.

   Nets. A net is one logical pin (0-7) of the sequencer as a wire on the board. On the chip, net
   k is driven by the output pad whose source select is sequencer pin k (open-drain on uio[6] and
   uio[7], whose enable is the pin's; push-pull elsewhere, where an undriven pin shows the pad's
   "undriven" level), and net k is what the input pad of logical pin k (.pinin) reads. On the
   interpreter, net k is pin k with its output enable. Both read the pin map from the image. *)

open Regs

type mode = Isa | Chip of { rtl : bool }

type opts = {
  clocks : int;                 (* clocks to run after the start *)
  peers : Peers.t list;
  hostin : int list;            (* bytes the host sends to the threads' IN during the run *)
  prog_words : int;
}

let default_opts = { clocks = 10_000; peers = []; hostin = []; prog_words = 1024 }

type result = {
  mode : mode;
  trace : Wave.trace;
  received : (int * int) list;             (* (tag, byte) the host read from HOSTOUT, or OUT on the interpreter *)
  port_pushes : (int * int * int) list;    (* interpreter: (clock, port, byte) of SENDs to ports *)
  run_start : int;                         (* chip clock of the run's first clock (0 on the interpreter) *)
  agree : bool option;                     (* chip with RTL: specification and RTL equal on every pad, every clock *)
  first_diff : int option;
  log : string list;
}

let rep4 = Peers.rep4
let bit v i = (v lsr i) land 1

(* resolve the nets: the chip's drive (nibble, enabled) per net, and the peers' drives *)
let resolve ~(chip : (int * bool) array) ~clock (peers : Peers.t list) =
  let nets = Array.map (fun (nib, oe) -> if oe then nib else 15) chip in
  List.iter (fun (p : Peers.t) -> List.iter (fun (n, nib) -> nets.(n) <- nets.(n) land nib) (p.drive ~clock)) peers;
  List.iter (fun (p : Peers.t) -> p.observe ~clock nets) peers;
  nets

let isa_io ~(seen : int array) ~host =
  let pin_in = Array.fold_left ( lor ) 0 (Array.mapi (fun k nib -> bit nib 3 lsl k) seen) in
  let pin_in4 = Array.fold_left ( lor ) 0 (Array.mapi (fun k nib -> nib lsl (4 * k)) seen) in
  Isa2.io ~pin_in4 ~host_in:(Option.value ~default:0 host) ~host_in_valid:(host <> None)
    ~port_out_ready:(Array.make 4 true) pin_in

(* ---- the pin map ---- *)

let reg_of (img : Image.t) a = match Image.reg img a with Some v -> v | None -> reset_value a

(* net k's output pad and input pad. The output pad is the pad that both shows sequencer pin k
   and is pin k's input pad (a bidirectional uio pin, as I2C needs), else the first general pad
   showing pin k. *)
let pin_map (img : Image.t) =
  let in_pad k = reg_of img (r_pinin k) land 15 in
  let out_pad k =
    let shows = List.filter (fun p -> reg_of img (r_padsel p) land 31 = src_seq k) general_out_pads in
    if List.mem (in_pad k) shows then Some (in_pad k) else List.nth_opt shows 0 in
  Array.init 8 (fun k -> (out_pad k, in_pad k))

(* What net k shows when sequencer pin k has quarter levels [nib] and enable [oe], as the chip's
   pad stage makes it (chip_spec.ml, [outputs]): a push-pull pad (0-7) always drives, the pin's
   level when enabled and the pad's undriven level otherwise; a uio pad drives only when the pin
   is enabled; the invert bit inverts the pin's level. A pin no pad shows is not on the board. *)
let pad_view (img : Image.t) =
  let map = pin_map img in
  fun k nib oe ->
    match fst map.(k) with
    | None -> (15, false)
    | Some p ->
      let sel = reg_of img (r_padsel p) in
      let nib = if bit sel 5 = 1 then nib lxor 15 else nib in
      if p < 8 then ((if oe then nib else rep4 (bit sel 6)), true) else (nib, oe)

(* ---- the interpreter ---- *)

let run_isa (img : Image.t) o =
  let bank = Array.make Isa2.bank_len 0 in
  List.iter (fun (a, v) -> bank.(a) <- v) img.bank;
  let st = Isa2.init ~boot:(Image.boot img) ~bank () in
  let mem = Image.store ~words:o.prog_words img in
  let hostq = Queue.create () in
  List.iter (fun b -> Queue.push b hostq) (img.hostin @ o.hostin);
  (* the pins as the board sees them through the image's pin map (see [pad_view]) *)
  let view = pad_view img in
  let outs_of (s : Isa2.state) = Array.init 8 (fun k -> view k ((s.pin_sub lsr (4 * k)) land 15) (bit s.pin_oe k = 1)) in
  let visible = ref (outs_of st) and pipe = Queue.create () in
  let nets = Array.make o.clocks [||] and pcs = Array.make o.clocks [||] in
  let outs = ref [] and received = ref [] and pushes = ref [] in
  for c = -2 to o.clocks - 1 do
    let out_now = outs_of st in
    let w = resolve ~chip:!visible ~clock:c o.peers in
    Queue.push w pipe;
    if c >= 0 then begin
      nets.(c) <- w;
      pcs.(c) <- Array.init 4 (fun t -> (st.pages.(t) lsl 8) lor st.pcs.(t));
      let seen = Queue.pop pipe in
      let e = Isa2.step st ~mem (isa_io ~seen ~host:(Queue.peek_opt hostq)) in
      if e.host_in_ready then ignore (Queue.pop hostq);
      (match e.host_out with Some (tag, b) -> outs := (c, tag, b) :: !outs; received := (tag, b) :: !received | None -> ());
      (match e.port_push with Some (p, b) -> pushes := (c, p, b) :: !pushes | None -> ())
    end;
    visible := out_now
  done;
  { mode = Isa;
    trace = { Wave.t0 = 0; nets; pcs; outs = List.rev !outs; clock_hz = 60_000_000 };
    received = List.rev !received; port_pushes = List.rev !pushes; run_start = 0; agree = None; first_diff = None;
    log = [] }

(* ---- the chip ---- *)

let chip_drive map (out : Chip_spec.outputs) =
  Array.map (fun (op, _) -> match op with
      | None -> (15, false)
      | Some p -> (out.pad_nib.(p), if p >= 8 then bit out.uio_oe (p - 8) = 1 else true)) map

(* load the image through the host link, then poll HOSTOUT and feed HOSTIN *)
let host_program (h : Host.t) (img : Image.t) ~hostin ~received =
  List.iter (fun (tgt, addr, data) -> Host.submit h (Host.Write { tgt; addr; data })) (Image.commands (Image.bytes img));
  let pending = ref hostin in
  let rec poll () =
    if !pending <> [] then
      Host.submit h (Host.Read { tgt = t_reg; addr = r_hostin_count; n = 1; k = (fun l ->
          let free = Chip_spec.hostin_depth - List.hd l in
          let now = List.filteri (fun i _ -> i < free) !pending in
          pending := List.filteri (fun i _ -> i >= free) !pending;
          if now <> [] then Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = now })) });
    Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 16; k = (fun l ->
        let rec pairs = function
          | t :: d :: r -> (if t land 0x80 <> 0 then received := (t land 7, d) :: !received); pairs r
          | _ -> () in
        pairs l) });
    Host.submit h (Host.Idle 32);
    Host.submit h (Host.Call poll) in
  Host.submit h (Host.Call poll)

let chip_cfg (img : Image.t) o = { Chip_spec.layout = Upe.Spec.layout_of_sizes img.layout; prog_words = o.prog_words }

(* the clock at which the sequencer starts: deterministic, set by the host's load sequence *)
let find_start (img : Image.t) o =
  let spec = Chip_spec.create ~cfg:(chip_cfg img o) () in
  let b = Board.create () in
  host_program b.host img ~hostin:[] ~received:(ref []);
  let rec go c =
    if c > 10_000_000 then failwith "the image never sets run"
    else if c >= 2 && Chip_spec.run spec then c
    else begin
      let smp = Board.samples b ~ext:(Array.make n_pads 15) in
      ignore (Board.advance b [ Board.spec_core spec ] ~smp ~reset:(c < 2));
      go (c + 1)
    end in
  go 0

let run_chip ?(rtl = true) (img : Image.t) o =
  let cfg = chip_cfg img o in
  let k0 = find_start img o in
  let spec = Chip_spec.create ~cfg () in
  let rtl_sim = if rtl then Some (Chip_sim.create ~cfg ()) else None in
  let cores = Board.spec_core spec :: (match rtl_sim with Some r -> [ Board.rtl_core r ] | None -> []) in
  let b = Board.create () in
  let received = ref [] in
  host_program b.host img ~hostin:o.hostin ~received;
  let map = pin_map img in
  let nets = Array.make o.clocks [||] and pcs = Array.make o.clocks [||] in
  let outs = ref [] and first_diff = ref None in
  (* after the run's window, 2,000 more clocks with the same world, so that the host can drain
     HOSTOUT; nothing of them is recorded, but OUTs executed then may reach the host *)
  let total = k0 + o.clocks + 2000 in
  for c = 0 to total - 1 do
    if c = k0 && not (Chip_spec.run spec) then failwith "the run did not start at the predicted clock";
    let rc = c - k0 in
    let w = resolve ~chip:(chip_drive map b.out) ~clock:rc o.peers in
    let ext = Array.make n_pads 15 in
    Array.iteri (fun k (_, ip) -> ext.(ip) <- w.(k)) map;
    (* uio pads that are outputs of a net are that net's wire *)
    Array.iteri (fun k (op, _) -> match op with Some p when p >= 8 -> ext.(p) <- w.(k) | _ -> ()) map;
    let inside = rc >= 0 && rc < o.clocks in
    if inside then begin
      nets.(rc) <- w;
      pcs.(rc) <- Array.init 4 (fun t -> (spec.seq.pages.(t) lsl 8) lor spec.seq.pcs.(t))
    end;
    let smp = Board.samples b ~ext in
    (match Board.advance b cores ~smp ~reset:(c < 2) with
     | [ a; r ] -> if (a.pad_nib <> r.pad_nib || a.uio_oe <> r.uio_oe) && !first_diff = None then first_diff := Some c
     | _ -> ());
    if inside then (match spec.out_pend with Some (tag, by) -> outs := (rc, tag, by) :: !outs | None -> ())
  done;
  let status = Chip_spec.status spec in
  let log =
    (if status land 1 <> 0 then [ "chip status: a memory access was refused (sticky)" ] else [])
    @ (if status land 2 <> 0 then [ "chip status: HOSTIN overflowed" ] else [])
    @ (if status land 4 <> 0 then [ "chip status: HOSTOUT overflowed: the host lost OUT bytes" ] else []) in
  { mode = Chip { rtl };
    trace = { Wave.t0 = 0; nets; pcs; outs = List.rev !outs; clock_hz = 60_000_000 };
    received = List.rev !received; port_pushes = []; run_start = k0;
    agree = (if rtl then Some (!first_diff = None) else None); first_diff = !first_diff; log }

let run mode img o = match mode with Isa -> run_isa img o | Chip { rtl } -> run_chip ~rtl img o

(* the first run clock at which two runs' nets differ *)
let compare (a : result) (b : result) =
  let n = min (Array.length a.trace.nets) (Array.length b.trace.nets) in
  let rec go c = if c >= n then None else if a.trace.nets.(c) <> b.trace.nets.(c) then Some c else go (c + 1) in
  go 0

(* the decoders' view: one sample per clock, bit k = net k's level at the end of the clock *)
let samples (r : result) =
  Array.to_list (Array.mapi (fun c nets ->
      { Ds.Decoders.c; bus = Array.fold_left ( lor ) 0 (Array.mapi (fun k nib -> ((nib lsr 3) land 1) lsl k) nets) })
      r.trace.nets)
