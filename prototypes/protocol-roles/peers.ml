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
