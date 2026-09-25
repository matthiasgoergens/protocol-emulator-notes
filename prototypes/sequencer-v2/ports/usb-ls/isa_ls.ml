(* Drop-in replacement for ../../../usb-ls/isa_ls.ml backed by ISA v2: the variant's own
   assembler (isa_ls_enc.ml, cut from its file by the dune rule), v2's interpreter fetching each
   word through Compat.of_ls. The host sees tag 1 where usb-ls had its event flag. *)
include Isa_ls_enc

type state = Isa2.state
type effects = { host_out : (int * bool) option; host_in_ready : bool }

let init () = Isa2.init ~boot:Compat.boot_by_thread ()

let step (st : state) ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let e = Isa2.step_f st ~fetch:(Compat.fetch_threads ~translate:Compat.of_ls mem)
      (Isa2.io ~host_in ~host_in_valid pin_in) in
  { host_out = Option.map (fun (tag, v) -> (v, tag <> 0)) e.host_out; host_in_ready = e.host_in_ready }
