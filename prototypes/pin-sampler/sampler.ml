(* The pin sampler as RTL (semantics in model.ml). *)
open Hardcaml
open Signal

let depth = 4   (* = Model.depth *)

let create ?(fault = false) ~clock ~clear ~pins ~clocked ~period ~width ~trig_pin ~trig_val ~offset ~frame_len ~pop () =
  let spec = Reg_spec.create ~clock ~clear () in
  let prev = reg spec pins in
  let bit v = mux trig_pin (bits_lsb v) in
  let edge = (bit pins ==: trig_val) &: (bit prev <>: trig_val) in
  (* [running] is "not armed": registers clear to 0, and the sampler starts armed *)
  let running = wire 1 and cnt = wire 12 and word = wire 16 and n = wire 5 and taken = wire 8 in
  let per = mux2 (width ==:. 1) (of_int ~width:5 16) (mux2 (width ==:. 2) (of_int ~width:5 8) (of_int ~width:5 4)) in
  let timed_armed = ~:clocked &: ~:running and timed_run = ~:clocked &: running in
  let take = mux2 clocked edge (timed_run &: (cnt ==:. 0)) in
  (* the new vector, placed at vector position n *)
  let m = mux2 (width ==:. 1) (of_int ~width:16 1) (mux2 (width ==:. 2) (of_int ~width:16 3) (of_int ~width:16 15)) in
  let v = uresize pins 16 &: m in
  let sh = uresize n 16 in
  let pos = mux2 (width ==:. 1) sh (mux2 (width ==:. 2) (sll sh 1) (sll sh 2)) in
  let placed = log_shift sll v (select pos 3 0) in
  let word_t = word |: placed and n_t = n +:. 1 and taken_t = taken +:. 1 in
  let frame_done = take &: (frame_len <>:. 0) &: (uresize taken_t 8 >=: frame_len) in
  let do_push = take &: ((n_t ==: per) |: frame_done) in
  let count_field = mux2 (n_t ==: per) (zero 4) (select n_t 3 0) in
  let count_field = if fault then select n_t 3 0 else count_field in
  (* FIFO: read before this clock's push lands; a push into a full FIFO is accepted only if the
     head is popped in the same clock *)
  let rd = wire 2 and wr = wire 2 and fcount = wire 3 in
  let nonempty = fcount <>:. 0 in
  let popping = pop &: nonempty in
  let accept = do_push &: ((fcount <>:. depth) |: popping) in
  let slots = List.init depth (fun i -> reg spec ~enable:(accept &: (wr ==:. i)) (concat_msb [ count_field; word_t ])) in
  let head = mux rd slots in
  rd <== reg spec (mux2 popping (rd +:. 1) rd);
  wr <== reg spec (mux2 accept (wr +:. 1) wr);
  fcount <== reg spec (fcount +: uresize accept 3 -: uresize popping 3);
  let overflows = reg_fb spec ~width:8 ~f:(fun o -> mux2 (do_push &: ~:accept) (o +:. 1) o) in
  (* sequencing *)
  word <== reg spec (mux2 do_push (zero 16) (mux2 take word_t word));
  n <== reg spec (mux2 do_push (zero 5) (mux2 take n_t n));
  taken <== reg spec (mux2 frame_done (zero 8) (mux2 take taken_t taken));
  running <== reg spec (mux2 frame_done gnd (mux2 (timed_armed &: edge) vdd running));
  cnt <== reg spec
      (mux2 (timed_armed &: edge) offset
         (mux2 timed_run (mux2 (cnt ==:. 0) (period -:. 1) (cnt -:. 1)) cnt));
  select head 15 0, select head 19 16, nonempty, overflows

let circuit ?fault () =
  let clock = input "clock" 1 and clear = input "clear" 1 and pins = input "pins" 4 in
  let clocked = input "clocked" 1 and period = input "period" 12 and width = input "width" 3 in
  let trig_pin = input "trig_pin" 2 and trig_val = input "trig_val" 1 and offset = input "offset" 12 in
  let frame_len = input "frame_len" 8 and pop = input "pop" 1 in
  let data, count, valid, overflows =
    create ?fault ~clock ~clear ~pins ~clocked ~period ~width ~trig_pin ~trig_val ~offset ~frame_len ~pop () in
  Circuit.create_exn ~name:"pin_sampler"
    [ output "data" data; output "count" count; output "valid" valid; output "overflows" overflows ]
