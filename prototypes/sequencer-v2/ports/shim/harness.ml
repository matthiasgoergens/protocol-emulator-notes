(* Drop-in replacement for an earlier variant's Harness module: the v2 RTL (sequencer2.ml) in
   Harness2, fetching the old per-thread programme arrays through Variant.translate. *)
type t = Harness2.t
type observed = { pin_out : int; pin_oe : int; host_out : int option; host_in_ready : bool; pcs : int list;
                  pin_sub : int }

let circuit = Harness2.circuit ()

let make (mem : int array array) =
  Harness2.make_f ~boot:Compat.boot_by_thread ~fetch:(Compat.fetch_threads ~translate:Variant.translate mem) ()

let fetch mem addr = Compat.fetch_threads ~translate:Variant.translate mem addr

let cycle ?pin_in4 s ~pin_in ~host_in ~host_in_valid =
  let o = Harness2.cycle s (Isa2.io ?pin_in4 ~host_in ~host_in_valid pin_in) in
  { pin_out = o.pin_out; pin_oe = o.pin_oe; host_out = Option.map snd o.host_out;
    host_in_ready = o.host_in_ready; pcs = Array.to_list (Harness2.per s "dbg_pc" 8); pin_sub = o.pin_sub }
