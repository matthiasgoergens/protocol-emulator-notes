(* Peer models: the devices at the other end of each bus, written from the protocols' definitions,
   not from the firmware in fw.ml. They see and drive bus levels one clock at a time and know
   nothing of slots, threads or the firmware's schedule. The timing they apply is real time at the
   60 MHz core clock (one clock = 16.67 ns). *)

let clock_hz = 60_000_000.

(* ------------------------------------------------------------------------------------------ *)
(* UART 8N1, lsb first *)
module Uart = struct
  (* An ideal transmitter: frame i starts (line low) at clock [start_i] and lasts ten bits of
     [bit] clocks (fractional); outside frames the line is high. [level c] is the line at clock c. *)
  let tx ~bit (frames : (float * int) list) =
    let frames = Array.of_list frames in
    fun c ->
      let c = float c in
      let v = ref 1 in
      Array.iter (fun (st, b) ->
          if c >= st && c < st +. (10. *. bit) then begin
            let k = int_of_float ((c -. st) /. bit) in
            v := if k = 0 then 0 else if k <= 8 then (b lsr (k - 1)) land 1 else 1
          end) frames;
      !v

  (* back-to-back frames from clock [first], each [gap] bits after the previous one's start
     (gap >= 10) *)
  let frames ~bit ~first ?(gap = 10.) bytes = List.mapi (fun i b -> (first +. (float i *. gap *. bit), b)) bytes

  (* An ideal receiver at [bit] clocks a bit: a start is the first low clock after a high one;
     bits are sampled at the start + (k + 1/2) bit. Returns (start clock, byte, stop bit high). *)
  let rx ~bit ~clocks (level : int -> int) =
    let res = ref [] and c = ref 1 in
    while !c < clocks do
      if level (!c - 1) = 1 && level !c = 0 then begin
        let st = !c in
        let at k = st + int_of_float ((float k +. 0.5) *. bit) in
        if at 9 >= clocks then c := clocks
        else begin
          let byte = ref 0 in
          for k = 1 to 8 do byte := !byte lor (level (at k) lsl (k - 1)) done;
          res := (st, !byte, level (at 9) = 1) :: !res;
          c := at 9 + 1
        end
      end else incr c
    done;
    List.rev !res
end

(* ------------------------------------------------------------------------------------------ *)
(* SPI. A mode is (CPOL, CPHA) and a bit order; SCLK idles at CPOL. CPHA 0: both sides sample on
   the leading edge (away from idle) and change their output after the trailing edge, the first
   bit being presented when CS falls; CPHA 1: change after the leading edge, sample on the
   trailing edge. *)
module Spi = struct
  type mode = { cpol : int; cpha : int; msb : bool }

  let bit_of ~msb b k = if msb then (b lsr (7 - k)) land 1 else (b lsr k) land 1

  (* A target. [replies] are the bytes it sends, one per byte of the transaction, 0xFF when they
     run out; [got] collects the bytes it received, (byte, complete), a partial byte at CS rise
     included with complete = false. Its MISO output follows its shift [delay] clocks late (the
     output's valid time); undriven (None) while CS is high. *)
  type target = {
    mode : mode; delay : int;
    replies : int Queue.t;
    mutable got : (int * bool) list;    (* newest first *)
    mutable p_sclk : int; mutable p_cs : int;
    mutable k : int;                    (* bits of the current byte done *)
    mutable rx : int; mutable tx : int;
    mutable out : int option;           (* the level MISO is moving to *)
    pipe : int option Queue.t;          (* the last [delay] values of [out] *)
  }

  let target ?(delay = 0) ~mode replies =
    let q = Queue.create () in
    List.iter (fun b -> Queue.push b q) replies;
    let pipe = Queue.create () in
    for _ = 1 to delay do Queue.push None pipe done;
    { mode; delay; replies = q; got = []; p_sclk = mode.cpol; p_cs = 1; k = 0; rx = 0; tx = 0xFF; out = None; pipe }

  let next_reply t = match Queue.take_opt t.replies with Some b -> b | None -> 0xFF

  (* one clock: the lines as they are in this clock; returns MISO for this clock (None: not
     driven) *)
  let step t ~sclk ~mosi ~cs =
    let m = t.mode in
    let lead = t.p_sclk = m.cpol && sclk <> m.cpol and trail = t.p_sclk <> m.cpol && sclk = m.cpol in
    let sample () =
      t.rx <- (if m.msb then ((t.rx lsl 1) lor mosi) land 0xFF else (t.rx lsr 1) lor (mosi lsl 7));
      t.k <- t.k + 1;
      if t.k = 8 then (t.got <- (t.rx, true) :: t.got; t.k <- 0; t.rx <- 0) in
    let present k = t.out <- Some (bit_of ~msb:m.msb t.tx k) in
    if t.p_cs = 1 && cs = 0 then begin
      t.k <- 0; t.rx <- 0; t.tx <- next_reply t;
      if m.cpha = 0 then present 0
    end else if cs = 1 then begin
      if t.p_cs = 0 && t.k > 0 then t.got <- (t.rx, false) :: t.got;
      t.out <- None; t.k <- 0
    end else begin
      (* CS low *)
      if m.cpha = 0 then begin
        if lead then sample ()
        else if trail then begin
          (* after a whole byte the next reply's first bit; else the byte's next bit *)
          if t.k = 0 then (t.tx <- next_reply t; present 0) else present t.k
        end
      end else begin
        if lead then present t.k
        else if trail then begin
          sample ();
          if t.k = 0 then t.tx <- next_reply t
        end
      end
    end;
    t.p_sclk <- sclk; t.p_cs <- cs;
    if t.delay = 0 then t.out
    else begin
      Queue.push t.out t.pipe;
      Queue.pop t.pipe
    end
end

(* ------------------------------------------------------------------------------------------ *)
(* I2C (NXP UM10204). Open-drain lines: a line is low when any device pulls it low and high
   otherwise. [Line] adds edge times: a line that starts to fall reads low [tf] clocks later and
   one released reads high [tr] clocks later (one threshold, at the end of the edge). *)
module I2c = struct
  type line = { mutable lvl : int; mutable want : int; mutable since : int; tr : int; tf : int }

  let line ~tr ~tf = { lvl = 1; want = 1; since = 0; tr; tf }

  (* this clock's level of a line that [pulled] devices pull low *)
  let line_step l ~pulled =
    let w = if pulled then 0 else 1 in
    if w <> l.want then (l.want <- w; l.since <- 0) else l.since <- l.since + 1;
    if l.lvl <> l.want && l.since >= (if l.want = 0 then l.tf else l.tr) then l.lvl <- l.want;
    l.lvl

  (* What a target saw and did, in order. *)
  type event =
    | Ev_start | Ev_restart | Ev_stop
    | Ev_addr of int * int * bool          (* 7-bit address, R/W bit, acknowledged *)
    | Ev_write of int * bool               (* a byte written to it, acknowledged *)
    | Ev_read of int * bool                (* a byte it sent, acknowledged by the controller *)

  let event_to_string = function
    | Ev_start -> "S" | Ev_restart -> "Sr" | Ev_stop -> "P"
    | Ev_addr (a, rw, ack) -> Printf.sprintf "A%02x%s%s" a (if rw = 1 then "r" else "w") (if ack then "+" else "-")
    | Ev_write (b, ack) -> Printf.sprintf "W%02x%s" b (if ack then "+" else "-")
    | Ev_read (b, ack) -> Printf.sprintf "R%02x%s" b (if ack then "+" else "-")

  (* A target with a 7-bit address and 256 byte registers: a write's first data byte sets the
     register pointer, later ones are stored at it (incrementing); a read returns the register
     at the pointer (incrementing). It acknowledges its address and every byte written, except
     after [nack_after] written bytes of a transaction. It drives SDA [t_vd] clocks after SCL
     falls (its data valid time) and, after a falling SCL edge, may hold SCL low for
     [stretch ()] clocks. It reads SDA when SCL rises. *)
  type target = {
    addr : int;
    regs : int array;
    t_vd : int;
    stretch : unit -> int;
    nack_after : int option;
    mutable events : event list;          (* newest first *)
    mutable p_sda : int; mutable p_scl : int;
    mutable phase : [ `Idle | `Addr | `Wr | `Rd | `Rd_ack | `Ignore ];
    mutable bits : int; mutable sh : int;
    mutable ptr : int; mutable nwr : int;
    mutable ack_clock : bool;             (* in the ninth clock of a byte it acknowledges *)
    mutable sda_low : bool; mutable sda_at : int; mutable sda_next : bool;   (* SDA drive, pending change *)
    mutable hold : int;                   (* clocks left of SCL held low *)
    mutable clock : int;
    mutable started : bool;
  }

  let target ?(t_vd = 4) ?(stretch = fun () -> 0) ?nack_after ~addr () =
    { addr; regs = Array.init 256 (fun i -> (i * 37 + 11) land 0xFF); t_vd; stretch; nack_after; events = [];
      p_sda = 1; p_scl = 1; phase = `Idle; bits = 0; sh = 0; ptr = 0; nwr = 0; ack_clock = false;
      sda_low = false; sda_at = max_int; sda_next = false; hold = 0; clock = 0; started = false }

  let ev t e = t.events <- e :: t.events
  let set_sda t low = t.sda_next <- low; t.sda_at <- t.clock + t.t_vd

  (* one clock on the bus levels [sda] and [scl]; returns (pull SDA low, pull SCL low) for the
     next clock *)
  let step t ~sda ~scl =
    t.clock <- t.clock + 1;
    if t.clock >= t.sda_at then (t.sda_low <- t.sda_next; t.sda_at <- max_int);
    let scl_rise = t.p_scl = 0 && scl = 1 and scl_fall = t.p_scl = 1 && scl = 0 in
    if t.p_scl = 1 && scl = 1 && t.p_sda = 1 && sda = 0 then begin
      (* START or repeated START *)
      ev t (if t.started then Ev_restart else Ev_start);
      t.started <- true; t.phase <- `Addr; t.bits <- 0; t.sh <- 0; t.nwr <- 0; t.ack_clock <- false;
      t.sda_low <- false; t.sda_at <- max_int
    end else if t.p_scl = 1 && scl = 1 && t.p_sda = 0 && sda = 1 && t.started then begin
      ev t Ev_stop; t.started <- false; t.phase <- `Idle; t.sda_low <- false; t.sda_at <- max_int
    end else if scl_rise then begin
      match t.phase with
      | `Addr | `Wr when not t.ack_clock -> t.sh <- ((t.sh lsl 1) lor sda) land 0xFF; t.bits <- t.bits + 1
      | `Rd_ack ->
        (* the controller's ACK (0) or NACK (1) to the byte just sent *)
        let acked = sda = 0 in
        (match t.events with Ev_read (b, _) :: r -> t.events <- Ev_read (b, acked) :: r | _ -> ());
        t.phase <- (if acked then `Rd else `Ignore); t.bits <- 0
      | _ -> ()
    end else if scl_fall then begin
      let h = t.stretch () in
      if h > 0 then t.hold <- h;
      (match t.phase with
       | (`Addr | `Wr) when t.ack_clock ->
         (* the end of our acknowledge clock *)
         t.ack_clock <- false; set_sda t false;
         if t.phase = `Rd then ()
       | `Addr when t.bits = 8 ->
         let a = t.sh lsr 1 and rw = t.sh land 1 in
         let ok = a = t.addr in
         ev t (Ev_addr (a, rw, ok));
         if ok then (set_sda t true; t.ack_clock <- true; t.bits <- 0;
                     if rw = 1 then t.phase <- `Rd else t.phase <- `Wr)
         else t.phase <- `Ignore
       | `Wr when t.bits = 8 ->
         let ok = match t.nack_after with Some n -> t.nwr < n | None -> true in
         ev t (Ev_write (t.sh, ok));
         if t.nwr = 0 then t.ptr <- t.sh else (t.regs.(t.ptr) <- t.sh; t.ptr <- (t.ptr + 1) land 0xFF);
         t.nwr <- t.nwr + 1; t.bits <- 0;
         if ok then (set_sda t true; t.ack_clock <- true) else t.phase <- `Ignore
       | `Rd ->
         if t.bits = 0 then begin
           (* the first falling edge after our ACK (or the controller's ACK): the next byte *)
           t.sh <- t.regs.(t.ptr); t.ptr <- (t.ptr + 1) land 0xFF;
           ev t (Ev_read (t.sh, false))
         end;
         if t.bits < 8 then begin
           set_sda t ((t.sh lsr (7 - t.bits)) land 1 = 0); t.bits <- t.bits + 1
         end else begin
           set_sda t false; t.phase <- `Rd_ack
         end
       | _ -> ());
      (* after our ACK clock in a read the first data bit goes out on this same edge *)
      ()
    end;
    (* in a read, the edge that ends our address ACK clock starts the first data bit *)
    t.p_sda <- sda; t.p_scl <- scl;
    if t.hold > 0 then t.hold <- t.hold - 1;
    (t.sda_low, t.hold > 0)
end
