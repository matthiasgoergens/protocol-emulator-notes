(* The host's side of the host link (README, "Host link protocol"), as a per-clock driver: it
   decides what the host drives on S, R and D in each clock and samples D when it reads. It
   obeys the protocol's timing with the margins below, and knows nothing about the chip beyond
   the protocol. *)

open Regs

type txn =
  | Write of { tgt : int; addr : int; data : int list }
  | Read of { tgt : int; addr : int; n : int; k : int list -> unit }   (* n >= 1 bytes *)
  | Idle of int
  | Call of (unit -> unit)                                              (* runs when reached *)

(* micro-steps, one or more per clock until a wait *)
type step =
  | Set_d of int                (* drive D *)
  | Release_d
  | Toggle_s
  | Set_r of int
  | Wait of int                 (* clocks *)
  | Sample of (int -> unit)     (* read D now *)
  | Do of (unit -> unit)

let write_setup = 2 and write_hold = 2 and read_gap = 8 and turnaround = 8

type t = {
  q : step Queue.t;
  mutable wait : int;
  mutable s : int; mutable r : int; mutable d : int option;
  mutable busy_clocks : int;
}

let create () = { q = Queue.create (); wait = 0; s = 0; r = 0; d = None; busy_clocks = 0 }

let idle t = Queue.is_empty t.q && t.wait = 0

let push_steps t l = List.iter (fun s -> Queue.push s t.q) l

let byte_steps b =
  [ Set_d (b lsr 4); Wait write_setup; Toggle_s; Wait write_hold;
    Set_d (b land 15); Wait write_setup; Toggle_s; Wait write_hold ]

let cmd t ~op ~tgt ~addr ~count =
  List.iter (fun b -> push_steps t (byte_steps b))
    [ (op lsl 4) lor tgt; (addr lsr 8) land 0xFF; addr land 0xFF; count - 1 ]

let submit t = function
  | Write { tgt; addr; data } ->
    (* at most 256 bytes per command *)
    let rec go addr = function
      | [] -> ()
      | l ->
        let chunk = List.filteri (fun i _ -> i < 256) l and rest = List.filteri (fun i _ -> i >= 256) l in
        cmd t ~op:op_write ~tgt ~addr ~count:(List.length chunk);
        List.iter (fun b -> push_steps t (byte_steps b)) chunk;
        go (addr + List.length chunk) rest
    in
    go addr data
  | Read { tgt; addr; n; k } ->
    assert (n >= 1 && n <= 256);
    cmd t ~op:op_read ~tgt ~addr ~count:n;
    let acc = ref [] and hi = ref 0 in
    push_steps t [ Release_d; Wait turnaround; Set_r 1; Wait read_gap ];
    for _ = 1 to n do
      push_steps t
        [ Sample (fun v -> hi := v); Toggle_s; Wait read_gap;
          Sample (fun v -> acc := ((!hi lsl 4) lor v) :: !acc); Toggle_s; Wait read_gap ]
    done;
    push_steps t [ Set_r 0; Wait turnaround; Do (fun () -> k (List.rev !acc)) ]
  | Idle n -> push_steps t [ Wait n ]
  | Call f -> push_steps t [ Do f ]

(* One clock. [d_in] is the level of the four data lines during this clock (whoever drives
   them). Returns what the host drives during this clock: (S, R, D or None). *)
let clock t ~d_in =
  if t.wait > 0 then t.wait <- t.wait - 1
  else begin
    let continue = ref true in
    while !continue && not (Queue.is_empty t.q) do
      match Queue.pop t.q with
      | Set_d v -> t.d <- Some v
      | Release_d -> t.d <- None
      | Toggle_s -> t.s <- 1 - t.s
      | Set_r v -> t.r <- v
      | Wait n -> t.wait <- n - 1; continue := false
      | Sample f -> f d_in
      | Do f -> f ()
    done
  end;
  if not (idle t) then t.busy_clocks <- t.busy_clocks + 1;
  (t.s, t.r, t.d)

(* convenience: register writes and reads *)
let wreg t a v = submit t (Write { tgt = t_reg; addr = a; data = [ v land 0xFF ] })
let wreg32 t a v = submit t (Write { tgt = t_reg; addr = a; data = List.init 4 (fun k -> (v lsr (8 * k)) land 0xFF) })
