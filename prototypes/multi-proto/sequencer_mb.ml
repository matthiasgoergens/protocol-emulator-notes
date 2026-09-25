(* Mailbox variant of the deadline sequencer RTL. See isa_mb.ml for the semantics this must match
   cycle for cycle; ../deadline-sequencer/sequencer.ml is the base it extends (unmodified).

   Parameters: pc_bits (6 or 7), depth (inbox entries: 1, 2 or 4). [mutant] plants a bug for the
   lockstep test's control: `Full_never makes an inbox never report full, so a SEND to a full
   inbox overwrites the oldest entry; `Wrong_slot writes a push one slot past the tail, which
   corrupts only the inbox's contents until the byte is popped. *)
open Hardcaml
open Signal

let n_threads = Isa_mb.n_threads

let log2 d = match d with 1 -> 0 | 2 -> 1 | 4 -> 2 | 8 -> 3 | _ -> failwith "depth must be 1, 2, 4 or 8"

let create ?(mutant : [ `Full_never | `Wrong_slot | `None ] = `None) ~(c : Isa_mb.cfg) ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid
    ~port_in ~port_in_valid ~port_out_ready ~flags () =
  let pb = c.pc_bits and d = c.depth in
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let thread = Variable.reg spec ~width:2 in
  let regs width = Array.init n_threads (fun _ -> Variable.reg spec ~width) in
  let pcs = regs pb and accs = regs 8 and cnts = regs 12 and dls = regs 12 in
  let pin_out = Variable.reg spec ~width:8 in
  let pin_oe = Variable.reg spec ~width:8 in
  let host_out = Variable.reg spec ~width:8 in
  let host_out_valid = Variable.reg spec ~width:1 in
  let host_in_ready = Variable.wire ~default:gnd in
  let port_out_data = Variable.reg spec ~width:8 in
  let port_out_valid = Variable.reg spec ~width:4 in
  let port_in_ready = Variable.wire ~default:(zero 4) in
  (* inboxes: [d] byte slots, a read pointer and an occupancy count each *)
  let lw = log2 d in
  let slots = Array.init n_threads (fun _ -> Array.init d (fun _ -> Variable.reg spec ~width:8)) in
  let heads = Array.init n_threads (fun _ -> Variable.reg spec ~width:(max 1 lw)) in
  let counts = Array.init n_threads (fun _ -> Variable.reg spec ~width:(lw + 1)) in
  let full i = match mutant with `Full_never -> gnd | `Wrong_slot | `None -> counts.(i).value ==:. d in
  let nonempty i = counts.(i).value <>:. 0 in
  let head_data i = if d = 1 then slots.(i).(0).value else mux (select heads.(i).value (lw - 1) 0) (Array.to_list (Array.map (fun (v : Variable.t) -> v.value) slots.(i))) in
  let values arr = Array.to_list (Array.map (fun (v : Variable.t) -> v.value) arr) in
  let sel arr = mux thread.value (values arr) in
  let pc = sel pcs and acc = sel accs and cnt = sel cnts and dl = sel dls in
  let instr = imem_data in
  let op = select instr 15 12 in
  let imm12 = select instr 11 0 and imm8 = select instr 7 0 in
  let pin_idx = select instr 11 9 and pin_val = bit instr 8 in
  let addr = select instr (pb - 1) 0 in
  let od = bit instr 7 in
  let mask8 = select instr 11 4 and setv = bit instr 3 and seto = bit instr 2 in
  let is_recv = bit instr 11 and ch_port = bit instr 10 and ch_lo = select instr 9 8 in
  let cval = bit instr 11 and cond = select instr 10 7 in
  let pin_bit = mux pin_idx (List.init 8 (fun i -> bit pin_in i)) in
  let cap_bit = bit instr 6 &: mux (select instr 5 3) (List.init 8 (fun i -> bit pin_in i)) in
  let pc_next = Variable.wire ~default:(pc +:. 1) in
  let acc_next = Variable.wire ~default:acc in
  let cnt_next = Variable.wire ~default:cnt in
  let dl_next = Variable.wire ~default:(mux2 (dl ==:. 0) dl (dl -:. 1)) in
  let stay = [ pc_next <-- pc ] in
  let fail_or_stay = [ if_ (dl ==:. 0) [ pc_next <-- addr ] stay ] in
  let with_pin_bit v = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) v (bit pin_out.value i))) in
  let with_oe_bit v = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) v (bit pin_oe.value i))) in
  let sho_bit = mux2 pin_val (bit acc 7) (bit acc 0) in
  let full_v = concat_lsb (List.init n_threads full) in
  let nonempty_v = concat_lsb (List.init n_threads nonempty) in
  let cond_bit = mux cond (List.init 8 (fun i -> bit acc i) @ List.init 4 (fun i -> bit full_v i) @ List.init 4 (fun i -> bit flags i)) in
  let onehot2 s = concat_lsb (List.init 4 (fun i -> s ==:. i)) in
  (* inbox push/pop requests, decoded once; at most one is active per cycle *)
  let push = Variable.wire ~default:gnd and pop = Variable.wire ~default:gnd in
  let opc o = of_int ~width:4 o in
  compile
    [ thread <-- thread.value +:. 1
    ; host_out_valid <-- gnd
    ; port_out_valid <--. 0
    ; switch op
        [ opc 1, [ pin_out <-- ((pin_out.value &: ~:mask8) |: (mask8 &: repeat setv 8))
                 ; pin_oe <-- ((pin_oe.value &: ~:mask8) |: (mask8 &: repeat seto 8)) ]
        ; opc 2, [ cnt_next <-- imm12 ]
        ; opc 3, [ dl_next <-- imm12 ]
        ; opc 4, [ acc_next <-- imm8 ]
        ; opc 5, [ if_ (pin_bit ==: pin_val) [] fail_or_stay ]
        ; opc 6, [ if_ (dl ==:. 0) [] stay ]
        ; opc 7, [ if_ od [ pin_out <-- with_pin_bit gnd; pin_oe <-- with_oe_bit (~:sho_bit) ]
                     [ pin_out <-- with_pin_bit sho_bit ]
                 ; acc_next <-- mux2 pin_val (sll acc 1 |: uresize cap_bit 8) (srl acc 1 |: concat_msb [ cap_bit; zero 7 ])
                 ; cnt_next <-- cnt -:. 1 ]
        ; opc 8, [ acc_next <-- mux2 pin_val (concat_msb [ select acc 6 0; pin_bit ])
                                            (concat_msb [ pin_bit; select acc 7 1 ])
                 ; cnt_next <-- cnt -:. 1 ]
        ; opc 9, [ pc_next <-- addr ]
        ; opc 10, [ if_ (cnt <>:. 0) [ pc_next <-- addr ] [] ]
        ; opc 11, [ host_out <-- acc; host_out_valid <-- vdd ]
        ; opc 12, [ if_ host_in_valid [ acc_next <-- host_in; host_in_ready <-- vdd ] stay ]
        ; opc 13, stay
        ; opc 14,
          [ if_ is_recv
              [ if_ ch_port
                  [ if_ (mux ch_lo (List.init 4 (fun i -> bit port_in_valid i)))
                      [ acc_next <-- mux ch_lo (Array.to_list port_in); port_in_ready <-- onehot2 ch_lo ]
                      fail_or_stay ]
                  [ if_ (mux ch_lo (List.init 4 (fun i -> bit nonempty_v i)))
                      [ acc_next <-- mux ch_lo (List.init 4 head_data); pop <-- vdd ]
                      fail_or_stay ] ]
              [ if_ ch_port
                  [ if_ (mux ch_lo (List.init 4 (fun i -> bit port_out_ready i)))
                      [ port_out_data <-- acc; port_out_valid <-- onehot2 ch_lo ]
                      fail_or_stay ]
                  [ if_ (~:(mux ch_lo (List.init 4 (fun i -> bit full_v i)))) [ push <-- vdd ] fail_or_stay ] ] ]
        ; opc 15, [ if_ (cond_bit ==: cval) [] fail_or_stay ] ]
    ; proc (List.init n_threads (fun t ->
        when_ (thread.value ==:. t)
          [ pcs.(t) <-- pc_next.value; accs.(t) <-- acc_next.value
          ; cnts.(t) <-- cnt_next.value; dls.(t) <-- dl_next.value ]))
    ; proc (List.init n_threads (fun i ->
        let mine = ch_lo ==:. i in
        let widx = if d = 1 then gnd else select (heads.(i).value +: uresize counts.(i).value (max 1 lw)) (lw - 1) 0 in
        let widx = match mutant with `Wrong_slot when d > 1 -> widx +:. 1 | _ -> widx in
        proc
          [ when_ (push.value &: mine)
              [ proc (List.init d (fun j -> when_ (if d = 1 then vdd else widx ==:. j) [ slots.(i).(j) <-- acc ]))
              ; (match mutant with
                 | `Full_never -> counts.(i) <-- mux2 (counts.(i).value ==:. d) counts.(i).value (counts.(i).value +:. 1)
                 | `Wrong_slot | `None -> counts.(i) <-- counts.(i).value +:. 1) ]
          ; when_ (pop.value &: mine)
              [ (if d = 1 then proc [] else heads.(i) <-- heads.(i).value +:. 1)
              ; counts.(i) <-- counts.(i).value -:. 1 ] ]))
    ];
  let tnext = thread.value +:. 1 in
  let imem_addr = concat_msb [ tnext; mux tnext (values pcs) ] in
  let pcs_out = concat_msb (List.rev (values pcs)) in
  let counts_out = concat_msb (List.rev (List.map (fun (v : Variable.t) -> uresize v.value 3) (Array.to_list counts))) in
  (* every architectural register, for the lockstep test only (the synthesised netlist has none of
     these ports): accumulators, counters, deadlines, inbox slots and read pointers *)
  let cat arr = concat_msb (List.rev (values arr)) in
  let dbg = [ "dbg_acc", cat accs; "dbg_cnt", cat cnts; "dbg_dl", cat dls;
              "dbg_slots", concat_msb (List.rev (List.concat_map (fun a -> values a) (Array.to_list slots)));
              "dbg_heads", (if d = 1 then zero 4 else cat heads); "dbg_thread", thread.value ] in
  ( imem_addr, pin_out.value, pin_oe.value, host_out.value, host_out_valid.value, host_in_ready.value, pcs_out
  , port_out_data.value, port_out_valid.value, port_in_ready.value, counts_out, dbg )

let circuit ?mutant ?(debug = false) (c : Isa_mb.cfg) =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let imem_data = input "imem_data" 16 and pin_in = input "pin_in" 8 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let port_in = Array.init 4 (fun i -> input (Printf.sprintf "port_in%d" i) 8) in
  let port_in_valid = input "port_in_valid" 4 and port_out_ready = input "port_out_ready" 4 in
  let flags = input "flags" 4 in
  let imem_addr, pin_out, pin_oe, host_out, host_out_valid, host_in_ready, pcs, pod, pov, pir, cnts, dbg =
    create ?mutant ~c ~clock ~clear ~imem_data ~pin_in ~host_in ~host_in_valid ~port_in ~port_in_valid
      ~port_out_ready ~flags () in
  Circuit.create_exn ~name:(Printf.sprintf "deadline_sequencer_mb_p%d_d%d" c.pc_bits c.depth)
    ([ output "imem_addr" imem_addr; output "pin_out" pin_out; output "pin_oe" pin_oe
    ; output "host_out" host_out; output "host_out_valid" host_out_valid
    ; output "host_in_ready" host_in_ready; output "pcs" pcs
    ; output "port_out_data" pod; output "port_out_valid" pov; output "port_in_ready" pir
    ; output "mb_counts" cnts ]
    @ (if debug then List.map (fun (n, sg) -> output n sg) dbg else []))
