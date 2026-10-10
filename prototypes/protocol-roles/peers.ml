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
  (* A controller: SCLK [act] clocks active and [idl] clocks idle a bit, CS falling [css] clocks
     before the first edge and rising [csh] after the last, [gap] more idle clocks between bytes.
     MOSI changes on the shift edge (CPHA 0: the first bit at CS fall, the others at trailing
     edges; CPHA 1: at leading edges); MISO is read at the sampling edge, in the clock the edge is
     driven. The bus levels are one clock behind the controller's own outputs, as a wire would
     be; [start] delays everything. Returns its outputs for a clock; [rx] collects MISO bytes. *)
  type controller = {
    cm : mode; tx : int array;
    sched : (int * [ `Cs of int | `Sclk of int | `Mosi of int | `Sample of int ]) list;   (* clock, action *)
    mutable rx : int list;                  (* newest first *)
    mutable cur : int;
    mutable o_sclk : int; mutable o_mosi : int; mutable o_cs : int;
    mutable left : (int * [ `Cs of int | `Sclk of int | `Mosi of int | `Sample of int ]) list;
    mutable done_ : bool;
  }

  let controller ?(start = 0) ?(gap = 0) ~mode ~act ~idl ~css ~csh bytes =
    let tx = Array.of_list bytes in
    let ev = ref [] and t = ref start in
    let add a = ev := (!t, a) :: !ev in
    let active = 1 - mode.cpol in
    add (`Cs 0);
    if mode.cpha = 0 then add (`Mosi (bit_of ~msb:mode.msb tx.(0) 0));
    t := !t + css;
    Array.iteri (fun i b ->
        for k = 0 to 7 do
          add (`Sclk active);
          if mode.cpha = 0 then add (`Sample (8 * i + k)) else add (`Mosi (bit_of ~msb:mode.msb b k));
          t := !t + act;
          add (`Sclk mode.cpol);
          if mode.cpha = 1 then add (`Sample (8 * i + k))
          else if k < 7 then add (`Mosi (bit_of ~msb:mode.msb b (k + 1)))
          else if i + 1 < Array.length tx then add (`Mosi (bit_of ~msb:mode.msb tx.(i + 1) 0));
          t := !t + idl + (if k = 7 then gap else 0)
        done) tx;
    t := !t - idl + csh;
    add (`Cs 1);
    let sched = List.rev !ev in
    { cm = mode; tx; sched; rx = []; cur = 0; o_sclk = mode.cpol; o_mosi = 0; o_cs = 1; left = sched; done_ = false }

  (* one clock: [miso] is the line now; returns (sclk, mosi, cs) driven during the next clock *)
  let controller_step c ~miso =
    let bits = ref [] in
    let rec go () = match c.left with
      | (t, a) :: r when t <= c.cur ->
        c.left <- r;
        (match a with
         | `Cs v -> c.o_cs <- v | `Sclk v -> c.o_sclk <- v | `Mosi v -> c.o_mosi <- v
         | `Sample k -> bits := (k, miso) :: !bits);
        go ()
      | _ -> () in
    go ();
    List.iter (fun (k, v) ->
        let i = k / 8 and j = k mod 8 in
        if j = 0 then c.rx <- 0 :: c.rx;
        let b = List.hd c.rx in
        let b = if c.cm.msb then b lor (v lsl (7 - j)) else b lor (v lsl j) in
        c.rx <- b :: List.tl c.rx;
        ignore i) (List.rev !bits);
    if c.left = [] then c.done_ <- true;
    c.cur <- c.cur + 1;
    (c.o_sclk, c.o_mosi, c.o_cs)
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

  (* A controller, as a script of steps run one clock at a time. Its timing is given in clocks;
     it waits for SCL to read high after releasing it (a target may stretch the clock) and times
     its high phase from then. It records the ACKs it sees and the bytes it reads. *)
  type cstep =
    | Pull_sda of bool | Pull_scl of bool    (* true: pull low; false: release *)
    | Delay of int                           (* clocks *)
    | Until_scl_high
    | Read_sda of (int -> unit)
    | Act of (unit -> unit)

  type ctiming = { c_low : int; c_high : int; c_hd_dat : int; c_hd_sta : int; c_su_sta : int; c_su_sto : int;
                   c_buf : int; c_smp : int }

  (* 100 kHz and 400 kHz with the specification's minima met: tLOW 5.0 / 1.33 us, tHIGH 5.0 /
     1.17 us (from SCL seen high), tHD;STA 4.17 / 0.6 us; SDA changed 333 ns after it starts to
     pull SCL low, the transmitter's internal hold of at least 300 ns that keeps a data change out
     of SCL's falling edge (UM10204, note to table 10) *)
  let c_standard = { c_low = 300; c_high = 300; c_hd_dat = 20; c_hd_sta = 250; c_su_sta = 290; c_su_sto = 250; c_buf = 290; c_smp = 150 }
  let c_fast = { c_low = 80; c_high = 70; c_hd_dat = 20; c_hd_sta = 36; c_su_sta = 38; c_su_sto = 38; c_buf = 80; c_smp = 35 }

  (* scaled to another clock rate (for finding the fastest SCL a target follows) *)
  let c_scaled (t : ctiming) k =
    let f x = max 1 (int_of_float (Float.round (float x *. k))) in
    { c_low = f t.c_low; c_high = f t.c_high; c_hd_dat = f t.c_hd_dat; c_hd_sta = f t.c_hd_sta; c_su_sta = f t.c_su_sta;
      c_su_sto = f t.c_su_sto; c_buf = f t.c_buf; c_smp = f t.c_smp }

  type controller = {
    q : cstep Queue.t;
    mutable wait : int;
    mutable c_sda_low : bool; mutable c_scl_low : bool;
    mutable acks : bool list;          (* newest first: true = ACK *)
    mutable reads : int list;          (* newest first *)
    mutable done_ : bool;
  }

  type cop = C_start | C_restart | C_stop | C_write of int | C_read of bool   (* read: ACK it? *)

  let controller (t : ctiming) ops =
    let c = { q = Queue.create (); wait = 0; c_sda_low = false; c_scl_low = false; acks = []; reads = []; done_ = false } in
    let add l = List.iter (fun s -> Queue.push s c.q) l in
    (* one clock pulse with SCL low at its start: SDA set [c_hd_dat] after, SCL released at
       [c_low], seen high, [sample] at [c_smp] after, SCL low [c_high] after seen high *)
    let pulse ?(sample = fun _ -> ()) sda_low =
      add [ Delay t.c_hd_dat; Pull_sda sda_low; Delay (t.c_low - t.c_hd_dat); Pull_scl false; Until_scl_high;
            Delay t.c_smp; Read_sda sample; Delay (t.c_high - t.c_smp); Pull_scl true ] in
    List.iter (function
        | C_start -> add [ Delay t.c_buf; Pull_sda true; Delay t.c_hd_sta; Pull_scl true ]
        | C_restart ->
          add [ Delay t.c_hd_dat; Pull_sda false; Delay (t.c_low - t.c_hd_dat); Pull_scl false; Until_scl_high;
                Delay t.c_su_sta; Pull_sda true; Delay t.c_hd_sta; Pull_scl true ]
        | C_stop ->
          add [ Delay t.c_hd_dat; Pull_sda true; Delay (t.c_low - t.c_hd_dat); Pull_scl false; Until_scl_high;
                Delay t.c_su_sto; Pull_sda false; Delay t.c_buf ]
        | C_write b ->
          for k = 7 downto 0 do pulse ((b lsr k) land 1 = 0) done;
          pulse ~sample:(fun v -> c.acks <- (v = 0) :: c.acks) false
        | C_read ack ->
          let v = ref 0 in
          for _ = 7 downto 0 do pulse ~sample:(fun x -> v := (!v lsl 1) lor x) false done;
          add [ Act (fun () -> c.reads <- !v :: c.reads) ];
          pulse ack) ops;
    add [ Act (fun () -> c.done_ <- true) ];
    c

  (* one clock on the bus levels; returns (pull SDA low, pull SCL low) for the next clock *)
  let controller_step c ~sda ~scl =
    if c.wait > 0 then c.wait <- c.wait - 1
    else begin
      let go = ref true in
      while !go && not (Queue.is_empty c.q) do
        match Queue.peek c.q with
        | Pull_sda v -> ignore (Queue.pop c.q); c.c_sda_low <- v
        | Pull_scl v -> ignore (Queue.pop c.q); c.c_scl_low <- v
        | Delay n -> ignore (Queue.pop c.q); if n > 1 then (c.wait <- n - 1; go := false) else if n = 1 then go := false
        | Until_scl_high -> if scl = 1 then ignore (Queue.pop c.q) else go := false
        | Read_sda f -> ignore (Queue.pop c.q); f sda
        | Act f -> ignore (Queue.pop c.q); f ()
      done
    end;
    (c.c_sda_low, c.c_scl_low)

end
