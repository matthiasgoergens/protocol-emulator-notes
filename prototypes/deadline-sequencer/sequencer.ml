(* Deadline sequencer RTL. See isa.ml for the semantics this must match cycle for cycle.
   Instruction memory is external (one-cycle synchronous read): the core presents imem_addr for
   the thread that executes on the next cycle and consumes imem_data on that cycle. *)
open Hardcaml
open Signal

let n_threads = Isa.n_threads
let pc_bits = Isa.pc_bits

let create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let thread = Variable.reg spec ~width:2 in
  let regs width = Array.init n_threads (fun _ -> Variable.reg spec ~width) in
  let pcs = regs pc_bits and accs = regs 8 and cnts = regs 12 and dls = regs 12 in
  let pin_out = Variable.reg spec ~width:8 in
  let pin_oe = Variable.reg spec ~width:8 in
  let host_out = Variable.reg spec ~width:8 in
  let host_out_valid = Variable.reg spec ~width:1 in
  let host_in_ready = Variable.wire ~default:gnd in
  let values arr = Array.to_list (Array.map (fun (v : Variable.t) -> v.value) arr) in
  let sel arr = mux thread.value (values arr) in
  let pc = sel pcs and acc = sel accs and cnt = sel cnts and dl = sel dls in
  let instr = imem_data in
  let op = select instr 15 12 in
  let imm12 = select instr 11 0 and imm8 = select instr 7 0 in
  let pin_idx = select instr 11 9 and pin_val = bit instr 8 in
  let addr6 = select instr 5 0 in
  let od = bit instr 7 in
  let mask8 = select instr 11 4 and setv = bit instr 3 and seto = bit instr 2 in
  let pin_bit = mux pin_idx (List.init 8 (fun i -> bit pin_in i)) in
  let pc_next = Variable.wire ~default:(pc +:. 1) in
  let acc_next = Variable.wire ~default:acc in
  let cnt_next = Variable.wire ~default:cnt in
  let dl_next = Variable.wire ~default:(mux2 (dl ==:. 0) dl (dl -:. 1)) in
  let stay = [ pc_next <-- pc ] in
  let with_pin_bit v = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) v (bit pin_out.value i))) in
  let with_oe_bit v = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) v (bit pin_oe.value i))) in
  let sho_bit = mux2 pin_val (bit acc 7) (bit acc 0) in
  let opc o = of_int ~width:4 (Isa.code_of_op o) in
  compile
    [ thread <-- thread.value +:. 1
    ; host_out_valid <-- gnd
    ; switch op
        [ opc SETP, [ pin_out <-- ((pin_out.value &: ~:mask8) |: (mask8 &: repeat setv 8))
                    ; pin_oe <-- ((pin_oe.value &: ~:mask8) |: (mask8 &: repeat seto 8)) ]
        ; opc LDC, [ cnt_next <-- imm12 ]
        ; opc LDD, [ dl_next <-- imm12 ]
        ; opc LDA, [ acc_next <-- imm8 ]
        ; opc WAITP, [ if_ (pin_bit ==: pin_val) [] [ if_ (dl ==:. 0) [ pc_next <-- addr6 ] stay ] ]
        ; opc WAITD, [ if_ (dl ==:. 0) [] stay ]
        ; opc SHO, [ if_ od [ pin_out <-- with_pin_bit gnd; pin_oe <-- with_oe_bit (~:sho_bit) ]
                       [ pin_out <-- with_pin_bit sho_bit ]
                   ; acc_next <-- mux2 pin_val (sll acc 1) (srl acc 1)
                   ; cnt_next <-- cnt -:. 1 ]
        ; opc SHI, [ acc_next <-- mux2 pin_val (concat_msb [ select acc 6 0; pin_bit ])
                                              (concat_msb [ pin_bit; select acc 7 1 ])
                   ; cnt_next <-- cnt -:. 1 ]
        ; opc JMP, [ pc_next <-- addr6 ]
        ; opc JNZ, [ if_ (cnt <>:. 0) [ pc_next <-- addr6 ] [] ]
        ; opc OUT, [ host_out <-- acc; host_out_valid <-- vdd ]
        ; opc IN, [ if_ host_in_valid [ acc_next <-- host_in; host_in_ready <-- vdd ] stay ]
        ; opc HALT, stay ]
    ; proc (List.init n_threads (fun t ->
        when_ (thread.value ==:. t)
          [ pcs.(t) <-- pc_next.value; accs.(t) <-- acc_next.value
          ; cnts.(t) <-- cnt_next.value; dls.(t) <-- dl_next.value ]))
    ];
  let tnext = thread.value +:. 1 in
  let imem_addr = concat_msb [ tnext; mux tnext (values pcs) ] in
  let pcs_out = concat_msb (List.rev (values pcs)) in
  imem_addr, pin_out.value, pin_oe.value, host_out.value, host_out_valid.value, host_in_ready.value, pcs_out

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let imem_data = input "imem_data" 16 and pin_in = input "pin_in" 8 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let imem_addr, pin_out, pin_oe, host_out, host_out_valid, host_in_ready, pcs =
    create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid in
  Circuit.create_exn ~name:"deadline_sequencer"
    [ output "imem_addr" imem_addr; output "pin_out" pin_out; output "pin_oe" pin_oe
    ; output "host_out" host_out; output "host_out_valid" host_out_valid
    ; output "host_in_ready" host_in_ready; output "pcs" pcs ]
