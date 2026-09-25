(* Independent PS/2 models: a PC-side host and a keyboard-side device, written from the protocol
   description (Chapweske, "The PS/2 Mouse/Keyboard Protocol"; the IBM PS/2 technical reference),
   not from the firmware. Both are clocked agents that sample the two open-collector lines every
   100 ns, and each checks the other side's timing:

   device to host: the device drives the clock at 10 to 16.7 kHz, each phase 30 to 50 us; data
   changes only while the clock is high, at least 5 us after the rising edge and at least 5 us
   before the falling edge; the host samples on the falling edge; start 0, eight data bits lsb
   first, odd parity, stop 1. The host may inhibit by holding the clock low for at least 100 us;
   a frame whose eleventh falling edge has not happened is then void.

   host to device: clock low >= 100 us, data low, clock released; the device clocks; the host
   changes data only while the clock is low and the device reads while it is high; eight data
   bits, parity, stop 1; then the device pulls data low through an eleventh clock (acknowledge). *)

let tick_hz = 10e6

type violation = { at : int; what : string }

let pp_violations vs =
  String.concat "; " (List.map (fun v -> Printf.sprintf "%.1fus %s" (float v.at /. 1e9) v.what) (List.rev vs))

let odd_parity b = let n = ref 0 in for i = 0 to 7 do n := !n + ((b lsr i) land 1) done; 1 - (!n land 1)
let to_us t = float t /. 1e9

(* ---------------------------------------------------------------- host (PC) *)
module Host = struct
  type cmd = { at : int; byte : int; bad_parity : bool }
  type t = {
    clk : Sim.Oc.t; data : Sim.Oc.t; who : string;
    mutable prev_clk : int; mutable prev_data : int;
    mutable nbits : int; mutable bits : int list;
    mutable last_fall : int; mutable last_rise : int; mutable last_data_change : int;
    mutable received : (int * int * bool) list;   (* time, byte, parity ok; newest first *)
    mutable voided : int;                          (* frames cut short by an inhibit or a stall *)
    mutable violations : violation list;
    mutable inhibits : (int * int) list;           (* scheduled: start, duration *)
    mutable inhibit_until : int;
    mutable cmds : cmd list;                       (* scheduled, in time order *)
    mutable sending : (cmd * int * int) option;    (* command, phase, falling edges seen *)
    mutable cmd_results : (int * int * bool) list; (* time, byte, acknowledged *)
    mutable phase_t : int;
  }
  let create ~clk ~data ?(who = "model-host") () =
    { clk; data; who; prev_clk = 1; prev_data = 1; nbits = 0; bits = []; last_fall = 0; last_rise = 0;
      last_data_change = 0; received = []; voided = 0; violations = []; inhibits = []; inhibit_until = 0;
      cmds = []; sending = None; cmd_results = []; phase_t = 0 }
  let viol h now what = h.violations <- { at = now; what } :: h.violations
  let set h line pull now = Sim.Oc.set line ~who:h.who ~pull ~now

  let finish_frame h now =
    let bits = Array.of_list (List.rev h.bits) in
    let byte = ref 0 in
    for i = 1 to 8 do byte := !byte lor (bits.(i) lsl (i - 1)) done;
    if bits.(0) <> 0 then viol h now "start bit not 0";
    if bits.(10) <> 1 then viol h now "stop bit not 1";
    h.received <- (now, !byte, bits.(9) = odd_parity !byte) :: h.received;
    h.nbits <- 0; h.bits <- []

  let void_frame h = if h.nbits > 0 then (h.voided <- h.voided + 1; h.nbits <- 0; h.bits <- [])

  let rx_step h now c d =
    if c = 0 && h.prev_clk = 1 then begin
      if h.nbits > 0 then begin
        let high = to_us (now - h.last_rise) in
        if high < 30. || high > 50. then viol h now (Printf.sprintf "clock high %.1fus" high);
        if h.last_data_change > h.last_rise && to_us (now - h.last_data_change) < 5. then
          viol h now (Printf.sprintf "data setup %.1fus" (to_us (now - h.last_data_change)))
      end;
      h.bits <- d :: h.bits; h.nbits <- h.nbits + 1; h.last_fall <- now;
      if h.nbits = 11 then finish_frame h now
    end;
    if c = 1 && h.prev_clk = 0 then begin
      if h.nbits > 0 then begin
        let low = to_us (now - h.last_fall) in
        if low < 30. || low > 50. then viol h now (Printf.sprintf "clock low %.1fus" low)
      end;
      h.last_rise <- now
    end;
    if d <> h.prev_data then begin
      if h.nbits > 0 && c = 0 then viol h now "data changed while clock low";
      if h.nbits > 0 && c = 1 && to_us (now - h.last_rise) < 5. then viol h now "data changed < 5us after rise";
      h.last_data_change <- now
    end;
    if h.nbits > 0 && now - h.last_fall > Sim.us 2000. then void_frame h

  let tx_step h now c (cmd, phase, edges) =
    let par = if cmd.bad_parity then 1 - odd_parity cmd.byte else odd_parity cmd.byte in
    match phase with
    | 0 -> if now - h.phase_t >= Sim.us 110. then (set h h.data true now; h.phase_t <- now; h.sending <- Some (cmd, 1, 0))
    | 1 -> if now - h.phase_t >= Sim.us 5. then (set h h.clk false now; h.phase_t <- now; h.sending <- Some (cmd, 2, 0))
    | _ ->
      if now - h.phase_t > Sim.us 16000. then begin
        viol h now "device did not clock the command";
        set h h.data false now; h.cmd_results <- (now, cmd.byte, false) :: h.cmd_results; h.sending <- None
      end else if c = 0 && h.prev_clk = 1 then begin
        let e = edges + 1 in
        h.phase_t <- now;
        if e <= 8 then set h h.data ((cmd.byte lsr (e - 1)) land 1 = 0) now
        else if e = 9 then set h h.data (par = 0) now
        else if e = 10 then set h h.data false now;
        if e = 11 then begin
          h.cmd_results <- (now, cmd.byte, Sim.Oc.level h.data ~now = 0) :: h.cmd_results;
          h.sending <- None
        end else h.sending <- Some (cmd, phase, e)
      end

  let fire h now =
    let c = Sim.Oc.level h.clk ~now and d = Sim.Oc.level h.data ~now in
    (match h.inhibits with
     | (t0, dur) :: rest when now >= t0 && h.sending = None && h.inhibit_until = 0 ->
       set h h.clk true now; h.inhibit_until <- now + dur; h.inhibits <- rest; void_frame h
     | _ -> ());
    if h.inhibit_until > 0 && now >= h.inhibit_until then (set h h.clk false now; h.inhibit_until <- 0);
    (match h.cmds, h.sending with
     | cmd :: rest, None when now >= cmd.at && h.inhibit_until = 0 ->
       h.cmds <- rest; void_frame h; set h h.clk true now; h.phase_t <- now; h.sending <- Some (cmd, 0, 0)
     | _ -> ());
    (match h.sending with
     | Some s -> tx_step h now c s
     | None -> if h.inhibit_until = 0 && not (Sim.Oc.pulled_by h.clk h.who) then rx_step h now c d);
    h.prev_clk <- c; h.prev_data <- d
end

(* ---------------------------------------------------------------- device (keyboard) *)
module Device = struct
  type state =
    | Idle
    | Tx of int * int          (* bit 0..10, step 0 set data / 1 check and clock low / 2 release / 3 gap *)
    | Rts_wait
    | Rx of int * int          (* pulse 1..11, step 0 low / 1 release / 2 sample / 3 end *)
  type t = {
    clk : Sim.Oc.t; data : Sim.Oc.t; who : string;
    half : int;
    mutable queue : int list;
    mutable sent : (int * int) list;          (* time, byte: frames completed, newest first *)
    mutable aborted : int;
    mutable received : (int * int * bool) list;     (* time, command byte, parity ok *)
    mutable violations : violation list;
    mutable state : state;
    mutable next_at : int;
    mutable t0 : int;
    mutable idle_since : int;
    mutable rx_bits : int list;
    mutable expect_arg : bool;
    mutable leds : int list;
    mutable bad_parity_next : bool;           (* control: send the next byte with even parity *)
    mutable prev_data : int;
    mutable rts_since : int;
    rts_delay : int;
  }
  let create ~clk ~data ~hz ?(rts_delay = Sim.us 60.) ?(who = "model-dev") () =
    { clk; data; who; half = Sim.period_of_hz (2. *. hz); queue = []; sent = []; aborted = 0; received = [];
      violations = []; state = Idle; next_at = 0; t0 = 0; idle_since = 0; rx_bits = []; expect_arg = false;
      leds = []; bad_parity_next = false; prev_data = 1; rts_since = -1; rts_delay }
  let viol d now what = d.violations <- { at = now; what } :: d.violations
  let set d line pull now = Sim.Oc.set line ~who:d.who ~pull ~now

  let respond d byte ok =
    let r =
      if not ok then [ 0xFE ]
      else if d.expect_arg then (d.expect_arg <- false; d.leds <- byte :: d.leds; [ 0xFA ])
      else match byte with
        | 0xFF -> [ 0xFA; 0xAA ] | 0xED -> d.expect_arg <- true; [ 0xFA ] | 0xEE -> [ 0xEE ]
        | 0xF2 -> [ 0xFA; 0xAB; 0x83 ] | _ -> [ 0xFA ] in
    d.queue <- r @ d.queue

  let fire d now =
    let c = Sim.Oc.level d.clk ~now and dt = Sim.Oc.level d.data ~now in
    let q = d.half / 2 in
    (match d.state with
     | Idle ->
       (* request to send: data low with the clock released, held for 10 us (not a line still rising) *)
       if c = 1 && dt = 0 then begin
         if d.rts_since < 0 then d.rts_since <- now
         else if now - d.rts_since >= Sim.us 10. then (d.state <- Rts_wait; d.next_at <- now + d.rts_delay; d.rts_since <- -1)
       end else d.rts_since <- -1;
       if d.state <> Idle then ()
       else if c = 0 || dt = 0 then d.idle_since <- now
       else if d.queue <> [] && now - d.idle_since >= Sim.us 50. then (d.state <- Tx (0, 0); d.next_at <- now)
     | Rts_wait -> if now >= d.next_at then (d.state <- Rx (1, 0); d.next_at <- now; d.rx_bits <- [])
     | Tx (bit, step) when now >= d.next_at ->
       let byte = List.hd d.queue in
       let p = if d.bad_parity_next then 1 - odd_parity byte else odd_parity byte in
       let v = if bit = 0 then 0 else if bit <= 8 then (byte lsr (bit - 1)) land 1 else if bit = 9 then p else 1 in
       (match step with
        | 0 -> set d d.data (v = 0) now; d.state <- Tx (bit, 1); d.next_at <- now + q
        | 1 ->
          if c = 0 then begin   (* host inhibit before this falling edge: abort, keep the byte *)
            set d d.data false now; d.aborted <- d.aborted + 1; d.state <- Idle; d.idle_since <- now
          end else (set d d.clk true now; d.state <- Tx (bit, 2); d.next_at <- now + d.half)
        | 2 ->
          set d d.clk false now;
          if bit = 10 then begin
            d.sent <- (now, byte) :: d.sent; d.queue <- List.tl d.queue; d.bad_parity_next <- false;
            d.state <- Idle; d.idle_since <- now
          end else (d.state <- Tx (bit, 3); d.next_at <- now + q)
        | _ -> d.state <- Tx (bit + 1, 0))
     | Rx (pulse, step) when now >= d.next_at ->
       (match step with
        | 0 -> set d d.clk true now; d.state <- Rx (pulse, 1); d.next_at <- now + d.half
        | 1 -> set d d.clk false now; d.state <- Rx (pulse, 2); d.next_at <- now + Sim.us 10.
        | 2 ->
          if pulse <= 10 then d.rx_bits <- dt :: d.rx_bits;
          if pulse = 10 then set d d.data true now;          (* acknowledge *)
          d.state <- Rx (pulse, 3); d.next_at <- now + d.half - Sim.us 10.
        | _ ->
          if pulse = 11 then begin
            set d d.data false now; d.state <- Idle; d.idle_since <- now;
            let bs = Array.of_list (List.rev d.rx_bits) in
            let byte = ref 0 in
            for i = 0 to 7 do byte := !byte lor (bs.(i) lsl i) done;
            let ok = bs.(8) = odd_parity !byte in
            d.received <- (now, !byte, ok) :: d.received;
            if bs.(9) <> 1 then viol d now "command stop bit not 1";
            respond d !byte ok
          end else (d.state <- Rx (pulse + 1, 0); d.next_at <- now))
     | _ -> ());
    (match d.state with
     | Rx (pulse, step) when dt <> d.prev_data && c = 1 && step >= 2 && pulse <= 10
                             && not (Sim.Oc.pulled_by d.data d.who) ->
       viol d now (Printf.sprintf "host changed data while clock high (pulse %d)" pulse)
     | _ -> ());
    d.prev_data <- dt
end
