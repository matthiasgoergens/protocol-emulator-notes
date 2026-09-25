(* RTL of the ISA variant in isa_ls.ml, a copy of ../deadline-sequencer/sequencer.ml with the
   four changes: 8-bit pc, SKNE, SHO pair mode, OUT event mode. Instruction memory is external
   with one cycle of read latency; the core presents the address (thread, pc) of the thread that
   executes next. *)
open Hardcaml
open Signal

let n_threads = Isa_ls.n_threads
let pc_bits = Isa_ls.pc_bits

let create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let thread = Variable.reg spec ~width:2 in
  let regs width = Array.init n_threads (fun _ -> Variable.reg spec ~width) in
  let pcs = regs pc_bits and accs = regs 8 and cnts = regs 12 and dls = regs 12 in
  let pin_out = Variable.reg spec ~width:8 in
  let pin_oe = Variable.reg spec ~width:8 in
  let host_out = Variable.reg spec ~width:8 in
  let host_out_tag = Variable.reg spec ~width:1 in
  let host_out_valid = Variable.reg spec ~width:1 in
  let host_in_ready = Variable.wire ~default:gnd in
  let values arr = Array.to_list (Array.map (fun (v : Variable.t) -> v.value) arr) in
  let sel arr = mux thread.value (values arr) in
  let pc = sel pcs and acc = sel accs and cnt = sel cnts and dl = sel dls in
  let instr = imem_data in
  let op = select instr 15 12 in
  let imm12 = select instr 11 0 and imm8 = select instr 7 0 in
  let pin_idx = select instr 11 9 and pin_val = bit instr 8 in
  let addr = select instr (pc_bits - 1) 0 in
  let od = bit instr 7 and pair = bit instr 6 in
  let mask8 = select instr 11 4 and setv = bit instr 3 and seto = bit instr 2 in
  let pin_bit = mux pin_idx (List.init 8 (fun i -> bit pin_in i)) in
  let pc_next = Variable.wire ~default:(pc +:. 1) in
  let acc_next = Variable.wire ~default:acc in
  let cnt_next = Variable.wire ~default:cnt in
  let dl_next = Variable.wire ~default:(mux2 (dl ==:. 0) dl (dl -:. 1)) in
  let stay = [ pc_next <-- pc ] in
  let pin2 = pin_idx +:. 1 in
  (* per-pin new values: the single-pin case writes pin_idx; pair mode also writes pin_idx+1 *)
  let b0 = mux2 pin_val (bit acc 7) (bit acc 0) in
  let b1 = mux2 pin_val (bit acc 6) (bit acc 1) in
  let hit0 i = pin_idx ==:. i and hit1 i = pair &: (pin2 ==:. i) in
  let bit_for i = mux2 (hit0 i) b0 b1 in
  let written i = hit0 i |: hit1 i in
  let sho_out = concat_lsb (List.init 8 (fun i ->
      mux2 (written i) (mux2 od gnd (bit_for i)) (bit pin_out.value i))) in
  let sho_oe = concat_lsb (List.init 8 (fun i ->
      mux2 (written i &: od) (~:(bit_for i)) (bit pin_oe.value i))) in
  let opc o = of_int ~width:4 (Isa_ls.code_of_op o) in
  compile
    [ thread <-- thread.value +:. 1
    ; host_out_valid <-- gnd
    ; switch op
        [ opc SETP, [ pin_out <-- ((pin_out.value &: ~:mask8) |: (mask8 &: repeat setv 8))
                    ; pin_oe <-- ((pin_oe.value &: ~:mask8) |: (mask8 &: repeat seto 8)) ]
        ; opc LDC, [ cnt_next <-- imm12 ]
        ; opc LDD, [ dl_next <-- imm12 ]
        ; opc LDA, [ acc_next <-- imm8 ]
        ; opc WAITP, [ if_ (pin_bit ==: pin_val) [] [ if_ (dl ==:. 0) [ pc_next <-- addr ] stay ] ]
        ; opc WAITD, [ if_ (dl ==:. 0) [] stay ]
        ; opc SHO, [ pin_out <-- sho_out; pin_oe <-- sho_oe
                   ; acc_next <-- mux2 pair (mux2 pin_val (sll acc 2) (srl acc 2)) (mux2 pin_val (sll acc 1) (srl acc 1))
                   ; cnt_next <-- cnt -:. 1 ]
        ; opc SHI, [ acc_next <-- mux2 pin_val (concat_msb [ select acc 6 0; pin_bit ])
                                              (concat_msb [ pin_bit; select acc 7 1 ])
                   ; cnt_next <-- cnt -:. 1 ]
        ; opc JMP, [ pc_next <-- addr ]
        ; opc JNZ, [ if_ (cnt <>:. 0) [ pc_next <-- addr ] [] ]
        ; opc OUT, [ host_out <-- mux2 pin_val imm8 acc; host_out_tag <-- pin_val; host_out_valid <-- vdd ]
        ; opc IN, [ if_ host_in_valid [ acc_next <-- host_in; host_in_ready <-- vdd ] stay ]
        ; opc HALT, stay
        ; opc SKNE, [ when_ ((acc <>: imm8) ==: ~:pin_val) [ pc_next <-- pc +:. 2 ] ] ]
    ; proc (List.init n_threads (fun t ->
        when_ (thread.value ==:. t)
          [ pcs.(t) <-- pc_next.value; accs.(t) <-- acc_next.value
          ; cnts.(t) <-- cnt_next.value; dls.(t) <-- dl_next.value ]))
    ];
  let tnext = thread.value +:. 1 in
  let imem_addr = concat_msb [ tnext; mux tnext (values pcs) ] in
  let pcs_out = concat_msb (List.rev (values pcs)) in
  imem_addr, pin_out.value, pin_oe.value, host_out.value, host_out_tag.value, host_out_valid.value, host_in_ready.value, pcs_out

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let imem_data = input "imem_data" 16 and pin_in = input "pin_in" 8 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let imem_addr, pin_out, pin_oe, host_out, host_out_tag, host_out_valid, host_in_ready, pcs =
    create ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid in
  Circuit.create_exn ~name:"deadline_sequencer_ls"
    [ output "imem_addr" imem_addr; output "pin_out" pin_out; output "pin_oe" pin_oe
    ; output "host_out" host_out; output "host_out_tag" host_out_tag; output "host_out_valid" host_out_valid
    ; output "host_in_ready" host_in_ready; output "pcs" pcs ]
