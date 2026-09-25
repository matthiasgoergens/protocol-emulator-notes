(* ISA variant "v": the deadline sequencer ISA (../deadline-sequencer/isa.ml) plus generic
   bit-stream assists. A proposal, kept separate so the base ISA is untouched. Everything the base
   ISA does is unchanged except that programme addresses are 8 bits wide (256 words per thread, the
   SRAM plan of record); the additions are listed here and motivated in README.md.

   Changes against the base ISA:
   - pc is 8 bits. WAITP's fail field and JMP/JNZ's address field are 8 bits ([7:0]); the base ISA
     left bits 7..6 of those fields unused, so base encodings keep their meaning.
   - Per-thread CRC engine: crc (16 bits) and poly (16 bits). A CRC of width w <= 16 is kept left
     aligned: a bit b updates crc <- ((crc << 1) & 0xFFFF) xor (poly if b xor crc[15]), with poly
     the w-bit polynomial shifted left by 16 - w. CAN's CRC-15 (0x4599) is poly 0x8B32; USB CRC-5
     (0x05) is 0x2800; CRC-16/USB (0x8005) is 0x8005.
   - Per-thread bit-stuffing tracker: last (1 bit), run (3 bits, saturating at 7), limit (3 bits),
     mode (1 bit). In "equal" mode (0) a bit equal to last lengthens the run, any other bit
     restarts it at 1 (CAN: five equal bits). In "ones" mode (1) a one lengthens the run and a zero
     clears it (USB: six ones; HDLC: five ones). The stuff condition is run >= limit.
   - SHO   pin[11:9] msb[8] od[7] crc[6] stf[5]         as before; with crc / stf set, the bit
                                                        driven also feeds the CRC / stuff tracker
   - SHI   pin[11:9] msb[8] crc[6] stf[5] norec[4]       as before; crc / stf feed the sampled bit
                                                        to the CRC / tracker; with norec the bit is
                                                        not recorded (acc and cnt unchanged), which
                                                        is how a stuff bit is consumed
   - OUT   src[11] tag[10:8] imm[7:0]                    host_out <- (src ? imm : acc) and
                                                        host_out_tag <- tag. Base OUT is src 0 tag 0
   - E JC  cond[11:8] addr[7:0]                          jump if cond, else fall through:
             0..7: acc bit cond is 1;  8: crc = 0;  9: run >= limit (stuff);
             10: cnt[2:0] = 0 (byte boundary);  11: last = 1;  12..15: never
   - F CFG sub[11:10]:
             0: crc <- 0, run <- 0, last <- bit 9, mode <- bit 8, limit <- bits 2..0
             1: poly[7:0] <- imm[7:0]      2: poly[15:8] <- imm[7:0]
             3: cnt <- acc (zero extended): a length taken from the data stream

   Bit positions avoid the base-compatible extension on master (SETP/SHO sub-slot q[1:0], SHI
   quad[7]): SHO uses bits 6..5, SHI bits 6..4, so both can coexist. *)

let n_threads = 4
let pc_bits = 8
let prog_len = 1 lsl pc_bits
let amask = prog_len - 1

type op = NOP | SETP | LDC | LDD | LDA | WAITP | WAITD | SHO | SHI | JMP | JNZ | OUT | IN | HALT | JC | CFG

let op_of_code = function
  | 1 -> SETP | 2 -> LDC | 3 -> LDD | 4 -> LDA | 5 -> WAITP | 6 -> WAITD | 7 -> SHO | 8 -> SHI
  | 9 -> JMP | 10 -> JNZ | 11 -> OUT | 12 -> IN | 13 -> HALT | 14 -> JC | 15 -> CFG | _ -> NOP

let code_of_op = function
  | NOP -> 0 | SETP -> 1 | LDC -> 2 | LDD -> 3 | LDA -> 4 | WAITP -> 5 | WAITD -> 6 | SHO -> 7
  | SHI -> 8 | JMP -> 9 | JNZ -> 10 | OUT -> 11 | IN -> 12 | HALT -> 13 | JC -> 14 | CFG -> 15

let enc op f = (code_of_op op lsl 12) lor (f land 0xFFF)
let nop = enc NOP 0
let setp ~mask ~value ~oe = enc SETP ((mask land 0xFF) lsl 4 lor (value lsl 3) lor (oe lsl 2))
let ldc n = assert (n >= 0 && n < 4096); enc LDC n
let ldd n = assert (n >= 0 && n < 4096); enc LDD n
let lda n = enc LDA (n land 0xFF)
let waitp ~pin ~value ~fail = enc WAITP ((pin lsl 9) lor (value lsl 8) lor (fail land amask))
let waitd = enc WAITD 0
let sho ?(od = 0) ?(crc = 0) ?(stf = 0) ~pin ~msb () =
  enc SHO ((pin lsl 9) lor (msb lsl 8) lor (od lsl 7) lor (crc lsl 6) lor (stf lsl 5))
let shi ?(crc = 0) ?(stf = 0) ?(norec = 0) ~pin ~msb () =
  enc SHI ((pin lsl 9) lor (msb lsl 8) lor (crc lsl 6) lor (stf lsl 5) lor (norec lsl 4))
let jmp a = enc JMP (a land amask)
let jnz a = enc JNZ (a land amask)
let out ?(tag = 0) () = enc OUT (tag lsl 8)
let outi ~tag v = enc OUT ((1 lsl 11) lor (tag lsl 8) lor (v land 0xFF))
let in_ = enc IN 0
let halt = enc HALT 0
let jc ~cond a = enc JC ((cond lsl 8) lor (a land amask))
let cond_acc k = k
let cond_crc0 = 8
let cond_stuff = 9
let cond_byte = 10
let cond_last1 = 11
let crc_clear ?(last = 1) ?(mode = 0) ~limit () = enc CFG ((last lsl 9) lor (mode lsl 8) lor (limit land 7))
let poly_lo v = enc CFG ((1 lsl 10) lor (v land 0xFF))
let poly_hi v = enc CFG ((2 lsl 10) lor (v land 0xFF))
let ldca = enc CFG (3 lsl 10)

type state = {
  pcs : int array; accs : int array; cnts : int array; dls : int array;
  crcs : int array; polys : int array; runs : int array; lasts : int array;
  limits : int array; modes : int array;
  mutable pin_out : int; mutable pin_oe : int; mutable thread : int;
}

let init () =
  let z () = Array.make n_threads 0 in
  { pcs = z (); accs = z (); cnts = z (); dls = z (); crcs = z (); polys = z (); runs = z ();
    lasts = z (); limits = z (); modes = z (); pin_out = 0; pin_oe = 0; thread = 0 }

type effects = { host_out : (int * int) option; host_in_ready : bool }   (* (tag, byte) *)

(* Configuration sharing: with [shared_cfg], poly, limit and mode are one set of registers for
   all four threads (written by whichever thread executes CFG); crc, run and last stay per thread.
   Halves the cost of the assists; CAN, USB and HDLC nodes on one core then share a polynomial
   unless they reload it. *)
let shared_cfg = ref false

let crc_step ~crc ~poly b =
  let fb = b lxor ((crc lsr 15) land 1) in
  ((crc lsl 1) land 0xFFFF) lxor (if fb = 1 then poly else 0)

let stuff_step ~mode ~run ~last b =
  if mode = 0 then (if run > 0 && b = last then min 7 (run + 1) else 1), b
  else (if b = 1 then min 7 (run + 1) else 0), b

let step st ~(mem : int array array) ~pin_in ~host_in ~host_in_valid =
  let t = st.thread in
  let tc = if !shared_cfg then 0 else t in   (* index of the configuration registers *)
  let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
  let instr = mem.(t).(pc) in
  let op = op_of_code ((instr lsr 12) land 0xF) in
  let imm12 = instr land 0xFFF and imm8 = instr land 0xFF in
  let pin = (instr lsr 9) land 7 and pin_val = (instr lsr 8) land 1 in
  let addr = instr land amask in
  let od = (instr lsr 7) land 1 in
  let fcrc = (instr lsr 6) land 1 and fstf = (instr lsr 5) land 1 and norec = (instr lsr 4) land 1 in
  let mask8 = (instr lsr 4) land 0xFF and setv = (instr lsr 3) land 1 and seto = (instr lsr 2) land 1 in
  let pin_bit = (pin_in lsr pin) land 1 in
  let pc_next = ref ((pc + 1) land amask) in
  let acc_next = ref acc and cnt_next = ref cnt in
  let dl_next = ref (if dl = 0 then 0 else dl - 1) in
  let host_out = ref None and host_in_ready = ref false in
  let stay () = pc_next := pc in
  let set_pin_bit v = st.pin_out <- (st.pin_out land lnot (1 lsl pin)) lor (v lsl pin) in
  let feed b =
    if fcrc = 1 then st.crcs.(t) <- crc_step ~crc:st.crcs.(t) ~poly:st.polys.(tc) b;
    if fstf = 1 then begin
      let r, l = stuff_step ~mode:st.modes.(tc) ~run:st.runs.(t) ~last:st.lasts.(t) b in
      st.runs.(t) <- r; st.lasts.(t) <- l
    end in
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
     let b = if pin_val = 1 then (acc lsr 7) land 1 else acc land 1 in
     if od = 1 then begin
       set_pin_bit 0;
       st.pin_oe <- (st.pin_oe land lnot (1 lsl pin)) lor ((1 - b) lsl pin)
     end else set_pin_bit b;
     feed b;
     acc_next := (if pin_val = 1 then (acc lsl 1) land 0xFF else acc lsr 1);
     cnt_next := (cnt - 1) land 0xFFF
   | SHI ->
     feed pin_bit;
     if norec = 0 then begin
       acc_next := (if pin_val = 1 then ((acc lsl 1) land 0xFF) lor pin_bit else (acc lsr 1) lor (pin_bit lsl 7));
       cnt_next := (cnt - 1) land 0xFFF
     end
   | JMP -> pc_next := addr
   | JNZ -> if cnt <> 0 then pc_next := addr
   | OUT ->
     let src = (instr lsr 11) land 1 and tag = (instr lsr 8) land 7 in
     host_out := Some (tag, if src = 1 then imm8 else acc)
   | IN -> if host_in_valid then (acc_next := host_in; host_in_ready := true) else stay ()
   | HALT -> stay ()
   | JC ->
     let c = (instr lsr 8) land 0xF in
     let taken =
       if c < 8 then (acc lsr c) land 1 = 1
       else if c = 8 then st.crcs.(t) = 0
       else if c = 9 then st.runs.(t) >= st.limits.(tc)
       else if c = 10 then cnt land 7 = 0
       else if c = 11 then st.lasts.(t) = 1
       else false in
     if taken then pc_next := addr
   | CFG ->
     (match (instr lsr 10) land 3 with
      | 0 ->
        st.crcs.(t) <- 0; st.runs.(t) <- 0; st.lasts.(t) <- (instr lsr 9) land 1;
        st.modes.(tc) <- (instr lsr 8) land 1; st.limits.(tc) <- instr land 7
      | 1 -> st.polys.(tc) <- (st.polys.(tc) land 0xFF00) lor imm8
      | 2 -> st.polys.(tc) <- (st.polys.(tc) land 0x00FF) lor (imm8 lsl 8)
      | _ -> cnt_next := acc));
  st.pcs.(t) <- !pc_next; st.accs.(t) <- !acc_next; st.cnts.(t) <- !cnt_next; st.dls.(t) <- !dl_next;
  st.thread <- (t + 1) mod n_threads;
  { host_out = !host_out; host_in_ready = !host_in_ready }
