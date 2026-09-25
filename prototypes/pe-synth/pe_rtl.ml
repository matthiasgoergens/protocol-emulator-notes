(* Processing elements to synthesise for the systolic-storage study (../systolic-storage).
   Each circuit is self-contained; main.exe prints its Verilog.

   ring_cell w   one cell of ../semiring-ring, cut out of the ring: the same arithmetic
                 (one adder with conditional inversion, max/min from the sign of x - y,
                 saturation), the same two 5-way source muxes (x from itself or 4 neighbours,
                 y from 4 neighbours or the constant k), the same byte-wide configuration chain
                 (one op byte plus w/8 bytes of k) and the same byte-wide init chain through the
                 state register. w = 24 is the ring's cell; w = 16 is it narrowed.
   pe16          the PE that ../systolic-storage/candidates.py assumes: add/sub/max/min with
                 saturation on one neighbour input, y from the state or the constant k, a 16-bit
                 state and a 16-bit pipeline register, 24 configuration flops (op byte + k).
   mac16         output-stationary multiply-accumulate: a moves east, b moves south (one
                 register each), acc += a * b signed, 32-bit accumulator, wrapping.
   minplus16     output-stationary min-plus (tropical) PE: acc = min(acc, a + b), unsigned,
                 saturating at 0xffff (infinity). *)
open Hardcaml
open Signal

(* byte-wide configuration chain; returns the bytes, first-shifted byte last *)
let chain spec ~enable ~din len =
  let regs = Array.make len (zero 8) in
  let prev = ref din in
  for j = 0 to len - 1 do
    let r = reg spec ~enable !prev in
    regs.(j) <- r;
    prev := r
  done;
  (fun k -> regs.(len - 1 - k)), !prev

let sat ~w v =
  let over = msb v ^: bit v (w - 1) in
  let vmax = (1 lsl (w - 1)) - 1 and vmin = -(1 lsl (w - 1)) in
  mux2 over (mux2 (msb v) (of_int ~width:w vmin) (of_int ~width:w vmax)) (select v (w - 1) 0)

(* the ring's ALU: op 0 add, 1 sub (both saturating), 2 max, 3 min *)
let alu ~w op x y =
  let is_add = op ==:. 0 in
  let y1 = sresize y (w + 1) in
  let t = sresize x (w + 1) +: mux2 is_add y1 ~:y1 +: uresize ~:is_add (w + 1) in
  let lt = msb t in
  let mx = mux2 lt y x and mn = mux2 lt x y in
  mux op [ sat ~w t; sat ~w t; mx; mn ]

let ring_cell w =
  assert (w mod 8 = 0);
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let init_in = input "init_in" 8 and init_strobe = input "init_strobe" 1 in
  let do_step = input "do_step" 1 in
  let nb = List.init 4 (fun j -> input (Printf.sprintf "nb%d" (j + 1)) w) in
  let nk = w / 8 in
  let cfg, cfg_out = chain (Reg_spec.create ~clock ()) ~enable:cfg_strobe ~din:cfg_in (1 + nk) in
  let o = cfg 0 in
  let k = concat_msb (List.init nk (fun j -> cfg (1 + j))) in
  let s = wire w in
  let x = mux (select o 4 2) (s :: nb) in
  let y = mux (select o 7 5) (nb @ [ k ]) in
  let next = alu ~w (select o 1 0) x y in
  let from_chain = if w > 8 then concat_msb [ select s (w - 9) 0; init_in ] else init_in in
  s <== reg spec (mux2 init_strobe from_chain (mux2 do_step next s));
  Circuit.create_exn ~name:(Printf.sprintf "ring_cell%d" w)
    [ output "s" s; output "cfg_out" cfg_out; output "init_out" (select s (w - 1) (w - 8)) ]

let pe16 () =
  let w = 16 in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let en = input "en" 1 and nbr = input "nbr_in" w in
  let cfg, cfg_out = chain (Reg_spec.create ~clock ()) ~enable:cfg_strobe ~din:cfg_in 3 in
  let o = cfg 0 and k = concat_msb [ cfg 1; cfg 2 ] in
  let s = wire w in
  (* op byte: bits 1:0 op, bit 2 y = k (else state), bit 3 x = state (else neighbour),
     bit 4 output the state (else the pipeline register); bits 7:5 unused *)
  let x = mux2 (bit o 3) s nbr and y = mux2 (bit o 2) k s in
  s <== reg spec ~enable:en (alu ~w (select o 1 0) x y);
  let pipe = reg spec nbr in
  Circuit.create_exn ~name:"pe16"
    [ output "out" (mux2 (bit o 4) s pipe); output "pipe_out" pipe; output "cfg_out" cfg_out ]

let mac16 () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let a = input "a_in" 16 and b = input "b_in" 16 and first = input "first" 1 in
  let en = input "en" 1 in
  let p = sresize (a *+ b) 32 in
  let acc = reg_fb spec ~enable:en ~width:32 ~f:(fun acc -> mux2 first p (acc +: p)) in
  Circuit.create_exn ~name:"mac16"
    [ output "acc" acc; output "a_out" (reg spec a); output "b_out" (reg spec b) ]

let minplus16 () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let a = input "a_in" 16 and b = input "b_in" 16 and first = input "first" 1 in
  let en = input "en" 1 in
  let t = uresize a 17 +: uresize b 17 in
  let sum = mux2 (msb t) (ones 16) (select t 15 0) in
  let acc = reg_fb spec ~enable:en ~width:16 ~f:(fun acc ->
    mux2 first sum (mux2 (sum <: acc) sum acc)) in
  Circuit.create_exn ~name:"minplus16"
    [ output "acc" acc; output "a_out" (reg spec a); output "b_out" (reg spec b) ]

let circuits =
  [ "ring_cell24", (fun () -> ring_cell 24); "ring_cell16", (fun () -> ring_cell 16);
    "pe16", pe16; "mac16", mac16; "minplus16", minplus16 ]
