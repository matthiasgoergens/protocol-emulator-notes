(* Cyclesim harness for the variant RTL, one-cycle-latency instruction memory, as ../deadline-sequencer/harness.ml. *)
open Hardcaml

let circuit_per = lazy (Sequencer_v.circuit ~debug:true ())
let circuit_shared = lazy (Sequencer_v.circuit ~debug:true ~shared_cfg:true ())
let circuit () = Lazy.force (if !Isa_v.shared_cfg then circuit_shared else circuit_per)

type t = {
  sim : Cyclesim.t_port_list; mem : int array array;
  imem_data : Bits.t ref; pin_in : Bits.t ref; host_in : Bits.t ref; host_in_valid : Bits.t ref; clear : Bits.t ref;
  imem_addr : Bits.t ref; pin_out : Bits.t ref; pin_oe : Bits.t ref; host_out : Bits.t ref;
  host_out_tag : Bits.t ref; dbg : Bits.t ref list; host_out_valid : Bits.t ref; host_in_ready : Bits.t ref; pcs : Bits.t ref;
  mutable pending_addr : int;
  mutable current_addr : int;
}

let make mem =
  let sim = Cyclesim.create (circuit ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let s = { sim; mem; imem_data = i "imem_data"; pin_in = i "pin_in"; host_in = i "host_in";
            host_in_valid = i "host_in_valid"; clear = i "clear"; imem_addr = o "imem_addr";
            pin_out = o "pin_out"; pin_oe = o "pin_oe"; host_out = o "host_out";
            host_out_tag = o "host_out_tag"; dbg = List.init Isa_v.n_threads (fun t -> o (Printf.sprintf "dbg%d" t));
            host_out_valid = o "host_out_valid"; host_in_ready = o "host_in_ready"; pcs = o "pcs";
            pending_addr = 0; current_addr = 0 } in
  s.clear := Bits.vdd; Cyclesim.cycle sim; s.clear := Bits.gnd;
  s.current_addr <- 0;
  s.pending_addr <- Bits.to_int !(s.imem_addr);
  s

let fetch mem addr = mem.(addr lsr Isa_v.pc_bits).(addr land (Isa_v.prog_len - 1))

type observed = { pin_out : int; pin_oe : int; host_out : (int * int) option; host_in_ready : bool; pcs : int list; dbg : int list }

let cycle s ~pin_in ~host_in ~host_in_valid =
  s.imem_data := Bits.of_int ~width:16 (fetch s.mem s.current_addr);
  s.pin_in := Bits.of_int ~width:8 pin_in;
  s.host_in := Bits.of_int ~width:8 host_in;
  s.host_in_valid := Bits.of_int ~width:1 (if host_in_valid then 1 else 0);
  Cyclesim.cycle s.sim;
  s.current_addr <- s.pending_addr;
  s.pending_addr <- Bits.to_int !(s.imem_addr);
  { pin_out = Bits.to_int !(s.pin_out); pin_oe = Bits.to_int !(s.pin_oe);
    host_out = (if Bits.to_int !(s.host_out_valid) = 1
                then Some (Bits.to_int !(s.host_out_tag), Bits.to_int !(s.host_out)) else None);
    host_in_ready = Bits.to_int !(s.host_in_ready) = 1;
    dbg = List.map (fun r -> Bits.to_int !r) s.dbg;
    pcs = List.init Isa_v.n_threads (fun t -> (Bits.to_int !(s.pcs) lsr (t * Isa_v.pc_bits)) land (Isa_v.prog_len - 1)) }
