(* Mechanical translation of programmes for the earlier ISA variants into ISA v2, one word at a
   time. Each translator is a function of the word and its own address only, so it can run at
   fetch time: firmware that patches its own words at run time (usb-ls's controller does) still
   runs, and the programme arrays the old test benches build are used as they are.

   What each translation does, and why it is exact where the variant's programme stays within
   its store:
   - base (../deadline-sequencer/isa.ml, 6-bit pc, quarter-clock bits): HALT becomes JMP to its
     own address (same behaviour: the thread stays, every slot); opcodes E and F (NOP in the base)
     become NOP; fields the base ignores are cleared (WAITP/JMP/JNZ address bits 7..6, SHO bits
     6..2, SHI bits 6..0, all of OUT, IN and WAITD's operand bits), because v2 gives several of
     them a meaning. The one inexactness: the base pc wraps at 64, v2's at 256, so a programme
     that runs off its last word behaves differently; no firmware here does (all end in HALT or
     a jump).
   - wide (../proto-jtag-swd/wide, 8-bit pc, no quarter-clock bits): as base, with 8-bit address
     fields, and SETP/SHO bits 1..0 and SHI bit 7 cleared (the wide variant predates them).
   - usb-ls (../usb-ls/isa_ls.ml, 8-bit pc): as wide, and SKNE (E, inv[8]) becomes EXT SKNE or
     SKEQ; SHO's pair bit 6 becomes pair + psel 1 (two accumulator bits); OUT's event bit 8
     becomes OUT src 1 tag 1 (the host sees tag <> 0 where usb-ls had its event flag). *)

let amask pc_bits = (1 lsl pc_bits) - 1

let of_base ?(quarter = true) ~pc_bits ~addr w =
  let m = amask pc_bits in
  match (w lsr 12) land 15 with
  | 0 -> 0
  | 1 -> if quarter then w else w land 0xFFFC
  | 2 | 3 -> w
  | 4 -> w land 0xF0FF
  | 5 -> (w land 0xFF00) lor (w land m)
  | 6 -> 0x6000
  | 7 -> if quarter then w land 0xFF83 else w land 0xFF80
  | 8 -> if quarter then w land 0xFF80 else w land 0xFF00
  | 9 | 10 -> (w land 0xF000) lor (w land m)
  | 11 -> 0xB000
  | 12 -> 0xC000
  | 13 -> Isa2.halt_at addr
  | _ -> 0

let of_wide ~addr w = of_base ~quarter:false ~pc_bits:8 ~addr w

let of_ls ~addr w =
  match (w lsr 12) land 15 with
  | 7 -> (w land 0xFF80) lor (if (w lsr 6) land 1 = 1 then 0x60 else 0)
  | 11 -> if (w lsr 8) land 1 = 1 then Isa2.outi ~tag:1 (w land 0xFF) else 0xB000
  | 14 -> if (w lsr 8) land 1 = 1 then Isa2.skeq (w land 0xFF) else Isa2.skne (w land 0xFF)
  | 15 -> 0
  | _ -> of_wide ~addr w

(* The old benches give each thread its own programme array; v2 has one store addressed by
   {page, pc}. Thread t boots at page t, pc 0, so {page, pc} = {t, pc}: the same address the old
   cores presented, {thread, pc}. A pc beyond the old array reads NOP. *)
let boot_by_thread = Array.init Isa2.n_threads (fun t -> (t, 0))

let fetch_threads ~translate (mem : int array array) a =
  let t = a lsr Isa2.pc_bits and pc = a land (Isa2.page_len - 1) in
  if pc < Array.length mem.(t) then translate ~addr:pc mem.(t).(pc) else 0

(* Pack several programmes into one store at chosen pages and offsets: a programme assembled for
   address 0 is relocated by adding [base] to every address field (WAITP, JMP, JNZ, MBX, WAITC).
   Used to show that a mix fits in the 512-word macro. *)
let relocate ~base w =
  let op = (w lsr 12) land 15 in
  if op = Isa2.op_waitp || op = Isa2.op_jmp || op = Isa2.op_jnz || op = Isa2.op_mbx || op = Isa2.op_waitc
  then (w land 0xFF00) lor (((w land 0xFF) + base) land 0xFF)
  else w

(* sequencer-ps2-can's variant v (../sequencer-ps2-can/isa_v.ml): as wide, except that OUT
   already has v2's layout (src[11] tag[10:8] imm[7:0]) and is kept. Its per-thread CRC engine,
   stuff tracker, JC and CFG were rejected for v2 (notes/architecture-v0.md section 2.1), so a word
   that uses them has no translation: [of_v] raises, which makes a programme that needs them fail
   loudly instead of running something else. *)
exception Untranslatable of int * int

let of_v ~addr w =
  match (w lsr 12) land 15 with
  | 7 -> if (w lsr 5) land 3 <> 0 then raise (Untranslatable (addr, w)) else of_wide ~addr w
  | 8 -> if (w lsr 4) land 7 <> 0 then raise (Untranslatable (addr, w)) else of_wide ~addr w
  | 11 -> w
  | 14 | 15 -> raise (Untranslatable (addr, w))
  | _ -> of_wide ~addr w
