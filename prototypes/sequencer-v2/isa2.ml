(* ISA v2 of the deadline sequencer: executable specification.

   The encoding is the table in notes/architecture-v0.md section 2.1, with the gaps in that table
   closed as listed under "Decisions" in README.md (each marked "D<n>" below). The base ISA
   (../deadline-sequencer/isa.ml) is unchanged in everything not listed here.

   Four hardware threads issue round-robin, one instruction per clock; thread t executes on every
   clock congruent to t mod 4 and every instruction takes exactly one slot.

   Per-thread state
     pc 8, page 2          the fetch address is {page, pc} in one shared store of 2^10 words
                           (the recommended 512x16 macro is pages 0 and 1)
     acc 8, cnt 12, dl 12  as in the base ISA
     bp 10                 bank pointer into the 1024-byte data bank (2 x 4 kbit gain cells)
     fine 8, armed 1       FINE offset for the thread's next pin write
     cfg 8                 bit 7: round-latched inputs; bits 6..0 exported to the chip (flag-input
                           selects), not interpreted by the core (D5)
     lsend 3               channel of the thread's last SEND, for WAITC condition 11 (D3)
   Shared state
     pin_out 8, pin_oe 8, the quarter-clock view pin_sub (as in the base ISA),
     inbox 4 x 8 bits with a full bit each (depth 1), latch 8 (round-latched pin_in)
   Host control (D1): a write port sets one thread's page and pc; it takes effect at the end of
   the clock and overrides that thread's own pc update if it executes in the same clock.

   16-bit instruction, opcode in 15..12:
     0 NOP
     1 SETP  mask[11:4] val[3] oe[2] q[1:0]      unchanged
     2 LDC   imm[11:0]  3 LDD imm[11:0]           unchanged
     4 LDA   imm[7:0]                             unchanged; 11..8 ignored
     5 WAITP pin[11:9] val[8] fail[7:0]           unchanged semantics, 8-bit fail
     6 WAITD                                      unchanged
     7 SHO   pin[11:9] msb[8] od[7] pair[6] psel[5] cap[4] q[1:0]
             b0 = acc[7] (msb) or acc[0]; pin <- b0.
             pair: pin+1 (mod 8) <- not b0 (psel 0) or the next acc bit, acc[6] / acc[1] (psel 1);
                   with psel 1 the accumulator shifts by two, else by one.
             od applies to every pin written (drive 0 for a 0, release for a 1); q is the sub-slot
             of every pin written, ignored with od as in the base ISA.
             cap: the partner pin (pin XOR 1) is sampled and enters the bit the shift vacates next
                  to the new data (msb: bit 0; lsb: bit 7); with psel 1 the other vacated bit is 0.
             cnt <- cnt - 1 in every mode. Bits 3..2 ignored.
     8 SHI   pin[11:9] msb[8] quad[7]             unchanged; 6..0 ignored
     9 JMP   addr[7:0]   A JNZ addr[7:0]          8-bit addresses within the thread's page
     B OUT   src[11] tag[10:8] imm[7:0]           host_out <- (tag, src ? imm : acc)
     C IN                                         unchanged
     D MBX   dir[11] ch[10:8] fail[7:0]
             SEND (dir 0): ch 0..3: if inbox ch is empty, it takes acc; ch 4..7: if out-port ch-4
             is ready, it takes acc. RECV (dir 1): ch 0..3: if inbox ch is full, acc <- its byte and
             it empties; ch 4..7: if in-port ch-4 is valid, acc <- its byte (ready pulse).
             Otherwise: at dl = 0 jump to fail, else stay. Every SEND sets lsend <- ch.
             HALT is the pseudo-op JMP self.
     E WAITC cond[11:8] fail[7:0]
             proceed if the condition holds, else at dl = 0 jump to fail, else stay.
             0..7 acc bit k; 8 cnt[2:0] = 0; 9 host_in_valid; 10 own inbox (inbox t) full;
             11 the last SEND target has space (inbox lsend empty, or out-port lsend-4 ready);
             12..15 flag input (cond-12) of this thread.
     F EXT   sub[11:8] imm[7:0]
             0 SKNE: skip the next instruction if acc <> imm; 1 SKEQ: skip if acc = imm
             2 FINE: fine <- imm, armed; the thread's next pin write (SETP or SHO) carries it out
               on fine_out and disarms (D4)
             3 CNTA: cnt <- acc (zero-extended)
             4 LDB: acc <- bank[bp], bp <- bp + 1;  5 STB: bank[bp] <- acc, bp <- bp + 1
             6 BANK: bp <- {imm[1:0], acc} (D2)
             7 CFG: cfg <- imm
             8..15: no operation (reserved)

   Round-latched inputs (cfg bit 7): the pin value seen by WAITP, SHI (not quad) and SHO's capture
   is the value of pin_in on the clock where thread 0 executes, for all four clocks of that round
   (D6). Without the bit the thread sees pin_in of its own clock. *)

let n_threads = 4
let pc_bits = 8
let page_bits = 2
let page_len = 1 lsl pc_bits
let store_len = 1 lsl (pc_bits + page_bits)
let bank_bits = 10
let bank_len = 1 lsl bank_bits

(* opcodes *)
let op_nop = 0 and op_setp = 1 and op_ldc = 2 and op_ldd = 3 and op_lda = 4 and op_waitp = 5
and op_waitd = 6 and op_sho = 7 and op_shi = 8 and op_jmp = 9 and op_jnz = 10 and op_out = 11
and op_in = 12 and op_mbx = 13 and op_waitc = 14 and op_ext = 15

(* EXT sub-operations *)
let x_skne = 0 and x_skeq = 1 and x_fine = 2 and x_cnta = 3 and x_ldb = 4 and x_stb = 5
and x_bank = 6 and x_cfg = 7

(* WAITC conditions *)
let c_acc k = k land 7
let c_byte = 8 and c_host = 9 and c_inbox = 10 and c_space = 11
let c_flag i = 12 + (i land 3)

(* ---- assembler ---- *)
let enc op f = (op lsl 12) lor (f land 0xFFF)
let nop = 0
let setp ?(q = 0) ~mask ~value ~oe () = enc op_setp (((mask land 0xFF) lsl 4) lor (value lsl 3) lor (oe lsl 2) lor (q land 3))
let ldc n = assert (n >= 0 && n < 4096); enc op_ldc n
let ldd n = assert (n >= 0 && n < 4096); enc op_ldd n
let lda n = enc op_lda (n land 0xFF)
let a8 a = a land 0xFF
let waitp ~pin ~value ~fail = enc op_waitp (((pin land 7) lsl 9) lor ((value land 1) lsl 8) lor a8 fail)
let waitd = enc op_waitd 0
let sho ?(od = 0) ?(pair = 0) ?(psel = 0) ?(cap = 0) ?(q = 0) ~pin ~msb () =
  enc op_sho (((pin land 7) lsl 9) lor (msb lsl 8) lor (od lsl 7) lor (pair lsl 6) lor (psel lsl 5)
              lor (cap lsl 4) lor (q land 3))
let shi ?(quad = 0) ~pin ~msb () = enc op_shi (((pin land 7) lsl 9) lor (msb lsl 8) lor (quad lsl 7))
let jmp a = enc op_jmp (a8 a)
let jnz a = enc op_jnz (a8 a)
let halt_at a = jmp a   (* HALT is JMP self *)
let out ?(tag = 0) () = enc op_out ((tag land 7) lsl 8)
let outi ~tag v = enc op_out ((1 lsl 11) lor ((tag land 7) lsl 8) lor (v land 0xFF))
let in_ = enc op_in 0
let send ~ch ~fail = enc op_mbx (((ch land 7) lsl 8) lor a8 fail)
let recv ~ch ~fail = enc op_mbx ((1 lsl 11) lor ((ch land 7) lsl 8) lor a8 fail)
let waitc ~cond ~fail = enc op_waitc (((cond land 15) lsl 8) lor a8 fail)
let ext sub imm = enc op_ext (((sub land 15) lsl 8) lor (imm land 0xFF))
let skne v = ext x_skne v
let skeq v = ext x_skeq v
let fine v = ext x_fine v
let cnta = ext x_cnta 0
let ldb = ext x_ldb 0
let stb = ext x_stb 0
let bank hi = ext x_bank hi
let cfg v = ext x_cfg v
let cfg_round_latch = 0x80

(* ---- interpreter ---- *)
type state = {
  pcs : int array; pages : int array; accs : int array; cnts : int array; dls : int array;
  bps : int array; fines : int array; armed : int array; cfgs : int array; lsend : int array;
  inbox : int array; full : int array;
  mutable pin_out : int; mutable pin_oe : int; mutable thread : int;
  mutable pin_sub : int; mutable latch : int;
  bankmem : int array;
}

(* [boot]: each thread's (page, pc) after reset, set by the host *)
let init ?(boot = Array.make n_threads (0, 0)) ?bank () =
  let z () = Array.make n_threads 0 in
  { pcs = Array.map snd boot; pages = Array.map fst boot; accs = z (); cnts = z (); dls = z (); bps = z (); fines = z ();
    armed = z (); cfgs = z (); lsend = z (); inbox = z (); full = z ();
    pin_out = 0; pin_oe = 0; thread = 0; pin_sub = 0; latch = 0;
    bankmem = (match bank with Some b -> Array.copy b | None -> Array.make bank_len 0) }

let copy st =
  let c = Array.copy in
  { pcs = c st.pcs; pages = c st.pages; accs = c st.accs; cnts = c st.cnts; dls = c st.dls;
    bps = c st.bps; fines = c st.fines; armed = c st.armed; cfgs = c st.cfgs; lsend = c st.lsend;
    inbox = c st.inbox; full = c st.full; pin_out = st.pin_out; pin_oe = st.pin_oe;
    thread = st.thread; pin_sub = st.pin_sub; latch = st.latch; bankmem = c st.bankmem }

type io = {
  pin_in : int;
  pin_in4 : int;                 (* bit 4i+p: pin i in quarter p of the last clock *)
  host_in : int; host_in_valid : bool;
  port_in : int array; port_in_valid : bool array; port_out_ready : bool array;
  flags : int;                   (* 16 bits: thread t's flag inputs are bits 4t..4t+3 *)
  host_ctl : (int * int * int) option;   (* (thread, page, pc) *)
}

let sub_of ~old_ ~new_ ~q =
  let r = ref 0 in
  for i = 0 to 7 do
    for p = 0 to 3 do
      let v = if p < q then (old_ lsr i) land 1 else (new_ lsr i) land 1 in
      r := !r lor (v lsl (4 * i + p))
    done
  done; !r

let replicate4 pin_in = sub_of ~old_:pin_in ~new_:pin_in ~q:0

let io ?pin_in4 ?(host_in = 0) ?(host_in_valid = false) ?(port_in = Array.make 4 0)
    ?(port_in_valid = Array.make 4 false) ?(port_out_ready = Array.make 4 false) ?(flags = 0)
    ?host_ctl pin_in =
  let pin_in4 = match pin_in4 with Some v -> v | None -> replicate4 pin_in in
  { pin_in; pin_in4; host_in; host_in_valid; port_in; port_in_valid; port_out_ready; flags; host_ctl }

type effects = {
  host_out : (int * int) option;        (* (tag, byte) *)
  host_in_ready : bool;
  port_pop : int option;                (* in-port popped *)
  port_push : (int * int) option;       (* (out-port, byte) *)
  bank_write : (int * int) option;      (* (address, byte) *)
  fine_out : int option;
}

let fetch st ~(mem : int array) t = mem.((st.pages.(t) lsl pc_bits) lor st.pcs.(t))

let step st ~(mem : int array) (io : io) =
  let t = st.thread in
  let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
  let instr = fetch st ~mem t in
  let opc = (instr lsr 12) land 0xF in
  let imm12 = instr land 0xFFF and imm8 = instr land 0xFF in
  let pin = (instr lsr 9) land 7 and pin_val = (instr lsr 8) land 1 in
  let addr = instr land 0xFF in
  let od = (instr lsr 7) land 1 in
  let mask8 = (instr lsr 4) land 0xFF and setv = (instr lsr 3) land 1 and seto = (instr lsr 2) land 1 in
  let q = instr land 3 in
  (* round latch: all four threads of a round see pin_in of thread 0's clock *)
  if t = 0 then st.latch <- io.pin_in;
  let pins = if st.cfgs.(t) land 0x80 <> 0 then st.latch else io.pin_in in
  let old_pins = st.pin_out in
  let sub_q = ref 0 in
  let pc_next = ref ((pc + 1) land 0xFF) in
  let acc_next = ref acc and cnt_next = ref cnt in
  let dl_next = ref (if dl = 0 then 0 else dl - 1) in
  let host_out = ref None and host_in_ready = ref false and port_pop = ref None
  and port_push = ref None and bank_write = ref None and fine_out = ref None in
  let stay () = pc_next := pc in
  let fail_or_stay () = if dl = 0 then pc_next := addr else stay () in
  let pin_write () =
    if st.armed.(t) = 1 then (fine_out := Some st.fines.(t); st.armed.(t) <- 0) in
  let drive p b =
    if od = 1 then begin
      st.pin_out <- st.pin_out land lnot (1 lsl p);
      st.pin_oe <- (st.pin_oe land lnot (1 lsl p)) lor ((1 - b) lsl p)
    end else st.pin_out <- (st.pin_out land lnot (1 lsl p)) lor (b lsl p) in
  let bp = st.bps.(t) in
  (match opc with
   | 1 ->
     sub_q := q; pin_write ();
     st.pin_out <- (st.pin_out land lnot mask8) lor (if setv = 1 then mask8 else 0);
     st.pin_oe <- (st.pin_oe land lnot mask8) lor (if seto = 1 then mask8 else 0)
   | 2 -> cnt_next := imm12
   | 3 -> dl_next := imm12
   | 4 -> acc_next := imm8
   | 5 -> if (pins lsr pin) land 1 <> pin_val then fail_or_stay ()
   | 6 -> if dl <> 0 then stay ()
   | 7 ->
     let pair = (instr lsr 6) land 1 and psel = (instr lsr 5) land 1 and cap = (instr lsr 4) land 1 in
     let msb = pin_val = 1 in
     let b0 = if msb then (acc lsr 7) land 1 else acc land 1 in
     pin_write ();
     drive pin b0;
     if pair = 1 then begin
       let b1 = if psel = 1 then (if msb then (acc lsr 6) land 1 else (acc lsr 1) land 1) else 1 - b0 in
       drive ((pin + 1) land 7) b1
     end;
     if od = 0 then sub_q := q;
     let sh = if pair = 1 && psel = 1 then 2 else 1 in
     let cbit = cap land ((pins lsr (pin lxor 1)) land 1) in
     acc_next := (if msb then ((acc lsl sh) land 0xFF) lor cbit
                  else (acc lsr sh) lor (cbit lsl 7));
     cnt_next := (cnt - 1) land 0xFFF
   | 8 ->
     let quad = (instr lsr 7) land 1 in
     let pin_bit = (pins lsr pin) land 1 in
     let nib = (io.pin_in4 lsr (4 * pin)) land 0xF in
     let rev4 n = ((n land 1) lsl 3) lor ((n land 2) lsl 1) lor ((n land 4) lsr 1) lor ((n land 8) lsr 3) in
     acc_next :=
       (if quad = 1 then
          (if pin_val = 1 then ((acc lsl 4) land 0xFF) lor rev4 nib else (acc lsr 4) lor (nib lsl 4))
        else if pin_val = 1 then ((acc lsl 1) land 0xFF) lor pin_bit else (acc lsr 1) lor (pin_bit lsl 7));
     cnt_next := (cnt - 1) land 0xFFF
   | 9 -> pc_next := addr
   | 10 -> if cnt <> 0 then pc_next := addr
   | 11 ->
     let src = (instr lsr 11) land 1 and tag = (instr lsr 8) land 7 in
     host_out := Some (tag, if src = 1 then imm8 else acc)
   | 12 -> if io.host_in_valid then (acc_next := io.host_in; host_in_ready := true) else stay ()
   | 13 ->
     let recv = (instr lsr 11) land 1 = 1 and ch = (instr lsr 8) land 7 in
     if not recv then begin
       st.lsend.(t) <- ch;
       if ch >= 4 then (if io.port_out_ready.(ch - 4) then port_push := Some (ch - 4, acc) else fail_or_stay ())
       else if st.full.(ch) = 0 then (st.inbox.(ch) <- acc; st.full.(ch) <- 1)
       else fail_or_stay ()
     end else begin
       if ch >= 4 then
         (if io.port_in_valid.(ch - 4) then (acc_next := io.port_in.(ch - 4); port_pop := Some (ch - 4))
          else fail_or_stay ())
       else if st.full.(ch) = 1 then (acc_next := st.inbox.(ch); st.full.(ch) <- 0)
       else fail_or_stay ()
     end
   | 14 ->
     let c = (instr lsr 8) land 0xF in
     let ls = st.lsend.(t) in
     let holds =
       if c < 8 then (acc lsr c) land 1 = 1
       else if c = 8 then cnt land 7 = 0
       else if c = 9 then io.host_in_valid
       else if c = 10 then st.full.(t) = 1
       else if c = 11 then (if ls >= 4 then io.port_out_ready.(ls - 4) else st.full.(ls) = 0)
       else (io.flags lsr (4 * t + c - 12)) land 1 = 1 in
     if not holds then fail_or_stay ()
   | 15 ->
     let sub = (instr lsr 8) land 0xF in
     if sub = x_skne then (if acc <> imm8 then pc_next := (pc + 2) land 0xFF)
     else if sub = x_skeq then (if acc = imm8 then pc_next := (pc + 2) land 0xFF)
     else if sub = x_fine then (st.fines.(t) <- imm8; st.armed.(t) <- 1)
     else if sub = x_cnta then cnt_next := acc
     else if sub = x_ldb then (acc_next := st.bankmem.(bp); st.bps.(t) <- (bp + 1) land (bank_len - 1))
     else if sub = x_stb then begin
       st.bankmem.(bp) <- acc; bank_write := Some (bp, acc);
       st.bps.(t) <- (bp + 1) land (bank_len - 1)
     end
     else if sub = x_bank then st.bps.(t) <- ((imm8 land 3) lsl 8) lor acc
     else if sub = x_cfg then st.cfgs.(t) <- imm8
   | _ -> ());
  st.pin_sub <- sub_of ~old_:old_pins ~new_:st.pin_out ~q:!sub_q;
  st.pcs.(t) <- !pc_next; st.accs.(t) <- !acc_next; st.cnts.(t) <- !cnt_next; st.dls.(t) <- !dl_next;
  (match io.host_ctl with
   | Some (ht, pg, hpc) -> st.pages.(ht) <- pg land 3; st.pcs.(ht) <- hpc land 0xFF
   | None -> ());
  st.thread <- (t + 1) mod n_threads;
  { host_out = !host_out; host_in_ready = !host_in_ready; port_pop = !port_pop;
    port_push = !port_push; bank_write = !bank_write; fine_out = !fine_out }

(* ---- disassembler (for traces and the README) ---- *)
let disasm w =
  let f = w land 0xFFF in
  let pin = (f lsr 9) land 7 and b8 = (f lsr 8) land 1 in
  match (w lsr 12) land 0xF with
  | 0 -> "nop"
  | 1 -> Printf.sprintf "setp mask=%02x val=%d oe=%d q=%d" ((f lsr 4) land 0xFF) ((f lsr 3) land 1) ((f lsr 2) land 1) (f land 3)
  | 2 -> Printf.sprintf "ldc %d" f
  | 3 -> Printf.sprintf "ldd %d" f
  | 4 -> Printf.sprintf "lda 0x%02x" (f land 0xFF)
  | 5 -> Printf.sprintf "waitp pin%d==%d fail=%d" pin b8 (f land 0xFF)
  | 6 -> "waitd"
  | 7 -> Printf.sprintf "sho pin%d %s%s%s%s%s q=%d" pin (if b8 = 1 then "msb" else "lsb")
           (if (f lsr 7) land 1 = 1 then " od" else "") (if (f lsr 6) land 1 = 1 then " pair" else "")
           (if (f lsr 5) land 1 = 1 then " psel" else "") (if (f lsr 4) land 1 = 1 then " cap" else "") (f land 3)
  | 8 -> Printf.sprintf "shi pin%d %s%s" pin (if b8 = 1 then "msb" else "lsb") (if (f lsr 7) land 1 = 1 then " quad" else "")
  | 9 -> Printf.sprintf "jmp %d" (f land 0xFF)
  | 10 -> Printf.sprintf "jnz %d" (f land 0xFF)
  | 11 -> if (f lsr 11) land 1 = 1 then Printf.sprintf "out tag=%d imm=0x%02x" ((f lsr 8) land 7) (f land 0xFF)
    else Printf.sprintf "out tag=%d acc" ((f lsr 8) land 7)
  | 12 -> "in"
  | 13 -> Printf.sprintf "%s ch%d fail=%d" (if (f lsr 11) land 1 = 1 then "recv" else "send") ((f lsr 8) land 7) (f land 0xFF)
  | 14 -> Printf.sprintf "waitc cond=%d fail=%d" ((f lsr 8) land 15) (f land 0xFF)
  | _ ->
    let imm = f land 0xFF in
    (match (f lsr 8) land 15 with
     | 0 -> Printf.sprintf "skne 0x%02x" imm | 1 -> Printf.sprintf "skeq 0x%02x" imm
     | 2 -> Printf.sprintf "fine %d" imm | 3 -> "cnta" | 4 -> "ldb" | 5 -> "stb"
     | 6 -> Printf.sprintf "bank %d" imm | 7 -> Printf.sprintf "cfg 0x%02x" imm
     | s -> Printf.sprintf "ext%d (reserved)" s)
