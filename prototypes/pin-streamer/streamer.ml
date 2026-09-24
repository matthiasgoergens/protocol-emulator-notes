(* The pin-vector streamer as RTL (semantics in model.ml). *)
open Hardcaml
open Signal

let create ?(fault = false) ~clock ~clear ~period ~width ~od_mask ~idle_out ~idle_oe ~host_data ~host_push () =
  let spec = Reg_spec.create ~clock ~clear () in
  let depth = Model.depth in
  (* FIFO: four words, read and write pointers, count *)
  let rd = wire 2 and wr = wire 2 and fcount = wire 3 in
  let full = fcount ==:. depth and empty = fcount ==:. 0 in
  let push = host_push &: ~:full in
  let slots = List.init depth (fun i -> reg spec ~enable:(push &: (wr ==:. i)) host_data) in
  let head = mux rd slots in
  let cnt = wire 12 and left = wire 5 and word = wire 16 in
  let tick = cnt ==:. 0 in
  let need = tick &: (left ==:. 0) in
  let pop = need &: ~:empty in
  let word_src = mux2 pop head word in
  let per_word = mux2 (width ==:. 1) (of_int ~width:5 16) (mux2 (width ==:. 2) (of_int ~width:5 (if fault then 7 else 8)) (of_int ~width:5 4)) in
  let left_eff = mux2 pop per_word left in
  let emit = tick &: (left_eff <>:. 0) in
  let go_idle = need &: empty in
  let shifted = mux2 (width ==:. 1) (srl word_src 1) (mux2 (width ==:. 2) (srl word_src 2) (srl word_src 4)) in
  rd <== reg spec (mux2 pop (rd +:. 1) rd);
  wr <== reg spec (mux2 push (wr +:. 1) wr);
  fcount <== reg spec (fcount +: uresize push 3 -: uresize pop 3);
  word <== reg spec (mux2 emit shifted word);
  left <== reg spec (mux2 emit (left_eff -:. 1) left);
  cnt <== reg spec (mux2 emit (period -:. 1) (mux2 tick cnt (cnt -:. 1)));
  let m = mux2 (width ==:. 1) (of_int ~width:4 1) (mux2 (width ==:. 2) (of_int ~width:4 3) (of_int ~width:4 15)) in
  let v = select word_src 3 0 &: m in
  let od = od_mask &: m in
  let drive_out = v &: ~:od and drive_oe = (m &: ~:od) |: (od &: ~:v) in
  (* pins after reset are idle; the clear value of the output registers cannot depend on inputs, so
     a flag selects idle until the first emission *)
  let out_r = wire 4 and oe_r = wire 4 and started = wire 1 in
  started <== reg spec (mux2 emit vdd (mux2 go_idle gnd started));
  out_r <== reg spec (mux2 emit drive_out out_r);
  oe_r <== reg spec (mux2 emit drive_oe oe_r);
  let pin_out = mux2 started out_r idle_out and pin_oe = mux2 started oe_r idle_oe in
  pin_out, pin_oe, full

let circuit ?fault () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let period = input "period" 12 and width = input "width" 3 and od_mask = input "od_mask" 4 in
  let idle_out = input "idle_out" 4 and idle_oe = input "idle_oe" 4 in
  let host_data = input "host_data" 16 and host_push = input "host_push" 1 in
  let pin_out, pin_oe, full = create ?fault ~clock ~clear ~period ~width ~od_mask ~idle_out ~idle_oe ~host_data ~host_push () in
  Circuit.create_exn ~name:"pin_streamer" [ output "pin_out" pin_out; output "pin_oe" pin_oe; output "full" full ]
