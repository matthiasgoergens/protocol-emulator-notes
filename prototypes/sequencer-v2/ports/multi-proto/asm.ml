(* The multi-proto label assembler (../../../multi-proto/asm.ml), re-targeted at ISA v2: same
   interface, so bridge_lib.ml assembles unchanged, but the output is v2 words.

   - Literal words (W) are base-ISA words from Isa (or multi-proto's SHX); they are translated with
     Compat.of_base at their address, and SHX becomes SHO with v2's capture bit when its capture
     pin is the partner pin (pin XOR 1), the only one v2 has; otherwise assembly fails.
   - SEND, RECV, JMP, JNZ, WAITP map one to one (8-bit addresses).
   - v2's WAITC has no polarity bit. A branch taken when an accumulator bit is 0 (br_clr) is one
     WAITC word; a branch taken when it is 1 (br_set) becomes two words, WAITC k -> skip; JMP l,
     one slot when not taken and two when taken (multi-proto: one either way). The timeline
     helpers count both words.
   - multi-proto's "wait while inbox i is full" (waitc (cond_full i) 0) becomes WAITC 11, "the
     last SEND target has space". That is the same condition only when the thread's last SEND
     went to inbox i; the assembler records each such word with its i, and the Isa_mb shim checks
     at every execution that the executing thread's lsend is i (Isa_mb.lsend_violations).
   - Other WAITC forms (a condition awaited at value 0, a full inbox awaited) have no v2
     translation and fail at assembly.

   Assembled arrays are registered (v2_programmes), so the core can tell them from raw base-ISA
   arrays such as the benches' all-HALT threads, which it translates at fetch. *)

type item =
  | W of int
  | L of string
  | R of string * (int -> int)
  | R2 of string * (target:int -> self:int -> int * int)   (* two words *)
  | Rc of string * int * (int -> int)                     (* a WAITC 11 standing for "inbox i not full" *)

let size = function L _ -> 0 | R2 _ -> 2 | _ -> 1

type b = { mutable items : item list; mutable now : int }
let create () = { items = []; now = 0 }
let emit b i = b.items <- i :: b.items; b.now <- b.now + size i
let emits b l = List.iter (emit b) l
let label b l = emit b (L l)

let pad b d =
  if d < 0 then failwith (Printf.sprintf "timeline: event %d slots in the past" (-d));
  if d = 1 then emit b (W Isa.nop)
  else if d >= 2 then begin
    if d - 2 > 0xFFF then failwith "timeline: gap too long for one LDD";
    emit b (W (Isa.ldd (d - 2))); emit b (W Isa.waitd);
    b.now <- b.now + d - 2
  end

let origin b = b.now <- 0
let at b t i = pad b (t - b.now); emit b i

let v2_programmes : int array list ref = ref []
let is_v2 a = List.exists (fun p -> p == a) !v2_programmes
let register p = v2_programmes := p :: !v2_programmes; p

(* (programme, address, inbox) of every WAITC 11 standing for "inbox not full" *)
let space_checks : (int array * int * int) list ref = ref []

(* a literal word: base ISA, or multi-proto's SHX (SHO with cap[6] cpin[5:3]) *)
let of_literal ~addr w =
  if (w lsr 12) land 15 = 7 && (w lsr 6) land 1 = 1 then begin
    let pin = (w lsr 9) land 7 and cpin = (w lsr 3) land 7 in
    if cpin <> pin lxor 1 then
      failwith (Printf.sprintf "SHX at %d captures pin %d; v2's capture pin for pin %d is %d" addr cpin pin (pin lxor 1));
    (w land 0xFF80) lor 0x10
  end else Compat.of_base ~pc_bits:7 ~addr w

let assemble ?(plen = 128) b =
  let items = List.rev b.items in
  let labels = Hashtbl.create 32 in
  let pos = ref 0 in
  List.iter (fun i ->
      (match i with L l -> if Hashtbl.mem labels l then failwith ("duplicate label " ^ l); Hashtbl.replace labels l !pos | _ -> ());
      pos := !pos + size i) items;
  if !pos > plen then failwith (Printf.sprintf "programme too long: %d words (limit %d)" !pos plen);
  let prog = Array.init plen Isa2.halt_at in
  let pos = ref 0 in
  let find l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("undefined label " ^ l) in
  let checks = ref [] in
  List.iter (function
    | L _ -> ()
    | W w -> prog.(!pos) <- of_literal ~addr:!pos w; incr pos
    | R (l, f) -> prog.(!pos) <- f (find l); incr pos
    | Rc (l, i, f) -> checks := (!pos, i) :: !checks; prog.(!pos) <- f (find l); incr pos
    | R2 (l, f) -> let a, c = f ~target:(find l) ~self:!pos in prog.(!pos) <- a; prog.(!pos + 1) <- c; pos := !pos + 2) items;
  let prog = register prog in
  List.iter (fun (a, i) -> space_checks := (prog, a, i) :: !space_checks) !checks;
  prog, !pos, labels

(* label-referencing forms *)
let jmp l = R (l, Isa2.jmp)
let jnz l = R (l, Isa2.jnz)
let send ch l = R (l, fun a -> Isa2.send ~ch ~fail:a)
let recv ch l = R (l, fun a -> Isa2.recv ~ch ~fail:a)
let br_clr bit l = R (l, fun a -> Isa2.waitc ~cond:(Isa2.c_acc bit) ~fail:a)
let br_set bit l = R2 (l, fun ~target ~self -> Isa2.waitc ~cond:(Isa2.c_acc bit) ~fail:(self + 2), Isa2.jmp target)
let waitc cond value l =
  if cond < 8 && value = 1 then R (l, fun a -> Isa2.waitc ~cond ~fail:a)
  else if cond >= 8 && cond < 12 && value = 0 then Rc (l, cond - 8, fun a -> Isa2.waitc ~cond:Isa2.c_space ~fail:a)
  else if cond >= 12 && value = 1 then R (l, fun a -> Isa2.waitc ~cond ~fail:a)
  else failwith (Printf.sprintf "waitc cond %d value %d has no v2 translation" cond value)
let waitp pin value l = R (l, fun a -> Isa2.waitp ~pin ~value ~fail:a)
let self_ref = ref 0
let fresh () = incr self_ref; Printf.sprintf "_self%d" !self_ref
let block_send b ch = let l = fresh () in emit b (L l); emit b (send ch l)
let block_recv b ch = let l = fresh () in emit b (L l); emit b (recv ch l)

(* a base-ISA programme (compiler.ml) in a v2 page, optionally looping instead of halting *)
let of_base ?(loop = false) (prog, len) ~plen =
  let p = Array.init plen (fun a -> if a < len then Compat.of_base ~pc_bits:6 ~addr:a prog.(a) else Isa2.halt_at a) in
  if loop then p.(len - 1) <- Isa2.jmp 0;
  register p
