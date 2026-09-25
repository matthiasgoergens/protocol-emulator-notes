(* A label assembler for the mailbox variant (7-bit addresses), with a timeline helper for
   straight-line code whose instructions must land on given slots: [at b t w] pads with NOP or
   LDD/WAITD so that [w] executes exactly t slots after the block's origin. Every instruction takes
   one slot, and LDD n; WAITD takes n + 2 slots, so the padding is exact by construction. *)

type item = W of int | L of string | R of string * (int -> int)

type b = { mutable items : item list; mutable now : int }
let create () = { items = []; now = 0 }
let emit b i = b.items <- i :: b.items; (match i with L _ -> () | _ -> b.now <- b.now + 1)
let emits b l = List.iter (emit b) l
let label b l = emit b (L l)

let pad b d =
  if d < 0 then failwith (Printf.sprintf "timeline: event %d slots in the past" (-d));
  if d = 1 then emit b (W Isa.nop)
  else if d >= 2 then begin
    if d - 2 > 0xFFF then failwith "timeline: gap too long for one LDD";
    emit b (W (Isa.ldd (d - 2))); emit b (W Isa.waitd);
    b.now <- b.now + d - 2          (* the two words take d slots *)
  end

(* the slot count restarts at a label that starts a timed block *)
let origin b = b.now <- 0
let at b t i = pad b (t - b.now); emit b i

let assemble ?(plen = 128) b =
  let items = List.rev b.items in
  let labels = Hashtbl.create 32 in
  let pos = ref 0 in
  List.iter (function L l -> if Hashtbl.mem labels l then failwith ("duplicate label " ^ l); Hashtbl.replace labels l !pos | _ -> incr pos) items;
  if !pos > plen then failwith (Printf.sprintf "programme too long: %d words (limit %d)" !pos plen);
  let prog = Array.make plen Isa.halt in
  let pos = ref 0 in
  let find l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("undefined label " ^ l) in
  List.iter (function
    | L _ -> ()
    | W w -> prog.(!pos) <- w; incr pos
    | R (l, f) -> prog.(!pos) <- f (find l); incr pos) items;
  prog, !pos, labels

(* label-referencing forms *)
let jmp l = R (l, Isa_mb.jmp)
let jnz l = R (l, Isa_mb.jnz)
let send ch l = R (l, fun a -> Isa_mb.send ~ch ~fail:a)
let recv ch l = R (l, fun a -> Isa_mb.recv ~ch ~fail:a)
let br_set bit l = R (l, fun a -> Isa_mb.br_set ~bit ~target:a)
let br_clr bit l = R (l, fun a -> Isa_mb.br_clr ~bit ~target:a)
let waitc cond value l = R (l, fun a -> Isa_mb.waitc ~cond ~value ~fail:a)
let waitp pin value l = R (l, fun a -> Isa_mb.waitp ~pin ~value ~fail:a)
(* a self-referencing wait: blocks until the condition holds (fail = own address) *)
let self_ref = ref 0
let fresh () = incr self_ref; Printf.sprintf "_self%d" !self_ref
let block_send b ch = let l = fresh () in emit b (L l); emit b (send ch l)
let block_recv b ch = let l = fresh () in emit b (L l); emit b (recv ch l)

(* take a base-ISA programme (e.g. from compiler.ml) into a 128-word memory, optionally turning its
   final HALT into a jump back to 0 so it runs forever *)
let of_base ?(loop = false) (prog, len) ~plen =
  let p = Array.make plen Isa.halt in
  Array.blit prog 0 p 0 len;
  if loop then p.(len - 1) <- Isa_mb.jmp 0;
  p
