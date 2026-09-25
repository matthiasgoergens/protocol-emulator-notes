(* The systolic matcher of ../systolic-matcher/matcher.ml, copied with one change: a datapath
   enable. Every datapath register (samples, partial sums, hit) advances only when [enable] is high,
   so the closed form of ../systolic-matcher/model.ml holds in enabled steps instead of clocks.
   This lets the array take one sample per received bit (here from the edge sampler, 10 Mbit/s at
   60 MHz) rather than one per clock. Proposed as an upstream change to the matcher: one enable on
   the register spec, no new cells. *)
open Hardcaml
open Signal

let n = Model.n

let create ~clock ~clear ~enable ~x ~cfg_in ~cfg_shift =
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg_spec = Reg_spec.create ~clock () in
  let chain = ref cfg_in in
  let cfg_reg () = let r = reg cfg_spec ~enable:cfg_shift !chain in chain := r; r in
  let cells = Array.init n (fun _ -> let m = cfg_reg () in let t = cfg_reg () in (m, t)) in
  let thr = concat_lsb (List.init 5 (fun _ -> cfg_reg ())) in
  let xin = ref x and yin = ref (zero 5) in
  Array.iter (fun (m, t) ->
    let xa = reg spec ~enable !xin in
    let xb = reg spec ~enable xa in
    let w = m &: (xa ==: t) in
    let y = reg spec ~enable (!yin +: uresize w 5) in
    xin := xb; yin := y) cells;
  let y = !yin in
  let hit = reg spec ~enable (y >=: thr) in
  y, hit

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 and enable = input "enable" 1 in
  let x = input "x" 1 and cfg_in = input "cfg_in" 1 and cfg_shift = input "cfg_shift" 1 in
  let y, hit = create ~clock ~clear ~enable ~x ~cfg_in ~cfg_shift in
  Circuit.create_exn ~name:"systolic_matcher_en" [ output "y" y; output "hit" hit ]
