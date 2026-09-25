(* A proposed variant of the deadline sequencer ISA (../deadline-sequencer/isa.ml), written for
   low-speed USB in firmware. Everything not listed below is unchanged, and a programme for the
   original ISA that stays within 64 words per thread runs identically.

   Changes, each backwards compatible:
   1. pc widened from 6 to 8 bits (256 words per thread, the size the original README plans for
      a 1024 x 16 SRAM). Address fields grow into unused bits: WAITP fail[7:0], JMP/JNZ addr[7:0].
   2. SKNE (opcode E) imm[7:0] inv[8]: skip the next instruction if acc <> imm (inv = 0) or if
      acc = imm (inv = 1). A skip costs the one slot of SKNE itself. The one data-dependent branch
      the original lacks: compare a received byte with a constant.
   3. SHO pair mode, bit 6: pins p and p+1 (mod 8) take two accumulator bits at once, p from the
      lower of the two (lsb mode: acc[0] to p, acc[1] to p+1, acc >>= 2; msb mode: acc[7] to p,
      acc[6] to p+1, acc <<= 2); cnt <- cnt - 1. Two pins that must change together (D+ and D-,
      SCK and MOSI, any differential pair) change on the same clock. od applies to both pins.
   4. OUT event mode, bit 8: host_out <- imm[7:0] with host_out_tag = 1 (acc untouched); plain
      OUT sends acc with tag 0. The host can then tell framing events from data bytes.

   Encodings checked against master's ISA (the four-phase extension): it uses SETP/SHO bits
   [1:0] for a sub-slot and SHI bit 7 for quad sampling. This variant uses SHO bit 6, OUT bit 8,
   WAITP bits [7:6], JMP/JNZ bits [7:6] and opcode E, none of which master uses. *)

let n_threads = 4
let pc_bits = 8
let prog_len = 1 lsl pc_bits

type op = NOP | SETP | LDC | LDD | LDA | WAITP | WAITD | SHO | SHI | JMP | JNZ | OUT | IN | HALT | SKNE

let op_of_code = function
  | 1 -> SETP | 2 -> LDC | 3 -> LDD | 4 -> LDA | 5 -> WAITP | 6 -> WAITD | 7 -> SHO | 8 -> SHI
  | 9 -> JMP | 10 -> JNZ | 11 -> OUT | 12 -> IN | 13 -> HALT | 14 -> SKNE | _ -> NOP

let code_of_op = function
  | NOP -> 0 | SETP -> 1 | LDC -> 2 | LDD -> 3 | LDA -> 4 | WAITP -> 5 | WAITD -> 6 | SHO -> 7
  | SHI -> 8 | JMP -> 9 | JNZ -> 10 | OUT -> 11 | IN -> 12 | HALT -> 13 | SKNE -> 14

let amask = prog_len - 1
let enc op f = (code_of_op op lsl 12) lor (f land 0xFFF)
let nop = enc NOP 0
let setp ~mask ~value ~oe = enc SETP ((mask land 0xFF) lsl 4 lor (value lsl 3) lor (oe lsl 2))
let ldc n = assert (n >= 0 && n < 4096); enc LDC n
let ldd n = assert (n >= 0 && n < 4096); enc LDD n
let lda n = enc LDA (n land 0xFF)
let waitp ~pin ~value ~fail = enc WAITP ((pin lsl 9) lor (value lsl 8) lor (fail land amask))
let waitd = enc WAITD 0
let sho ?(od = 0) ?(pair = 0) ~pin ~msb () = enc SHO ((pin lsl 9) lor (msb lsl 8) lor (od lsl 7) lor (pair lsl 6))
let shi ~pin ~msb = enc SHI ((pin lsl 9) lor (msb lsl 8))
let jmp a = enc JMP (a land amask)
let jnz a = enc JNZ (a land amask)
let out = enc OUT 0
let oute ev = enc OUT ((1 lsl 8) lor (ev land 0xFF))
let in_ = enc IN 0
let halt = enc HALT 0
let skne ?(inv = 0) imm = enc SKNE ((inv lsl 8) lor (imm land 0xFF))

type state = {
  pcs : int array; accs : int array; cnts : int array; dls : int array;
  mutable pin_out : int; mutable pin_oe : int; mutable thread : int;
}

let init () = {
  pcs = Array.make n_threads 0; accs = Array.make n_threads 0; cnts = Array.make n_threads 0;
  dls = Array.make n_threads 0; pin_out = 0; pin_oe = 0; thread = 0;
}

type effects = { host_out : (int * bool) option; host_in_ready : bool }

let step st ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let t = st.thread in
  let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
  let instr = mem.(t).(pc) in
  let op = op_of_code ((instr lsr 12) land 0xF) in
  let imm12 = instr land 0xFFF and imm8 = instr land 0xFF in
  let pin = (instr lsr 9) land 7 and pin_val = (instr lsr 8) land 1 in
  let addr = instr land amask in
  let od = (instr lsr 7) land 1 and pair = (instr lsr 6) land 1 in
  let mask8 = (instr lsr 4) land 0xFF and setv = (instr lsr 3) land 1 and seto = (instr lsr 2) land 1 in
  let pin_bit = (pin_in lsr pin) land 1 in
  let pc_next = ref ((pc + 1) land amask) in
  let acc_next = ref acc and cnt_next = ref cnt in
  let dl_next = ref (if dl = 0 then 0 else dl - 1) in
  let host_out = ref None and host_in_ready = ref false in
  let stay () = pc_next := pc in
  let set_bit p v =
    if od = 1 then begin
      st.pin_out <- st.pin_out land lnot (1 lsl p);
      st.pin_oe <- (st.pin_oe land lnot (1 lsl p)) lor ((1 - v) lsl p)
    end else st.pin_out <- (st.pin_out land lnot (1 lsl p)) lor (v lsl p) in
  (match op with
   | NOP -> ()
   | SETP ->
     st.pin_out <- (st.pin_out land lnot mask8) lor (if setv = 1 then mask8 else 0);
     st.pin_oe <- (st.pin_oe land lnot mask8) lor (if seto = 1 then mask8 else 0)
   | LDC -> cnt_next := imm12
   | LDD -> dl_next := imm12
   | LDA -> acc_next := imm8
   | WAITP -> if pin_bit <> pin_val then (if dl = 0 then pc_next := addr else stay ())
   | WAITD -> if dl <> 0 then stay ()
   | SHO ->
     if pair = 1 then begin
       let b0, b1 = if pin_val = 1 then (acc lsr 7) land 1, (acc lsr 6) land 1 else acc land 1, (acc lsr 1) land 1 in
       set_bit pin b0; set_bit ((pin + 1) land 7) b1;
       acc_next := (if pin_val = 1 then (acc lsl 2) land 0xFF else acc lsr 2)
     end else begin
       set_bit pin (if pin_val = 1 then (acc lsr 7) land 1 else acc land 1);
       acc_next := (if pin_val = 1 then (acc lsl 1) land 0xFF else acc lsr 1)
     end;
     cnt_next := (cnt - 1) land 0xFFF
   | SHI ->
     acc_next := (if pin_val = 1 then ((acc lsl 1) land 0xFF) lor pin_bit else (acc lsr 1) lor (pin_bit lsl 7));
     cnt_next := (cnt - 1) land 0xFFF
   | JMP -> pc_next := addr
   | JNZ -> if cnt <> 0 then pc_next := addr
   | OUT -> host_out := Some (if pin_val = 1 then (imm8, true) else (acc, false))
   | IN -> if host_in_valid then (acc_next := host_in; host_in_ready := true) else stay ()
   | HALT -> stay ()
   | SKNE -> if (acc <> imm8) = (pin_val = 0) then pc_next := (pc + 2) land amask);
  st.pcs.(t) <- !pc_next; st.accs.(t) <- !acc_next; st.cnts.(t) <- !cnt_next; st.dls.(t) <- !dl_next;
  st.thread <- (t + 1) mod n_threads;
  { host_out = !host_out; host_in_ready = !host_in_ready }
