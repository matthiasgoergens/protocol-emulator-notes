open Hardcaml
open Signal

let n = Model.n

(* cfg chain: on cfg_shift every configuration register takes its predecessor's value and the
   first takes cfg_in. Registers are created in the order m_0, t_0, m_1, t_1, ..., thr[0..4], so
   after shifting K bits the last bit shifted sits in m_0 and the first in thr[4]; Model.cfg_bits
   emits the sequence in exactly that order. *)
let create ~clock ~clear ~x ~cfg_in ~cfg_shift =
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg_spec = Reg_spec.create ~clock () in   (* configuration survives a datapath reset *)
  let chain = ref cfg_in in
  let cfg_reg () = let r = reg cfg_spec ~enable:cfg_shift !chain in chain := r; r in
  (* cells 0..N-1 each take (m, t) in that order along the chain; then the threshold bits *)
  let cells = Array.init n (fun _ -> let m = cfg_reg () in let t = cfg_reg () in (m, t)) in
  let thr = concat_lsb (List.init 5 (fun _ -> cfg_reg ())) in
  (* datapath *)
  let xin = ref x and yin = ref (zero 5) in
  Array.iter (fun (m, t) ->
    let xa = reg spec !xin in
    let xb = reg spec xa in
    let w = m &: (xa ==: t) in
    let y = reg spec (!yin +: uresize w 5) in
    xin := xb; yin := y) cells;
  let y = !yin in
  let hit = reg spec (y >=: thr) in
  y, hit

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let x = input "x" 1 and cfg_in = input "cfg_in" 1 and cfg_shift = input "cfg_shift" 1 in
  let y, hit = create ~clock ~clear ~x ~cfg_in ~cfg_shift in
  Circuit.create_exn ~name:"systolic_matcher" [ output "y" y; output "hit" hit ]
