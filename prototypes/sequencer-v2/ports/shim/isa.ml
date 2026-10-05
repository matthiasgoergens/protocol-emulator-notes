(* Drop-in replacement for an earlier variant's Isa module, backed by ISA v2 (isa2.ml).

   The assembler (types, encoders, constants) is the variant's own, taken unchanged from its file
   by the dune rule that makes isa_enc.ml (everything before "type state"). The interpreter is
   v2's: each word is translated by Variant.translate as it is fetched (compat.ml), thread t runs
   from page t, and the state is v2's state, so a bench that reads st.pin_out or st.pcs sees v2. *)
include Isa_enc

type state = Isa2.state
type effects = { host_out : int option; host_in_ready : bool }

let init () = Isa2.init ~boot:Compat.boot_by_thread ()

let step ?pin_in4 (st : state) ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let e = Isa2.step_f st ~fetch:(Compat.fetch_threads ~translate:Variant.translate mem)
      (Isa2.io ?pin_in4 ~host_in ~host_in_valid pin_in) in
  { host_out = Option.map snd e.host_out; host_in_ready = e.host_in_ready }

let sub_of = Isa2.sub_of
let replicate4 = Isa2.replicate4
