(* A two-pass label assembler over Isa2's encoders, for the S/PDIF firmware.

   A programme is a list of items; [I f] is one word whose encoding may use label addresses, [L]
   names the address of the next word. Branch targets are 8-bit addresses within the thread's
   page. [self] in a fail field means "this instruction's own address": a blocking wait at dl = 0
   (WAITC, MBX), which is how every wait in this firmware is written. *)

type item = L of string | I of (env -> int)
and env = { addr : string -> int; here : int }

let assemble ?(origin = 0) items =
  let tbl = Hashtbl.create 64 in
  let pc = ref origin in
  List.iter (function L s -> if Hashtbl.mem tbl s then failwith ("duplicate label " ^ s); Hashtbl.replace tbl s !pc | I _ -> incr pc) items;
  if !pc > Isa2.page_len then failwith (Printf.sprintf "programme of %d words does not fit a page" (!pc - origin));
  let addr s = match Hashtbl.find_opt tbl s with Some a -> a | None -> failwith ("undefined label " ^ s) in
  let pc = ref origin in
  let words = List.filter_map (function L _ -> None | I f -> let w = f { addr; here = !pc } in incr pc; Some w) items in
  (Array.of_list words, addr)

let i w = I (fun _ -> w)
let ( @@@ ) f lbl = I (fun e -> f (e.addr lbl))

(* common shapes *)
let recv_w ch = I (fun e -> Isa2.recv ~ch ~fail:e.here)          (* RECV, waiting *)
let send_w ch = I (fun e -> Isa2.send ~ch ~fail:e.here)          (* SEND, waiting *)
let waitc_else cond lbl = I (fun e -> Isa2.waitc ~cond ~fail:(e.addr lbl))   (* proceed if cond, else jump *)
let jmp lbl = I (fun e -> Isa2.jmp (e.addr lbl))
let jnz lbl = I (fun e -> Isa2.jnz (e.addr lbl))
let lda v = i (Isa2.lda v)
