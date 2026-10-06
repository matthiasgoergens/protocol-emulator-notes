(* Executable specification of the whole chip core, one clock per [step].

   It is composed from the blocks' own models, which are not written anew here:
   - the sequencer: ISA v2's interpreter (Isa2, ../sequencer-v2/isa2.ml);
   - the PE array: Upe.Model (../unified-pe/verify/model.ml);
   - the streamer and the sampler: Pstream.Model and Psample.Model;
   - the edge-tracking sampler and the CRC unit: the models in Eth10.Edge_sampler and
     Eth10.Crc_unit; the matcher: the closed form of Eth10.Model.
   New here, because nothing specified them before: the glue (host link, its FIFOs, the register
   file, the pin map and pad sources, the flag selects, the port holds between the threads and
   the array, the memories) and the pin NCO, which has RTL (../multiphase/nco.ml) but no model.
   The NCO's behaviour is written below from nco.ml's header comment.

   The boundary is the four-phase stage's (README, "Phases"): inputs are, per input pad, the
   four quarter samples the core sees in this clock (bit p = quarter p); outputs are, per output
   pad, the nibble of levels for the next clock's four quarters, and the uio output enables.
   Outputs depend only on the state at the start of the clock.

   Within a clock everything reads the state as it was at the start of the clock, and every
   update lands at its end, as registers do. Where models must be stepped in some order, the
   order below is the one in which their inputs become available, and no model reads another's
   updated state. *)

open Regs
module UM = Upe.Model
module US = Upe.Spec
module SM = Pstream.Model
module PM = Psample.Model
module ES = Eth10.Edge_sampler
module CRC = Eth10.Crc_unit
module MM = Eth10.Model

type config = { layout : US.layout; prog_words : int }

let default_config = { layout = US.layout_of_sizes [| 1; 1; 1; 1 |]; prog_words = 1024 }
let bank_bytes = Isa2.bank_len
let hostin_depth = 16 and hostout_depth = 8

(* a host-link byte that was decoded in the previous clock and acts in this one *)
type action =
  | A_reg of int * int            (* address, byte *)
  | A_prog of int * int
  | A_bank of int * int
  | A_hostin of int
  | A_pecfg of int * int          (* segment, byte *)
  | A_peinit of int * int
  | A_peseg of int * int * int    (* segment, sel, byte *)
  | A_stream of int * int         (* address mod 4, byte *)
  | A_match of int                (* bit *)

type parser = Idle | Addr_hi | Addr_lo | Count | Wdata | Rdata

type t = {
  cfg : config;
  regs : int array;
  mutable err_mem : bool; mutable hin_ovf : bool; mutable hout_ovf : bool; mutable act_drop : bool;
  prog : int array;
  bank : int array;
  mutable seq : Isa2.state;
  hostin : int Queue.t;
  hostout : (int * int) Queue.t;
  mutable out_pend : (int * int) option;     (* the core's OUT, registered; enters the FIFO now *)
  mutable push_pend : (int * int) option;    (* the core's SEND to a port, registered *)
  send_hi : bool array;                      (* per port: the next SEND byte is the high byte *)
  hold_st : int array;                       (* per port: 0 empty, 1 low byte next, 2 high byte next *)
  hold_w : int array;
  pe : UM.t;
  mutable str : SM.t;
  mutable smp : PM.t;
  mutable es : ES.st;
  mutable es_out : ES.out;
  mutable es_last : int;                     (* the last recovered bit, held between bits *)
  mutable crc : int;
  chain : int array;                         (* the matcher's 37 configuration bits, in chain order *)
  mutable mhist : int array;
  mutable mtime : int;
  mutable nco_acc : int;
  mutable nco_out : int;
  (* host link *)
  mutable prev_s : int; mutable prev_r : int;
  mutable nphase : int; mutable hi_nib : int;
  mutable pst : parser; mutable op : int; mutable tgt : int; mutable addr : int;
  mutable remaining : int;
  mutable rbuf : int; mutable rphase : int;
  mutable pend_action : action option;
  mutable pend_fetch : (int * int) option;   (* target, address *)
  mutable prog_lo : int; mutable str_lo : int; mutable str_hi : int;
  mutable hout_lat : bool; mutable smp_lat : bool;
  mutable last_fetch : (int * int * int) option;   (* for diagnostics *)
}

let rep4 b = if b <> 0 then 15 else 0
let bit v i = (v lsr i) land 1
let u32 v = v land 0xFFFF_FFFF
let reg32 t a = t.regs.(a) lor (t.regs.(a + 1) lsl 8) lor (t.regs.(a + 2) lsl 16) lor (t.regs.(a + 3) lsl 24)

(* ---- block configurations from the registers ---- *)

let streamer_cfg t : SM.cfg =
  let r = t.regs in
  { period = r.(r_str_per) lor ((r.(r_str_per + 1) land 15) lsl 8); width = (r.(r_str_per + 1) lsr 4) land 7;
    od_mask = r.(r_str_pins) land 15; idle_out = (r.(r_str_pins) lsr 4) land 15; idle_oe = r.(r_str_idle_oe) land 15 }

let sampler_cfg t : PM.cfg =
  let r = t.regs in
  { clocked = bit r.(r_smp_per + 1) 7 = 1; period = r.(r_smp_per) lor ((r.(r_smp_per + 1) land 15) lsl 8);
    width = (r.(r_smp_per + 1) lsr 4) land 7; trig_pin = (r.(r_smp_off + 1) lsr 4) land 3;
    trig_val = bit r.(r_smp_off + 1) 6; offset = r.(r_smp_off) lor ((r.(r_smp_off + 1) land 15) lsl 8);
    frame_len = r.(r_smp_frame) }

let es_cfg t : ES.cfg =
  let r = t.regs in
  { mode = (match r.(r_es_mode) land 3 with 0 -> ES.Manchester | 2 -> ES.Nrz | _ -> ES.Biphase_mark);
    invert = bit r.(r_es_mode) 2 = 1;
    holdoff = r.(r_es_holdoff) lor ((r.(r_es_holdoff + 1) land 3) lsl 8);
    timeout = r.(r_es_timeout) lor ((r.(r_es_timeout + 1) land 3) lsl 8);
    offset = r.(r_es_offset); period = r.(r_es_period) }

(* The CRC unit's model takes a width; the RTL takes a mask. The host must write a mask of the
   form 2^w - 1 (README); the width is then the number of ones. *)
let crc_cfg t : CRC.cfg =
  let mask = reg32 t r_crc_mask in
  let rec ones v = if v = 0 then 0 else (v land 1) + ones (v lsr 1) in
  { width = max 1 (ones mask); poly = reg32 t r_crc_poly; init = reg32 t r_crc_init;
    reflected = bit t.regs.(r_crc_ctrl) 0 = 1; xorout = reg32 t r_crc_xorout; residue = reg32 t r_crc_residue }

let matcher_cfg t : MM.cfg =
  { t = Array.init MM.n (fun i -> t.chain.(2 * i + 1)); m = Array.init MM.n (fun i -> t.chain.(2 * i));
    thr = Array.fold_left ( lor ) 0 (Array.init 5 (fun k -> t.chain.(32 + k) lsl k)) }

let matcher_now t =
  let c = matcher_cfg t and x k = t.mhist.(k) in
  (MM.y_at c x t.mtime, MM.hit_at c x t.mtime)

let boot t = Array.init 4 (fun th -> ((t.regs.(r_boot_page) lsr (2 * th)) land 3, t.regs.(r_boot_pc th)))

(* coverage of chip-level events, for the lockstep's report (not part of the behaviour) *)
let cov : (string, int) Hashtbl.t = Hashtbl.create 64
let hit name = Hashtbl.replace cov name (1 + Option.value ~default:0 (Hashtbl.find_opt cov name))

let es_zero : ES.out = { bit = 0; valid = false; burst_end = false; overrun = false }

(* The edge sampler's bit output is defined only while its valid is high; the glue holds the
   last recovered bit, so pads, flags and the sampler see a level. *)
let es_level t = if t.es_out.valid then t.es_out.bit else t.es_last

let create ?(cfg = default_config) () =
  let regs = Array.init reg_space reset_value in
  let t =
    { cfg; regs; err_mem = false; hin_ovf = false; hout_ovf = false; act_drop = false;
      prog = Array.make cfg.prog_words 0; bank = Array.make bank_bytes 0;
      seq = Isa2.Spec.reset ~boot:(Array.make 4 (0, 0)) ~bank:(Array.make bank_bytes 0);
      hostin = Queue.create (); hostout = Queue.create (); out_pend = None; push_pend = None;
      send_hi = Array.make 4 false; hold_st = Array.make 4 0; hold_w = Array.make 4 0;
      pe = UM.create ~layout:cfg.layout ();
      str = SM.create { period = 1; width = 1; od_mask = 0; idle_out = 0; idle_oe = 0 };
      smp = PM.create { clocked = false; period = 1; width = 1; trig_pin = 0; trig_val = 0; offset = 0; frame_len = 0 };
      es = ES.init (); es_out = es_zero; es_last = 0; crc = 0; chain = Array.make 37 0; mhist = Array.make 1024 0;
      mtime = 0; nco_acc = 0; nco_out = 0; prev_s = 0; prev_r = 0; nphase = 0; hi_nib = 0; pst = Idle;
      op = 0; tgt = 0; addr = 0; remaining = 0; rbuf = 0; rphase = 0; pend_action = None;
      pend_fetch = None; prog_lo = 0; str_lo = 0; str_hi = 0; hout_lat = false; smp_lat = false; last_fetch = None }
  in
  t.seq <- Isa2.Spec.reset ~boot:(boot t) ~bank:t.bank;
  t.str <- SM.create (streamer_cfg t);
  t.smp <- PM.create (sampler_cfg t);
  t

(* ---- outputs: from the state at the start of the clock ---- *)

type outputs = { pad_nib : int array; uio_oe : int }

let taps t = (UM.state t.pe).taps

let source t (taps : US.tap array) src =
  if src < 8 then ((t.seq.pin_sub lsr (4 * src)) land 15, bit t.seq.pin_oe src)
  else if src < 12 then (rep4 (bit t.str.out (src - 8)), bit t.str.oe (src - 8))
  else if src = src_nco_quarter then (t.nco_out land 15, 1)
  else if src = src_nco_half then ((t.nco_out lsr 4) land 15, 1)
  else if src = src_nco_grid then ((t.nco_out lsr 8) land 15, 1)
  else if src >= 16 && src < 20 then (rep4 (Bool.to_int taps.(src - 16).tf), 1)
  else if src >= 20 && src < 24 then (rep4 (taps.(src - 20).td land 1), 1)
  else if src = src_es_bit then (rep4 (es_level t), 1)
  else (0, 1)

let outputs t =
  let taps = taps t in
  let pad_nib = Array.make n_pads 0 and uio_oe = ref 0 in
  List.iter
    (fun p ->
      let sel = t.regs.(r_padsel p) in
      let nib, oe = source t taps (sel land 31) in
      let nib = if bit sel 5 = 1 then nib lxor 15 else nib in
      if p < 8 then pad_nib.(p) <- (if oe = 1 then nib else rep4 (bit sel 6))
      else begin
        pad_nib.(p) <- nib;
        if oe = 1 then uio_oe := !uio_oe lor (1 lsl (p - 8))
      end)
    general_out_pads;
  (* host data: the current read nibble, driven while the host's read request is seen *)
  let rnib = if t.rphase = 0 then t.rbuf lsr 4 else t.rbuf land 15 in
  for k = 0 to 3 do pad_nib.(pad_hdata + k) <- rep4 (bit rnib k) done;
  if t.prev_r = 1 then uio_oe := !uio_oe lor 0xF;
  { pad_nib; uio_oe = !uio_oe }

let flags t (taps : US.tap array) =
  let src s =
    if s < 4 then taps.(s).tf
    else if s < 8 then taps.(s - 4).tv
    else if s = fl_es_valid then t.es_out.valid
    else if s = fl_es_bit then es_level t = 1
    else if s = fl_es_in_burst then t.es.in_burst
    else if s = fl_es_burst_end then t.es_out.burst_end
    else if s = fl_crc_check then t.crc = (crc_cfg t).residue
    else if s = fl_match_hit then snd (matcher_now t)
    else if s = fl_stream_full then SM.full t.str
    else if s = fl_sample_valid then not (Queue.is_empty t.smp.fifo)
    else if s = fl_nco then bit t.nco_out 0 = 1
    else false
  in
  let v = ref 0 in
  for f = 0 to 15 do if src (t.regs.(r_flagsel f) land 31) then v := !v lor (1 lsl f) done;
  !v

(* ---- host-link reads ---- *)

let run t = bit t.regs.(r_ctrl) 0 = 1
let held t = bit t.regs.(r_ctrl) 1 = 1

let status t =
  Bool.to_int t.err_mem lor (Bool.to_int t.hin_ovf lsl 1) lor (Bool.to_int t.hout_ovf lsl 2)
  lor (Bool.to_int (Queue.length t.hostin >= hostin_depth) lsl 3)
  lor (Bool.to_int (not (Queue.is_empty t.hostout)) lsl 4)
  lor (Bool.to_int (not (Queue.is_empty t.smp.fifo)) lsl 5)
  lor (Bool.to_int (SM.full t.str) lsl 6) lor (Bool.to_int t.act_drop lsl 7)

let read_reg t a =
  if a >= reg_space then 0
  else if rw_bits a > 0 then t.regs.(a)
  else if a = r_status then status t
  else if a = r_hostin_count then Queue.length t.hostin
  else if a = r_hostout_count then Queue.length t.hostout
  else if a >= r_crc_raw && a < r_crc_raw + 4 then (t.crc lsr (8 * (a - r_crc_raw))) land 0xFF
  else if a = r_match then (let y, hit = matcher_now t in y lor (Bool.to_int hit lsl 7))
  else if a = r_smp_overflows then t.smp.overflows land 0xFF
  else 0

(* the byte a fetch returns, and whether it pops the sampler *)
let fetch t (tgt, a) =
  let a = a land 0xFFFF in
  if tgt = t_reg then (read_reg t a, false)
  else if tgt = t_prog then
    if run t then (t.err_mem <- true; (0, false))
    else
      let w = t.prog.((a lsr 1) land (t.cfg.prog_words - 1)) in
      ((if a land 1 = 0 then w else w lsr 8) land 0xFF, false)
  else if tgt = t_bank then
    if run t then (t.err_mem <- true; (0, false)) else (t.bank.(a land (bank_bytes - 1)), false)
  else if tgt = t_hostout then
    if a land 1 = 0 then begin
      t.hout_lat <- not (Queue.is_empty t.hostout);
      ((match Queue.peek_opt t.hostout with Some (tag, _) -> 0x80 lor tag | None -> 0), false)
    end
    else if t.hout_lat then (t.hout_lat <- false; (snd (Queue.pop t.hostout), false))
    else begin
      if not (Queue.is_empty t.hostout) then hit "HOSTOUT entry arrived between tag and data";
      (0, false)
    end
  else if tgt = t_sample then
    match a land 3, Queue.peek_opt t.smp.fifo with
    | 0, h -> t.smp_lat <- h <> None; ((match h with Some (_, n) -> 0x80 lor n | None -> 0), false)
    | 1, Some (w, _) when t.smp_lat -> (w land 0xFF, false)
    | 2, h ->
      let lat = t.smp_lat in
      t.smp_lat <- false;
      (match h with Some (w, _) when lat -> ((w lsr 8) land 0xFF, true) | _ -> (0, false))
    | _ -> (0, false)
  else (0, false)

(* the action of one written data byte *)
let action_of ~tgt ~addr b =
  let a = addr land 0xFFFF in
  if tgt = t_reg then Some (A_reg (a, b))
  else if tgt = t_prog then Some (A_prog (a, b))
  else if tgt = t_bank then Some (A_bank (a, b))
  else if tgt = t_hostin then Some (A_hostin b)
  else if tgt = t_pecfg then Some (A_pecfg (a land 3, b))
  else if tgt = t_peinit then Some (A_peinit (a land 3, b))
  else if tgt = t_peseg then Some (A_peseg ((a lsr 2) land 3, a land 3, b))
  else if tgt = t_stream then Some (A_stream (a land 3, b))
  else if tgt = t_match then Some (A_match (b land 1))
  else None

(* ---- one clock ---- *)

let reset_all t ~smp =
  (* the core's clear loads the boot registers as they are during this clock *)
  let boot_now = boot t in
  Array.iteri (fun a _ -> t.regs.(a) <- reset_value a) t.regs;
  t.err_mem <- false; t.hin_ovf <- false; t.hout_ovf <- false; t.act_drop <- false;
  Queue.clear t.hostin; Queue.clear t.hostout; t.out_pend <- None; t.push_pend <- None;
  Array.fill t.send_hi 0 4 false; Array.fill t.hold_st 0 4 0; Array.fill t.hold_w 0 4 0;
  t.es <- ES.init (); t.es_out <- es_zero; t.es_last <- 0; t.crc <- 0; t.mtime <- 0; t.nco_acc <- 0; t.nco_out <- 0;
  t.prev_s <- bit smp.(pad_hstb) 3; t.prev_r <- bit smp.(pad_hrd) 3;
  t.nphase <- 0; t.hi_nib <- 0; t.pst <- Idle; t.op <- 0; t.tgt <- 0; t.addr <- 0; t.remaining <- 0;
  t.rbuf <- 0; t.rphase <- 0; t.pend_action <- None; t.pend_fetch <- None;
  t.prog_lo <- 0; t.str_lo <- 0; t.str_hi <- 0; t.hout_lat <- false; t.smp_lat <- false;
  t.seq <- Isa2.Spec.reset ~boot:boot_now ~bank:t.bank;
  t.str <- SM.create (streamer_cfg t);
  t.smp <- PM.create (sampler_cfg t)

let step t ~smp ~reset =
  let out = outputs t in
  let taps = taps t in
  if reset then begin
    (* the array has no reset: it runs on with idle inputs; segment 0's fixed port still shows the
       edge sampler's output register during this clock *)
    UM.cycle t.pe
      { US.idle with fixed_d = [| es_level t; 0; 0; 0 |]; fixed_v = [| t.es_out.valid; false; false; false |] };
    reset_all t ~smp;
    out
  end
  else begin
    let lvl i = bit smp.(i) 3 in
    let running = run t and hold = held t and boot_now = boot t in
    let flags = flags t taps in
    let act = t.pend_action in
    let reg_act a = match act with Some (A_reg (x, b)) when x = a -> Some b | _ -> None in
    (* the host's fetch, from the state at the start of the clock *)
    let fetched = Option.map (fetch t) t.pend_fetch in
    (match t.pend_fetch, fetched with
     | Some (tg, a), Some (b, _) -> t.last_fetch <- Some (tg, a, b)
     | _ -> ());
    (* sequencer *)
    let pin_sel k = t.regs.(r_pinin k) land 15 in
    let pin_in = Array.fold_left ( lor ) 0 (Array.init 8 (fun k -> lvl (pin_sel k) lsl k)) in
    let pin_in4 = Array.fold_left ( lor ) 0 (Array.init 8 (fun k -> smp.(pin_sel k) lsl (4 * k))) in
    let new_push = ref None and new_out = ref None and hostin_pop = ref false in
    let port_pops = Array.make 4 false in
    if running then begin
      let host_ctl =
        Option.map (fun b -> (b land 3, (b lsr 2) land 3, t.regs.(r_restart_pc))) (reg_act r_restart) in
      let io =
        Isa2.io ~pin_in4 ~host_in:(Option.value ~default:0 (Queue.peek_opt t.hostin))
          ~host_in_valid:(not (Queue.is_empty t.hostin))
          ~port_in:(Array.init 4 (fun p -> if t.hold_st.(p) = 2 then t.hold_w.(p) lsr 8 else t.hold_w.(p) land 0xFF))
          ~port_in_valid:(Array.map (fun s -> s <> 0) t.hold_st) ~port_out_ready:(Array.make 4 true) ~flags
          ?host_ctl pin_in
      in
      let w = t.prog.(Isa2.fetch_addr t.seq t.seq.thread land (t.cfg.prog_words - 1)) in
      hit (Printf.sprintf "op %X" (w lsr 12));
      let e = Isa2.step_f t.seq ~fetch:(fun a -> t.prog.(a land (t.cfg.prog_words - 1))) io in
      if host_ctl <> None then hit "restart";
      if e.host_in_ready then hit "IN from host";
      (match e.port_pop with Some _ -> hit "RECV from a segment" | None -> ());
      (match e.port_push with Some _ -> hit "SEND to a segment" | None -> ());
      (match e.host_out with Some _ -> hit "OUT to host" | None -> ());
      (match e.bank_write with Some _ -> hit "STB" | None -> ());
      if flags <> 0 then hit "a flag input set";
      if e.host_in_ready then hostin_pop := true;
      (match e.port_pop with Some p -> port_pops.(p) <- true | None -> ());
      new_push := e.port_push;
      new_out := e.host_out
    end;
    (* the array: a thread's SEND (registered last clock) goes first; a host write waits *)
    let mbx, host_mbx_done =
      match t.push_pend, act with
      | Some (p, b), _ -> ((true, p, (if t.send_hi.(p) then 1 else 0), b), false)
      | None, Some (A_peseg (sg, sel, b)) -> hit "host feed write"; ((true, sg, sel, b), true)
      | None, _ -> ((false, 0, 0, 0), false)
    in
    let mbx_wr, mbx_seg, mbx_sel, mbx_byte = mbx in
    let cfg_w = match act with Some (A_pecfg (sg, b)) -> Some (sg, b) | _ -> None in
    let init_w = match act with Some (A_peinit (sg, b)) -> Some (sg, b) | _ -> None in
    UM.cycle t.pe
      { mbx_wr; mbx_seg; mbx_sel; mbx_byte;
        cfg_wr = cfg_w <> None; cfg_seg = Option.fold ~none:0 ~some:fst cfg_w; cfg_byte = Option.fold ~none:0 ~some:snd cfg_w;
        init_wr = init_w <> None; init_seg = Option.fold ~none:0 ~some:fst init_w;
        init_byte = Option.fold ~none:0 ~some:snd init_w;
        fixed_d = [| es_level t; 0; 0; 0 |]; fixed_v = [| t.es_out.valid; false; false; false |] };
    (* port glue: SEND byte order, RECV holding registers *)
    let port_reset = Option.value ~default:0 (reg_act r_port_reset) in
    (match t.push_pend with Some (p, _) -> t.send_hi.(p) <- not t.send_hi.(p) | None -> ());
    for p = 0 to 3 do
      if bit port_reset p = 1 then (t.send_hi.(p) <- false; t.hold_st.(p) <- 0)
      else
        match t.hold_st.(p) with
        | 0 -> if taps.(p).tv then (hit "tap captured"; t.hold_st.(p) <- 1; t.hold_w.(p) <- taps.(p).td)
        | 1 -> if port_pops.(p) then t.hold_st.(p) <- 2
        | _ -> if port_pops.(p) then t.hold_st.(p) <- 0
    done;
    t.push_pend <- !new_push;
    (* host FIFOs: pops before pushes, so a full FIFO takes a push in the clock its head leaves *)
    if !hostin_pop then ignore (Queue.pop t.hostin);
    (match act with
     | Some (A_hostin b) -> hit "HOSTIN push"; if Queue.length t.hostin < hostin_depth then Queue.push b t.hostin else t.hin_ovf <- true
     | _ -> ());
    (match t.out_pend with
     | Some e -> if Queue.length t.hostout < hostout_depth then Queue.push e t.hostout else t.hout_ovf <- true
     | None -> ());
    t.out_pend <- !new_out;
    (* the assists *)
    let smp_pop = match fetched with Some (_, p) -> p | None -> false in
    let es_old = t.es_out and es_lvl = es_level t and c_residue_now = (crc_cfg t).residue in
    let _, hit_now = matcher_now t in
    if hold then begin
      t.es <- ES.init (); t.es_out <- es_zero; t.es_last <- 0; t.crc <- 0; t.mtime <- 0; t.nco_acc <- 0; t.nco_out <- 0
    end
    else begin
      if t.str.left > 0 || not (Queue.is_empty t.str.fifo) then hit "streamer busy";
      SM.step t.str;
      (match act with
       | Some (A_stream (2, b)) -> SM.push ~count:(b land 15) t.str ((t.str_hi lsl 8) lor t.str_lo)
       | _ -> ());
      let pins =
        if bit t.regs.(r_smp_src) 0 = 1 then es_lvl lor (Bool.to_int es_old.valid lsl 1)
        else Array.fold_left ( lor ) 0 (Array.init 4 (fun j -> lvl (t.regs.(r_smp_pin j) land 15) lsl j))
      in
      let before = Queue.length t.smp.fifo in
      ignore (PM.step t.smp ~pins ~pop:smp_pop);
      if Queue.length t.smp.fifo > before then hit "sampler word";
      let es_pad = t.regs.(r_es_pads) land 15 and act_pad = (t.regs.(r_es_pads) lsr 4) land 15 in
      let active = bit t.regs.(r_es_mode) 3 = 0 || lvl act_pad = 1 in
      if es_old.valid then hit "recovered bit";
      if hit_now then hit "matcher hit";
      if t.crc = c_residue_now then hit "CRC check true";
      t.es_last <- es_lvl;
      t.es_out <- ES.step_clock (es_cfg t) t.es ~active (List.init 4 (fun p -> bit smp.(es_pad) p));
      let start = reg_act r_crc_start <> None || (bit t.regs.(r_crc_ctrl) 1 = 1 && hit_now) in
      let c = crc_cfg t in
      t.crc <- (if start then c.init else if es_old.valid then CRC.step c t.crc es_old.bit else t.crc);
      if es_old.valid then begin
        if t.mtime >= Array.length t.mhist then
          t.mhist <- Array.append t.mhist (Array.make (Array.length t.mhist) 0);
        t.mhist.(t.mtime) <- es_old.bit;
        t.mtime <- t.mtime + 1
      end;
      (* the pin NCO (../multiphase/nco.ml): the levels of the accumulator at the clock's four
         quarter points, registered; then the accumulator advances by inc *)
      let inc = reg32 t r_nco_inc in
      let a = [| t.nco_acc; u32 (t.nco_acc + (inc lsr 2)); u32 (t.nco_acc + (inc lsr 1));
                 u32 (t.nco_acc + (inc lsr 1) + (inc lsr 2)) |] in
      let l p = 1 - bit a.(p) 31 in
      t.nco_out <- (l 0 lor (l 1 lsl 1) lor (l 2 lsl 2) lor (l 3 lsl 3))
                   lor ((l 0 lor (l 0 lsl 1) lor (l 2 lsl 2) lor (l 2 lsl 3)) lsl 4)
                   lor (rep4 (l 0) lsl 8);
      t.nco_acc <- u32 (t.nco_acc + inc)
    end;
    (match act with
     | Some (A_match b) -> for k = 36 downto 1 do t.chain.(k) <- t.chain.(k - 1) done; t.chain.(0) <- b
     | _ -> ());
    (* memories *)
    (match act with
     | Some (A_prog (a, b)) ->
       if running then t.err_mem <- true
       else if a land 1 = 0 then t.prog_lo <- b
       else t.prog.((a lsr 1) land (t.cfg.prog_words - 1)) <- (b lsl 8) lor t.prog_lo
     | Some (A_bank (a, b)) -> if running then t.err_mem <- true else t.bank.(a land (bank_bytes - 1)) <- b
     | Some (A_stream (0, b)) -> t.str_lo <- b
     | Some (A_stream (1, b)) -> t.str_hi <- b
     | _ -> ());
    (* the host link *)
    (match fetched with Some (b, _) -> t.rbuf <- b | None -> ());
    t.pend_fetch <- None;
    let next_action = ref None in
    let s = lvl pad_hstb and r = lvl pad_hrd in
    let d = Array.fold_left ( lor ) 0 (Array.init 4 (fun k -> lvl (pad_hdata + k) lsl k)) in
    if r <> t.prev_r then begin
      (* raising R starts reading what a READ command fetched; lowering it ends the command *)
      t.nphase <- 0; t.rphase <- 0;
      if r = 0 then t.pst <- Idle
    end
    else if s <> t.prev_s then begin
      if r = 0 then begin
        if t.nphase = 0 then (t.hi_nib <- d; t.nphase <- 1)
        else begin
          t.nphase <- 0;
          let b = (t.hi_nib lsl 4) lor d in
          match t.pst with
          | Idle ->
            let op = b lsr 4 in
            if op = op_write || op = op_read then (t.op <- op; t.tgt <- b land 15; t.pst <- Addr_hi)
          | Addr_hi -> t.addr <- b lsl 8; t.pst <- Addr_lo
          | Addr_lo -> t.addr <- t.addr lor b; t.pst <- Count
          | Count ->
            t.remaining <- b + 1;
            if t.op = op_write then t.pst <- Wdata
            else (t.pst <- Rdata; t.pend_fetch <- Some (t.tgt, t.addr))
          | Wdata ->
            next_action := action_of ~tgt:t.tgt ~addr:t.addr b;
            t.addr <- (t.addr + 1) land 0xFFFF;
            t.remaining <- t.remaining - 1;
            if t.remaining = 0 then t.pst <- Idle
          | Rdata -> t.pst <- Idle
        end
      end
      else if t.rphase = 0 then t.rphase <- 1
      else begin
        t.rphase <- 0;
        if t.pst = Rdata && t.remaining > 1 then begin
          t.remaining <- t.remaining - 1;
          t.addr <- (t.addr + 1) land 0xFFFF;
          t.pend_fetch <- Some (t.tgt, t.addr)
        end
        else begin
          t.remaining <- 0; t.rbuf <- 0;
          if t.pst = Rdata then t.pst <- Idle
        end
      end
    end;
    t.prev_s <- s; t.prev_r <- r;
    (* an action waits a clock when a thread's SEND took the array's write port; a newer byte
       overwrites a waiting one, and that is recorded *)
    let waiting = match act with Some (A_peseg _) when not host_mbx_done -> hit "host feed write waited for a SEND"; act | _ -> None in
    (match !next_action, waiting with
     | Some a, Some _ -> t.act_drop <- true; t.pend_action <- Some a
     | Some a, None -> t.pend_action <- Some a
     | None, w -> t.pend_action <- w);
    (* register writes land at the end of the clock *)
    (match act with
     | Some (A_reg (a, b)) ->
       if a = r_status then (t.err_mem <- false; t.hin_ovf <- false; t.hout_ovf <- false; t.act_drop <- false)
       else if a < reg_space && rw_bits a > 0 then t.regs.(a) <- b land ((1 lsl rw_bits a) - 1)
     | _ -> ());
    (* a clock spent in clear leaves the sequencer in its reset state, from the boot registers as
       they were during the clock; a held streamer and sampler are recreated with the
       configuration as it is now, which is what their idle outputs show in the next clock *)
    if not running then t.seq <- Isa2.Spec.reset ~boot:boot_now ~bank:t.bank;
    if hold then begin
      t.str <- SM.create (streamer_cfg t);
      t.smp <- PM.create (sampler_cfg t)
    end;
    out
  end
