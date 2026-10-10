(* A small assembler for ISA v2 (../sequencer-v2/isa2.ml) with labels, for one thread's page.

   A programme is a list of items. Words are ISA v2 words; branches name labels; [Wait n] is a
   delay of exactly n slots, built from NOPs and LDD/WAITD pairs. The result is the thread's
   256-word page (unused words are NOP), and [assemble] fails if the programme does not fit:
   that is the "fits in a thread's programme page" check of every firmware here.

   Every address field of ISA v2 is 8 bits within the thread's page (Isa2: JMP, JNZ, WAITP's
   and WAITC's fail target, MBX's fail target), so a programme assembled here runs from any
   page, at pc 0. *)

type item =
  | W of int                                             (* one word *)
  | Label of string
  | Jmp of string
  | Jnz of string
  | Waitp of { pin : int; value : int; fail : string }   (* fail: the label jumped to at dl = 0 *)
  | Waitc of { cond : int; fail : string }
  | Halt                                                 (* JMP to itself *)
  | Wait of int                                          (* exactly n slots, n >= 0 *)

(* [Wait n] in words. LDD x; WAITD takes x + 2 slots (LDD's own, then WAITD from dl = x down to
   0), so one pair covers 2..4097 slots; a longer wait is a chain of pairs. Every pair ends with
   dl = 0, which the WAITP and WAITC branches that follow rely on (they branch only at dl = 0). *)
let rec wait_words n =
  if n <= 0 then []
  else if n = 1 then [ Isa2.nop ]
  else if n <= 4097 then [ Isa2.ldd (n - 2); Isa2.waitd ]
  else [ Isa2.ldd 4095; Isa2.waitd ] @ wait_words (n - 4097)

let expand items =
  List.concat_map (function Wait n -> List.map (fun w -> W w) (wait_words n) | i -> [ i ]) items

exception Too_long of int

let assemble items =
  let items = expand items in
  let labels = Hashtbl.create 32 in
  let pos = ref 0 in
  List.iter (function
      | Label l ->
        if Hashtbl.mem labels l then failwith ("label defined twice: " ^ l);
        Hashtbl.replace labels l !pos
      | _ -> incr pos) items;
  if !pos > Isa2.page_len then raise (Too_long !pos);
  let find l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("undefined label " ^ l) in
  let page = Array.make Isa2.page_len Isa2.nop in
  let pos = ref 0 in
  let put w = page.(!pos) <- w; incr pos in
  List.iter (function
      | Label _ -> ()
      | W w -> put w
      | Jmp l -> put (Isa2.jmp (find l))
      | Jnz l -> put (Isa2.jnz (find l))
      | Waitp { pin; value; fail } -> put (Isa2.waitp ~pin ~value ~fail:(find fail))
      | Waitc { cond; fail } -> put (Isa2.waitc ~cond ~fail:(find fail))
      | Halt -> put (Isa2.halt_at !pos)
      | Wait _ -> assert false) items;
  page, !pos

let listing (page, len) =
  let b = Buffer.create 1024 in
  for i = 0 to len - 1 do Printf.bprintf b "  %3d: %s\n" i (Isa2.disasm page.(i)) done;
  Buffer.contents b
