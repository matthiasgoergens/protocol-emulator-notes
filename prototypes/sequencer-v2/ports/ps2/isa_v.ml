(* Drop-in replacement for ../../../sequencer-ps2-can/isa_v.ml backed by ISA v2: the variant's own
   assembler (isa_v_enc.ml, cut from its file by the dune rule), v2's interpreter fetching each word
   through Compat.of_v. The rejected CRC and stuffing engines are absent: a word that uses them
   raises Compat.Untranslatable. *)
include Isa_v_enc

type state = Isa2.state
type effects = { host_out : (int * int) option; host_in_ready : bool }   (* (tag, byte) *)

let init () = Isa2.init ~boot:Compat.boot_by_thread ()

let step (st : state) ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let e = Isa2.step_f st ~fetch:(Compat.fetch_threads ~translate:Compat.of_v mem)
      (Isa2.io ~host_in ~host_in_valid pin_in) in
  { host_out = e.host_out; host_in_ready = e.host_in_ready }
