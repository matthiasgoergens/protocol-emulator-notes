(* Drop-in replacement for ../../../usb-ls/sequencer_ls.ml: the v2 core (sequencer2.ml) behind a
   combinational translator of usb-ls words into v2 words, the hardware twin of Compat.of_ls.
   fw_sys.ml feeds the core raw usb-ls words from the programme arrays the controller patches, so
   the translation has to happen on the fetch path. HALT's translation, JMP to its own address,
   takes the address from a register holding the previous clock's fetch address. The interpreter
   side (isa_ls.ml) uses Compat.of_ls, so the lockstep also checks this translator against it. *)
open Hardcaml
open Signal

let n_threads = Isa2.n_threads
let pc_bits = Isa2.pc_bits

let translate ~addr w =
  let c16 x = of_int ~width:16 x in
  let op4 x = of_int ~width:4 x in
  let b8 = bit w 8 and imm8 = select w 7 0 in
  mux (select w 15 12)
    [ zero 16                                                        (* 0 NOP *)
    ; w &: c16 0xFFFC                                                (* 1 SETP: no q in usb-ls *)
    ; w; w                                                           (* 2 LDC, 3 LDD *)
    ; w &: c16 0xF0FF                                                (* 4 LDA *)
    ; w                                                              (* 5 WAITP, 8-bit fail *)
    ; c16 0x6000                                                     (* 6 WAITD *)
    ; (w &: c16 0xFF80) |: mux2 (bit w 6) (c16 0x60) (zero 16)       (* 7 SHO: pair -> pair+psel *)
    ; w &: c16 0xFF00                                                (* 8 SHI: no quad *)
    ; w; w                                                           (* 9 JMP, A JNZ *)
    ; mux2 b8 (concat_msb [ op4 11; vdd; of_int ~width:3 1; imm8 ]) (c16 0xB000)   (* B OUT *)
    ; c16 0xC000                                                     (* C IN *)
    ; concat_msb [ op4 9; zero 4; addr ]                             (* D HALT -> JMP self *)
    ; concat_msb [ op4 15; zero 3; b8; imm8 ]                        (* E SKNE -> EXT 0/1 *)
    ; zero 16 ]                                                      (* F NOP *)

let create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let fetch = wire 10 in
  let cur = reg spec fetch in
  let z w = zero w in
  let o = Sequencer2.create ~clock ~clear ~imem_data:(translate ~addr:(select cur 7 0) imem_data)
      ~pin_in ~pin_in4:(concat_msb (List.rev (List.concat (List.init 8 (fun i -> List.init 4 (fun _ -> bit pin_in i))))))
      ~host_in ~host_in_valid ~port_in:(Array.make 4 (z 8)) ~port_in_valid:(z 4) ~port_out_ready:(z 4)
      ~flags:(z 16) ~ctl_valid:gnd ~ctl_thread:(z 2) ~ctl_page:(z 2) ~ctl_pc:(z 8)
      ~boot_page:(of_int ~width:8 0b11100100) ~boot_pc:(z 32) ~bank_rdata:(z 8) () in
  fetch <== o.imem_addr;
  o.imem_addr, o.pin_out, o.pin_oe, o.host_out, o.host_tag <>:. 0, o.host_out_valid, o.host_in_ready,
  List.assoc "dbg_pc" o.dbg

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let imem_data = input "imem_data" 16 and pin_in = input "pin_in" 8 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let imem_addr, pin_out, pin_oe, host_out, host_out_tag, host_out_valid, host_in_ready, pcs =
    create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid in
  Circuit.create_exn ~name:"deadline_sequencer_v2_ls"
    [ output "imem_addr" imem_addr; output "pin_out" pin_out; output "pin_oe" pin_oe
    ; output "host_out" host_out; output "host_out_tag" host_out_tag; output "host_out_valid" host_out_valid
    ; output "host_in_ready" host_in_ready; output "pcs" pcs ]
