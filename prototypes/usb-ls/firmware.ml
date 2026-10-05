(* Low-speed USB device firmware for the deadline sequencer.

   T0, the bit layer, uses only the original instruction set and fits the original 64 words:
   it follows the line with deadline waits, recovers the bit clock from every edge (a software
   DPLL), decodes NRZI, drops stuff bits, suppresses the sync pattern, detects EOP and bus
   reset, and publishes each bit as VALUE plus a rising edge on STB, with BUSY high during a
   packet. An EOP is a strobe with BUSY low and VALUE 0; a stuff error is the same with VALUE 1.

   T1 answers IN tokens (data from the reply FIFO, NAK or STALL) and reports the host's ACK.
   T2 handles SETUP and OUT transactions: it forwards the data to the controller, checks the
   CRC through the assist and replies ACK or STALL. T3 is free for the application.
   T1 and T2 listen to the same bits; each ignores packets that are not its business.

   Everything protocol-specific that can be computed ahead is: the reply waveforms are symbol
   streams precomputed by the controller (fw_codec.ml); the token checks compare the received
   bytes with precomputed bytes (address, endpoint and CRC5 included), which the controller
   patches into the programme when the address changes; the reply choices per state are JMP
   targets the controller patches.

   Timing, in slots (one slot = one instruction of one thread = 4 clocks at 60 MHz; a low-speed
   bit is 10 slots). LDD n at slot u makes dl reach 0 at slot u + 1 + n, where a WAITD proceeds
   or a waiting WAITP gives up. *)

open Asm
module I = Isa_ls

let p_dp = Fw_sys.p_dp and p_dm = Fw_sys.p_dm and p_value = Fw_sys.p_value and p_stb = Fw_sys.p_stb
let p_idle = Fw_sys.p_idle and p_crc_en = Fw_sys.p_crc_en and p_crc_ok = Fw_sys.p_crc_ok and p_rdy = Fw_sys.p_rdy
let bit n = 1 lsl n

(* events to the controller *)
let ev_reset = 1 and ev_sent = 2 and ev_ack = 3 and ev_setup = 4 and ev_out = 5 and ev_ok = 6 and ev_bad = 7
let ev_out1 = 8 and ev_data = 9

(* ---------------- T0: the bit layer ---------------- *)

type t0_cfg = {
  zero : int;          (* LDD after an edge: the next sample 1.5 bits after it *)
  one : int;           (* LDD after a one: the next sample one bit later *)
  late : int;          (* LDD after an edge that came while a one was being published *)
  reset_slots : int;   (* SE0 this long after it is seen is a bus reset *)
  jk_swap : bool;      (* control: full-speed polarity *)
  stock_events : bool; (* LDA+OUT instead of the OUT event mode, for the original ISA *)
}

(* Slot arithmetic (s: the slot whose WAITP saw the edge, about one slot after it; f: the slot
   whose WAITP gave up at the deadline, the sample point):
   - after an edge, LDD at s+4, sample at s+14: 1.5 bits after the edge, the middle of the
     next bit. The path back to the edge wait is 8 slots (9 from K), shorter than a bit even
     for a host 1.5 % fast (9.85 slots), so every edge is timed by a waiting WAITP;
   - after a one, LDD at f+6, sample at f+10;
   - an edge that arrives while a one is being published is not timed: the line was still at
     its old level at the sample (f) and has changed by the check at f+5, so the edge is taken
     to be in the middle of that window (f+2), and LDD at f+8 puts the next sample at f+17.
     This pulls a sample point that has drifted late back towards the middle of the bit.
   Three earlier versions failed the random tests with the host 1 % fast: one published a one
   in 7 slots and let the late detection feed into the next sample point, so alternating bits
   walked it off the end of the bit; one took a full bit (10 slots) to come back from a zero,
   so in a run of zeros it never timed an edge at all; one took an untimed edge to be at its
   nominal place, which kept a late sample point late, and long runs of ones with stuff bits
   (0xFF bytes) then drifted it out of the bit. *)
let t0_default = { zero = 9; one = 3; late = 8; reset_slots = 40; jk_swap = false; stock_events = false }

let t0 ?(cfg = t0_default) () =
  let dp, dm = if cfg.jk_swap then p_dm, p_dp else p_dp, p_dm in
  let setp m v = i (I.setp ~mask:m ~value:v ~oe:1) in
  let waitp p v l = (fun a -> I.waitp ~pin:p ~value:v ~fail:a) @@@ l in
  let jmp l = I.jmp @@@ l and jnz l = I.jnz @@@ l in
  let ev e = if cfg.stock_events then [ i (I.lda e); i I.out ] else [ i (I.oute e) ] in
  let vs = bit p_value lor bit p_stb in
  [ L "init"; setp (bit p_idle) 1;
    (* idle at J: D- falls for a SOP (to K) or for SE0 (keep-alive or reset); both are sorted
       out as an edge from J *)
    L "iw"; waitp dm 0 "iw"; jmp "zj";
    (* ---- line at J ---- *)
    (* a one: publish it (VALUE and a rising STB), then check the stuff count *)
    L "one_j"; setp (bit p_stb) 0; setp vs 1; jnz "one_j2";
    (* seventh one: stuff error. Keep VALUE 1, wait for the SE0, and end the packet with it:
       an end of packet with VALUE 1 is an abort *)
    L "stufferr"; setp (bit p_value lor bit p_idle) 1; setp (bit p_stb) 0;
    L "se"; waitp dp 0 "se"; waitp dm 0 "se"; jmp "eop2";
    L "one_j2"; i (I.shi ~pin:0 ~msb:0); waitp dm 1 "late_j"; i (I.ldd cfg.one);
    L "wj"; waitp dm 0 "one_j";
    (* D- fell: K (a zero or a stuff bit), or SE0 (end of packet) *)
    L "zj"; i (I.ldd 0); waitp dp 1 "eop"; setp (vs lor bit p_idle) 0; i (I.ldd cfg.zero);
    L "zjc"; jnz "zj2";
    i (I.ldc 6); jmp "wk";                       (* a stuff bit: not published *)
    L "zj2"; setp (bit p_stb) 1; i (I.ldc 6);
    (* ---- line at K ---- *)
    L "wk"; waitp dp 0 "one_k";
    L "zk"; i (I.ldd 0); waitp dm 1 "eop"; setp vs 0; i (I.ldd cfg.zero);
    L "zkc"; jnz "zk2";
    i (I.ldc 6); jmp "wj";
    L "zk2"; setp (bit p_stb) 1; i (I.ldc 6); jmp "wj";
    L "one_k"; setp (bit p_stb) 0; setp vs 1; jnz "one_k2"; jmp "stufferr";
    L "one_k2"; i (I.shi ~pin:0 ~msb:0); waitp dp 1 "late_k"; i (I.ldd cfg.one); jmp "wk";
    (* an edge during the publication of a one *)
    L "late_j"; waitp dp 1 "eop"; setp (vs lor bit p_idle) 0; i (I.ldd cfg.late); jmp "zjc";
    L "late_k"; waitp dm 1 "eop"; setp vs 0; i (I.ldd cfg.late); jmp "zkc";
    (* end of packet: IDLE rises, then STB falls and stays low for six slots, then a strobe
       with VALUE low. A byte reader notices IDLE during the low; a token checker waits for the
       strobe. The long low matters: a consumer that has just finished a byte is busy for
       several slots, and a one-slot low here was missed (the host's ACK after a SETUP was
       then not seen). SE0 for longer than [reset_slots] is a bus reset. *)
    L "eop"; setp (bit p_idle) 1; setp vs 0;
    L "eop2"; i (I.ldd 3); i I.waitd; setp (bit p_stb) 1;
    L "ew"; i (I.ldd cfg.reset_slots); waitp dm 1 "rst";
    L "ew2"; setp (bit p_stb) 0; jmp "iw";
    L "rst" ] @ ev ev_reset @ [ L "rw"; waitp dm 1 "rw"; jmp "ew2" ]

(* ---------------- shared pieces for T1 and T2 ---------------- *)

let waitp p v l = (fun a -> I.waitp ~pin:p ~value:v ~fail:a) @@@ l
let jmp l = I.jmp @@@ l and jnz l = I.jnz @@@ l

(* skip the published sync bits (zeros) up to the first one; [arm] runs on it; a packet that
   ends first goes to [gone] *)
let sync_skip ~gone ~arm =
  let s = fresh "sync" and z = fresh "syncz" and k = fresh "synck" in
  [ L s; waitp p_stb 1 s; waitp p_idle 0 gone; waitp p_value 1 z ] @ arm
  @ [ jmp k; L z; waitp p_stb 0 z; jmp s; L k ]

(* Read one byte, LSB first. Each bit is STB low, then high. The end of the packet is IDLE
   high during a low, which jumps to [e]. After seeing a bit's strobe the loop does only SHI
   and JNZ, so it leaves a byte 3.5 slots after the strobe; the next strobe can come 9 slots
   after the last (a host 1.5 % fast), which leaves 4 instructions for the caller's work
   between bytes (storing the byte, a compare, the next LDC) before it must be back waiting for
   the low. Two earlier versions had more work per bit or per byte and lost the first bit of a
   byte when the next strobe came quickly. [rb_body] is the loop without its LDC, so that a
   caller can load the counter before its compares. *)
let rb_body e =
  let l = fresh "rb" and l2 = fresh "rb2" in
  [ L l2; waitp p_stb 0 l2; waitp p_idle 0 e; L l; waitp p_stb 1 l; i (I.shi ~pin:p_value ~msb:0); jnz l2 ]

let rb e = i (I.ldc 8) :: rb_body e

(* the next strobe must be a clean end of packet *)
let eopchk ~more ~abort =
  let l = fresh "eop" and l0 = fresh "eop0" in
  [ L l0; waitp p_stb 0 l0; L l; waitp p_stb 1 l; waitp p_idle 1 more; waitp p_value 0 abort ]

(* a compare whose immediate the controller patches, under a label *)
let skne_p label imm target = [ L label; i (I.skne imm); jmp target ]

(* Transmitting. The caller has set the deadline; at it the line is driven J (D- first, so the
   line never leaves J), and the first symbol follows two slots later. Symbols come four to a
   byte from immediates (handshakes) or from the reply FIFO (data), one every 10 slots. *)
let drive_j = [ i (I.setp ~mask:(bit p_dm) ~value:1 ~oe:1); i (I.setp ~mask:(bit p_dp) ~value:0 ~oe:1) ]
let release = i (I.setp ~mask:(bit p_dp lor bit p_dm) ~value:0 ~oe:0)
let sho2 = i (I.sho ~pair:1 ~pin:p_dp ~msb:0 ())

let handshake ~label ~after ?jk_swap pid =
  match Fw_codec.reply ?jk_swap [ pid ] with
  | [] -> assert false
  | b0 :: rest ->
    let l0 = fresh "hs" in
    [ L label; i (I.lda b0); i (I.ldc 4); i I.waitd ] @ drive_j @ [ sho2; i (I.ldd 7); jnz l0;
      L l0; i I.waitd; sho2; i (I.ldd 7); jnz l0 ]
    @ List.concat_map (fun b -> let l = fresh "hs" in [ i (I.lda b); i (I.ldc 4); L l; i I.waitd; sho2; i (I.ldd 7); jnz l ]) rest
    @ [ i I.waitd; release; jmp after ]

(* J-drive happens [drive] slots after the EOP strobe is seen. The host releases the bus three
   of its bits after its SE0 begins, about 1.9 bits (19 slots) after we see the EOP; 23 leaves
   margin for a host 1.5 % slow. The first K then follows 2 slots and 1 to 4 pad symbols later:
   2.5 to 5.5 bit times after the host's EOP, inside the 2 to 6.5 the specification allows. *)
type t12_cfg = { drive : int; data_timeout : int; skip_crc : bool; jk_swap12 : bool }
let t12_default = { drive = 23; data_timeout = 120; skip_crc = false; jk_swap12 = false }

(* ---------------- T1: IN tokens and the host's ACK ---------------- *)

let t1 ?(cfg = t12_default) () =
  (* EOPCHK success is slot 0; after it: WAITP RDY (3), LDD (4), JMP (5), IN/LDA, LDC, WAITD ->
     J-drive (SETP) at 4 + v + 2 *)
  let v = cfg.drive - 6 in
  let in_ep ep =
    let e = Printf.sprintf "ti%d" ep and ee = Printf.sprintf "ti%de" ep and nr = Printf.sprintf "nr%d" ep in
    [ L e ] @ rb_body "idle1" @ skne_p (Printf.sprintf "p_ic%d" ep) 0 ee @ [ jmp "drain1" ]
    @ [ L ee ] @ eopchk ~more:"drain1" ~abort:"idle1"
    @ [ waitp p_rdy 1 nr; i (I.ldd v); L (Printf.sprintf "p_ep%d_rdy" ep); jmp "send_nak";
        L nr; i (I.ldd v); L (Printf.sprintf "p_ep%d_nr" ep); jmp "send_nak" ] in
  (* T1 also owns the CRC assist: it clears it at every SOP and arms it right after every PID,
     so the CRC covers what follows the PID. Only a data packet leaves it armed to its end,
     where T2 reads CRC_OK; any other PID disarms it, so a packet whose PID is not DATA0/1
     can never show a good CRC. That is T2's PID check, done in time. *)
  let en v = i (I.setp ~mask:(bit p_crc_en) ~value:v ~oe:1) in
  [ L "init"; release;
    L "idle1"; waitp p_idle 0 "idle1"; en 0 ] @ sync_skip ~gone:"idle1" ~arm:[] @ rb "idle1"
  @ [ en 1; i (I.ldc 8); i (I.skne ~inv:1 0x69); jmp "notin";
      (* IN token: address and endpoint bit *)
      L "tin" ] @ rb_body "idle1"
  @ [ i (I.ldc 8) ] @ skne_p "p_ia0" 0 "ti0" @ skne_p "p_ia1" 0x80 "ti1" @ [ jmp "drain1" ]
  @ in_ep 0 @ in_ep 1
  @ [ L "notin"; i (I.skne 0xD2); jmp "gack"; i (I.skne 0xC3); jmp "dkeep"; i (I.skne 0x4B); jmp "dkeep";
      L "drain1"; en 0; L "d1"; waitp p_idle 1 "d1"; jmp "idle1";
      L "dkeep"; waitp p_idle 1 "dkeep"; jmp "idle1";
      L "gack" ] @ eopchk ~more:"drain1" ~abort:"idle1" @ [ i (I.oute ev_ack); jmp "idle1" ]
  @ [ L "send_data"; i I.in_; i (I.ldc 4); i I.waitd ] @ drive_j @ [ sho2; i (I.ldd 7); jnz "dl";
      L "dloop"; i I.in_; i (I.skne Fw_codec.terminator); jmp "dend"; i (I.ldc 4);
      L "dl"; i I.waitd; sho2; i (I.ldd 7); jnz "dl"; jmp "dloop";
      L "dend"; i I.waitd; release; i (I.oute ev_sent); jmp "idle1" ]
  @ handshake ~label:"send_nak" ~after:"idle1" ~jk_swap:cfg.jk_swap12 0x5A
  @ handshake ~label:"send_stall" ~after:"idle1" ~jk_swap:cfg.jk_swap12 0x1E

(* ---------------- T2: SETUP and OUT ---------------- *)

let t2 ?(cfg = t12_default) () =
  (* The forwarder learns of the end of the packet when IDLE rises during the low before the
     end strobe, about five slots before a token checker sees the strobe; its handler then
     needs WAITP VALUE, WAITP CRC_OK, the OUT event, LDD: J-drive at 3.5 + 3 + v + 2 slots
     after the low, which puts it with T1's (the strobe is 5 slots after the low, T1 drives 23
     after seeing it). *)
  let v = cfg.drive - 2 in
  let crc_check bad = if cfg.skip_crc then [] else [ waitp p_crc_ok 1 bad ] in
  (* the second token byte (endpoint high bits and CRC5), end of packet, then the event *)
  let tail ~l ~p_c ~ev =
    let c = fresh "tail" in
    [ L l ] @ rb_body "w2" @ skne_p p_c 0 c @ [ jmp "drain2"; L c ] @ eopchk ~more:"drain2" ~abort:"w2"
    @ [ i (I.oute ev); jmp "data" ] in
  (* One data path for all three tokens. The token's event reaches the controller while the
     data packet is still arriving (at least 32 bit times, 1,280 clocks), in time for it to
     patch the handshake: ACK after SETUP; ACK or STALL after OUT to endpoint 0 by the state
     of the control transfer; STALL after OUT to endpoint 1, which has no OUT direction. *)
  [ L "init";
    L "w2"; waitp p_idle 0 "w2" ] @ sync_skip ~gone:"w2" ~arm:[] @ rb "w2"
  @ [ i (I.ldc 8); i (I.skne 0x2D); jmp "ts"; i (I.skne 0xE1); jmp "to";
      L "drain2"; waitp p_idle 1 "drain2"; jmp "w2";
      L "bad2"; i (I.oute ev_bad); jmp "w2";
      L "ts" ] @ rb_body "w2" @ [ i (I.ldc 8) ] @ skne_p "p_sa0" 0 "s_b2" @ [ jmp "drain2" ]
  @ tail ~l:"s_b2" ~p_c:"p_sc0" ~ev:ev_setup
  @ [ L "to" ] @ rb_body "w2" @ [ i (I.ldc 8) ] @ skne_p "p_oa0" 0 "o0_b2" @ skne_p "p_oa1" 0x80 "o1_b2" @ [ jmp "drain2" ]
  @ tail ~l:"o0_b2" ~p_c:"p_oc0" ~ev:ev_out
  @ tail ~l:"o1_b2" ~p_c:"p_oc1" ~ev:ev_out1
  (* the data packet: wait for its SOP; the PID is forwarded as the first byte (T1 checks it
     through the CRC assist) *)
  @ [ L "data"; i (I.ldd cfg.data_timeout); waitp p_idle 0 "w2"; i (I.ldd 0) ]
  @ sync_skip ~gone:"w2" ~arm:[ i (I.oute ev_data) ] @ [ i (I.ldc 8); L "fwd" ] @ rb_body "fwd_e"
  @ [ i I.out; i (I.ldc 8); jmp "fwd";
      L "fwd_e"; waitp p_value 0 "bad2" ] @ crc_check "bad2"
  @ [ i (I.oute ev_ok); i (I.ldd v); L "p_hs"; jmp "send_ack" ]
  @ handshake ~label:"send_ack" ~after:"w2" ~jk_swap:cfg.jk_swap12 0xD2
  @ handshake ~label:"send_stall2" ~after:"w2" ~jk_swap:cfg.jk_swap12 0x1E

let t3 = [ L "t3"; i I.halt ]

type images = { mem : int array array; p0 : prog; p1 : prog; p2 : prog }

let build ?t0cfg ?t12cfg () =
  let p0 = assemble (t0 ?cfg:t0cfg ()) and p1 = assemble (t1 ?cfg:t12cfg ()) and p2 = assemble (t2 ?cfg:t12cfg ()) in
  let p3 = assemble t3 in
  { mem = [| Array.copy p0.words; Array.copy p1.words; Array.copy p2.words; Array.copy p3.words |]; p0; p1; p2 }
