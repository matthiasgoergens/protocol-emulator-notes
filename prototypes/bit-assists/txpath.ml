(* The transmit serialiser: bytes in, a coded line pair out. A two-byte FIFO (filled by a thread's
   SEND on the chip), a symbol timer, the stuff tracker (transmit) and the line coder (encoder),
   then a two-phase tail. Protocol-agnostic; the protocols are configurations:

   - USB low speed: 40 clocks per symbol, LSB first, stuff run 6 of ones, NRZI toggling on 0 with
     the idle level J (inverted so that line a, D-, idles high); tail SE0 for 2 symbols, then J for
     1, then released. The thread sends the sync byte 0x80, the PID and the rest.
   - 10BASE-T: 3 clocks per symbol (half a bit), LSB first, no stuffing, Manchester; tail TD+ high
     for 6 symbols (TP_IDL, 300 ns), then released to the idle level. The thread sends the
     preamble, the SFD and the frame with its FCS.
   - CAN, HDLC: pass or NRZI, stuff run 5; MSB first for CAN.

   A frame starts when a byte is in the FIFO while the serialiser is idle: the clock after, the
   stuff tracker and the encoder restart and the first symbol goes out (it is on [a], [b] from the
   clock after that); then one symbol every [period] clocks. At every bit boundary the next bit is
   a stuff bit if one is due, else the next data bit, from the shift register or from the FIFO's
   head; if there is none, the frame's data has ended (an underrun ends the frame: the sender keeps
   the FIFO from running dry until its last byte). A stuff bit due after the last data bit is
   sent. Then the tail: [tail1] symbols of the level pair (a1, b1), then [tail2] of (a2, b2), each
   0 to 15 symbols, and the serialiser is idle again. During data, b is the complement of a (a
   differential pair); [busy] is high from the first symbol to the end of the tail.

   The model below and the RTL further down are written separately from these rules. *)

type tail = { len : int; la : int; lb : int }
type cfg = { period : int; msb_first : bool; stuff : Stuff.cfg; code : Linecode.cfg; tail1 : tail; tail2 : tail }

let depth = 2

let usb_ls =
  { period = 40; msb_first = false; stuff = Stuff.usb; code = { Linecode.usb with invert = true };
    tail1 = { len = 2; la = 0; lb = 0 }; tail2 = { len = 1; la = 1; lb = 0 } }

let eth10 =
  { period = 3; msb_first = false; stuff = Stuff.off; code = Linecode.ieee_manchester;
    tail1 = { len = 6; la = 1; lb = 0 }; tail2 = { len = 0; la = 0; lb = 0 } }

(* ---- model ---- *)

type phase = Idle | Data | Tail1 | Tail2

type st = {
  fifo : int Queue.t;
  mutable phase : phase;
  mutable ctr : int;
  mutable sh : int;
  mutable nb : int;
  mutable tl : int;
  mutable a : int;
  mutable b : int;
  mutable busy : bool;
  stf : Stuff.st;
  enc : Linecode.enc;
}

let init () =
  { fifo = Queue.create (); phase = Idle; ctr = 0; sh = 0; nb = 0; tl = 0; a = 0; b = 0; busy = false;
    stf = Stuff.init (); enc = Linecode.enc_init () }

(* a frame in progress or waiting to start *)
let active st = st.phase <> Idle || not (Queue.is_empty st.fifo)

let first_bit c byte = if c.msb_first then (byte lsr 7) land 1 else byte land 1
let shift c byte = if c.msb_first then (byte lsl 1) land 0xFF else byte lsr 1

(* One clock. [push]: a byte offered to the FIFO at the end of this clock; returns whether it was
   taken (the FIFO has room after this clock's pop). *)
let step c st ~push =
  let popped = ref false in
  let enter_tail k =
    let t = if k = 1 then c.tail1 else c.tail2 in
    if k = 1 && t.len > 0 then (st.phase <- Tail1; st.tl <- t.len - 1; st.a <- t.la; st.b <- t.lb; st.busy <- true)
    else if c.tail2.len > 0 then
      (st.phase <- Tail2; st.tl <- c.tail2.len - 1; st.a <- c.tail2.la; st.b <- c.tail2.lb; st.busy <- true)
    else (st.phase <- Idle; st.busy <- false)
  in
  let symbol () =
    match st.phase with
    | Idle -> ()
    | Data ->
      if Linecode.need_bit c.code st.enc then begin
        let data =
          if st.nb > 0 then Some (first_bit c st.sh)
          else match Queue.peek_opt st.fifo with Some x -> Some (first_bit c x) | None -> None in
        let x = Stuff.tx_peek c.stuff st.stf ~data in
        Stuff.tx_commit c.stuff st.stf x;
        match x with
        | Stuff.Underrun -> enter_tail 1
        | Stuff.Stuffed s | Stuff.Data s ->
          (match x with
           | Stuff.Data _ ->
             if st.nb > 0 then (st.sh <- shift c st.sh; st.nb <- st.nb - 1)
             else (let h = Queue.pop st.fifo in popped := true; st.sh <- shift c h; st.nb <- 7)
           | _ -> ());
          let sym = Linecode.enc_tick c.code st.enc ~bit:s in
          st.a <- sym; st.b <- 1 - sym; st.busy <- true
      end
      else begin
        let sym = Linecode.enc_tick c.code st.enc ~bit:0 in
        st.a <- sym; st.b <- 1 - sym; st.busy <- true
      end
    | Tail1 -> if st.tl > 0 then st.tl <- st.tl - 1 else enter_tail 2
    | Tail2 -> if st.tl > 0 then st.tl <- st.tl - 1 else (st.phase <- Idle; st.busy <- false)
  in
  (match st.phase with
   | Idle ->
     (* the stuff tracker and the encoder are held in restart while idle *)
     Stuff.restart st.stf; Linecode.enc_restart st.enc; st.nb <- 0;
     if not (Queue.is_empty st.fifo) then (st.phase <- Data; st.ctr <- 0)
   | _ ->
     if st.ctr = 0 then (st.ctr <- max 0 (c.period - 1); symbol ()) else st.ctr <- st.ctr - 1);
  ignore !popped;
  (* the FIFO takes a push when it has room after this clock's pop *)
  match push with
  | Some x when Queue.length st.fifo < depth -> Queue.push x st.fifo; true
  | _ -> false

(* ---- RTL ---- *)
open Hardcaml
open Signal

type tail_signals = { s_len : Signal.t; (* 4 bits *) s_la : Signal.t; s_lb : Signal.t }

type cfg_signals = {
  s_period : Signal.t;   (* 12 bits *)
  s_msb : Signal.t;
  s_stuff : Stuff.cfg_signals;
  s_code : Linecode.cfg_signals;
  s_tail1 : tail_signals;
  s_tail2 : tail_signals;
}

let tail_const t = { s_len = of_int ~width:4 t.len; s_la = of_int ~width:1 t.la; s_lb = of_int ~width:1 t.lb }

let cfg_const c =
  { s_period = of_int ~width:12 c.period; s_msb = of_bool c.msb_first; s_stuff = Stuff.cfg_const c.stuff;
    s_code = Linecode.cfg_const c.code; s_tail1 = tail_const c.tail1; s_tail2 = tail_const c.tail2 }

let bug = ref ""
let is b = !bug = b

let bugs =
  [ "tx_first_bit_msb", "the first bit of a byte is its MSB even when LSB first is configured";
    "tx_tail_skips_first", "tail 1 lasts one symbol less than configured";
    "tx_no_final_stuff", "a stuff bit due after the last data bit is not sent";
    "tx_pair_not_complement", "line b repeats line a during data";
    "tx_period_off_by_one", "a symbol lasts period + 1 clocks";
    "tx_fifo_full_accepts", "a push into a full FIFO overwrites the newest byte" ]

type out = { a : Signal.t; b : Signal.t; busy : Signal.t; active : Signal.t; count : Signal.t; accept : Signal.t }

let p_idle = 0 and p_data = 1 and p_tail1 = 2 and p_tail2 = 3

(* [push], [push_data]: a byte offered this clock; [accept] says it was taken. *)
let create ~clock ~clear ~(cfg : cfg_signals) ~push ~push_data =
  let spec = Reg_spec.create ~clock ~clear () in
  let phase = wire 2 and ctr = wire 12 and sh = wire 8 and nb = wire 3 and tl = wire 4 in
  let a = wire 1 and b = wire 1 and busy = wire 1 in
  (* the FIFO: two slots, read pointer, count *)
  let count = wire 2 and rd = wire 1 in
  let slot0 = wire 8 and slot1 = wire 8 in
  let head = mux2 rd slot1 slot0 in
  let fifo_ne = count <>:. 0 in
  let is_idle = phase ==:. p_idle and is_data = phase ==:. p_data in
  let tick = ~:is_idle &: (ctr ==:. 0) in
  let first_bit x = mux2 cfg.s_msb (msb x) (if is "tx_first_bit_msb" then msb x else lsb x) in
  let shifted x = mux2 cfg.s_msb (sll x 1) (srl x 1) in
  let have_sh = nb <>:. 0 in
  let data_valid = have_sh |: fifo_ne in
  let data_bit = mux2 have_sh (first_bit sh) (first_bit head) in
  let need = wire 1 in
  let due = tick &: is_data &: need in
  let stx = Stuff.tx ~clock ~clear ~restart:is_idle ~cfg:cfg.s_stuff ~due ~data_bit ~data_valid in
  let underrun = if is "tx_no_final_stuff" then due &: ~:data_valid else stx.underrun in
  let take = stx.take in
  let enc_tick = tick &: is_data &: ~:underrun in
  let enc = Linecode.encoder ~clock ~clear ~restart:is_idle ~cfg:cfg.s_code ~tick:enc_tick ~bit:stx.out_bit in
  need <== enc.need_bit;
  (* the symbol of this tick (the encoder's own line register holds it too, but [a] also carries
     the tail's levels) *)
  let sym = enc.sym in
  let pop = take &: ~:have_sh in
  (* tail sequencing at a tick *)
  let t1 = cfg.s_tail1 and t2 = cfg.s_tail2 in
  let t1_len = if is "tx_tail_skips_first" then mux2 (t1.s_len ==:. 0) t1.s_len (t1.s_len -:. 1) else t1.s_len in
  let enter_tail2 = (* from data or tail 1 *)
    [ (t2.s_len <>:. 0), (of_int ~width:2 p_tail2, t2.s_len -:. 1, t2.s_la, t2.s_lb, vdd) ] in
  let to_idle = (of_int ~width:2 p_idle, zero 4, a, b, gnd) in
  let pick l default = List.fold_right (fun (c, (p, t, la, lb, bz)) (p', t', la', lb', bz') ->
      (mux2 c p p', mux2 c t t', mux2 c la la', mux2 c lb lb', mux2 c bz bz')) l default in
  let from_underrun =
    pick ((t1_len <>:. 0, (of_int ~width:2 p_tail1, t1_len -:. 1, t1.s_la, t1.s_lb, vdd)) :: enter_tail2) to_idle in
  let from_tail1 = pick ((tl <>:. 0, (phase, tl -:. 1, a, b, busy)) :: enter_tail2) to_idle in
  let from_tail2 = pick [ (tl <>:. 0, (phase, tl -:. 1, a, b, busy)) ] to_idle in
  let sym_b = if is "tx_pair_not_complement" then sym else ~:sym in
  let from_data =
    pick [ (underrun, from_underrun) ] (phase, tl, sym, sym_b, vdd) in
  let at_tick =
    pick [ (is_data, from_data); (phase ==:. p_tail1, from_tail1) ] from_tail2 in
  let n_phase, n_tl, n_a, n_b, n_busy = at_tick in
  let n_phase = mux2 is_idle (mux2 fifo_ne (of_int ~width:2 p_data) phase) (mux2 tick n_phase phase) in
  phase <== reg spec n_phase;
  tl <== reg spec (mux2 tick n_tl tl);
  a <== reg spec (mux2 tick n_a a);
  b <== reg spec (mux2 tick n_b b);
  busy <== reg spec (mux2 tick n_busy busy);
  let reload = mux2 (cfg.s_period ==:. 0) (zero 12) (cfg.s_period -:. 1) in
  let reload = if is "tx_period_off_by_one" then mux2 (cfg.s_period ==:. 0) (zero 12) cfg.s_period else reload in
  ctr <== reg spec (mux2 is_idle (zero 12) (mux2 tick reload (ctr -:. 1)));
  (* the shift register *)
  let after_take = mux2 have_sh (shifted sh) (shifted head) in
  sh <== reg spec (mux2 take after_take sh);
  nb <== reg spec (mux2 is_idle (zero 3) (mux2 take (mux2 have_sh (nb -:. 1) (of_int ~width:3 7)) nb));
  (* FIFO *)
  let accept = push &: ((count <>:. depth) |: pop) in
  let accept = if is "tx_fifo_full_accepts" then push else accept in
  let wr = wire 1 in
  let wr_slot = mux2 (accept &: (count ==:. depth) &: ~:pop) (~:wr) wr in
  (* the overwrite fault writes the slot behind the write pointer *)
  slot0 <== reg spec (mux2 (accept &: (wr_slot ==:. 0)) push_data slot0);
  slot1 <== reg spec (mux2 (accept &: (wr_slot ==:. 1)) push_data slot1);
  wr <== reg spec (mux2 (accept &: ~:((count ==:. depth) &: ~:pop)) (~:wr) wr);
  rd <== reg spec (mux2 pop (~:rd) rd);
  let n_count = count +: uresize (accept &: ~:((count ==:. depth) &: ~:pop)) 2 -: uresize pop 2 in
  count <== reg spec n_count;
  { a; b; busy; active = ~:is_idle |: fifo_ne; count; accept }
