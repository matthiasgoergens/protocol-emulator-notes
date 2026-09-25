(* Drop-in replacement for ../../../sequencer-ps2-can/isa_v.ml backed by ISA v2 (as ../ps2/isa_v.ml),
   for benches that mix v2 programmes (registered with Compat.register_v2) with raw variant words
   (the bench's all-HALT threads), which are translated by Compat.of_v. *)
include Isa_v_enc

type state = Isa2.state
type effects = { host_out : (int * int) option; host_in_ready : bool }

let init () = Isa2.init ~boot:Compat.boot_by_thread ()

let memo : (int array array * (int -> int)) option ref = ref None

let fetch_for mem =
  match !memo with
  | Some (m, f) when m == mem -> f
  | _ -> let f = Compat.fetch_mixed ~translate:Compat.of_v mem in memo := Some (mem, f); f

let step (st : state) ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let e = Isa2.step_f st ~fetch:(fetch_for mem) (Isa2.io ~host_in ~host_in_valid pin_in) in
  { host_out = e.host_out; host_in_ready = e.host_in_ready }
