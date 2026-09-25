(* Drop-in replacement for ../../../sequencer-ps2-can/harness_v.ml: the v2 RTL in Harness2,
   fetching the variant's per-thread programme arrays through Compat.of_v. *)
type t = Harness2.t
type observed = { pin_out : int; pin_oe : int; host_out : (int * int) option; host_in_ready : bool;
                  pcs : int list; dbg : int list }

let make (mem : int array array) =
  Harness2.make_f ~boot:Compat.boot_by_thread ~fetch:(Compat.fetch_threads ~translate:Compat.of_v mem) ()

let cycle s ~pin_in ~host_in ~host_in_valid =
  let o = Harness2.cycle s (Isa2.io ~host_in ~host_in_valid pin_in) in
  { pin_out = o.pin_out; pin_oe = o.pin_oe; host_out = o.host_out; host_in_ready = o.host_in_ready;
    pcs = Array.to_list (Harness2.per s "dbg_pc" 8); dbg = [] }
