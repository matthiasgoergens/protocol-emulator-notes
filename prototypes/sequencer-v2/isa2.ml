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

(* The interpreter is written once, over an abstract domain of values [VALUE], and instantiated
   with OCaml integers ([Int_value] below), which is the executable specification every test uses.
   ../formal instantiates the same code with SMT-LIB terms for bounded model checking, so there is
   one semantics, not two.

   A value is a bit-vector of a fixed width; truth values are a separate type [b]. The integer
   instance does not record widths, so every operation that could leave its width ([add], [sub],
   [lognot], [shl]) is told the width ([~w]) and wraps there. [shl] and [lshr] shift by a value of
   the same width as the shifted one, giving 0 when the shift is at least the width. *)
module type VALUE = sig
  type t
  type b
  type mem                                    (* the data bank: 2^10 bytes *)
  val const : w:int -> int -> t
  val add : w:int -> t -> t -> t
  val sub : w:int -> t -> t -> t
  val logand : t -> t -> t
  val logor : t -> t -> t
  val logxor : t -> t -> t
  val lognot : w:int -> t -> t
  val shl : w:int -> t -> t -> t
  val lshr : t -> t -> t
  val extract : t -> hi:int -> lo:int -> t
  val zext : w:int -> t -> t                  (* zero-extend to w bits *)
  val eq : t -> t -> b
  val ult : t -> t -> b
  val ite : b -> t -> t -> t
  val tt : b
  val ff : b
  val not_ : b -> b
  val and_ : b -> b -> b
  val or_ : b -> b -> b
  val mem_read : mem -> t -> t
  val mem_write : mem -> b -> t -> t -> mem   (* store the byte at the address if [b] holds *)
  val mem_ite : b -> mem -> mem -> mem
  val mem_copy : mem -> mem
  val known_false : b -> bool                 (* [b] is false whatever the inputs; may answer
                                                 [false] when unsure (see [unless_false]) *)
end

(* The interpreter's state, inputs and effects, for values ['t], truth values ['b] and a data bank
   ['mem]. They are defined outside [Make] so that every instance over the same types shares them:
   [Spec.state] below is the same type as [Make (Int_value).state]. *)
type ('t, 'mem) state_of = {
  pcs : 't array; pages : 't array; accs : 't array; cnts : 't array; dls : 't array;
  bps : 't array; fines : 't array; armed : 't array; cfgs : 't array; lsend : 't array;
  inbox : 't array; full : 't array;
  mutable pin_out : 't; mutable pin_oe : 't; mutable thread : int;
  mutable pin_sub : 't; mutable latch : 't;
  mutable bankmem : 'mem;
}

type ('t, 'b) io_of = {
  pin_in : 't;
  pin_in4 : 't;                  (* bit 4i+p: pin i in quarter p of the last clock *)
  host_in : 't; host_in_valid : 'b;
  port_in : 't array; port_in_valid : 'b array; port_out_ready : 'b array;
  flags : 't;                    (* 16 bits: thread t's flag inputs are bits 4t..4t+3 *)
  host_ctl : (int * 't * 't) option;   (* (thread, page, pc) *)
}

(* What one clock does besides changing the state; each effect happens when its ['b] holds. *)
type ('t, 'b) effects_of = {
  host_out : 'b * 't * 't;        (* tag, byte *)
  host_in_ready : 'b;
  port_pop : 'b * 't;             (* in-port *)
  port_push : 'b * 't * 't;       (* out-port, byte *)
  bank_write : 'b * 't * 't;      (* address, byte *)
  bank_read : 'b * 't;            (* address *)
  fine_out : 'b * 't;
  pins_written : 't;              (* the pins this clock's SETP or SHO writes, for checks *)
}

module Make (V : VALUE) = struct
  open V
  (* BEGIN body of Make *)

  type state = (t, mem) state_of
  type io = (t, b) io_of
  type effects = (t, b) effects_of

  let[@inline] c w n = const ~w n
  let[@inline] bit x i = eq (extract x ~hi:i ~lo:i) (c 1 1)
  let[@inline] of_b x = ite x (c 1 1) (c 1 0)
  let[@inline] ite_b s x y = or_ (and_ s x) (and_ (not_ s) y)

  (* [unless_false s d f] is [f ()], or [d] when [s] is known to be false. It guards a value that
     is only ever used where [s] holds, such as the result of one opcode, so the choice between
     [d] and [f ()] cannot change the outcome; it only saves computing it. On integers [s] is
     always known, so a clock computes only its own opcode's results; on SMT terms it skips
     building terms that would fold away; on signals it is never taken. *)
  let unless_false s d f = if known_false s then d else f ()

  (* bit [i] of [v], for a value [i]; [w] is the width of [v] *)
  (* instruction fields, and the opcode test *)
  let[@inline] field instr hi lo = extract instr ~hi ~lo
  let[@inline] flag instr i = bit instr i
  let[@inline] is opc op = eq opc (c 4 op)

  let[@inline] bit_at ~w v i = bit (lshr v (zext ~w i)) 0

  (* one-bit values, most significant first, as one value *)
  let of_bits bits =
    let w = List.length bits in
    List.fold_left (fun r x -> logor (shl ~w r (c w 1)) (zext ~w x)) (c w 0) bits

  (* [arr.(i)] for a value [i] of [w] bits *)
  let select ~w arr i =
    let n = Array.length arr in
    let r = ref arr.(n - 1) in
    for k = n - 2 downto 0 do r := ite (eq i (c w k)) arr.(k) !r done; !r

  let select_b ~w arr i =
    let n = Array.length arr in
    let r = ref arr.(n - 1) in
    for k = n - 2 downto 0 do r := ite_b (eq i (c w k)) arr.(k) !r done; !r

  let reset ~boot ~bank =
    let z w = Array.make n_threads (c w 0) in
    { pcs = Array.map snd boot; pages = Array.map fst boot; accs = z 8; cnts = z 12; dls = z 12;
      bps = z 10; fines = z 8; armed = z 1; cfgs = z 8; lsend = z 3; inbox = z 8; full = z 1;
      pin_out = c 8 0; pin_oe = c 8 0; thread = 0; pin_sub = c 32 0; latch = c 8 0; bankmem = bank }

  let copy st =
    let a = Array.copy in
    { pcs = a st.pcs; pages = a st.pages; accs = a st.accs; cnts = a st.cnts; dls = a st.dls;
      bps = a st.bps; fines = a st.fines; armed = a st.armed; cfgs = a st.cfgs; lsend = a st.lsend;
      inbox = a st.inbox; full = a st.full; pin_out = st.pin_out; pin_oe = st.pin_oe;
      thread = st.thread; pin_sub = st.pin_sub; latch = st.latch; bankmem = mem_copy st.bankmem }

  (* [merge s x y]: the state that is [x] where [s] holds and [y] elsewhere (same thread) *)
  let merge s x y =
    assert (x.thread = y.thread);
    let m = Array.map2 (ite s) in
    { pcs = m x.pcs y.pcs; pages = m x.pages y.pages; accs = m x.accs y.accs; cnts = m x.cnts y.cnts;
      dls = m x.dls y.dls; bps = m x.bps y.bps; fines = m x.fines y.fines; armed = m x.armed y.armed;
      cfgs = m x.cfgs y.cfgs; lsend = m x.lsend y.lsend; inbox = m x.inbox y.inbox;
      full = m x.full y.full; pin_out = ite s x.pin_out y.pin_out; pin_oe = ite s x.pin_oe y.pin_oe;
      thread = x.thread; pin_sub = ite s x.pin_sub y.pin_sub; latch = ite s x.latch y.latch;
      bankmem = mem_ite s x.bankmem y.bankmem }

  (* the quarter-clock view of a clock whose instruction moved the pins from [old_] to [new_] at
     sub-slot [q]: bit 4i+p is old_ bit i for p < q, new_ bit i otherwise *)
  let sub_of ~old_ ~new_ ~q =
    (* bit i of an 8-bit value to bit 4i of a 32-bit one, by the usual shift-and-mask steps *)
    let spread x =
      let step y s m = logand (logor y (shl ~w:32 y (c 32 s))) (c 32 m) in
      step (step (step (zext ~w:32 x) 12 0x000F000F) 6 0x03030303) 3 0x11111111 in
    let old4 = spread old_ and new4 = spread new_ in
    let quarter p = shl ~w:32 (ite (ult (c 2 p) q) old4 new4) (c 32 p) in
    logor (logor (quarter 0) (quarter 1)) (logor (quarter 2) (quarter 3))

  let fetch_addr st t = logor (shl ~w:10 (zext ~w:10 st.pages.(t)) (c 10 pc_bits)) (zext ~w:10 st.pcs.(t))

  (* One clock: the current thread executes [instr], the word at [fetch_addr st st.thread]. Every
     next-state value is computed from the state as it was at the start of the clock; the state
     is updated at the end. *)
  let exec st ~instr (io : io) =
    let t = st.thread in
    let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
    let opc = field instr 15 12 in
    let imm12 = field instr 11 0 and imm8 = field instr 7 0 in
    let pin = field instr 11 9 and msb = flag instr 8 and od = flag instr 7 in
    let addr = imm8 in
    let mask8 = field instr 11 4 and setv = flag instr 3 and seto = flag instr 2 and q = field instr 1 0 in
    (* round latch: all four threads of a round see pin_in of thread 0's clock (D6) *)
    let latch = if t = 0 then io.pin_in else st.latch in
    let pins = ite (bit st.cfgs.(t) 7) latch io.pin_in in
    let pin_at p = bit_at ~w:8 pins p in
    let dl_zero = eq dl (c 12 0) in
    let pc1 = add ~w:8 pc (c 8 1) in
    let fail_or_stay = ite dl_zero addr pc in
    (* SETP *)
    let set_masked x v = logor (logand x (lognot ~w:8 mask8)) (ite v mask8 (c 8 0)) in
    (* SHO: drive [p] with the one-bit [v]; open drain (od) drives 0 for a 0, releases for a 1 *)
    let pair = flag instr 6 and psel = flag instr 5 and cap = flag instr 4 in
    let onehot p = shl ~w:8 (c 8 1) (zext ~w:8 p) in
    let is_sho = is opc op_sho in
    let sho_pins, sho_acc = unless_false is_sho ((st.pin_out, st.pin_oe), acc) (fun () ->
        let acc_bit i = extract acc ~hi:i ~lo:i in
        let drive (po, oe) p v =
          let m = onehot p and one = eq v (c 1 1) in
          let keep x = logand x (lognot ~w:8 m) in
          ite od (keep po) (logor (keep po) (ite one m (c 8 0))),
          ite od (logor (keep oe) (ite one (c 8 0) m)) oe in
        let b0 = ite msb (acc_bit 7) (acc_bit 0) in
        let b1 = ite psel (ite msb (acc_bit 6) (acc_bit 1)) (lognot ~w:1 b0) in
        let one_pin = drive (st.pin_out, st.pin_oe) pin b0 in
        let two_pins = drive one_pin (add ~w:3 pin (c 3 1)) b1 in
        let sho_pins = (ite pair (fst two_pins) (fst one_pin), ite pair (snd two_pins) (snd one_pin)) in
        let sh = ite (and_ pair psel) (c 8 2) (c 8 1) in
        let cbit = zext ~w:8 (of_b (and_ cap (pin_at (logxor pin (c 3 1))))) in
        sho_pins, ite msb (logor (shl ~w:8 acc sh) cbit) (logor (lshr acc sh) (shl ~w:8 cbit (c 8 7)))) in
    (* SHI *)
    let shi_acc = unless_false (is opc op_shi) acc (fun () ->
        let quad = flag instr 7 in
        let pin_bit = zext ~w:8 (of_b (pin_at pin)) in
        let nib = extract (lshr io.pin_in4 (shl ~w:32 (zext ~w:32 pin) (c 32 2))) ~hi:3 ~lo:0 in
        let rev4 = of_bits (List.map (fun i -> extract nib ~hi:i ~lo:i) [ 0; 1; 2; 3 ]) in
        ite quad
          (ite msb (logor (shl ~w:8 acc (c 8 4)) (zext ~w:8 rev4))
             (logor (lshr acc (c 8 4)) (shl ~w:8 (zext ~w:8 nib) (c 8 4))))
          (ite msb (logor (shl ~w:8 acc (c 8 1)) pin_bit)
             (logor (lshr acc (c 8 1)) (shl ~w:8 pin_bit (c 8 7))))) in
    (* MBX: channel 0..3 is an inbox, 4..7 a port *)
    let recv = flag instr 11 and ch = field instr 10 8 in
    let to_port = bit ch 2 and slot = extract ch ~hi:1 ~lo:0 in
    let is_mbx = is opc op_mbx in
    let is_send = and_ is_mbx (not_ recv) and is_recv = and_ is_mbx recv in
    let full_at i = eq (select ~w:2 st.full i) (c 1 1) in
    let send_ok, recv_ok, recv_byte = unless_false is_mbx (ff, ff, acc) (fun () ->
        ite_b to_port (select_b ~w:2 io.port_out_ready slot) (not_ (full_at slot)),
        ite_b to_port (select_b ~w:2 io.port_in_valid slot) (full_at slot),
        ite to_port (select ~w:2 io.port_in slot) (select ~w:2 st.inbox slot)) in
    (* WAITC *)
    let ls = st.lsend.(t) in
    let is_waitc = is opc op_waitc in
    let holds = unless_false is_waitc ff (fun () ->
        let cond = field instr 11 8 in
        let ls_slot = extract ls ~hi:1 ~lo:0 in
        let space = ite_b (bit ls 2) (select_b ~w:2 io.port_out_ready ls_slot) (not_ (full_at ls_slot)) in
        let is_cond k = eq cond (c 4 k) in
        ite_b (ult cond (c 4 8)) (bit_at ~w:8 acc (extract cond ~hi:2 ~lo:0))
          (ite_b (is_cond c_byte) (eq (extract cnt ~hi:2 ~lo:0) (c 3 0))
             (ite_b (is_cond c_host) io.host_in_valid
                (ite_b (is_cond c_inbox) (eq st.full.(t) (c 1 1))
                   (ite_b (is_cond c_space) space
                      (bit (lshr io.flags (zext ~w:16 (extract cond ~hi:1 ~lo:0))) (4 * t))))))) in
    (* EXT *)
    let is_ext = is opc op_ext in
    let ext_sub = field instr 11 8 in
    let x k = and_ is_ext (eq ext_sub (c 4 k)) in
    let skip = unless_false is_ext ff (fun () ->
        or_ (and_ (x x_skne) (not_ (eq acc imm8))) (and_ (x x_skeq) (eq acc imm8))) in
    let bp = st.bps.(t) in
    let pin_write = or_ (is opc op_setp) is_sho in
    (* next state *)
    (* Each next value is a chain [ite s1 v1 @@ ite s2 v2 @@ ... @@ default]: v1 where s1 holds,
       else v2 where s2 holds, ..., else the default. *)
    let is_waitp = is opc op_waitp in
    let pc_next =
      ite is_waitp (unless_false is_waitp pc (fun () ->
          ite (eq (of_b (pin_at pin)) (field instr 8 8)) pc1 fail_or_stay)) @@
      ite (is opc op_waitd) (ite dl_zero pc1 pc) @@
      ite (is opc op_jmp) addr @@
      ite (is opc op_jnz) (ite (eq cnt (c 12 0)) pc1 addr) @@
      ite (is opc op_in) (ite io.host_in_valid pc1 pc) @@
      ite is_mbx (ite (ite_b recv recv_ok send_ok) pc1 fail_or_stay) @@
      ite is_waitc (ite holds pc1 fail_or_stay) @@
      ite skip (add ~w:8 pc (c 8 2)) @@
      pc1 in
    let is_ldb = x x_ldb in
    let acc_next =
      ite (is opc op_lda) imm8 @@
      ite is_sho sho_acc @@
      ite (is opc op_shi) shi_acc @@
      ite (is opc op_in) (ite io.host_in_valid io.host_in acc) @@
      ite is_recv (ite recv_ok recv_byte acc) @@
      ite is_ldb (unless_false is_ldb acc (fun () -> mem_read st.bankmem bp)) @@
      acc in
    let cnt_dec = sub ~w:12 cnt (c 12 1) in
    let cnt_next =
      ite (is opc op_ldc) imm12 @@
      ite is_sho cnt_dec @@
      ite (is opc op_shi) cnt_dec @@
      ite (x x_cnta) (zext ~w:12 acc) @@
      cnt in
    let dl_next = ite (is opc op_ldd) imm12 (ite dl_zero (c 12 0) (sub ~w:12 dl (c 12 1))) in
    let is_setp = is opc op_setp in
    let setp_out, setp_oe = unless_false is_setp (st.pin_out, st.pin_oe) (fun () ->
        set_masked st.pin_out setv, set_masked st.pin_oe seto) in
    let pin_out_next = ite is_setp setp_out @@ ite is_sho (fst sho_pins) @@ st.pin_out in
    let pin_oe_next = ite is_setp setp_oe @@ ite is_sho (snd sho_pins) @@ st.pin_oe in
    let sub_q = ite is_setp q @@ ite is_sho (ite od (c 2 0) q) @@ c 2 0 in
    let inbox_next = unless_false is_mbx st.inbox (fun () -> Array.mapi (fun k v ->
        ite (and_ (and_ is_send (not_ to_port)) (and_ (eq slot (c 2 k)) (not_ (full_at slot)))) acc v) st.inbox) in
    let full_next = unless_false is_mbx st.full (fun () -> Array.mapi (fun k v ->
        let here = and_ (not_ to_port) (eq slot (c 2 k)) in
        ite (and_ is_send here) (c 1 1) (ite (and_ is_recv here) (c 1 0) v)) st.full) in
    let bp_next = unless_false is_ext bp (fun () ->
        ite (or_ is_ldb (x x_stb)) (add ~w:10 bp (c 10 1)) @@
        ite (x x_bank) (logor (shl ~w:10 (zext ~w:10 (extract imm8 ~hi:1 ~lo:0)) (c 10 8)) (zext ~w:10 acc)) @@
        bp) in
    let armed = eq st.armed.(t) (c 1 1) in
    let effects =
      { host_out = (is opc op_out, field instr 10 8, ite (flag instr 11) imm8 acc);
        host_in_ready = and_ (is opc op_in) io.host_in_valid;
        port_pop = (unless_false is_mbx ff (fun () ->
            and_ (and_ is_recv to_port) (select_b ~w:2 io.port_in_valid slot)), slot);
        port_push = (unless_false is_mbx ff (fun () ->
            and_ (and_ is_send to_port) (select_b ~w:2 io.port_out_ready slot)), slot, acc);
        bank_write = (x x_stb, bp, acc);
        bank_read = (is_ldb, bp);
        fine_out = (and_ pin_write armed, st.fines.(t));
        pins_written =
          ite is_setp mask8 @@
          ite is_sho (unless_false is_sho (c 8 0) (fun () ->
              logor (onehot pin) (ite pair (onehot (add ~w:3 pin (c 3 1))) (c 8 0)))) @@
          c 8 0 } in
    (* commit *)
    st.bankmem <- unless_false (x x_stb) st.bankmem (fun () -> mem_write st.bankmem (x x_stb) bp acc);
    st.pin_sub <- sub_of ~old_:st.pin_out ~new_:pin_out_next ~q:sub_q;
    st.pin_out <- pin_out_next; st.pin_oe <- pin_oe_next; st.latch <- latch;
    if inbox_next != st.inbox then Array.blit inbox_next 0 st.inbox 0 n_threads;
    if full_next != st.full then Array.blit full_next 0 st.full 0 n_threads;
    st.lsend.(t) <- ite is_send ch ls;
    st.fines.(t) <- ite (x x_fine) imm8 st.fines.(t);
    st.armed.(t) <- ite (x x_fine) (c 1 1) (ite pin_write (c 1 0) st.armed.(t));
    st.cfgs.(t) <- ite (x x_cfg) imm8 st.cfgs.(t);
    st.bps.(t) <- bp_next;
    st.pcs.(t) <- pc_next; st.accs.(t) <- acc_next; st.cnts.(t) <- cnt_next; st.dls.(t) <- dl_next;
    (match io.host_ctl with
     | Some (ht, pg, hpc) -> st.pages.(ht) <- extract pg ~hi:1 ~lo:0; st.pcs.(ht) <- extract hpc ~hi:7 ~lo:0
     | None -> ());
    st.thread <- (t + 1) mod n_threads;
    effects
  (* END body of Make *)
end

(* The executable specification: [Make] over OCaml integers. *)
(* The integer instance. [@inline] makes ocamlopt (without flambda) inline each operation into
   [Spec] below, where they are known functions; the annotations keep comparisons on [int]. *)
module Int_value = struct
  type t = int
  type b = bool
  type mem = int array
  let[@inline] mask w = (1 lsl w) - 1
  let[@inline] const ~w n = n land mask w
  let[@inline] add ~w (x : int) y = (x + y) land mask w
  let[@inline] sub ~w (x : int) y = (x - y) land mask w
  let[@inline] logand (x : int) y = x land y
  let[@inline] logor (x : int) y = x lor y
  let[@inline] logxor (x : int) y = x lxor y
  let[@inline] lognot ~w x = lnot x land mask w
  let[@inline] shl ~w x s = if s >= w then 0 else (x lsl s) land mask w
  let[@inline] lshr x s = if s >= Sys.int_size then 0 else x lsr s
  let[@inline] extract x ~hi ~lo = (x lsr lo) land mask (hi - lo + 1)
  let[@inline] zext ~w:_ (x : int) = x
  let[@inline] eq (x : int) y = x = y
  let[@inline] ult (x : int) y = x < y
  let[@inline] ite s (x : int) y = if s then x else y
  let tt = true
  let ff = false
  let[@inline] not_ x = not x
  let[@inline] and_ x y = x && y
  let[@inline] or_ x y = x || y
  let[@inline] mem_read (m : int array) a = m.(a)
  let[@inline] mem_write (m : int array) s a v = if s then m.(a) <- v; m
  let[@inline] mem_ite s (x : int array) y = if s then x else y
  let mem_copy (m : int array) = Array.copy m
  let[@inline] known_false b = not b
end

(* The executable specification. It is [Make (Int_value)], written out: the lines between the
   BEGIN and END markers below are a verbatim copy of [Make]'s body, so that the compiler sees
   [Int_value]'s operations as known functions and inlines them. Through the functor, without
   flambda, every operation is an indirect call; bridge A of the multi-proto port took three times
   as long. The build checks that the copy is verbatim (specialise.awk, run from ./dune), and
   [./specialise.sh] rewrites it after an edit of [Make]. *)
module Spec = struct
  open (Int_value : VALUE with type t = int and type b = bool and type mem = int array)
  (* BEGIN copy of Make's body *)

  type state = (t, mem) state_of
  type io = (t, b) io_of
  type effects = (t, b) effects_of

  let[@inline] c w n = const ~w n
  let[@inline] bit x i = eq (extract x ~hi:i ~lo:i) (c 1 1)
  let[@inline] of_b x = ite x (c 1 1) (c 1 0)
  let[@inline] ite_b s x y = or_ (and_ s x) (and_ (not_ s) y)

  (* [unless_false s d f] is [f ()], or [d] when [s] is known to be false. It guards a value that
     is only ever used where [s] holds, such as the result of one opcode, so the choice between
     [d] and [f ()] cannot change the outcome; it only saves computing it. On integers [s] is
     always known, so a clock computes only its own opcode's results; on SMT terms it skips
     building terms that would fold away; on signals it is never taken. *)
  let unless_false s d f = if known_false s then d else f ()

  (* bit [i] of [v], for a value [i]; [w] is the width of [v] *)
  (* instruction fields, and the opcode test *)
  let[@inline] field instr hi lo = extract instr ~hi ~lo
  let[@inline] flag instr i = bit instr i
  let[@inline] is opc op = eq opc (c 4 op)

  let[@inline] bit_at ~w v i = bit (lshr v (zext ~w i)) 0

  (* one-bit values, most significant first, as one value *)
  let of_bits bits =
    let w = List.length bits in
    List.fold_left (fun r x -> logor (shl ~w r (c w 1)) (zext ~w x)) (c w 0) bits

  (* [arr.(i)] for a value [i] of [w] bits *)
  let select ~w arr i =
    let n = Array.length arr in
    let r = ref arr.(n - 1) in
    for k = n - 2 downto 0 do r := ite (eq i (c w k)) arr.(k) !r done; !r

  let select_b ~w arr i =
    let n = Array.length arr in
    let r = ref arr.(n - 1) in
    for k = n - 2 downto 0 do r := ite_b (eq i (c w k)) arr.(k) !r done; !r

  let reset ~boot ~bank =
    let z w = Array.make n_threads (c w 0) in
    { pcs = Array.map snd boot; pages = Array.map fst boot; accs = z 8; cnts = z 12; dls = z 12;
      bps = z 10; fines = z 8; armed = z 1; cfgs = z 8; lsend = z 3; inbox = z 8; full = z 1;
      pin_out = c 8 0; pin_oe = c 8 0; thread = 0; pin_sub = c 32 0; latch = c 8 0; bankmem = bank }

  let copy st =
    let a = Array.copy in
    { pcs = a st.pcs; pages = a st.pages; accs = a st.accs; cnts = a st.cnts; dls = a st.dls;
      bps = a st.bps; fines = a st.fines; armed = a st.armed; cfgs = a st.cfgs; lsend = a st.lsend;
      inbox = a st.inbox; full = a st.full; pin_out = st.pin_out; pin_oe = st.pin_oe;
      thread = st.thread; pin_sub = st.pin_sub; latch = st.latch; bankmem = mem_copy st.bankmem }

  (* [merge s x y]: the state that is [x] where [s] holds and [y] elsewhere (same thread) *)
  let merge s x y =
    assert (x.thread = y.thread);
    let m = Array.map2 (ite s) in
    { pcs = m x.pcs y.pcs; pages = m x.pages y.pages; accs = m x.accs y.accs; cnts = m x.cnts y.cnts;
      dls = m x.dls y.dls; bps = m x.bps y.bps; fines = m x.fines y.fines; armed = m x.armed y.armed;
      cfgs = m x.cfgs y.cfgs; lsend = m x.lsend y.lsend; inbox = m x.inbox y.inbox;
      full = m x.full y.full; pin_out = ite s x.pin_out y.pin_out; pin_oe = ite s x.pin_oe y.pin_oe;
      thread = x.thread; pin_sub = ite s x.pin_sub y.pin_sub; latch = ite s x.latch y.latch;
      bankmem = mem_ite s x.bankmem y.bankmem }

  (* the quarter-clock view of a clock whose instruction moved the pins from [old_] to [new_] at
     sub-slot [q]: bit 4i+p is old_ bit i for p < q, new_ bit i otherwise *)
  let sub_of ~old_ ~new_ ~q =
    (* bit i of an 8-bit value to bit 4i of a 32-bit one, by the usual shift-and-mask steps *)
    let spread x =
      let step y s m = logand (logor y (shl ~w:32 y (c 32 s))) (c 32 m) in
      step (step (step (zext ~w:32 x) 12 0x000F000F) 6 0x03030303) 3 0x11111111 in
    let old4 = spread old_ and new4 = spread new_ in
    let quarter p = shl ~w:32 (ite (ult (c 2 p) q) old4 new4) (c 32 p) in
    logor (logor (quarter 0) (quarter 1)) (logor (quarter 2) (quarter 3))

  let fetch_addr st t = logor (shl ~w:10 (zext ~w:10 st.pages.(t)) (c 10 pc_bits)) (zext ~w:10 st.pcs.(t))

  (* One clock: the current thread executes [instr], the word at [fetch_addr st st.thread]. Every
     next-state value is computed from the state as it was at the start of the clock; the state
     is updated at the end. *)
  let exec st ~instr (io : io) =
    let t = st.thread in
    let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
    let opc = field instr 15 12 in
    let imm12 = field instr 11 0 and imm8 = field instr 7 0 in
    let pin = field instr 11 9 and msb = flag instr 8 and od = flag instr 7 in
    let addr = imm8 in
    let mask8 = field instr 11 4 and setv = flag instr 3 and seto = flag instr 2 and q = field instr 1 0 in
    (* round latch: all four threads of a round see pin_in of thread 0's clock (D6) *)
    let latch = if t = 0 then io.pin_in else st.latch in
    let pins = ite (bit st.cfgs.(t) 7) latch io.pin_in in
    let pin_at p = bit_at ~w:8 pins p in
    let dl_zero = eq dl (c 12 0) in
    let pc1 = add ~w:8 pc (c 8 1) in
    let fail_or_stay = ite dl_zero addr pc in
    (* SETP *)
    let set_masked x v = logor (logand x (lognot ~w:8 mask8)) (ite v mask8 (c 8 0)) in
    (* SHO: drive [p] with the one-bit [v]; open drain (od) drives 0 for a 0, releases for a 1 *)
    let pair = flag instr 6 and psel = flag instr 5 and cap = flag instr 4 in
    let onehot p = shl ~w:8 (c 8 1) (zext ~w:8 p) in
    let is_sho = is opc op_sho in
    let sho_pins, sho_acc = unless_false is_sho ((st.pin_out, st.pin_oe), acc) (fun () ->
        let acc_bit i = extract acc ~hi:i ~lo:i in
        let drive (po, oe) p v =
          let m = onehot p and one = eq v (c 1 1) in
          let keep x = logand x (lognot ~w:8 m) in
          ite od (keep po) (logor (keep po) (ite one m (c 8 0))),
          ite od (logor (keep oe) (ite one (c 8 0) m)) oe in
        let b0 = ite msb (acc_bit 7) (acc_bit 0) in
        let b1 = ite psel (ite msb (acc_bit 6) (acc_bit 1)) (lognot ~w:1 b0) in
        let one_pin = drive (st.pin_out, st.pin_oe) pin b0 in
        let two_pins = drive one_pin (add ~w:3 pin (c 3 1)) b1 in
        let sho_pins = (ite pair (fst two_pins) (fst one_pin), ite pair (snd two_pins) (snd one_pin)) in
        let sh = ite (and_ pair psel) (c 8 2) (c 8 1) in
        let cbit = zext ~w:8 (of_b (and_ cap (pin_at (logxor pin (c 3 1))))) in
        sho_pins, ite msb (logor (shl ~w:8 acc sh) cbit) (logor (lshr acc sh) (shl ~w:8 cbit (c 8 7)))) in
    (* SHI *)
    let shi_acc = unless_false (is opc op_shi) acc (fun () ->
        let quad = flag instr 7 in
        let pin_bit = zext ~w:8 (of_b (pin_at pin)) in
        let nib = extract (lshr io.pin_in4 (shl ~w:32 (zext ~w:32 pin) (c 32 2))) ~hi:3 ~lo:0 in
        let rev4 = of_bits (List.map (fun i -> extract nib ~hi:i ~lo:i) [ 0; 1; 2; 3 ]) in
        ite quad
          (ite msb (logor (shl ~w:8 acc (c 8 4)) (zext ~w:8 rev4))
             (logor (lshr acc (c 8 4)) (shl ~w:8 (zext ~w:8 nib) (c 8 4))))
          (ite msb (logor (shl ~w:8 acc (c 8 1)) pin_bit)
             (logor (lshr acc (c 8 1)) (shl ~w:8 pin_bit (c 8 7))))) in
    (* MBX: channel 0..3 is an inbox, 4..7 a port *)
    let recv = flag instr 11 and ch = field instr 10 8 in
    let to_port = bit ch 2 and slot = extract ch ~hi:1 ~lo:0 in
    let is_mbx = is opc op_mbx in
    let is_send = and_ is_mbx (not_ recv) and is_recv = and_ is_mbx recv in
    let full_at i = eq (select ~w:2 st.full i) (c 1 1) in
    let send_ok, recv_ok, recv_byte = unless_false is_mbx (ff, ff, acc) (fun () ->
        ite_b to_port (select_b ~w:2 io.port_out_ready slot) (not_ (full_at slot)),
        ite_b to_port (select_b ~w:2 io.port_in_valid slot) (full_at slot),
        ite to_port (select ~w:2 io.port_in slot) (select ~w:2 st.inbox slot)) in
    (* WAITC *)
    let ls = st.lsend.(t) in
    let is_waitc = is opc op_waitc in
    let holds = unless_false is_waitc ff (fun () ->
        let cond = field instr 11 8 in
        let ls_slot = extract ls ~hi:1 ~lo:0 in
        let space = ite_b (bit ls 2) (select_b ~w:2 io.port_out_ready ls_slot) (not_ (full_at ls_slot)) in
        let is_cond k = eq cond (c 4 k) in
        ite_b (ult cond (c 4 8)) (bit_at ~w:8 acc (extract cond ~hi:2 ~lo:0))
          (ite_b (is_cond c_byte) (eq (extract cnt ~hi:2 ~lo:0) (c 3 0))
             (ite_b (is_cond c_host) io.host_in_valid
                (ite_b (is_cond c_inbox) (eq st.full.(t) (c 1 1))
                   (ite_b (is_cond c_space) space
                      (bit (lshr io.flags (zext ~w:16 (extract cond ~hi:1 ~lo:0))) (4 * t))))))) in
    (* EXT *)
    let is_ext = is opc op_ext in
    let ext_sub = field instr 11 8 in
    let x k = and_ is_ext (eq ext_sub (c 4 k)) in
    let skip = unless_false is_ext ff (fun () ->
        or_ (and_ (x x_skne) (not_ (eq acc imm8))) (and_ (x x_skeq) (eq acc imm8))) in
    let bp = st.bps.(t) in
    let pin_write = or_ (is opc op_setp) is_sho in
    (* next state *)
    (* Each next value is a chain [ite s1 v1 @@ ite s2 v2 @@ ... @@ default]: v1 where s1 holds,
       else v2 where s2 holds, ..., else the default. *)
    let is_waitp = is opc op_waitp in
    let pc_next =
      ite is_waitp (unless_false is_waitp pc (fun () ->
          ite (eq (of_b (pin_at pin)) (field instr 8 8)) pc1 fail_or_stay)) @@
      ite (is opc op_waitd) (ite dl_zero pc1 pc) @@
      ite (is opc op_jmp) addr @@
      ite (is opc op_jnz) (ite (eq cnt (c 12 0)) pc1 addr) @@
      ite (is opc op_in) (ite io.host_in_valid pc1 pc) @@
      ite is_mbx (ite (ite_b recv recv_ok send_ok) pc1 fail_or_stay) @@
      ite is_waitc (ite holds pc1 fail_or_stay) @@
      ite skip (add ~w:8 pc (c 8 2)) @@
      pc1 in
    let is_ldb = x x_ldb in
    let acc_next =
      ite (is opc op_lda) imm8 @@
      ite is_sho sho_acc @@
      ite (is opc op_shi) shi_acc @@
      ite (is opc op_in) (ite io.host_in_valid io.host_in acc) @@
      ite is_recv (ite recv_ok recv_byte acc) @@
      ite is_ldb (unless_false is_ldb acc (fun () -> mem_read st.bankmem bp)) @@
      acc in
    let cnt_dec = sub ~w:12 cnt (c 12 1) in
    let cnt_next =
      ite (is opc op_ldc) imm12 @@
      ite is_sho cnt_dec @@
      ite (is opc op_shi) cnt_dec @@
      ite (x x_cnta) (zext ~w:12 acc) @@
      cnt in
    let dl_next = ite (is opc op_ldd) imm12 (ite dl_zero (c 12 0) (sub ~w:12 dl (c 12 1))) in
    let is_setp = is opc op_setp in
    let setp_out, setp_oe = unless_false is_setp (st.pin_out, st.pin_oe) (fun () ->
        set_masked st.pin_out setv, set_masked st.pin_oe seto) in
    let pin_out_next = ite is_setp setp_out @@ ite is_sho (fst sho_pins) @@ st.pin_out in
    let pin_oe_next = ite is_setp setp_oe @@ ite is_sho (snd sho_pins) @@ st.pin_oe in
    let sub_q = ite is_setp q @@ ite is_sho (ite od (c 2 0) q) @@ c 2 0 in
    let inbox_next = unless_false is_mbx st.inbox (fun () -> Array.mapi (fun k v ->
        ite (and_ (and_ is_send (not_ to_port)) (and_ (eq slot (c 2 k)) (not_ (full_at slot)))) acc v) st.inbox) in
    let full_next = unless_false is_mbx st.full (fun () -> Array.mapi (fun k v ->
        let here = and_ (not_ to_port) (eq slot (c 2 k)) in
        ite (and_ is_send here) (c 1 1) (ite (and_ is_recv here) (c 1 0) v)) st.full) in
    let bp_next = unless_false is_ext bp (fun () ->
        ite (or_ is_ldb (x x_stb)) (add ~w:10 bp (c 10 1)) @@
        ite (x x_bank) (logor (shl ~w:10 (zext ~w:10 (extract imm8 ~hi:1 ~lo:0)) (c 10 8)) (zext ~w:10 acc)) @@
        bp) in
    let armed = eq st.armed.(t) (c 1 1) in
    let effects =
      { host_out = (is opc op_out, field instr 10 8, ite (flag instr 11) imm8 acc);
        host_in_ready = and_ (is opc op_in) io.host_in_valid;
        port_pop = (unless_false is_mbx ff (fun () ->
            and_ (and_ is_recv to_port) (select_b ~w:2 io.port_in_valid slot)), slot);
        port_push = (unless_false is_mbx ff (fun () ->
            and_ (and_ is_send to_port) (select_b ~w:2 io.port_out_ready slot)), slot, acc);
        bank_write = (x x_stb, bp, acc);
        bank_read = (is_ldb, bp);
        fine_out = (and_ pin_write armed, st.fines.(t));
        pins_written =
          ite is_setp mask8 @@
          ite is_sho (unless_false is_sho (c 8 0) (fun () ->
              logor (onehot pin) (ite pair (onehot (add ~w:3 pin (c 3 1))) (c 8 0)))) @@
          c 8 0 } in
    (* commit *)
    st.bankmem <- unless_false (x x_stb) st.bankmem (fun () -> mem_write st.bankmem (x x_stb) bp acc);
    st.pin_sub <- sub_of ~old_:st.pin_out ~new_:pin_out_next ~q:sub_q;
    st.pin_out <- pin_out_next; st.pin_oe <- pin_oe_next; st.latch <- latch;
    if inbox_next != st.inbox then Array.blit inbox_next 0 st.inbox 0 n_threads;
    if full_next != st.full then Array.blit full_next 0 st.full 0 n_threads;
    st.lsend.(t) <- ite is_send ch ls;
    st.fines.(t) <- ite (x x_fine) imm8 st.fines.(t);
    st.armed.(t) <- ite (x x_fine) (c 1 1) (ite pin_write (c 1 0) st.armed.(t));
    st.cfgs.(t) <- ite (x x_cfg) imm8 st.cfgs.(t);
    st.bps.(t) <- bp_next;
    st.pcs.(t) <- pc_next; st.accs.(t) <- acc_next; st.cnts.(t) <- cnt_next; st.dls.(t) <- dl_next;
    (match io.host_ctl with
     | Some (ht, pg, hpc) -> st.pages.(ht) <- extract pg ~hi:1 ~lo:0; st.pcs.(ht) <- extract hpc ~hi:7 ~lo:0
     | None -> ());
    st.thread <- (t + 1) mod n_threads;
    effects
  (* END copy of Make's body *)
end

type state = Spec.state   (* (int, int array) state_of *)

(* [boot]: each thread's (page, pc) after reset, set by the host *)
let init ?(boot = Array.make n_threads (0, 0)) ?bank () =
  Spec.reset ~boot ~bank:(match bank with Some b -> Array.copy b | None -> Array.make bank_len 0)

let copy = Spec.copy

type io = Spec.io         (* (int, bool) io_of *)

let sub_of = Spec.sub_of

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
  bank_read : int option;               (* address read by LDB *)
  fine_out : int option;
}

let fetch_addr = Spec.fetch_addr
let fetch st ~(mem : int array) t = mem.(fetch_addr st t)

(* [step_f] reads the store through [fetch] (a function of the 10-bit address), so a programme
   can be translated word by word as it is fetched (compat.ml); [step] reads an array. *)
let rec step st ~(mem : int array) (io : io) = step_f st ~fetch:(Array.get mem) io

and step_f st ~(fetch : int -> int) (io : io) =
  let (e : Spec.effects) = Spec.exec st ~instr:(fetch (fetch_addr st st.thread)) io in
  let opt (v, x) = if v then Some x else None in
  let opt2 (v, x, y) = if v then Some (x, y) else None in
  { host_out = opt2 e.host_out; host_in_ready = e.host_in_ready; port_pop = opt e.port_pop;
    port_push = opt2 e.port_push; bank_write = opt2 e.bank_write;
    bank_read = opt e.bank_read; fine_out = opt e.fine_out }

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
