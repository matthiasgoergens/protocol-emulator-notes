(* The four-phase output and input stage.

   Four clocks ph0..ph3 run at the core clock, 0, 90, 180 and 270 degrees apart; ph0 is the core
   clock. Every output pin has four lanes, lane p a toggle flip-flop clocked on ph p, and the pin is
   the XOR of its lanes, so each lane can put one edge per clock at quarter p. The core hands the
   stage a nibble per pin and clock (Isa pin_sub: bit p = level during quarter p). The stage turns
   the nibble into toggles and registers them on ph0; lane p picks its toggle up a quarter later
   (p = 1..3) or at the next ph0 edge (p = 0). Invariant, with N_k the nibble held from core edge
   E_k to E_(k+1): after E_(k+1) + p/4, the pin equals N_k[p].

   Lanes belong to phases, not to threads. A static thread-to-phase map (thread t always on quarter
   t) cannot place an edge anywhere but at quarter (c mod 4) of clock c, because thread t only
   issues on clocks c = t mod 4; the sub-slot has to come with each write (Isa q field).

   Each input pin has four sampling flip-flops, one per phase, each followed by a second flip-flop on
   the same phase (a two-flop synchroniser per phase: the pad is asynchronous to every phase), then
   a retiming flip-flop on ph0. After E_(j+2) the core sees the four samples taken at E_j + p/4.

   Two clockings of the same logic:
   - [Phases]: four real clock inputs, for Verilog, event simulation and static timing;
   - [Substep]: one clock at four times the rate with a one-hot enable, for Cyclesim. Fast cycle
     4j + p is the edge at E_j + p/4, and registers of phase p are enabled on it. With ideal,
     skew-free phases the two are the same circuit cycle for cycle. *)
open Hardcaml
open Signal

type clocking =
  | Phases of { clocks : Signal.t array; clear : Signal.t }
  | Substep of { clock : Signal.t; clear : Signal.t; en : Signal.t }

let reg_on clocking p d =
  match clocking with
  | Phases { clocks; clear } -> reg (Reg_spec.create ~clock:clocks.(p) ~clear ()) d
  | Substep { clock; clear; en } -> reg (Reg_spec.create ~clock ~clear ()) ~enable:(bit en p) d

let toggle_on clocking p t =
  let w = wire 1 in
  let q = reg_on clocking p (w ^: t) in
  w <== q; q

(* planted faults, each of which the tests must catch *)
type fault = No_fault | Lane_on_wrong_phase | No_prev3 | Or_combiner | Sampler_wrong_phase

(* [sub]: 4 bits per pin, bit 4i+p = pin i during quarter p. Returns the pins and per-lane outputs. *)
let output_stage ?(fault = No_fault) clocking ~sub =
  let n = width sub / 4 in
  let pins = List.init n (fun i ->
      let nib p = bit sub (4 * i + p) in
      let prev3 = reg_on clocking 0 (nib 3) in
      let prev = if fault = No_prev3 then gnd else prev3 in
      let lane0 = toggle_on clocking 0 (nib 0 ^: prev) in
      let lanes = lane0 :: List.init 3 (fun k ->
          let p = k + 1 in
          let t = reg_on clocking 0 (nib p ^: nib (p - 1)) in
          let ph = if fault = Lane_on_wrong_phase && p = 2 then 3 else p in
          toggle_on clocking ph t) in
      if fault = Or_combiner then reduce ~f:( |: ) lanes else reduce ~f:( ^: ) lanes) in
  concat_lsb pins

(* [pads]: one bit per input pin. Returns 4 bits per pin, bit 4i+p = the sample at quarter p. *)
let input_stage ?(fault = No_fault) clocking ~pads =
  let n = width pads in
  concat_lsb (List.concat (List.init n (fun i ->
      List.init 4 (fun p ->
          let ph = if fault = Sampler_wrong_phase && p = 1 then 2 else p in
          let s = reg_on clocking ph (bit pads i) in
          let r = reg_on clocking ph s in
          reg_on clocking 0 r))))

let n_out = 2
let n_in = 2

(* the stage on its own, with real phase clocks: for Verilog, iverilog and STA *)
let circuit_phases ?fault () =
  let clocks = Array.init 4 (fun p -> input (Printf.sprintf "ph%d" p) 1) in
  let clear = input "clear" 1 in
  let clocking = Phases { clocks; clear } in
  let sub = input "sub" (4 * n_out) and oe = input "oe" n_out and pads = input "pads" n_in in
  let pin = output_stage ?fault clocking ~sub in
  (* output enables change with quarter 0 *)
  let oe_q = reg_on clocking 0 oe in
  let samples = input_stage ?fault clocking ~pads in
  Circuit.create_exn ~name:"multiphase_stage"
    [ output "pin" pin; output "pin_oe" oe_q; output "samples" samples ]

(* the same logic on one fast clock with enables, for Cyclesim *)
let circuit_substep ?fault ?(n_out = n_out) ?(n_in = n_in) () =
  let clock = input "clock" 1 and clear = input "clear" 1 and en = input "en" 4 in
  let clocking = Substep { clock; clear; en } in
  let sub = input "sub" (4 * n_out) and pads = input "pads" n_in in
  let pin = output_stage ?fault clocking ~sub in
  let samples = input_stage ?fault clocking ~pads in
  Circuit.create_exn ~name:"multiphase_substep" [ output "pin" pin; output "samples" samples ]

(* Cyclesim driver for the sub-step circuit. [step s ~sub ~pads] advances one core clock: four fast
   cycles, returning the pin value after each (quarter 0..3 of the output timeline). [sub] is the
   nibble the core registers at the start of this core clock (N_j, held until E_(j+1));
   [pads p] the pad value just before the edge at quarter p. *)
module Sim = struct
  type t = {
    sim : Cyclesim.t_port_list; en : Bits.t ref; sub : Bits.t ref; pads : Bits.t ref;
    pin : Bits.t ref; samples : Bits.t ref; n_out : int; n_in : int;
    mutable prev_sub : int;
  }

  let create ?fault ?(n_out = n_out) ?(n_in = n_in) () =
    let sim = Cyclesim.create (circuit_substep ?fault ~n_out ~n_in ()) in
    let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
    i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
    { sim; en = i "en"; sub = i "sub"; pads = i "pads"; pin = o "pin"; samples = o "samples";
      n_out; n_in; prev_sub = 0 }

  (* returns (pin after each quarter, as an array of 4 ints) and the samples word seen by the core
     after this clock's ph0 edge *)
  let step s ~sub ~pads =
    let pins = Array.make 4 0 and samples = ref 0 in
    for p = 0 to 3 do
      s.en := Bits.of_int ~width:4 (1 lsl p);
      (* the edge at quarter 0 is E_j itself: the core's register still holds the previous nibble *)
      s.sub := Bits.of_int ~width:(4 * s.n_out) (if p = 0 then s.prev_sub else sub);
      s.pads := Bits.of_int ~width:s.n_in (pads p);
      Cyclesim.cycle s.sim;
      pins.(p) <- Bits.to_int !(s.pin);
      if p = 0 then samples := Bits.to_int !(s.samples)
    done;
    s.prev_sub <- sub;
    pins, !samples
end
