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
