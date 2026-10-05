(* The interpreter's value domain as Hardcaml signals: Isa2.Make (Hw_value) is the executable
   specification turned into combinational logic, which spec_core.ml wraps in registers so that
   Yosys can compare it with the hand-written RTL (sequencer2.ml).

   The data bank is not modelled as a memory: a read returns [rd], a free input of the miter (the
   RTL gets the same byte one clock later, as from its synchronous SRAM), and a write is recorded
   as port signals (at most one write per clock). Equivalence for every read value implies
   equivalence for every memory. *)
open Hardcaml
open Signal

type t = Signal.t
type b = Signal.t
type mem = { rd : t; we : t; waddr : t; wdata : t }

let const ~w n = of_int ~width:w (n land ((1 lsl w) - 1))
let add ~w x y = assert (width x = w); x +: y
let sub ~w x y = assert (width x = w); x -: y
let logand = ( &: )
let logor = ( |: )
let logxor = ( ^: )
let lognot ~w x = assert (width x = w); ~:x
let shl ~w x s = assert (width x = w); log_shift sll x s
let lshr x s = log_shift srl x s
let extract x ~hi ~lo = select x hi lo
let zext ~w x = uresize x w
let eq = ( ==: )
let ult = ( <: )
let ite c x y = mux2 c x y
let tt = vdd
let ff = gnd
let not_ = ( ~: )
let and_ = ( &: )
let or_ = ( |: )
let mem_read m _ = m.rd
let mem_write m c a v = { m with we = c; waddr = a; wdata = v }
let mem_ite c x y = { rd = x.rd; we = mux2 c x.we y.we; waddr = mux2 c x.waddr y.waddr; wdata = mux2 c x.wdata y.wdata }
let mem_copy m = m
(* never: every opcode's logic is built, so the circuit is the whole instruction set *)
let known_false _ = false
