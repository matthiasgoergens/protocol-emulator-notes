(* ISA v2 deadline sequencer RTL. isa2.ml is the specification this must match cycle for cycle.

   Memories are outside the core, as in ../deadline-sequencer:
   - programme store: one-cycle synchronous read; the core presents imem_addr = {page, pc} of the
     thread that executes on the next clock (with the host-control write bypassed into it);
   - data bank: one-cycle synchronous read and write. STB presents bank_we, bank_addr and
     bank_wdata in its own clock. LDB presents bank_re and bank_addr in its own clock; the byte
     comes back on bank_rdata during the next clock and is written to the thread's accumulator
     then, three clocks before that thread's next slot, so the thread never sees the difference.
     For the lockstep comparison the harness shows the in-flight byte (the SRAM's output after
     the edge) as the thread's accumulator during that one clock (dbg_pend says which thread).

   [bug] plants one fault for the lockstep test's controls (see the list in [bugs]). *)
open Hardcaml
open Signal

let n_threads = Isa2.n_threads

type bug =
  | Pc6 | Page_ignored | Ctl_no_bypass
  | Pair_no_complement | Psel_shift1 | Cap_same_pin | Cap_wrong_bit
  | Out_tag_dropped | Out_src_ignored
  | Send_ignores_full | Recv_no_fail | Port_index | Lsend_on_success_only
  | Waitc_byte_4bits | Waitc_space_own | Waitc_flag_thread0 | Waitc_host_inverted
  | Skne_inverted | Skeq_skip_one | Fine_no_disarm | Cnta_7bits
  | Ldb_no_increment | Ldb_wrong_thread | Ldb_reads_next | Stb_data_cnt | Bank_hi_ignored | Cfg_latch_ignored | Latch_every_clock

let bugs =
  [ Pc6, "pc wraps at 6 bits"; Page_ignored, "page bits not in the fetch address";
    Ctl_no_bypass, "host pc write not bypassed into the fetch";
    Pair_no_complement, "SHO pair psel 0 drives b0, not its complement";
    Psel_shift1, "SHO pair psel 1 shifts by one"; Cap_same_pin, "SHO cap samples pin, not pin XOR 1";
    Cap_wrong_bit, "SHO cap (msb) enters bit 1";
    Out_tag_dropped, "OUT tag always 0"; Out_src_ignored, "OUT src 1 sends acc";
    Send_ignores_full, "SEND overwrites a full inbox"; Recv_no_fail, "RECV on an empty inbox stays at dl = 0";
    Port_index, "MBX port channel off by one"; Lsend_on_success_only, "lsend only set by a successful SEND";
    Waitc_byte_4bits, "WAITC 8 tests cnt[3:0]"; Waitc_space_own, "WAITC 11 tests the own inbox";
    Waitc_flag_thread0, "WAITC flags read from thread 0's group";
    Waitc_host_inverted, "WAITC 9 inverted";
    Skne_inverted, "SKNE skips on equal"; Skeq_skip_one, "SKEQ skip lands on pc+1";
    Fine_no_disarm, "FINE not disarmed by the pin write"; Cnta_7bits, "CNTA drops acc bit 7";
    Ldb_no_increment, "LDB does not increment bp"; Ldb_wrong_thread, "LDB byte lands in the next thread's acc";
    Ldb_reads_next, "LDB reads bp + 1"; Stb_data_cnt, "STB writes cnt[7:0]";
    Bank_hi_ignored, "BANK ignores imm"; Cfg_latch_ignored, "CFG round latch ignored";
    Latch_every_clock, "round latch loads every clock" ]

type outputs = {
  imem_addr : Signal.t; pin_out : Signal.t; pin_oe : Signal.t; pin_sub : Signal.t;
  host_out : Signal.t; host_tag : Signal.t; host_out_valid : Signal.t; host_in_ready : Signal.t;
  port_out_data : Signal.t; port_out_valid : Signal.t; port_in_ready : Signal.t;
  bank_addr : Signal.t; bank_we : Signal.t; bank_re : Signal.t; bank_wdata : Signal.t;
  fine_out : Signal.t; fine_valid : Signal.t; cfg_out : Signal.t;
  dbg : (string * Signal.t) list;
}

(* [unreset] names register groups built without the clear, as planted faults for the power-up
   determinism proof (../formal/powerup): "cfg", "dl", "host_tag", "inbox", "prev_pins". The
   default (none) is the real core. *)
let unreset_groups = [ "cfg"; "dl"; "host_tag"; "inbox"; "prev_pins" ]

let create ?bug ?(unreset = []) ~clock ~clear ~imem_data ~pin_in ~pin_in4 ~host_in ~host_in_valid ~port_in
    ~port_in_valid ~port_out_ready ~flags ~ctl_valid ~ctl_thread ~ctl_page ~ctl_pc ~boot_page ~boot_pc ~bank_rdata () =
  let is b = match bug with Some x -> x = b | None -> false in
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let thread = Variable.reg spec ~width:2 in
  (* pc and page have no reset of their own: clear loads them from boot_pc and boot_page, the
     host's per-thread start address (a configuration register outside the core) *)
  let spec_nc = Reg_spec.create ~clock () in
  List.iter (fun g -> if not (List.mem g unreset_groups) then invalid_arg ("Sequencer2: unreset " ^ g)) unreset;
  let spec_of g = if List.mem g unreset then spec_nc else spec in
  let regs ?(group = "") width = Array.init n_threads (fun _ -> Variable.reg (spec_of group) ~width) in
  let pcs = Array.init n_threads (fun _ -> Variable.reg spec_nc ~width:8) in
  let pages = Array.init n_threads (fun _ -> Variable.reg spec_nc ~width:2) in
  let accs = regs 8 and cnts = regs 12 and dls = regs ~group:"dl" 12 in
  let bps = regs 10 and fines = regs 8 and armed = regs 1 and cfgs = regs ~group:"cfg" 8 and lsend = regs 3 in
  let inbox = regs ~group:"inbox" 8 and full = regs 1 in
  let pin_out = Variable.reg spec ~width:8 and pin_oe = Variable.reg spec ~width:8 in
  let prev_pins = Variable.reg (spec_of "prev_pins") ~width:8 and q_reg = Variable.reg spec ~width:2 in
  let latch = Variable.reg spec ~width:8 in
  let host_out = Variable.reg spec ~width:8 and host_tag = Variable.reg (spec_of "host_tag") ~width:3 in
  let host_out_valid = Variable.reg spec ~width:1 in
  let port_out_data = Variable.reg spec ~width:8 and port_out_valid = Variable.reg spec ~width:4 in
  let fine_out = Variable.reg spec ~width:8 and fine_valid = Variable.reg spec ~width:1 in
  let pend_valid = Variable.reg spec ~width:1 and pend_thread = Variable.reg spec ~width:2 in
  let host_in_ready = Variable.wire ~default:gnd in
  let port_in_ready = Variable.wire ~default:(zero 4) in
  let values arr = Array.to_list (Array.map (fun (v : Variable.t) -> v.value) arr) in
  let sel arr = mux thread.value (values arr) in
  let pc = sel pcs and acc = sel accs and cnt = sel cnts and dl = sel dls in
  let bp = sel bps and cfg = sel cfgs and ls = sel lsend and arm = sel armed in
  let full_v = concat_lsb (values full) in
  let instr = imem_data in
  let op = select instr 15 12 in
  let imm12 = select instr 11 0 and imm8 = select instr 7 0 in
  let pin_idx = select instr 11 9 and pin_val = bit instr 8 in
  let addr = select instr 7 0 in
  let od = bit instr 7 and pair = bit instr 6 and psel = bit instr 5 and cap = bit instr 4 in
  let mask8 = select instr 11 4 and setv = bit instr 3 and seto = bit instr 2 in
  let q = select instr 1 0 and quad = bit instr 7 in
  let dir = bit instr 11 and ch = select instr 10 8 in
  let cond = select instr 11 8 and sub = select instr 11 8 in
  (* round latch *)
  let latch_load = if is Latch_every_clock then vdd else thread.value ==:. 0 in
  let pins =
    if is Cfg_latch_ignored then pin_in
    else mux2 (bit cfg 7) (mux2 (thread.value ==:. 0) pin_in latch.value) pin_in in
  let pin_at i = mux i (List.init 8 (fun k -> bit pins k)) in
  let pin_bit = pin_at pin_idx in
  let nib = mux pin_idx (List.init 8 (fun i -> select pin_in4 (4 * i + 3) (4 * i))) in
  let rev4 n = concat_lsb [ bit n 3; bit n 2; bit n 1; bit n 0 ] in
  let pc_inc k = if is Pc6 then concat_msb [ zero 2; select (pc +:. k) 5 0 ] else pc +:. k in
  let sub_q = Variable.wire ~default:(zero 2) in
  let pin_out_n = Variable.wire ~default:pin_out.value in
  let pin_oe_n = Variable.wire ~default:pin_oe.value in
  let pc_next = Variable.wire ~default:(pc_inc 1) in
  let acc_next = Variable.wire ~default:acc in
  let cnt_next = Variable.wire ~default:cnt in
  let dl_next = Variable.wire ~default:(mux2 (dl ==:. 0) dl (dl -:. 1)) in
  let bp_next = Variable.wire ~default:bp in
  let fine_n = Variable.wire ~default:(sel fines) in
  let armed_n = Variable.wire ~default:arm in
  let cfg_n = Variable.wire ~default:cfg in
  let lsend_n = Variable.wire ~default:ls in
  let push = Variable.wire ~default:gnd and pop = Variable.wire ~default:gnd in
  let bank_we = Variable.wire ~default:gnd and bank_re = Variable.wire ~default:gnd in
  let stay = [ pc_next <-- pc ] in
  let fail_or_stay = [ if_ (dl ==:. 0) [ pc_next <-- addr ] stay ] in
  let pin_write =
    [ when_ (arm ==:. 1) [ fine_out <-- sel fines; fine_valid <-- vdd
                         ; (if is Fine_no_disarm then proc [] else armed_n <-- gnd) ] ] in
  (* SHO: b0 on pin, b1 on pin+1 when paired *)
  let msb = pin_val in
  let b0 = mux2 msb (bit acc 7) (bit acc 0) in
  let b1 = mux2 psel (mux2 msb (bit acc 6) (bit acc 1))
      (if is Pair_no_complement then b0 else ~:b0) in
  let pin_hi = pin_idx +:. 1 in
  let onehot3 s = concat_lsb (List.init 8 (fun i -> s ==:. i)) in
  let m0 = onehot3 pin_idx and m1 = mux2 pair (onehot3 pin_hi) (zero 8) in
  (* value per pin: b0 at pin_idx, b1 at pin+1 *)
  let vals = concat_lsb (List.init 8 (fun i -> mux2 (pin_idx ==:. i) b0 b1)) in
  let wmask = m0 |: m1 in
  let sho_out = mux2 od ((pin_out.value &: ~:wmask)) ((pin_out.value &: ~:wmask) |: (wmask &: vals)) in
  let sho_oe = mux2 od ((pin_oe.value &: ~:wmask) |: (wmask &: ~:vals)) pin_oe.value in
  let shift2 = pair &: psel in
  let cpin = if is Cap_same_pin then pin_idx else pin_idx ^: of_int ~width:3 1 in
  let cbit = cap &: pin_at cpin in
  let acc_sho =
    mux2 msb
      (mux2 shift2 (concat_msb [ select acc 5 0; zero 1; cbit ])
         (if is Cap_wrong_bit then concat_msb [ select acc 6 1; cbit; zero 1 ]
          else concat_msb [ select acc 6 0; cbit ]))
      (mux2 shift2 (concat_msb [ cbit; zero 1; select acc 7 2 ]) (concat_msb [ cbit; select acc 7 1 ])) in
  let acc_sho = if is Psel_shift1 then
      mux2 msb (concat_msb [ select acc 6 0; cbit ]) (concat_msb [ cbit; select acc 7 1 ]) else acc_sho in
  (* WAITC *)
  let own_full = mux thread.value (List.init 4 (fun i -> bit full_v i)) in
  let space =
    if is Waitc_space_own then ~:own_full
    else mux2 (bit ls 2) (mux (select ls 1 0) (List.init 4 (fun i -> bit port_out_ready i)))
        (~:(mux (select ls 1 0) (List.init 4 (fun i -> bit full_v i)))) in
  let my_flags = if is Waitc_flag_thread0 then select flags 3 0
    else mux thread.value (List.init 4 (fun i -> select flags (4 * i + 3) (4 * i))) in
  let byte_b = if is Waitc_byte_4bits then select cnt 3 0 ==:. 0 else select cnt 2 0 ==:. 0 in
  let host_c = if is Waitc_host_inverted then ~:host_in_valid else host_in_valid in
  let holds = mux cond (List.init 8 (fun i -> bit acc i)
                        @ [ byte_b; host_c; own_full; space ]
                        @ List.init 4 (fun i -> bit my_flags i)) in
  (* MBX *)
  let pidx = if is Port_index then select ch 1 0 +:. 1 else select ch 1 0 in
  let is_port = bit ch 2 in
  let onehot2 s = concat_lsb (List.init 4 (fun i -> s ==:. i)) in
  let ch_full = mux (select ch 1 0) (List.init 4 (fun i -> bit full_v i)) in
  let opc o = of_int ~width:4 o in
  let subc s = of_int ~width:4 s in
  let skip2 = pc_inc 2 in
  compile
    [ thread <-- thread.value +:. 1
    ; host_out_valid <-- gnd
    ; port_out_valid <--. 0
    ; fine_valid <-- gnd
    ; pend_valid <-- gnd
    ; when_ latch_load [ latch <-- pin_in ]
    ; switch op
        [ opc Isa2.op_setp,
          [ sub_q <-- q; proc pin_write
          ; pin_out_n <-- ((pin_out.value &: ~:mask8) |: (mask8 &: repeat setv 8))
          ; pin_oe_n <-- ((pin_oe.value &: ~:mask8) |: (mask8 &: repeat seto 8)) ]
        ; opc Isa2.op_ldc, [ cnt_next <-- imm12 ]
        ; opc Isa2.op_ldd, [ dl_next <-- imm12 ]
        ; opc Isa2.op_lda, [ acc_next <-- imm8 ]
        ; opc Isa2.op_waitp, [ if_ (pin_bit ==: pin_val) [] fail_or_stay ]
        ; opc Isa2.op_waitd, [ if_ (dl ==:. 0) [] stay ]
        ; opc Isa2.op_sho,
          [ proc pin_write
          ; pin_out_n <-- sho_out; pin_oe_n <-- sho_oe
          ; if_ od [] [ sub_q <-- q ]
          ; acc_next <-- acc_sho
          ; cnt_next <-- cnt -:. 1 ]
        ; opc Isa2.op_shi,
          [ acc_next <-- mux2 quad
                (mux2 pin_val (concat_msb [ select acc 3 0; rev4 nib ]) (concat_msb [ nib; select acc 7 4 ]))
                (mux2 pin_val (concat_msb [ select acc 6 0; pin_bit ]) (concat_msb [ pin_bit; select acc 7 1 ]))
          ; cnt_next <-- cnt -:. 1 ]
        ; opc Isa2.op_jmp, [ pc_next <-- addr ]
        ; opc Isa2.op_jnz, [ if_ (cnt <>:. 0) [ pc_next <-- addr ] [] ]
        ; opc Isa2.op_out,
          [ host_out <-- (if is Out_src_ignored then acc else mux2 (bit instr 11) imm8 acc)
          ; host_tag <-- (if is Out_tag_dropped then zero 3 else select instr 10 8)
          ; host_out_valid <-- vdd ]
        ; opc Isa2.op_in, [ if_ host_in_valid [ acc_next <-- host_in; host_in_ready <-- vdd ] stay ]
        ; opc Isa2.op_mbx,
          [ if_ dir
              [ if_ is_port
                  [ if_ (mux pidx (List.init 4 (fun i -> bit port_in_valid i)))
                      [ acc_next <-- mux pidx (Array.to_list port_in); port_in_ready <-- onehot2 pidx ]
                      fail_or_stay ]
                  [ if_ ch_full [ acc_next <-- mux (select ch 1 0) (values inbox); pop <-- vdd ]
                      (if is Recv_no_fail then stay else fail_or_stay) ] ]
              [ (if is Lsend_on_success_only then proc [] else lsend_n <-- ch)
              ; if_ is_port
                  [ if_ (mux pidx (List.init 4 (fun i -> bit port_out_ready i)))
                      [ port_out_data <-- acc; port_out_valid <-- onehot2 pidx
                      ; (if is Lsend_on_success_only then lsend_n <-- ch else proc []) ]
                      fail_or_stay ]
                  [ if_ ((if is Send_ignores_full then gnd else ch_full))
                      fail_or_stay
                      [ push <-- vdd; (if is Lsend_on_success_only then lsend_n <-- ch else proc []) ] ] ] ]
        ; opc Isa2.op_waitc, [ if_ holds [] fail_or_stay ]
        ; opc Isa2.op_ext,
          [ switch sub
              [ subc Isa2.x_skne,
                [ if_ (if is Skne_inverted then acc ==: imm8 else acc <>: imm8) [ pc_next <-- skip2 ] [] ]
              ; subc Isa2.x_skeq,
                [ if_ (acc ==: imm8) [ pc_next <-- (if is Skeq_skip_one then pc_inc 1 else skip2) ] [] ]
              ; subc Isa2.x_fine, [ fine_n <-- imm8; armed_n <-- vdd ]
              ; subc Isa2.x_cnta,
                [ cnt_next <-- uresize (if is Cnta_7bits then uresize (select acc 6 0) 8 else acc) 12 ]
              ; subc Isa2.x_ldb,
                [ bank_re <-- vdd; (if is Ldb_no_increment then proc [] else bp_next <-- bp +:. 1) ]
              ; subc Isa2.x_stb, [ bank_we <-- vdd; bp_next <-- bp +:. 1 ]
              ; subc Isa2.x_bank,
                [ bp_next <-- concat_msb [ (if is Bank_hi_ignored then zero 2 else select imm8 1 0); acc ] ]
              ; subc Isa2.x_cfg, [ cfg_n <-- imm8 ] ] ] ]
    ; prev_pins <-- pin_out.value
    ; q_reg <-- sub_q.value
    ; pin_out <-- pin_out_n.value
    ; pin_oe <-- pin_oe_n.value
    ; when_ bank_re.value [ pend_valid <-- vdd; pend_thread <-- thread.value ]
    ; proc (List.init n_threads (fun t ->
        let me = thread.value ==:. t in
        let ctl_me = ctl_valid &: (ctl_thread ==:. t) in
        proc
          [ if_ clear
              [ pcs.(t) <-- select boot_pc (8 * t + 7) (8 * t); pages.(t) <-- select boot_page (2 * t + 1) (2 * t) ]
              [ when_ me [ pcs.(t) <-- pc_next.value ]
              ; when_ ctl_me [ pcs.(t) <-- ctl_pc; pages.(t) <-- ctl_page ] ]
          ; when_ me
              [ accs.(t) <-- acc_next.value
              ; cnts.(t) <-- cnt_next.value; dls.(t) <-- dl_next.value
              ; bps.(t) <-- bp_next.value; fines.(t) <-- fine_n.value; armed.(t) <-- armed_n.value
              ; cfgs.(t) <-- cfg_n.value; lsend.(t) <-- lsend_n.value ]
          ; when_ (pend_valid.value &: (pend_thread.value ==:. (if is Ldb_wrong_thread then (t + 3) mod 4 else t)))
              [ accs.(t) <-- bank_rdata ]
          ; when_ (push.value &: (select ch 1 0 ==:. t)) [ inbox.(t) <-- acc; full.(t) <-- vdd ]
          ; when_ (pop.value &: (select ch 1 0 ==:. t)) [ full.(t) <-- gnd ] ]))
    ];
  let pin_sub = concat_lsb (List.concat (List.init 8 (fun i ->
      List.init 4 (fun p -> mux2 (of_int ~width:2 p <: q_reg.value) (bit prev_pins.value i) (bit pin_out.value i))))) in
  let tnext = thread.value +:. 1 in
  let ctl_next = if is Ctl_no_bypass then gnd else ctl_valid &: (ctl_thread ==: tnext) in
  let f_pc = mux2 ctl_next ctl_pc (mux tnext (values pcs)) in
  let f_page = if is Page_ignored then zero 2 else mux2 ctl_next ctl_page (mux tnext (values pages)) in
  let imem_addr = concat_msb [ f_page; f_pc ] in
  let cat l = concat_msb (List.rev l) in
  let dbg =
    [ "dbg_pc", cat (values pcs); "dbg_page", cat (values pages); "dbg_acc", cat (values accs);
      "dbg_pend", concat_msb [ pend_valid.value; pend_thread.value ];
      "dbg_cnt", cat (values cnts); "dbg_dl", cat (values dls); "dbg_bp", cat (values bps);
      "dbg_fine", cat (values fines); "dbg_armed", cat (values armed); "dbg_cfg", cat (values cfgs);
      "dbg_lsend", cat (values lsend); "dbg_inbox", cat (values inbox); "dbg_full", cat (values full);
      "dbg_thread", thread.value; "dbg_latch", latch.value ] in
  { imem_addr; pin_out = pin_out.value; pin_oe = pin_oe.value; pin_sub;
    host_out = host_out.value; host_tag = host_tag.value; host_out_valid = host_out_valid.value;
    host_in_ready = host_in_ready.value;
    port_out_data = port_out_data.value; port_out_valid = port_out_valid.value;
    port_in_ready = port_in_ready.value;
    bank_addr = (if is Ldb_reads_next then mux2 bank_re.value (bp +:. 1) bp else bp); bank_we = bank_we.value; bank_re = bank_re.value;
    bank_wdata = (if is Stb_data_cnt then select cnt 7 0 else acc);
    fine_out = fine_out.value; fine_valid = fine_valid.value; cfg_out = cat (values cfgs); dbg }

let circuit ?bug ?unreset ?(debug = true) () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let imem_data = input "imem_data" 16 and pin_in = input "pin_in" 8 and pin_in4 = input "pin_in4" 32 in
  let host_in = input "host_in" 8 and host_in_valid = input "host_in_valid" 1 in
  let port_in = Array.init 4 (fun i -> input (Printf.sprintf "port_in%d" i) 8) in
  let port_in_valid = input "port_in_valid" 4 and port_out_ready = input "port_out_ready" 4 in
  let flags = input "flags" 16 in
  let ctl_valid = input "ctl_valid" 1 and ctl_thread = input "ctl_thread" 2 in
  let ctl_page = input "ctl_page" 2 and ctl_pc = input "ctl_pc" 8 in
  let bank_rdata = input "bank_rdata" 8 in
  let boot_page = input "boot_page" 8 and boot_pc = input "boot_pc" 32 in
  let o = create ?bug ?unreset ~clock ~clear ~imem_data ~pin_in ~pin_in4 ~host_in ~host_in_valid ~port_in
      ~port_in_valid ~port_out_ready ~flags ~ctl_valid ~ctl_thread ~ctl_page ~ctl_pc ~boot_page ~boot_pc ~bank_rdata () in
  Circuit.create_exn ~name:"deadline_sequencer_v2"
    ([ output "imem_addr" o.imem_addr; output "pin_out" o.pin_out; output "pin_oe" o.pin_oe
     ; output "pin_sub" o.pin_sub; output "host_out" o.host_out; output "host_tag" o.host_tag
     ; output "host_out_valid" o.host_out_valid; output "host_in_ready" o.host_in_ready
     ; output "port_out_data" o.port_out_data; output "port_out_valid" o.port_out_valid
     ; output "port_in_ready" o.port_in_ready; output "bank_addr" o.bank_addr
     ; output "bank_we" o.bank_we; output "bank_re" o.bank_re; output "bank_wdata" o.bank_wdata
     ; output "fine_out" o.fine_out; output "fine_valid" o.fine_valid; output "cfg_out" o.cfg_out ]
     @ (if debug then List.map (fun (n, s) -> output n s) o.dbg else []))
