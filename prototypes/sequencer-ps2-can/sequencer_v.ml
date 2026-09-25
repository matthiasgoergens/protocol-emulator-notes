(* RTL of ISA variant "v" (isa_v.ml): ../deadline-sequencer/sequencer.ml plus an 8-bit pc, the
   per-thread CRC engine and stuff tracker, JC, CFG and the tagged OUT. Must match Isa_v.step
   cycle for cycle; main.exe checks that by lockstep on random programmes. *)
open Hardcaml
open Signal

let n_threads = Isa_v.n_threads
let pc_bits = Isa_v.pc_bits

let create ~shared_cfg ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let thread = Variable.reg spec ~width:2 in
  let regs width = Array.init n_threads (fun _ -> Variable.reg spec ~width) in
  let pcs = regs pc_bits and accs = regs 8 and cnts = regs 12 and dls = regs 12 in
  let crcs = regs 16 and runs = regs 3 and lasts = regs 1 in
  (* configuration: per thread, or one set shared by all threads (see Isa_v.shared_cfg) *)
  let cfg_regs width = if shared_cfg then [| Variable.reg spec ~width |] else regs width in
  let polys = cfg_regs 16 and limits = cfg_regs 3 and modes = cfg_regs 1 in
  let pin_out = Variable.reg spec ~width:8 in
  let pin_oe = Variable.reg spec ~width:8 in
  let host_out = Variable.reg spec ~width:8 in
  let host_out_tag = Variable.reg spec ~width:3 in
  let host_out_valid = Variable.reg spec ~width:1 in
  let host_in_ready = Variable.wire ~default:gnd in
  let values arr = Array.to_list (Array.map (fun (v : Variable.t) -> v.value) arr) in
  let sel arr = mux thread.value (values arr) in
  let pc = sel pcs and acc = sel accs and cnt = sel cnts and dl = sel dls in
  let sel_cfg arr = if shared_cfg then arr.(0).Variable.value else sel arr in
  let crc = sel crcs and poly = sel_cfg polys and run = sel runs and last = sel lasts in
  let limit = sel_cfg limits and mode = sel_cfg modes in
  let instr = imem_data in
  let op = select instr 15 12 in
  let imm12 = select instr 11 0 and imm8 = select instr 7 0 in
  let pin_idx = select instr 11 9 and pin_val = bit instr 8 in
  let addr = select instr 7 0 in
  let od = bit instr 7 in
  let fcrc = bit instr 6 and fstf = bit instr 5 and norec = bit instr 4 in
  let mask8 = select instr 11 4 and setv = bit instr 3 and seto = bit instr 2 in
  let pin_bit = mux pin_idx (List.init 8 (fun i -> bit pin_in i)) in
  let pc_next = Variable.wire ~default:(pc +:. 1) in
  let acc_next = Variable.wire ~default:acc in
  let cnt_next = Variable.wire ~default:cnt in
  let dl_next = Variable.wire ~default:(mux2 (dl ==:. 0) dl (dl -:. 1)) in
  let crc_next = Variable.wire ~default:crc in
  let poly_next = Variable.wire ~default:poly in
  let run_next = Variable.wire ~default:run in
  let last_next = Variable.wire ~default:last in
  let limit_next = Variable.wire ~default:limit in
  let mode_next = Variable.wire ~default:mode in
  let stay = [ pc_next <-- pc ] in
  let with_pin_bit v = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) v (bit pin_out.value i))) in
  let with_oe_bit v = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) v (bit pin_oe.value i))) in
  let sho_bit = mux2 pin_val (bit acc 7) (bit acc 0) in
  (* the bit fed to the CRC engine and stuff tracker: driven bit for SHO, sampled bit for SHI *)
  let feed b =
    let fb = b ^: bit crc 15 in
    let crc_upd = (sll crc 1) ^: (poly &: repeat fb 16) in
    let run_sat = mux2 (run ==:. 7) run (run +:. 1) in
    let run_upd =
      mux2 mode
        (mux2 b run_sat (zero 3))
        (mux2 ((run <>:. 0) &: (b ==: last)) run_sat (one 3)) in
    [ when_ fcrc [ crc_next <-- crc_upd ]
    ; when_ fstf [ run_next <-- run_upd; last_next <-- b ] ] in
  let opc o = of_int ~width:4 (Isa_v.code_of_op o) in
  let cond = select instr 11 8 in
  let taken =
    mux cond
      (List.init 8 (fun k -> bit acc k)
       @ [ crc ==:. 0; run >=: limit; select cnt 2 0 ==:. 0; last; gnd; gnd; gnd; gnd ]) in
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
        ; opc SHO, [ if_ od [ pin_out <-- with_pin_bit gnd; pin_oe <-- with_oe_bit (~:sho_bit) ]
                       [ pin_out <-- with_pin_bit sho_bit ]
                   ; proc (feed sho_bit)
                   ; acc_next <-- mux2 pin_val (sll acc 1) (srl acc 1)
                   ; cnt_next <-- cnt -:. 1 ]
        ; opc SHI, [ proc (feed pin_bit)
                   ; when_ (~:norec)
                       [ acc_next <-- mux2 pin_val (concat_msb [ select acc 6 0; pin_bit ])
                                                  (concat_msb [ pin_bit; select acc 7 1 ])
                       ; cnt_next <-- cnt -:. 1 ] ]
        ; opc JMP, [ pc_next <-- addr ]
        ; opc JNZ, [ if_ (cnt <>:. 0) [ pc_next <-- addr ] [] ]
        ; opc OUT, [ host_out <-- mux2 (bit instr 11) imm8 acc; host_out_tag <-- select instr 10 8
                   ; host_out_valid <-- vdd ]
        ; opc IN, [ if_ host_in_valid [ acc_next <-- host_in; host_in_ready <-- vdd ] stay ]
        ; opc HALT, stay
        ; opc JC, [ when_ taken [ pc_next <-- addr ] ]
        ; opc CFG, [ switch (select instr 11 10)
                       [ of_int ~width:2 0, [ crc_next <-- zero 16; run_next <-- zero 3; last_next <-- bit instr 9
                                            ; mode_next <-- bit instr 8; limit_next <-- select instr 2 0 ]
                       ; of_int ~width:2 1, [ poly_next <-- concat_msb [ select poly 15 8; imm8 ] ]
                       ; of_int ~width:2 2, [ poly_next <-- concat_msb [ imm8; select poly 7 0 ] ]
                       ; of_int ~width:2 3, [ cnt_next <-- uresize acc 12 ] ] ] ]
    ; proc (List.init n_threads (fun t ->
        when_ (thread.value ==:. t)
          ([ pcs.(t) <-- pc_next.value; accs.(t) <-- acc_next.value
           ; cnts.(t) <-- cnt_next.value; dls.(t) <-- dl_next.value
           ; crcs.(t) <-- crc_next.value
           ; runs.(t) <-- run_next.value; lasts.(t) <-- last_next.value ]
           @ (if shared_cfg then []
              else [ polys.(t) <-- poly_next.value; limits.(t) <-- limit_next.value; modes.(t) <-- mode_next.value ]))))
    ; (if shared_cfg then proc [ polys.(0) <-- poly_next.value; limits.(0) <-- limit_next.value; modes.(0) <-- mode_next.value ]
       else proc [])
    ];
  let tnext = thread.value +:. 1 in
  let imem_addr = concat_msb [ tnext; mux tnext (values pcs) ] in
  let pcs_out = concat_msb (List.rev (values pcs)) in
  (* debug view of the assist state, for lockstep only: per thread crc, run, last *)
  let dbg = List.init n_threads (fun t -> concat_msb [ lasts.(t).value; runs.(t).value; crcs.(t).value ]) in
  imem_addr, pin_out.value, pin_oe.value, host_out.value, host_out_tag.value, host_out_valid.value,
  host_in_ready.value, pcs_out, dbg

let circuit ?(debug = false) ?(shared_cfg = false) () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let imem_data = input "imem_data" 16 and pin_in = input "pin_in" 8 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let imem_addr, pin_out, pin_oe, host_out, host_out_tag, host_out_valid, host_in_ready, pcs, dbg =
    create ~shared_cfg ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid in
  Circuit.create_exn ~name:(if shared_cfg then "deadline_sequencer_vs" else "deadline_sequencer_v")
    ([ output "imem_addr" imem_addr; output "pin_out" pin_out; output "pin_oe" pin_oe
    ; output "host_out" host_out; output "host_out_tag" host_out_tag
    ; output "host_out_valid" host_out_valid
    ; output "host_in_ready" host_in_ready; output "pcs" pcs ]
    @ (if debug then List.mapi (fun t d -> output (Printf.sprintf "dbg%d" t) d) dbg else []))
