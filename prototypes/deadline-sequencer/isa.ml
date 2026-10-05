(* The deadline sequencer ISA: executable specification.

   Four hardware threads issue round-robin, one instruction per cycle, so thread t executes on
   every cycle congruent to t mod 4 and every instruction takes exactly one slot. Timing is exact
   by construction: nothing stalls, nothing is shared except the pins.

   Per-thread state: pc (6 bits), acc (8-bit shift register), cnt (12-bit loop counter),
   dl (12-bit deadline, decrements once per slot while non-zero).
   Shared state: pin_out and pin_oe (8 bits each).

   16-bit instruction, opcode in bits 15..12:
     0 NOP
     1 SETP  mask[11:4] val[3] oe[2] q[1:0]
                                       masked pins <- val, their output enables <- oe; the new
                                       level starts at quarter-clock sub-slot q (see below)
     2 LDC   imm[11:0]                 cnt <- imm
     3 LDD   imm[11:0]                 dl  <- imm (no decrement this slot)
     4 LDA   imm[7:0]                  acc <- imm
     5 WAITP pin[11:9] val[8] fail[5:0]
              proceed when pin_in[pin] = val; else if dl = 0 jump to fail; else stay
     6 WAITD                           proceed when dl = 0, else stay
     7 SHO   pin[11:9] msb[8] od[7] q[1:0]
                                       pin_out[pin] <- acc bit (msb ? bit 7 : bit 0); acc shifts;
                                       cnt <- cnt - 1. With od set (open drain): pin_out[pin] <- 0
                                       and pin_oe[pin] <- not bit, i.e. drive low for 0, release for 1.
                                       q[1:0]: sub-slot of the new level (ignored with od set)
     8 SHI   pin[11:9] msb[8] quad[7]  pin_in[pin] shifts into acc (msb ? at bit 0 : at bit 7);
                                       cnt <- cnt - 1. With quad set, the pin's four quarter-clock
                                       samples of the last clock (pin_in4) shift in instead, four
                                       bits at once, in time order (msb: acc <- acc << 4 | s0 s1 s2 s3
                                       with s0 at bit 3; else acc <- acc >> 4 | s3 s2 s1 s0 << 4)
     9 JMP   addr[5:0]
     A JNZ   addr[5:0]                 jump if cnt <> 0
     B OUT                             host_out <- acc, host_out_valid for one cycle
     C IN                              if host_in_valid: acc <- host_in, host_in_ready for one
                                       cycle, proceed; else stay
     D HALT                            stay forever
     E, F NOP

   Quarter-clock outputs (for the four-phase output stage, prototypes/multiphase): besides pin_out,
   each clock produces pin_sub, four bits per pin: bit 4i+p is pin i's level during quarter p of the
   clock period. An instruction with sub-slot q changes its pins' level from quarter q on, so
   pin_sub = old level for p < q, new level for p >= q; q = 0 (every existing programme) is the
   clock-grid behaviour, and quarter 3 always equals pin_out. The stage turns pin_sub into edges
   placed on a quarter-clock grid; the sequencer itself never runs faster than one clock. *)

let n_threads = 4
let pc_bits = 6
let prog_len = 1 lsl pc_bits

type op = NOP | SETP | LDC | LDD | LDA | WAITP | WAITD | SHO | SHI | JMP | JNZ | OUT | IN | HALT

let op_of_code = function
  | 1 -> SETP | 2 -> LDC | 3 -> LDD | 4 -> LDA | 5 -> WAITP | 6 -> WAITD | 7 -> SHO | 8 -> SHI
  | 9 -> JMP | 10 -> JNZ | 11 -> OUT | 12 -> IN | 13 -> HALT | _ -> NOP

let code_of_op = function
  | NOP -> 0 | SETP -> 1 | LDC -> 2 | LDD -> 3 | LDA -> 4 | WAITP -> 5 | WAITD -> 6 | SHO -> 7
  | SHI -> 8 | JMP -> 9 | JNZ -> 10 | OUT -> 11 | IN -> 12 | HALT -> 13

(* Assembler helpers: each returns the 16-bit word. *)
let enc op f = (code_of_op op lsl 12) lor (f land 0xFFF)
let nop = enc NOP 0
let setpq ~q ~mask ~value ~oe = enc SETP ((mask land 0xFF) lsl 4 lor (value lsl 3) lor (oe lsl 2) lor (q land 3))
let setp ~mask ~value ~oe = setpq ~q:0 ~mask ~value ~oe
let ldc n = enc LDC n
let ldd n = enc LDD n
let lda n = enc LDA (n land 0xFF)
let waitp ~pin ~value ~fail = enc WAITP ((pin lsl 9) lor (value lsl 8) lor (fail land 0x3F))
let waitd = enc WAITD 0
let sho ?(od = 0) ?(q = 0) ~pin ~msb () = enc SHO ((pin lsl 9) lor (msb lsl 8) lor (od lsl 7) lor (q land 3))
let shi ~pin ~msb = enc SHI ((pin lsl 9) lor (msb lsl 8))
let shi_quad ~pin ~msb = enc SHI ((pin lsl 9) lor (msb lsl 8) lor (1 lsl 7))
let jmp a = enc JMP (a land 0x3F)
let jnz a = enc JNZ (a land 0x3F)
let out = enc OUT 0
let in_ = enc IN 0
let halt = enc HALT 0

(* Interpreter. *)
type state = {
  pcs : int array; accs : int array; cnts : int array; dls : int array;
  mutable pin_out : int; mutable pin_oe : int; mutable thread : int;
  mutable pin_sub : int;   (* 32 bits: bit 4i+p = pin i during quarter p of the last clock *)
}

let init () = {
  pcs = Array.make n_threads 0; accs = Array.make n_threads 0; cnts = Array.make n_threads 0;
  dls = Array.make n_threads 0; pin_out = 0; pin_oe = 0; thread = 0; pin_sub = 0;
}

(* pin_sub for a clock whose instruction moved the pins from [old_] to [new_] at sub-slot [q] *)
let sub_of ~old_ ~new_ ~q =
  let r = ref 0 in
  for i = 0 to 7 do
    for p = 0 to 3 do
      let v = if p < q then (old_ lsr i) land 1 else (new_ lsr i) land 1 in
      r := !r lor (v lsl (4 * i + p))
    done
  done; !r

(* the four samples of each pin when only the one-per-clock view exists: all equal *)
let replicate4 pin_in = sub_of ~old_:pin_in ~new_:pin_in ~q:0

type effects = { host_out : int option; host_in_ready : bool }

(* One cycle: the current thread executes one instruction from [mem.(thread).(pc)]. *)
let step ?pin_in4 st ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let pin_in4 = match pin_in4 with Some v -> v | None -> replicate4 pin_in in
  let old_pins = st.pin_out in
  let t = st.thread in
  let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
  let instr = mem.(t).(pc) in
  let op = op_of_code ((instr lsr 12) land 0xF) in
  let imm12 = instr land 0xFFF and imm8 = instr land 0xFF in
  let pin = (instr lsr 9) land 7 and pin_val = (instr lsr 8) land 1 in
  let addr6 = instr land 0x3F in
  let od = (instr lsr 7) land 1 in
  let mask8 = (instr lsr 4) land 0xFF and setv = (instr lsr 3) land 1 and seto = (instr lsr 2) land 1 in
  let pin_bit = (pin_in lsr pin) land 1 in
  let q = instr land 3 and quad = (instr lsr 7) land 1 in
  let nib = (pin_in4 lsr (4 * pin)) land 0xF in
  let rev4 n = ((n land 1) lsl 3) lor ((n land 2) lsl 1) lor ((n land 4) lsr 1) lor ((n land 8) lsr 3) in
  let sub_q = ref 0 in
  let pc_next = ref ((pc + 1) land (prog_len - 1)) in
  let acc_next = ref acc and cnt_next = ref cnt in
  let dl_next = ref (if dl = 0 then 0 else dl - 1) in
  let host_out = ref None and host_in_ready = ref false in
  let stay () = pc_next := pc in
  let set_pin_bit v = st.pin_out <- (st.pin_out land lnot (1 lsl pin)) lor (v lsl pin) in
  (match op with
   | NOP -> ()
   | SETP ->
     sub_q := q;
     st.pin_out <- (st.pin_out land lnot mask8) lor (if setv = 1 then mask8 else 0);
     st.pin_oe <- (st.pin_oe land lnot mask8) lor (if seto = 1 then mask8 else 0)
   | LDC -> cnt_next := imm12
   | LDD -> dl_next := imm12
   | LDA -> acc_next := imm8
   | WAITP -> if pin_bit <> pin_val then (if dl = 0 then pc_next := addr6 else stay ())
   | WAITD -> if dl <> 0 then stay ()
   | SHO ->
     let b = if pin_val = 1 then (acc lsr 7) land 1 else acc land 1 in
     if od = 1 then begin
       set_pin_bit 0;
       st.pin_oe <- (st.pin_oe land lnot (1 lsl pin)) lor ((1 - b) lsl pin)
     end else (set_pin_bit b; sub_q := q);
     acc_next := (if pin_val = 1 then (acc lsl 1) land 0xFF else acc lsr 1);
     cnt_next := (cnt - 1) land 0xFFF
   | SHI when quad = 1 ->
     acc_next := (if pin_val = 1 then ((acc lsl 4) land 0xFF) lor rev4 nib else (acc lsr 4) lor (nib lsl 4));
     cnt_next := (cnt - 1) land 0xFFF
   | SHI ->
     acc_next := (if pin_val = 1 then ((acc lsl 1) land 0xFF) lor pin_bit else (acc lsr 1) lor (pin_bit lsl 7));
     cnt_next := (cnt - 1) land 0xFFF
   | JMP -> pc_next := addr6
   | JNZ -> if cnt <> 0 then pc_next := addr6
   | OUT -> host_out := Some acc
   | IN -> if host_in_valid then (acc_next := host_in; host_in_ready := true) else stay ()
   | HALT -> stay ());
  st.pin_sub <- sub_of ~old_:old_pins ~new_:st.pin_out ~q:!sub_q;
  st.pcs.(t) <- !pc_next; st.accs.(t) <- !acc_next; st.cnts.(t) <- !cnt_next; st.dls.(t) <- !dl_next;
  st.thread <- (t + 1) mod n_threads;
  { host_out = !host_out; host_in_ready = !host_in_ready }
