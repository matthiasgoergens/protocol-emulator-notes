(* The receive framer: a recovered bit stream in (from the edge-tracking sampler), bytes of a
   frame out. The line decoder and the stuff tracker (receive) run on every recovered bit; their
   output, one registered "chain" bit, feeds a start-pattern detector and a byte packer with a
   two-byte FIFO (read by a thread's RECV on the chip). Protocol-agnostic:

   - USB low speed: NRZI decode toggling on 0, destuff run 6 of ones; a frame starts after the
     sync pattern (the last eight chain bits 0,0,0,0,0,0,0,1, i.e. 0x80 with the newest bit in bit
     7) and ends when the line goes idle (SE0, from the edge sampler's active input); the CRC unit
     on the chip sees the frame's bits after the 8-bit PID.
   - 10BASE-T: pass (the edge sampler decodes Manchester), no stuffing; starts after the SFD 0xD5,
     ends at the end of the sampler's burst; CRC over the whole frame.
   - CAN: pass, destuff run 5 of either; started by the host or on a pattern, MSB first.

   Per clock, from the state at its start:
   1. The chain: with the sampler's [valid], its bit goes through the decoder and, if the decoder
      completes a bit, the destuffer; a kept bit becomes the chain bit of the next clock ([cv],
      [cb]), with [ce] set when the decoder (Manchester code violation) or the destuffer (stuff
      violation) found an error.
   2. The framer, on this clock's chain bit. In a frame: an end condition ([end_inactive] and the
      line not active, [end_burst] and the sampler's burst end, or the host's [stop]) ends it, and
      this clock's chain bit is not part of it; otherwise a chain bit is shifted into the byte
      (LSB first unless [msb_first]), every eighth completes a byte into the FIFO (a full FIFO
      drops it and sets [ovf]), and [ce] sets [err]. Every chain bit enters the 8-bit history
      (newest in bit 7); out of a frame, a frame starts when [start_on_pattern] and the history,
      with this bit, matches [pattern] where [pmask] has ones, unless [half_duplex] and the
      transmitter is active. The history counts only bits received since the last clear or the
      end of the last frame: until eight have arrived nothing matches. So a cleared history does
      not look like received zeros, and a frame's last bits followed by the idle line (USB: a
      packet ending in seven 0s, then the decoded 1s of the EOP and idle) cannot complete a
      start pattern. The host's [start] starts (or restarts) a frame in any state. A
      start clears the FIFO, the byte, the bit count, [err] and [ovf].
   3. The CRC feed (for the chip's CRC unit): this clock's chain bit, valid when it is a frame bit
      and at least [skip] frame bits came before it; [frame_start] loads the CRC's init.
   [done_] (a frame has ended and its bytes have been read: not in a frame and the FIFO empty)
   and [err] are the thread's end-of-frame and error flags. *)

type cfg = {
  code : Linecode.cfg;
  stuff : Stuff.cfg;
  msb_first : bool;
  pattern : int;
  pmask : int;
  start_on_pattern : bool;
  half_duplex : bool;
  end_inactive : bool;
  end_burst : bool;
  skip : int;
}

let depth = 2

let usb_ls =
  { code = Linecode.usb; stuff = Stuff.usb; msb_first = false; pattern = 0x80; pmask = 0xFF; start_on_pattern = true;
    half_duplex = true; end_inactive = true; end_burst = false; skip = 8 }

let eth10 =
  { code = Linecode.pass; stuff = Stuff.off; msb_first = false; pattern = 0xD5; pmask = 0xFF; start_on_pattern = true;
    half_duplex = true; end_inactive = false; end_burst = true; skip = 0 }

(* ---- model ---- *)

type st = {
  dec : Linecode.dec;
  dst : Stuff.st;
  mutable cv : bool; mutable cb : int; mutable ce : bool;
  mutable hist : int;
  mutable hcount : int;
  mutable in_frame : bool;
  mutable nbits : int;
  mutable sh : int;
  mutable fbits : int;
  fifo : int Queue.t;
  mutable err : bool;
  mutable ovf : bool;
}

let init () =
  { dec = Linecode.dec_init (); dst = Stuff.init (); cv = false; cb = 0; ce = false; hist = 0; hcount = 0; in_frame = false; nbits = 0;
    sh = 0; fbits = 0; fifo = Queue.create (); err = false; ovf = false }

type inputs = { bit : int; valid : bool; active : bool; burst_end : bool; start : bool; stop : bool; tx_active : bool; pop : bool }

type outputs = { crc_bit : int; crc_valid : bool; frame_start : bool }

let done_ st = (not st.in_frame) && Queue.is_empty st.fifo

let matches c hist = (hist lxor c.pattern) land c.pmask = 0

let step c st (i : inputs) =
  (* 2. the framer on this clock's chain bit, and 3. the CRC feed *)
  let ending = st.in_frame && ((c.end_inactive && not i.active) || (c.end_burst && i.burst_end) || i.stop) in
  let crc_valid = st.in_frame && (not ending) && st.cv && st.fbits >= c.skip in
  let hist' = if st.cv then (st.hist lsr 1) lor (st.cb lsl 7) else st.hist in
  let hcount' = if st.cv then min 8 (st.hcount + 1) else st.hcount in
  let hcount' = if ending then 0 else hcount' in
  let start =
    i.start
    || ((not st.in_frame) && c.start_on_pattern && st.cv && hcount' = 8 && matches c hist'
        && not (c.half_duplex && i.tx_active)) in
  let out = { crc_bit = st.cb; crc_valid; frame_start = start } in
  if i.pop then ignore (Queue.take_opt st.fifo);
  if start then begin
    st.in_frame <- true; st.nbits <- 0; st.sh <- 0; st.fbits <- 0; st.err <- false; st.ovf <- false; Queue.clear st.fifo
  end
  else if ending then st.in_frame <- false
  else if st.in_frame then begin
    if st.ce then st.err <- true;
    if st.cv then begin
      st.sh <- (if c.msb_first then ((st.sh lsl 1) lor st.cb) land 0xFF else (st.sh lsr 1) lor (st.cb lsl 7));
      st.fbits <- min 255 (st.fbits + 1);
      st.nbits <- st.nbits + 1;
      if st.nbits = 8 then begin
        st.nbits <- 0;
        if Queue.length st.fifo < depth then Queue.push st.sh st.fifo else st.ovf <- true
      end
    end
  end;
  st.hist <- hist'; st.hcount <- hcount';
  (* 1. the chain *)
  (if i.valid then begin
     match Linecode.dec_step c.code st.dec i.bit with
     | Some b, cerr ->
       let keep, serr = Stuff.rx_step c.stuff st.dst b in
       st.cv <- keep; st.cb <- (if keep then b else st.cb); st.ce <- cerr || serr
     | None, cerr -> st.cv <- false; st.ce <- cerr
   end
   else (st.cv <- false; st.ce <- false));
  out

(* ---- RTL ---- *)
open Hardcaml
open Signal

type cfg_signals = {
  s_code : Linecode.cfg_signals;
  s_stuff : Stuff.cfg_signals;
  s_msb : Signal.t;
  s_pattern : Signal.t;
  s_pmask : Signal.t;
  s_start_on_pattern : Signal.t;
  s_half_duplex : Signal.t;
  s_end_inactive : Signal.t;
  s_end_burst : Signal.t;
  s_skip : Signal.t;   (* 8 bits *)
}

let cfg_const c =
  { s_code = Linecode.cfg_const c.code; s_stuff = Stuff.cfg_const c.stuff; s_msb = of_bool c.msb_first;
    s_pattern = of_int ~width:8 c.pattern; s_pmask = of_int ~width:8 c.pmask; s_start_on_pattern = of_bool c.start_on_pattern;
    s_half_duplex = of_bool c.half_duplex; s_end_inactive = of_bool c.end_inactive; s_end_burst = of_bool c.end_burst;
    s_skip = of_int ~width:8 c.skip }

let bug = ref ""
let is b = !bug = b

let bugs =
  [ "rx_pattern_old_history", "the start pattern is matched against the history before this bit";
    "rx_no_half_duplex", "a frame starts on the pattern while the transmitter is active";
    "rx_end_keeps_bit", "the chain bit of the clock a frame ends is still packed";
    "rx_start_keeps_fifo", "a frame start does not clear the FIFO";
    "rx_skip_off_by_one", "the CRC feed skips one frame bit more than configured";
    "rx_err_not_sticky", "the error flag shows only the last chain bit's error";
    "rx_msb_ignored", "bytes are packed LSB first even when MSB first is configured";
    "rx_history_kept_at_end", "the end of a frame does not restart the history count" ]

type out = {
  head : Signal.t; nonempty : Signal.t; count : Signal.t;
  in_frame : Signal.t; done_ : Signal.t; err : Signal.t; ovf : Signal.t;
  crc_bit : Signal.t; crc_valid : Signal.t; frame_start : Signal.t;
  dbg : (string * Signal.t) list;
}

let create ~clock ~clear ~(cfg : cfg_signals) ~bit ~valid ~active ~burst_end ~start ~stop ~tx_active ~pop =
  let spec = Reg_spec.create ~clock ~clear () in
  (* 1. the chain *)
  let dec = Linecode.decoder ~clock ~clear ~cfg:cfg.s_code ~valid ~sym:bit in
  let srx = Stuff.rx ~clock ~clear ~restart:gnd ~cfg:cfg.s_stuff ~valid:dec.out_valid ~b:dec.out_bit in
  let cv = reg spec srx.keep in
  let cb = wire 1 in
  cb <== reg spec (mux2 srx.keep dec.out_bit cb);
  let ce = reg spec (valid &: (dec.err |: srx.err)) in
  (* 2. the framer *)
  let in_frame = wire 1 and nbits = wire 3 and sh = wire 8 and fbits = wire 8 and hist = wire 8 in
  let err = wire 1 and ovf = wire 1 in
  let ending = in_frame &: ((cfg.s_end_inactive &: ~:active) |: (cfg.s_end_burst &: burst_end) |: stop) in
  let skip = if is "rx_skip_off_by_one" then cfg.s_skip +:. 1 else cfg.s_skip in
  let crc_valid = in_frame &: ~:ending &: cv &: (uresize fbits 9 >=: uresize skip 9) in
  let hist' = mux2 cv (concat_msb [ cb; select hist 7 1 ]) hist in
  let hm = if is "rx_pattern_old_history" then hist else hist' in
  let hcount = wire 4 in
  let hcount' = mux2 (if is "rx_history_kept_at_end" then gnd else ending) (zero 4) (mux2 (cv &: (hcount <>:. 8)) (hcount +:. 1) hcount) in
  hcount <== reg spec hcount';
  let matches = (((hm ^: cfg.s_pattern) &: cfg.s_pmask) ==:. 0) &: (hcount' ==:. 8) in
  let busy_tx = if is "rx_no_half_duplex" then gnd else cfg.s_half_duplex &: tx_active in
  let frame_start = start |: (~:in_frame &: cfg.s_start_on_pattern &: cv &: matches &: ~:busy_tx) in
  let packing = in_frame &: (if is "rx_end_keeps_bit" then vdd else ~:ending) &: ~:frame_start in
  let shift_in = packing &: cv in
  let msb = if is "rx_msb_ignored" then gnd else cfg.s_msb in
  let sh' = mux2 msb (concat_msb [ select sh 6 0; cb ]) (concat_msb [ cb; select sh 7 1 ]) in
  let byte_done = shift_in &: (nbits ==:. 7) in
  (* the FIFO: two slots *)
  let count = wire 2 and rd = wire 1 and wr = wire 1 and slot0 = wire 8 and slot1 = wire 8 in
  let nonempty = count <>:. 0 in
  let popping = pop &: nonempty in
  let room = (count <>:. depth) |: popping in
  let clear_fifo = if is "rx_start_keeps_fifo" then gnd else frame_start in
  let push = byte_done &: room &: ~:clear_fifo in
  slot0 <== reg spec (mux2 (push &: (wr ==:. 0)) sh' slot0);
  slot1 <== reg spec (mux2 (push &: (wr ==:. 1)) sh' slot1);
  wr <== reg spec (mux2 clear_fifo gnd (mux2 push (~:wr) wr));
  rd <== reg spec (mux2 clear_fifo gnd (mux2 popping (~:rd) rd));
  count <== reg spec (mux2 clear_fifo (zero 2) (count +: uresize push 2 -: uresize popping 2));
  let head = mux2 rd slot1 slot0 in
  in_frame <== reg spec (mux2 frame_start vdd (mux2 ending gnd in_frame));
  nbits <== reg spec (mux2 frame_start (zero 3) (mux2 shift_in (nbits +:. 1) nbits));
  sh <== reg spec (mux2 frame_start (zero 8) (mux2 shift_in sh' sh));
  fbits <== reg spec (mux2 frame_start (zero 8) (mux2 (shift_in &: (fbits <>:. 255)) (fbits +:. 1) fbits));
  let err_next = if is "rx_err_not_sticky" then packing &: ce else err |: (packing &: ce) in
  err <== reg spec (mux2 frame_start gnd err_next);
  ovf <== reg spec (mux2 frame_start gnd (ovf |: (byte_done &: ~:room)));
  hist <== reg spec hist';
  let done_ = ~:in_frame &: ~:nonempty in
  { head; nonempty; count; in_frame; done_; err; ovf; crc_bit = cb; crc_valid; frame_start;
    dbg = [ "rx_cv", cv; "rx_cb", cb; "rx_ce", ce; "rx_hist", hist; "rx_hcount", hcount; "rx_nbits", nbits; "rx_sh", sh; "rx_fbits", fbits ] }
