(* Independent decoders over a cycle trace of bus levels. They know the protocols, not the
   compiler's arithmetic: they sample where a receiver would sample. *)

type sample = { c : int; bus : int }   (* bus: line levels after open-drain resolution *)

let level s pin = (s.bus lsr pin) land 1

(* transitions of one line: (cycle, new level) *)
let edges trace pin =
  let prev = ref None and out = ref [] in
  List.iter (fun s ->
    let v = level s pin in
    (match !prev with Some p when p <> v -> out := (s.c, v) :: !out | _ -> ());
    prev := Some v) trace;
  List.rev !out

(* UART 8N1 lsb first at a fixed bit length in cycles; returns (start cycle, byte, framing ok). *)
let uart trace ~pin ~bit_cycles =
  let arr = Array.of_list trace in
  let n = Array.length arr in
  let at c = if c < n then level arr.(c) pin else 1 in
  let res = ref [] in
  let c = ref 1 in
  while !c < n do
    if at (!c - 1) = 1 && at !c = 0 then begin
      let start = !c in
      let mid k = start + bit_cycles / 2 + k * bit_cycles in
      let byte = ref 0 in
      for k = 1 to 8 do byte := !byte lor (at (mid k) lsl (k - 1)) done;
      let stop_ok = at (mid 9) = 1 in
      res := (start, !byte, stop_ok) :: !res;
      c := mid 9 + 1
    end else incr c
  done;
  List.rev !res

(* SPI mode 0, msb first: sample mosi on sclk rising edges while cs is low; bytes per cs window. *)
let spi trace ~sclk ~mosi ~cs =
  let bytes = ref [] and cur = ref 0 and nb = ref 0 in
  let prev = ref None in
  List.iter (fun s ->
    (match !prev with
     | Some p when level p cs = 0 && level s cs = 0 && level p sclk = 0 && level s sclk = 1 ->
       cur := (!cur lsl 1) lor level s mosi; incr nb;
       if !nb = 8 then (bytes := !cur :: !bytes; cur := 0; nb := 0)
     | Some p when level p cs = 0 && level s cs = 1 -> cur := 0; nb := 0
     | _ -> ());
    prev := Some s) trace;
  List.rev !bytes

(* I2C: START = sda falls while scl high; data sampled on scl rising; 9th bit is ack (0 = acked);
   STOP = sda rises while scl high. Returns (byte, acked) list and whether a STOP was seen. *)
let i2c trace ~sda ~scl =
  let bytes = ref [] and cur = ref 0 and nb = ref 0 and started = ref false and stopped = ref false in
  let prev = ref None in
  List.iter (fun s ->
    (match !prev with
     | Some p ->
       let sda_fall = level p sda = 1 && level s sda = 0 and sda_rise = level p sda = 0 && level s sda = 1 in
       let scl_rise = level p scl = 0 && level s scl = 1 in
       if level s scl = 1 && level p scl = 1 && sda_fall then (started := true; nb := 0; cur := 0)
       else if level s scl = 1 && level p scl = 1 && sda_rise && !started then (stopped := true; started := false)
       else if !started && scl_rise then begin
         if !nb < 8 then (cur := (!cur lsl 1) lor level s sda; incr nb)
         else (bytes := (!cur, level s sda = 0) :: !bytes; cur := 0; nb := 0)
       end
     | None -> ());
    prev := Some s) trace;
  List.rev !bytes, !stopped
