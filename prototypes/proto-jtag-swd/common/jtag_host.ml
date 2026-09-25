(* JTAG host as firmware on the deadline sequencer, stock ISA, two threads.

   Why two threads. A full-duplex scan shifts TDI out and TDO in on the same clock, but a thread
   has one 8-bit accumulator, and SHO and SHI both shift it: interleaved they shift twice per bit
   and scramble the data. So the work is split:

   - thread 0, the driver, is a vector engine. Each host byte holds four TCK cycles as (TMS, TDI)
     pairs, bit 2i = TMS and bit 2i+1 = TDI of cycle i. Per cycle: TCK low, TMS, TDI, TCK high.
     The driver knows nothing of the TAP: navigation, scans, their lengths and data are
     precomputed by the host (the vector compiler below), as for the Ethernet transmitter.
   - thread 1, the sampler, follows TCK as seen on the pad (WAITP on the clock pin), samples TDO
     one slot after each rising edge it sees, and hands the host a byte every eight TCKs. It has
     no timing of its own, so the host may stall the driver (a late IN just stretches TCK, which
     JTAG allows: the TAP is static) and nothing is lost.

   Target side, per IEEE 1149.1: TMS and TDI are sampled on TCK rising, TDO changes on TCK falling,
   so TDO is valid across the rising edge and the sampler reads it in the high phase. *)

open Asm

let tck = Wire.p_clk and tms = Wire.p_tms and tdi = Wire.p_tdi and tdo = Wire.p_tdo

(* Timing knobs, in slots (4 core clocks each): [lo] extra slots of setup before the rising edge,
   [hi] extra slots of high phase beyond the SETP that raises TCK. The sampler needs the high
   phase to outlast its one-slot reaction (hi >= 1). *)
type timing = { lo : int; hi : int; sample_delay : int }
let fastest = { lo = 0; hi = 1; sample_delay = 0 }

let driver ?(swap_tms_tdi = false) t =
  assert (t.hi >= 1);
  let m p = 1 lsl p in
  let tms_pin, tdi_pin = if swap_tms_tdi then tdi, tms else tms, tdi in
  let tck_cycle k =
    [ W (Isa.setp ~mask:(m tck) ~value:0 ~oe:1) ]
    @ (if k = 1 then [ W Isa.in_ ] else [])
    @ [ W (Isa.sho ~pin:tms_pin ~msb:0 ()); W (Isa.sho ~pin:tdi_pin ~msb:0 ()) ]
    @ pad t.lo
    @ [ W (Isa.setp ~mask:(m tck) ~value:1 ~oe:1) ]
    @ (if k = 4 then pad (t.hi - 1) @ [ Jmp "top" ] else pad t.hi) in
  [ W (Isa.setp ~mask:(m tck lor m tms lor m tdi) ~value:0 ~oe:1); L "top" ]
  @ List.concat_map tck_cycle [ 1; 2; 3; 4 ]

let sampler t =
  [ L "top" ]
  @ List.concat (List.init 8 (fun _ ->
      [ Hold (tck, 0); Hold (tck, 1) ] @ pad t.sample_delay @ [ W (Isa.shi ~pin:tdo ~msb:0) ]))
  @ [ W Isa.out; Jmp "top" ]

let programmes ?swap_tms_tdi t =
  let d, dl = assemble (driver ?swap_tms_tdi t) and s, sl = assemble (sampler t) in
  [| d; s; halted; halted |], (dl, sl)

(* ---- The vector compiler: TAP navigation and scans as (tms, tdi) per TCK. ---- *)

type vec = { vtms : int; vtdi : int }
let v tms tdi = { vtms = tms; vtdi = tdi }

(* Every sequence starts and ends in Run-Test/Idle, except [reset], which starts anywhere. *)
let reset = List.init 5 (fun _ -> v 1 0) @ [ v 0 0 ]
let idle n = List.init n (fun _ -> v 0 0)

(* A scan returns its vectors and the offsets (within them) of the shifted bits, whose TDO
   samples are the captured register contents. Planted bugs for the controls: [early_exit] raises
   TMS one bit early (the TAP leaves Shift one bit short and ends up out of step);
   [drop_select] leaves out one TMS=1 on the way to Shift-IR, so the scan lands in the DR path. *)
let scan ?(early_exit = false) ?(drop_select = false) ~ir bits =
  let n = List.length bits in
  let head = if ir then [ v 1 0; v 1 0; v 0 0; v 0 0 ] else [ v 1 0; v 0 0; v 0 0 ] in
  let head = if drop_select && ir then [ v 1 0; v 0 0; v 0 0 ] else head in
  let last = if early_exit then n - 2 else n - 1 in
  let body = List.mapi (fun i b -> v (if i >= last then 1 else 0) b) bits in
  let tail = [ v 1 0; v 0 0 ] in
  head @ body @ tail, List.init (List.length body) (fun i -> List.length head + i)

(* Pack vectors for the driver (4 per byte) after padding to a multiple of 8 with idle. *)
let pad8 vs = let r = List.length vs mod 8 in if r = 0 then vs else vs @ idle (8 - r)

let pack vs =
  let a = Array.of_list vs in
  List.init (Array.length a / 4) (fun j ->
    let b = ref 0 in
    for i = 0 to 3 do
      let x = a.(4 * j + i) in
      b := !b lor (x.vtms lsl (2 * i)) lor (x.vtdi lsl (2 * i + 1))
    done; !b)

(* The sampler's bytes back into one TDO bit per TCK. *)
let unpack bytes = List.concat_map (fun b -> List.init 8 (fun i -> (b lsr i) land 1)) bytes

let bits_of_int ~n x = List.init n (fun i -> (x lsr i) land 1)
let int_of_bits bs = List.fold_left (fun (acc, i) b -> (acc lor (b lsl i), i + 1)) (0, 0) bs |> fst
