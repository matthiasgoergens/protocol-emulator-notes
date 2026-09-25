(* A two-pass assembler with labels. An item is a label or an instruction that may refer to
   labels. [assemble] returns the words (padded with HALT) and the label table, which the
   controller uses to find the words it patches. *)

type item = L of string | I of ((string -> int) -> int)

let i w = I (fun _ -> w)
let ( @@@ ) f l = I (fun lab -> f (lab l))   (* an instruction taking a label's address *)

type prog = { words : int array; labels : (string, int) Hashtbl.t; used : int }

let assemble ?(size = Isa_ls.prog_len) ?(fill = Isa_ls.halt) items =
  let labels = Hashtbl.create 64 in
  let pc = ref 0 in
  List.iter (function
    | L l -> if Hashtbl.mem labels l then failwith ("duplicate label " ^ l); Hashtbl.replace labels l !pc
    | I _ -> incr pc) items;
  if !pc > size then failwith (Printf.sprintf "programme of %d words exceeds %d" !pc size);
  let lookup l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("undefined label " ^ l) in
  let words = Array.make size fill in
  let pc = ref 0 in
  List.iter (function L _ -> () | I f -> words.(!pc) <- f lookup; incr pc) items;
  { words; labels; used = !pc }

let addr p l = Hashtbl.find p.labels l

(* unique label generator for macros *)
let fresh =
  let n = ref 0 in
  fun base -> incr n; Printf.sprintf "%s_%d" base !n
