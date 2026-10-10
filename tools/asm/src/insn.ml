(* ISA v2 instructions as values: decoded from a word, encoded through Isa2's own encoder
   functions (../../prototypes/sequencer-v2/isa2.ml), printed as assembly. The assembler and the
   disassembler share this module, so a printed instruction always reassembles to its word.

   A word is *canonical* when [encode (decode w) = w]. The words that are not canonical are
   exactly those with a bit set that the instruction ignores (LDA bits 11..8, SHO bits 3..2, ...);
   the disassembler prints them as ".word". *)

type t =
  | Nop
  | Setp of { mask : int; v : int; oe : int; q : int }
  | Ldc of int
  | Ldd of int
  | Lda of int
  | Waitp of { pin : int; v : int; fail : int }
  | Waitd
  | Sho of { pin : int; msb : bool; od : bool; pair : bool; psel : bool; cap : bool; q : int }
  | Shi of { pin : int; msb : bool; quad : bool }
  | Jmp of int
  | Jnz of int
  | Out of { tag : int }                   (* src 0: the accumulator *)
  | Outi of { tag : int; v : int }         (* src 1: the immediate *)
  | In
  | Send of { ch : int; fail : int }
  | Recv of { ch : int; fail : int }
  | Waitc of { cond : int; fail : int }
  | Ext of { sub : int; imm : int }        (* SKNE, SKEQ, FINE, CNTA, LDB, STB, BANK, CFG, reserved *)

let b2i b = if b then 1 else 0

let encode = function
  | Nop -> Isa2.nop
  | Setp { mask; v; oe; q } -> Isa2.setp ~q ~mask ~value:v ~oe ()
  | Ldc n -> Isa2.ldc n
  | Ldd n -> Isa2.ldd n
  | Lda n -> Isa2.lda n
  | Waitp { pin; v; fail } -> Isa2.waitp ~pin ~value:v ~fail
  | Waitd -> Isa2.waitd
  | Sho { pin; msb; od; pair; psel; cap; q } ->
    Isa2.sho ~od:(b2i od) ~pair:(b2i pair) ~psel:(b2i psel) ~cap:(b2i cap) ~q ~pin ~msb:(b2i msb) ()
  | Shi { pin; msb; quad } -> Isa2.shi ~quad:(b2i quad) ~pin ~msb:(b2i msb) ()
  | Jmp a -> Isa2.jmp a
  | Jnz a -> Isa2.jnz a
  | Out { tag } -> Isa2.out ~tag ()
  | Outi { tag; v } -> Isa2.outi ~tag v
  | In -> Isa2.in_
  | Send { ch; fail } -> Isa2.send ~ch ~fail
  | Recv { ch; fail } -> Isa2.recv ~ch ~fail
  | Waitc { cond; fail } -> Isa2.waitc ~cond ~fail
  | Ext { sub; imm } -> Isa2.ext sub imm

let field w lo n = (w lsr lo) land ((1 lsl n) - 1)
let flag w b = (w lsr b) land 1 = 1

let decode w =
  let f = w land 0xFFF in
  match field w 12 4 with
  | 0 -> Nop
  | 1 -> Setp { mask = field f 4 8; v = field f 3 1; oe = field f 2 1; q = field f 0 2 }
  | 2 -> Ldc f
  | 3 -> Ldd f
  | 4 -> Lda (field f 0 8)
  | 5 -> Waitp { pin = field f 9 3; v = field f 8 1; fail = field f 0 8 }
  | 6 -> Waitd
  | 7 -> Sho { pin = field f 9 3; msb = flag f 8; od = flag f 7; pair = flag f 6; psel = flag f 5;
               cap = flag f 4; q = field f 0 2 }
  | 8 -> Shi { pin = field f 9 3; msb = flag f 8; quad = flag f 7 }
  | 9 -> Jmp (field f 0 8)
  | 10 -> Jnz (field f 0 8)
  | 11 -> if flag f 11 then Outi { tag = field f 8 3; v = field f 0 8 } else Out { tag = field f 8 3 }
  | 12 -> In
  | 13 -> if flag f 11 then Recv { ch = field f 8 3; fail = field f 0 8 } else Send { ch = field f 8 3; fail = field f 0 8 }
  | 14 -> Waitc { cond = field f 8 4; fail = field f 0 8 }
  | _ -> Ext { sub = field f 8 4; imm = field f 0 8 }

let canonical w = encode (decode w) = w

(* ---- names ---- *)

let cond_names = [ "acc0", 0; "acc1", 1; "acc2", 2; "acc3", 3; "acc4", 4; "acc5", 5; "acc6", 6; "acc7", 7;
                   "byte", 8; "host", 9; "inbox", 10; "space", 11;
                   "flag0", 12; "flag1", 13; "flag2", 14; "flag3", 15 ]
let chan_names = [ "inbox0", 0; "inbox1", 1; "inbox2", 2; "inbox3", 3; "port0", 4; "port1", 5; "port2", 6; "port3", 7 ]
let ext_names = [ "skne", 0; "skeq", 1; "fine", 2; "cnta", 3; "ldb", 4; "stb", 5; "bank", 6; "cfg", 7 ]
let ext_takes_imm = function 0 | 1 | 2 | 6 | 7 -> true | 3 | 4 | 5 -> false | _ -> true

let name_of l v = fst (List.find (fun (_, x) -> x = v) l)

(* the address fields of an instruction (branch target or fail target), for labels *)
let targets = function
  | Waitp { fail; _ } | Send { fail; _ } | Recv { fail; _ } | Waitc { fail; _ } -> [ fail ]
  | Jmp a | Jnz a -> [ a ]
  | _ -> []

(* Assembly text. [target pc a] names address [a] as seen from the instruction at [pc]: a label,
   "." for the instruction itself, or a number. *)
let to_asm ?(target = fun pc a -> if a = pc then "." else Printf.sprintf "%d" a) ~pc i =
  let t = target pc in
  let pr = Printf.sprintf in
  let opt b s = if b then ", " ^ s else "" in
  let q n = if n = 0 then "" else pr ", q=%d" n in
  match i with
  | Nop -> "nop"
  | Setp { mask; v; oe; q = qq } -> pr "setp 0x%02x, %d, %d%s" mask v oe (q qq)
  | Ldc n -> pr "ldc %d" n
  | Ldd n -> pr "ldd %d" n
  | Lda n -> pr "lda 0x%02x" n
  | Waitp { pin; v; fail } -> pr "waitp %d, %d, %s" pin v (t fail)
  | Waitd -> "waitd"
  | Sho { pin; msb; od; pair; psel; cap; q = qq } ->
    pr "sho %d, %s%s%s%s%s%s" pin (if msb then "msb" else "lsb") (opt od "od") (opt pair "pair")
      (opt psel "psel") (opt cap "cap") (q qq)
  | Shi { pin; msb; quad } -> pr "shi %d, %s%s" pin (if msb then "msb" else "lsb") (opt quad "quad")
  | Jmp a -> if a = pc then "halt" else pr "jmp %s" (t a)
  | Jnz a -> pr "jnz %s" (t a)
  | Out { tag } -> if tag = 0 then "out" else pr "out tag=%d" tag
  | Outi { tag; v } -> if tag = 0 then pr "outi 0x%02x" v else pr "outi 0x%02x, tag=%d" v tag
  | In -> "in"
  | Send { ch; fail } -> pr "send %s, %s" (name_of chan_names ch) (t fail)
  | Recv { ch; fail } -> pr "recv %s, %s" (name_of chan_names ch) (t fail)
  | Waitc { cond; fail } -> pr "waitc %s, %s" (name_of cond_names cond) (t fail)
  | Ext { sub; imm } ->
    if sub < 8 && (ext_takes_imm sub || imm = 0) then
      let n = name_of ext_names sub in
      if ext_takes_imm sub then
        (match sub with 2 | 6 -> pr "%s %d" n imm | _ -> pr "%s 0x%02x" n imm)
      else n
    else pr "ext %d, 0x%02x" sub imm

(* the mnemonics the assembler accepts *)
let mnemonics =
  [ "nop"; "setp"; "ldc"; "ldd"; "lda"; "waitp"; "waitd"; "sho"; "shi"; "jmp"; "jnz"; "halt"; "out";
    "outi"; "in"; "send"; "recv"; "waitc"; "skne"; "skeq"; "fine"; "cnta"; "ldb"; "stb"; "bank";
    "cfg"; "ext" ]
