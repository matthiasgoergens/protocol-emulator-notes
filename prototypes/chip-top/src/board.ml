(* The board around the chip core: the four-phase stage's timing at the pads (README, "Phases"),
   the host on the host link, and the outside world on the general pads.

   Clock k: the pads show the core's outputs of clock k - 1 (the stage registers them); the outside
   world and the host react to those levels; the core sees in clock k the samples taken in clock
   k - 2. Levels are nibbles: bit p is the level during quarter p. *)

open Regs

type core = { step : smp:int array -> reset:bool -> Chip_spec.outputs }

let spec_core (s : Chip_spec.t) = { step = (fun ~smp ~reset -> Chip_spec.step s ~smp ~reset) }
let rtl_core (r : Chip_sim.t) = { step = (fun ~smp ~reset -> Chip_sim.step r ~smp ~reset) }

let zero_out : Chip_spec.outputs = { pad_nib = Array.make n_pads 0; uio_oe = 0 }

type t = {
  mutable host : Host.t;
  mutable out : Chip_spec.outputs;     (* what the pads show during this clock *)
  mutable pipe : int array list;       (* the last two clocks' samples, oldest first *)
  mutable clock : int;
  mutable trace : (int array * int) list;  (* optional: per clock, pad levels and uio_oe *)
  keep_trace : bool;
}

let create ?(keep_trace = false) () =
  { host = Host.create (); out = zero_out; pipe = [ Array.make n_pads 0; Array.make n_pads 0 ]; clock = 0;
    trace = []; keep_trace }

let rep4 b = if b <> 0 then 15 else 0
let bit v i = (v lsr i) land 1

(* The pad levels of the uio pins during this clock: the chip's where it drives, else [ext]. *)
let resolve_uio (out : Chip_spec.outputs) i ~ext = if bit out.uio_oe (i - 8) = 1 then out.pad_nib.(i) else ext

(* The samples of this clock, given the outside world's levels [ext] (16 nibbles; entries for
   the host-link pads are ignored) and the host. Advances the host by one clock. *)
let samples b ~ext =
  let out = b.out in
  let d_chip k = if bit out.uio_oe k = 1 then Some (bit out.pad_nib.(pad_hdata + k) 3) else None in
  let d_in = ref 0 in
  for k = 0 to 3 do
    let v = match d_chip k with Some v -> v | None -> (match b.host.d with Some d -> bit d k | None -> 0) in
    d_in := !d_in lor (v lsl k)
  done;
  let s, r, d = Host.clock b.host ~d_in:!d_in in
  let smp = Array.copy ext in
  for k = 0 to 3 do
    smp.(pad_hdata + k) <-
      (if bit out.uio_oe k = 1 then out.pad_nib.(pad_hdata + k)
       else match d with Some d -> rep4 (bit d k) | None -> 0)
  done;
  smp.(pad_hstb) <- rep4 s;
  smp.(pad_hrd) <- rep4 r;
  smp

(* One clock with the samples [smp] taken in it: the core sees the samples of two clocks ago. *)
let advance b (cores : core list) ~smp ~reset =
  let seen = List.hd b.pipe in
  b.pipe <- List.tl b.pipe @ [ smp ];
  let outs = List.map (fun c -> c.step ~smp:seen ~reset) cores in
  if b.keep_trace then b.trace <- (Array.copy b.out.pad_nib, b.out.uio_oe) :: b.trace;
  b.out <- List.hd outs;
  b.clock <- b.clock + 1;
  outs
