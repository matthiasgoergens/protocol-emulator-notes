(* Pin assignment, bus resolution and the delays between the core and the devices.

   Pins (the ARM/JTAG shared connector): 0 TCK/SWCLK, 1 TMS/SWDIO, 2 TDI, 3 TDO. Pull-ups on TMS,
   TDI, TDO and SWDIO, a pull-down on TCK/SWCLK, so an undriven clock never makes an edge.

   Timing model, per core clock c:
   - the core steps, reading pin_in(c) = bus(c - 1 - sync): one clock for the pad register and
     [sync] more for an input synchroniser;
   - the pads drive pin_out/pin_oe from the step's result; the devices see those levels at c;
   - a device's own output reaches the bus [tco] clocks after it decides it (clock-to-out and
     board flight, in core clocks);
   - a line driven by both the core and a device in the same clock is contention, counted. *)

let p_clk = 0 and p_tms = 1 and p_tdi = 2 and p_tdo = 3
let p_swclk = 0 and p_swdio = 1

let bit v i = (v lsr i) land 1

(* A fixed delay of n clocks; n = 0 passes the value straight through. *)
type 'a delay = { q : 'a Queue.t }
let delay n init = let q = Queue.create () in for _ = 1 to n do Queue.push init q done; { q }
let through d x = Queue.push x d.q; Queue.pop d.q

(* Resolve one line: core drive (oe, level), device drive, pull level. *)
let resolve ~oe ~out ~dev ~pull ~contention =
  match oe, dev with
  | true, Some _ -> incr contention; out   (* flagged; the value hardly matters after that *)
  | true, None -> out
  | false, Some d -> d
  | false, None -> pull

(* Clock edge statistics from a per-clock trace of one line. *)
type clock_stats = { rising : int; min_high : int; min_low : int; min_period : int; max_period : int }

let clock_stats (trace : int array) =
  let n = Array.length trace in
  let rising = ref 0 and last_rise = ref (-1) and last_fall = ref (-1) in
  let min_high = ref max_int and min_low = ref max_int and minp = ref max_int and maxp = ref 0 in
  for c = 1 to n - 1 do
    if trace.(c - 1) = 0 && trace.(c) = 1 then begin
      incr rising;
      if !last_fall >= 0 then min_low := min !min_low (c - !last_fall);
      if !last_rise >= 0 then (minp := min !minp (c - !last_rise); maxp := max !maxp (c - !last_rise));
      last_rise := c
    end;
    if trace.(c - 1) = 1 && trace.(c) = 0 then begin
      if !last_rise >= 0 then min_high := min !min_high (c - !last_rise);
      last_fall := c
    end
  done;
  { rising = !rising; min_high = !min_high; min_low = !min_low; min_period = !minp; max_period = !maxp }
