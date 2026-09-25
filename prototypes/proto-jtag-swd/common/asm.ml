(* A small label assembler for sequencer programmes, and the two ways to run one: the interpreter
   (Isa, the executable specification) and the RTL (Sequencer through Harness). Shared by the
   stock-ISA and the wide-ISA builds, which link different Isa modules. *)

type item =
  | W of int                              (* a literal instruction word *)
  | L of string                           (* label *)
  | Jmp of string
  | Jnz of string
  | Waitp of int * int * string           (* pin, value, fail label *)
  | Hold of int * int                     (* wait indefinitely for pin = value (WAITP failing to itself) *)

let assemble items =
  let labels = Hashtbl.create 16 in
  let pos = ref 0 in
  List.iter (function
    | L l -> if Hashtbl.mem labels l then failwith ("duplicate label " ^ l); Hashtbl.replace labels l !pos
    | _ -> incr pos) items;
  let len = !pos in
  if len > Isa.prog_len then
    failwith (Printf.sprintf "programme too long: %d words, store holds %d" len Isa.prog_len);
  let find l = try Hashtbl.find labels l with Not_found -> failwith ("undefined label " ^ l) in
  let prog = Array.make Isa.prog_len Isa.halt in
  let pos = ref 0 in
  let put w = prog.(!pos) <- w; incr pos in
  List.iter (function
    | L _ -> ()
    | W w -> put w
    | Jmp l -> put (Isa.jmp (find l))
    | Jnz l -> put (Isa.jnz (find l))
    | Waitp (pin, value, l) -> put (Isa.waitp ~pin ~value ~fail:(find l))
    | Hold (pin, value) -> put (Isa.waitp ~pin ~value ~fail:!pos)) items;
  prog, len

(* n slots of delay: NOPs up to 2, then LDD k; WAITD, which takes k + 2 slots and leaves dl = 0. *)
let pad n =
  if n <= 0 then [] else if n = 1 then [ W Isa.nop ] else [ W (Isa.ldd (n - 2)); W Isa.waitd ]

(* A core, stepped one clock: interpreter or RTL. [pin_out]/[pin_oe] are the registered levels
   after the step, i.e. what the pads drive from this clock on. *)
type obs = { pin_out : int; pin_oe : int; host_out : int option; host_in_ready : bool }
type core = { name : string; step : pin_in:int -> host_in:int -> host_in_valid:bool -> obs }

let dbg_pc = ref 0   (* thread 0's pc after the last interpreter step, for debugging *)

let interp mem =
  let st = Isa.init () in
  { name = "interpreter";
    step = (fun ~pin_in ~host_in ~host_in_valid ->
      let e = Isa.step st ~mem ~pin_in ~host_in ~host_in_valid in
      dbg_pc := st.pcs.(0);
      { pin_out = st.pin_out; pin_oe = st.pin_oe; host_out = e.host_out; host_in_ready = e.host_in_ready }) }

let rtl mem =
  let s = Harness.make mem in
  { name = "rtl";
    step = (fun ~pin_in ~host_in ~host_in_valid ->
      let o = Harness.cycle s ~pin_in ~host_in ~host_in_valid in
      { pin_out = o.pin_out; pin_oe = o.pin_oe; host_out = o.host_out; host_in_ready = o.host_in_ready }) }

let halted = Array.make Isa.prog_len Isa.halt

let disassemble w =
  let f = w land 0xFFF in
  match Isa.op_of_code ((w lsr 12) land 0xF) with
  | Isa.NOP -> "nop"
  | SETP -> Printf.sprintf "setp mask=%02x val=%d oe=%d" ((f lsr 4) land 0xFF) ((f lsr 3) land 1) ((f lsr 2) land 1)
  | LDC -> Printf.sprintf "ldc %d" f | LDD -> Printf.sprintf "ldd %d" f | LDA -> Printf.sprintf "lda 0x%02x" (f land 0xFF)
  | WAITP -> Printf.sprintf "waitp pin%d==%d fail=%d" ((f lsr 9) land 7) ((f lsr 8) land 1) (f land (Isa.prog_len - 1))
  | WAITD -> "waitd" | SHO -> Printf.sprintf "sho pin%d" ((f lsr 9) land 7) | SHI -> Printf.sprintf "shi pin%d" ((f lsr 9) land 7)
  | JMP -> Printf.sprintf "jmp %d" (f land (Isa.prog_len - 1)) | JNZ -> Printf.sprintf "jnz %d" (f land (Isa.prog_len - 1))
  | OUT -> "out" | IN -> "in" | HALT -> "halt"
