(* Copied verbatim from ../../sequencer-ps2-can/can_fw.ml (the host driver's stuffer for the CAN
   transmit thread), so that it can serve as an independent reference here without that
   prototype's ISA. [drop_stuff] omits the k-th stuff bit (a planted fault there). *)
let stuff ?(drop_stuff = -1) bits =
  let out = ref [] and last = ref (-1) and run = ref 0 and k = ref 0 in
  List.iter (fun b ->
    out := b :: !out;
    if b = !last then incr run else (last := b; run := 1);
    if !run = 5 then begin
      if !k <> drop_stuff then out := (1 - b) :: !out;
      incr k;
      if !k - 1 <> drop_stuff then (last := 1 - b; run := 1) else run := 0
    end) bits;
  List.rev !out
