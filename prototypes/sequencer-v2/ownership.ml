(* Ownership of the shared resources other than pins: the data bank, the four inboxes and the
   four ports. Pins have their own discipline (each pin driven by one thread, or by a declared
   time-division group); nothing protected the rest, so a thread that reads the bank, an inbox or
   a port could be disturbed by any other thread (../formal/README.md, findings).

   A declaration says, for each thread, what it may touch:
   - bank addresses it may read (LDB) and write (STB), as inclusive ranges of the 1024-byte bank;
   - inboxes it may send to (SEND, and WAITC 11 waiting for space) and receive from (RECV, and
     WAITC 10 polling its own inbox);
   - out-ports it may send to (SEND to channel 4 + j, WAITC 11 on it) and in-ports it may
     receive from (RECV from channel 4 + j).
   Anything not declared is forbidden. "Touch" means naming the resource, whether or not the
   instruction succeeds: a SEND to a full inbox has still looked at it.

   The declaration is checked two ways, from this one definition:
   - statically, by the hazard checker (../verif-oracles/hazard), over every reachable
     instruction, with bank addresses from a data-flow analysis of the bank pointer;
   - by bounded model checking (../formal, props.ml), over every input sequence, from the
     interpreter's own effects (bank_read, bank_write, inbox_send, inbox_recv, port_out,
     port_in). *)

type thread = {
  bank_read : (int * int) list;     (* inclusive address ranges, 0..1023 *)
  bank_write : (int * int) list;
  inbox_send : int list;            (* inboxes 0..3 *)
  inbox_recv : int list;
  port_out : int list;              (* ports 0..3, i.e. MBX channels 4..7 *)
  port_in : int list;
}

type t = thread array               (* one entry per thread *)

let nothing = { bank_read = []; bank_write = []; inbox_send = []; inbox_recv = []; port_out = []; port_in = [] }
let none () : t = Array.make 4 nothing

let in_ranges ranges a = List.exists (fun (lo, hi) -> lo <= a && a <= hi) ranges

(* bit i set for each i in the list *)
let mask l = List.fold_left (fun m i -> m lor (1 lsl i)) 0 l

let check_well_formed (o : t) =
  if Array.length o <> 4 then invalid_arg "Ownership: one entry per thread (4)";
  Array.iteri (fun t th ->
      List.iter (fun (lo, hi) ->
          if lo < 0 || hi > 1023 || lo > hi then invalid_arg (Printf.sprintf "Ownership: T%d bank range %d..%d" t lo hi))
        (th.bank_read @ th.bank_write);
      List.iter (fun i -> if i < 0 || i > 3 then invalid_arg (Printf.sprintf "Ownership: T%d inbox or port %d" t i))
        (th.inbox_send @ th.inbox_recv @ th.port_out @ th.port_in))
    o

let ranges_text = function
  | [] -> "-"
  | l -> String.concat "," (List.map (fun (lo, hi) -> if lo = hi then string_of_int lo else Printf.sprintf "%d..%d" lo hi) l)

let ints_text = function [] -> "-" | l -> String.concat "," (List.map string_of_int l)

let describe (o : t) =
  String.concat "\n" (Array.to_list (Array.mapi (fun t th ->
      Printf.sprintf "T%d: bank read %s, write %s; inbox send %s, recv %s; port out %s, in %s" t
        (ranges_text th.bank_read) (ranges_text th.bank_write) (ints_text th.inbox_send) (ints_text th.inbox_recv)
        (ints_text th.port_out) (ints_text th.port_in)) o))
