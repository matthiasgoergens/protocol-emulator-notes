(* The firmware system: the sequencer (ISA variant), a two-flop synchroniser on every pin
   input, and the CRC assist, as RTL and as an executable model built from the interpreter.

   Pins: 0 D+, 1 D- (the bus, bidirectional), 2 VALUE, 3 STB, 4 IDLE (low during a packet;
   driven by the bit-layer thread and read back by the others), 5 CRC_EN (driven by the SETUP/OUT thread), 6 CRC_OK (from
   the CRC assist), 7 RDY (the reply FIFO in front of host_in is non-empty).

   Pad model: pin_in[i] = pin_oe[i] ? pin_out[i] : external[i], then two flops. External inputs
   are the bus on pins 0 and 1, the CRC assist's ok on pin 6 and the FIFO's non-empty flag on
   pin 7. The CRC assist reads VALUE, STB and CRC_EN straight from pin_out. *)
open Hardcaml
open Signal

let p_dp = 0 and p_dm = 1 and p_value = 2 and p_stb = 3 and p_idle = 4 and p_crc_en = 5 and p_crc_ok = 6 and p_rdy = 7

let circuit ?(crc = Crc_unit.usb_crc16) () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let imem_data = input "imem_data" 16 in
  let dp_in = input "dp_in" 1 and dm_in = input "dm_in" 1 and rdy = input "rdy" 1 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let pin_in = wire 8 in
  let imem_addr, pin_out, pin_oe, host_out, host_out_tag, host_out_valid, host_in_ready, pcs =
    Sequencer_ls.create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid in
  let crc_ok = Crc_unit.create ~cfg:crc ~clock ~clear ~en:(bit pin_out p_crc_en) ~frame:(~:(bit pin_out p_idle)) ~stb:(bit pin_out p_stb) ~value:(bit pin_out p_value) in
  let ext = concat_lsb [ dp_in; dm_in; gnd; gnd; gnd; gnd; crc_ok; rdy ] in
  let raw = (pin_oe &: pin_out) |: (~:pin_oe &: ext) in
  pin_in <== reg spec (reg spec raw);
  Circuit.create_exn ~name:"usb_ls_firmware_system"
    [ output "imem_addr" imem_addr; output "pin_out" pin_out; output "pin_oe" pin_oe
    ; output "host_out" host_out; output "host_out_tag" host_out_tag; output "host_out_valid" host_out_valid
    ; output "host_in_ready" host_in_ready; output "pcs" pcs; output "crc_ok" crc_ok ]

(* the same system as a model *)
module Model = struct
  type t = { st : Isa_ls.state; crc : Crc_unit.Model.t; mutable s1 : int; mutable s2 : int }
  let create ?(crc = Crc_unit.usb_crc16) () = { st = Isa_ls.init (); crc = Crc_unit.Model.create crc; s1 = 0; s2 = 0 }
  let bitv x i = (x lsr i) land 1
  (* one clock; returns the interpreter's effects. Register semantics: everything samples the
     values from before the clock edge. *)
  let step t ~mem ~dp ~dm ~rdy ~host_in ~host_in_valid =
    let st = t.st in
    let po = st.pin_out and poe = st.pin_oe in
    let ok = if Crc_unit.Model.ok t.crc then 1 else 0 in
    let ext = dp lor (dm lsl 1) lor (ok lsl p_crc_ok) lor (rdy lsl p_rdy) in
    let raw = (poe land po) lor (lnot poe land ext) land 0xFF in
    let eff = Isa_ls.step st ~mem ~pin_in:t.s2 ~host_in ~host_in_valid in
    Crc_unit.Model.step t.crc ~en:(bitv po p_crc_en) ~frame:(1 - bitv po p_idle) ~stb:(bitv po p_stb) ~value:(bitv po p_value);
    t.s2 <- t.s1; t.s1 <- raw;
    eff
end

(* the RTL in Cyclesim with a one-cycle-latency instruction memory (as ../deadline-sequencer's
   harness) *)
module Rtl_sim = struct
  type t = {
    sim : Cyclesim.t_port_list;
    imem_data : Bits.t ref; dp_in : Bits.t ref; dm_in : Bits.t ref; rdy : Bits.t ref;
    host_in : Bits.t ref; host_in_valid : Bits.t ref;
    imem_addr : Bits.t ref; pin_out : Bits.t ref; pin_oe : Bits.t ref; host_out : Bits.t ref; host_out_tag : Bits.t ref;
    host_out_valid : Bits.t ref; host_in_ready : Bits.t ref; pcs : Bits.t ref;
    mutable current_addr : int; mutable pending_addr : int;
  }
  let create ?crc () =
    let sim = Cyclesim.create (circuit ?crc ()) in
    let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
    let s = { sim; imem_data = i "imem_data"; dp_in = i "dp_in"; dm_in = i "dm_in"; rdy = i "rdy"; host_in = i "host_in";
              host_in_valid = i "host_in_valid"; imem_addr = o "imem_addr"; pin_out = o "pin_out"; pin_oe = o "pin_oe";
              host_out = o "host_out"; host_out_tag = o "host_out_tag"; host_out_valid = o "host_out_valid";
              host_in_ready = o "host_in_ready"; pcs = o "pcs"; current_addr = 0; pending_addr = 0 } in
    let clear = i "clear" in
    clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
    s.current_addr <- 0; s.pending_addr <- Bits.to_int !(s.imem_addr);
    s
  let step s ~(mem : int array array) ~dp ~dm ~rdy ~host_in ~host_in_valid =
    let a = s.current_addr in
    s.imem_data := Bits.of_int ~width:16 mem.(a lsr Isa_ls.pc_bits).(a land (Isa_ls.prog_len - 1));
    s.dp_in := Bits.of_int ~width:1 dp; s.dm_in := Bits.of_int ~width:1 dm; s.rdy := Bits.of_int ~width:1 rdy;
    s.host_in := Bits.of_int ~width:8 host_in; s.host_in_valid := Bits.of_int ~width:1 (if host_in_valid then 1 else 0);
    Cyclesim.cycle s.sim;
    s.current_addr <- s.pending_addr; s.pending_addr <- Bits.to_int !(s.imem_addr);
    { Isa_ls.host_out = (if Bits.to_int !(s.host_out_valid) = 1 then Some (Bits.to_int !(s.host_out), Bits.to_int !(s.host_out_tag) = 1) else None);
      host_in_ready = Bits.to_int !(s.host_in_ready) = 1 }
  let pins s = Bits.to_int !(s.pin_out), Bits.to_int !(s.pin_oe)
  let pcs s = let v = Bits.to_int !(s.pcs) in List.init Isa_ls.n_threads (fun t -> (v lsr (t * Isa_ls.pc_bits)) land (Isa_ls.prog_len - 1))
end
