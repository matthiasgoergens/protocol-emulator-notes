(* A static hazard checker for ISA v2 programmes: structural conflicts as an exhaustive case table
   in which a missing entry means REJECTED.

   Idea credited to Gergo Erdi's typed microcode (his CPU microcode's "Combine" type family has a
   clause for each pair of micro-operations that may share a cycle; with no clause there is no
   type, so a conflicting pair does not compile). OCaml has no type families, so the same
   discipline is kept in two layers:
   - compile time: the decoder and the classifier below are matches over closed variants with no
     wildcard, and this file is compiled with warnings 4 (fragile match), 8 (non-exhaustive) and 9
     as errors (see dune). A new opcode, EXT operation or use kind does not compile until it is
     classified;
   - run time: the verdict tables are allow-lists. A combination with no entry is REJECTED, and
     the rejection names the missing key. A use the classifier cannot classify (a reserved EXT
     operation) raises Unhandled instead of being ignored.

   What is checked, for one set of four thread programmes plus declarations (who owns what, the
   array's bank streams, the refresh schedule):
   - every reachable instruction of every thread, from its boot address, following every branch
     both ways (data-independent over-approximation: unreachable words are not checked);
   - SOLO: each use of a resource against its declaration (pin ownership, bank grants) and its
     wait class (a SEND whose failure path waits for ever on a full inbox is "unbounded");
   - PAIRS: every two uses of one resource by different actors, keyed by the two kinds, whether
     they can fall in the same clock (threads issue in clocks t mod 4; refresh and array streams
     in their declared clocks), and whether the resource is declared shared between them;
   - COUNTERPART: a SEND needs a reachable RECV on that inbox in another thread, and vice versa.

   - OWNERSHIP of the bank, the inboxes and the ports (../../sequencer-v2/ownership.ml, declared
     per thread in [decl.owns]): a use outside the thread's declaration is "undeclared", for which
     the SOLO table has no entry, so it is REJECTED. Bank addresses come from a data-flow analysis
     of the bank pointer (see [flow]): every address an LDB or STB can reach must be in the
     thread's declared ranges. Since the ranges are declared per thread, two threads' bank uses
     are disjoint exactly when their declarations are, which is checked too ([overlaps]).

   Not checked (stated, not hidden): runtime pc changes by the host (D1 of sequencer-v2);
   programmes that patch their own words (usb-ls's controller); timing (deadlines met), which is
   the lockstep's and the protocol models' job. *)

exception Unhandled of string
exception Bad_table of string

(* ---- decoding: every v2 opcode and EXT operation, no wildcard ---- *)
type instr =
  | Nop | Setp of { mask : int } | Ldc | Ldd | Lda | Waitp of { pin : int; fail : int } | Waitd
  | Sho of { pin : int; pair : bool; cap : bool } | Shi of { pin : int } | Jmp of int | Jnz of int
  | Out | In | Send of { ch : int; fail : int } | Recv of { ch : int; fail : int }
  | Waitc of { cond : int; fail : int }
  | Skne | Skeq | Fine | Cnta | Ldb | Stb | Bank of { hi : int } | Cfg | Ext_reserved of int

let decode w =
  let f = w land 0xFFF in
  let pin = (f lsr 9) land 7 and a8 = f land 0xFF in
  match (w lsr 12) land 15 with
  | 0 -> Nop | 1 -> Setp { mask = (f lsr 4) land 0xFF } | 2 -> Ldc | 3 -> Ldd | 4 -> Lda
  | 5 -> Waitp { pin; fail = a8 } | 6 -> Waitd
  | 7 -> Sho { pin; pair = (f lsr 6) land 1 = 1; cap = (f lsr 4) land 1 = 1 }
  | 8 -> Shi { pin } | 9 -> Jmp a8 | 10 -> Jnz a8 | 11 -> Out | 12 -> In
  | 13 -> let ch = (f lsr 8) land 7 in if (f lsr 11) land 1 = 0 then Send { ch; fail = a8 } else Recv { ch; fail = a8 }
  | 14 -> Waitc { cond = (f lsr 8) land 15; fail = a8 }
  | 15 ->
    (match (f lsr 8) land 15 with
     | 0 -> Skne | 1 -> Skeq | 2 -> Fine | 3 -> Cnta | 4 -> Ldb | 5 -> Stb | 6 -> Bank { hi = a8 } | 7 -> Cfg
     | s -> Ext_reserved s)
  | _ -> assert false   (* four bits *)

(* ---- resources, actors, use kinds ---- *)
type resource = Pin of int | Bankr of int | Inbox of int | Feed of int | Tap of int
type actor = Thread of int | Array_seg of int | Refresher

type kind =
  | Pin_drive | Pin_sample
  | Bank_read | Bank_write | Bank_refresh | Bank_stream
  | Send_k | Space_wait | Recv_k | Poll
  | Feed_push | Tap_pop

(* every kind, by an exhaustive successor function: a new constructor fails to compile here *)
let next_kind = function
  | Pin_drive -> Some Pin_sample | Pin_sample -> Some Bank_read | Bank_read -> Some Bank_write
  | Bank_write -> Some Bank_refresh | Bank_refresh -> Some Bank_stream | Bank_stream -> Some Send_k
  | Send_k -> Some Space_wait | Space_wait -> Some Recv_k | Recv_k -> Some Poll | Poll -> Some Feed_push
  | Feed_push -> Some Tap_pop | Tap_pop -> None
let all_kinds = let rec go k = k :: (match next_kind k with Some n -> go n | None -> []) in go Pin_drive

type cls = C_pin | C_bank | C_inbox | C_feed | C_tap
let class_of = function
  | Pin_drive | Pin_sample -> C_pin
  | Bank_read | Bank_write | Bank_refresh | Bank_stream -> C_bank
  | Send_k | Space_wait | Recv_k | Poll -> C_inbox
  | Feed_push -> C_feed | Tap_pop -> C_tap
let class_of_res = function Pin _ -> C_pin | Bankr _ -> C_bank | Inbox _ -> C_inbox | Feed _ -> C_feed | Tap _ -> C_tap

(* the wait class applies to mailbox and port kinds only *)
type wait = No_wait | Bounded | Unbounded
let waits_apply = function
  | Send_k | Space_wait | Recv_k | Poll | Feed_push | Tap_pop -> true
  | Pin_drive | Pin_sample | Bank_read | Bank_write | Bank_refresh | Bank_stream -> false

let kind_name = function
  | Pin_drive -> "pin-drive" | Pin_sample -> "pin-sample" | Bank_read -> "bank-read (LDB)"
  | Bank_write -> "bank-write (STB)" | Bank_refresh -> "bank-refresh" | Bank_stream -> "bank-stream (array)"
  | Send_k -> "send" | Space_wait -> "space-wait (WAITC 11)" | Recv_k -> "recv" | Poll -> "poll (WAITC 10)"
  | Feed_push -> "feed-push" | Tap_pop -> "tap-pop"
let wait_name = function No_wait -> "-" | Bounded -> "bounded" | Unbounded -> "UNBOUNDED"
let res_name = function
  | Pin p -> Printf.sprintf "pin %d" p | Bankr b -> Printf.sprintf "bank %d" b | Inbox i -> Printf.sprintf "inbox %d" i
  | Feed j -> Printf.sprintf "feed %d" j | Tap j -> Printf.sprintf "tap %d" j
let actor_name = function
  | Thread t -> Printf.sprintf "T%d" t | Array_seg s -> Printf.sprintf "array segment %d" s | Refresher -> "refresh"

(* ---- declarations ---- *)
type decl = {
  grants : (resource * actor * kind list) list;   (* pins only: actor may use the pin with these kinds *)
  owns : Ownership.t;                             (* bank addresses, inboxes and ports, per thread *)
  shared : (resource * actor list) list;          (* declared sharing groups (e.g. a TDM pin) *)
  refresh : (int * int * int) list;               (* bank, period, offset: clocks the refresh owns *)
  streams : (int * int) list;                     (* bank, segment: the array uses the bank port every clock *)
  boot : (int * int) array;                       (* per thread (page, pc) *)
  waivers : (resource * actor * kind * string) list;
  (* a SOLO rejection the programme's author has argued away, with the argument; printed as
     WAIVED with its reason, never silent. The table itself is not changed by a waiver. *)
}

let no_decl = { grants = []; owns = Ownership.none (); shared = []; refresh = []; streams = []; boot = Array.init 4 (fun t -> (t, 0)); waivers = [] }

(* ---- the tables ---- *)
type decl_rel = Declared | Undeclared

(* SOLO allow-list: (kind, wait, declaration) -> reason *)
let solo_table = [
  (Pin_drive, No_wait, Declared), "the thread owns the pin";
  (Pin_sample, No_wait, Declared), "the thread reads its own pin";
  (Pin_sample, No_wait, Undeclared), "sampling any pin is harmless (monitors, loop-backs)";
  (Bank_read, No_wait, Declared), "bank granted to the thread";
  (Bank_write, No_wait, Declared), "bank granted to the thread";
  (Bank_refresh, No_wait, Declared), "refresh schedule (declared by construction)";
  (Bank_stream, No_wait, Declared), "array port use (declared by construction)";
  (Send_k, Bounded, Declared), "SEND with a failure path that leaves";
  (Space_wait, Bounded, Declared), "space wait with a failure path that leaves";
  (Recv_k, Bounded, Declared), "RECV with a failure path";
  (Recv_k, Unbounded, Declared), "a consumer may idle on an empty inbox";
  (Poll, Bounded, Declared), "own-inbox poll with a failure path";
  (Poll, Unbounded, Declared), "a consumer may idle on its own inbox";
  (Feed_push, Bounded, Declared), "feed write with a failure path";
  (Tap_pop, Bounded, Declared), "tap read with a failure path";
  (Tap_pop, Unbounded, Declared), "a consumer may idle on an empty tap";
]
(* Absent on purpose, so REJECTED: a pin driven by a thread that does not own it; any bank use
   not granted; SEND / space wait / feed push that waits for ever on a full target ("send to a
   full inbox without a deadline"); any mailbox or port use not declared. *)

(* PAIR allow-list: (kind a, kind b, can share a clock, declared shared) -> reason; a <= b in
   all_kinds order. Pins hold their value between writes, so for pins the clock does not matter. *)
let pair_table =
  let both f = [ f false; f true ] in
  List.concat [
    both (fun c -> (Pin_drive, Pin_drive, c, true), "declared time-division group: each member drives in its own slots; the interleave is the protocol model's to check");
    List.concat_map (fun c -> both (fun s -> (Pin_drive, Pin_sample, c, s), "another actor reads the pin")) [ false; true ];
    List.concat_map (fun c -> both (fun s -> (Pin_sample, Pin_sample, c, s), "two readers")) [ false; true ];
    (* one bank port: any two users in different clocks; never two in the same clock *)
    List.concat_map (fun (a, b) -> both (fun s -> (a, b, false, s), "one port, different clocks"))
      [ (Bank_read, Bank_read); (Bank_read, Bank_write); (Bank_write, Bank_write);
        (Bank_read, Bank_refresh); (Bank_write, Bank_refresh); (Bank_read, Bank_stream);
        (Bank_write, Bank_stream); (Bank_refresh, Bank_stream) ];
    (* inboxes: one producer, one consumer *)
    List.concat_map (fun (a, b) -> List.concat_map (fun c -> both (fun s -> (a, b, c, s), "producer and consumer")) [ false; true ])
      [ (Send_k, Recv_k); (Send_k, Poll); (Space_wait, Recv_k); (Space_wait, Poll); (Send_k, Space_wait) ];
    List.concat_map (fun c -> [ (Send_k, Send_k, c, true), "declared multi-producer inbox" ]) [ false; true ];
  ]
(* Absent, so REJECTED: two undeclared drivers of a pin; two bank users in one clock (refresh
   against access, array stream against LDB/STB, read against write); two consumers of one
   inbox (RECV/RECV, RECV/POLL of another thread); undeclared multiple producers; two writers of
   one feed register or two readers of one tap. *)

(* COUNTERPART: a mailbox use needs the other side somewhere (another actor, reachable) *)
let counterpart_kinds = function
  | Send_k | Space_wait -> Some [ Recv_k; Poll ]
  | Recv_k | Poll -> Some [ Send_k ]
  | Feed_push | Tap_pop -> None   (* the array side is configuration, declared through grants *)
  | Pin_drive | Pin_sample | Bank_read | Bank_write | Bank_refresh | Bank_stream -> None

let index k = let rec go i = function [] -> assert false | x :: r -> if x = k then i else go (i + 1) r in go 0 all_kinds

(* table sanity, at start-up: keys well formed, no duplicates, every kind listed once *)
let () =
  let n = List.length all_kinds in
  if List.length (List.sort_uniq compare all_kinds) <> n then raise (Bad_table "all_kinds repeats a kind");
  List.iter (fun ((k, w, _), _) ->
      if waits_apply k = (w = No_wait) then raise (Bad_table ("solo entry with a wait class that does not apply: " ^ kind_name k)))
    solo_table;
  List.iter (fun ((a, b, _, _), _) ->
      if class_of a <> class_of b then raise (Bad_table (Printf.sprintf "pair entry across classes: %s / %s" (kind_name a) (kind_name b)));
      if index a > index b then raise (Bad_table (Printf.sprintf "pair entry not in canonical order: %s / %s" (kind_name a) (kind_name b))))
    pair_table;
  let dup l = List.length (List.sort_uniq compare (List.map fst l)) <> List.length l in
  if dup solo_table || dup pair_table then raise (Bad_table "duplicate key")

type tables = { solo : ((kind * wait * decl_rel) * string) list; pairs : ((kind * kind * bool * bool) * string) list }
let default_tables = { solo = solo_table; pairs = pair_table }

(* ---- uses of one instruction ---- *)
type use = { res : resource; kind : kind; actor : actor; addr : int; wait : wait; text : string;
             cells : int list (* LDB, STB: the bank addresses it can touch; [] otherwise *) }

let n_threads = 4

(* follow a failure target through unconditional jumps and NOPs: if that path comes back to
   [self], the wait never leaves. A path that loops elsewhere (a HALT, JMP self) has left the
   wait: the thread gave up. No step limit: a page has 256 addresses, and a revisited address
   other than [self] ends the search. *)
let wait_class ~fetch ~page ~self ~fail =
  let seen = Array.make 256 false in
  let rec go pc =
    if pc = self then Unbounded
    else if seen.(pc) then Bounded
    else begin
      seen.(pc) <- true;
      match decode (fetch ((page lsl 8) lor pc)) with
      | Jmp a -> go a
      | Nop -> go ((pc + 1) land 0xFF)
      | Setp _ | Ldc | Ldd | Lda | Waitp _ | Waitd | Sho _ | Shi _ | Jnz _ | Out | In | Send _ | Recv _
      | Waitc _ | Skne | Skeq | Fine | Cnta | Ldb | Stb | Bank _ | Cfg | Ext_reserved _ -> Bounded
    end in
  go fail

(* the bank pointer a BANK sets: bp <- {imm[1:0], acc} *)
let bank_sel = function
  | Bank { hi } -> Some (hi land 3)
  | Nop | Setp _ | Ldc | Ldd | Lda | Waitp _ | Waitd | Sho _ | Shi _ | Jmp _ | Jnz _ | Out | In | Send _ | Recv _
  | Waitc _ | Skne | Skeq | Fine | Cnta | Ldb | Stb | Cfg | Ext_reserved _ -> None
let send_ch = function
  | Send { ch; _ } -> Some ch
  | Nop | Setp _ | Ldc | Ldd | Lda | Waitp _ | Waitd | Sho _ | Shi _ | Jmp _ | Jnz _ | Out | In | Bank _ | Recv _
  | Waitc _ | Skne | Skeq | Fine | Cnta | Ldb | Stb | Cfg | Ext_reserved _ -> None

(* the accumulator, as far as BANK needs it: a known constant, or anything *)
type acc = Known of int | Any
(* what an instruction leaves in the accumulator, given what was there; [imm] is the word's low
   byte (LDA's immediate) *)
let acc_after i ~imm a = match i with
  | Lda -> Known imm
  | In | Recv _ | Shi _ | Sho _ | Ldb -> Any
  | Nop | Setp _ | Ldc | Ldd | Waitp _ | Waitd | Jmp _ | Jnz _ | Out | Send _ | Waitc _ | Skne | Skeq | Fine
  | Cnta | Stb | Bank _ | Cfg | Ext_reserved _ -> a

(* does the instruction step the bank pointer (post-increment)? *)
let steps_bp = function
  | Ldb | Stb -> true
  | Nop | Setp _ | Ldc | Ldd | Lda | Waitp _ | Waitd | Sho _ | Shi _ | Jmp _ | Jnz _ | Out | In | Send _ | Recv _
  | Waitc _ | Skne | Skeq | Fine | Cnta | Bank _ | Cfg | Ext_reserved _ -> false

let join_acc x y = match x, y with
  | Known a, Known b -> if a = b then Known a else Any
  | Known _, Any | Any, Known _ | Any, Any -> Any

(* successors of the instruction at [pc] *)
let successors ~fetch ~page pc =
  let nx = (pc + 1) land 0xFF in
  match decode (fetch ((page lsl 8) lor pc)) with
  | Jmp a -> [ a ] | Jnz a -> [ a; nx ]
  | Waitp { fail; _ } | Send { fail; _ } | Recv { fail; _ } | Waitc { fail; _ } -> [ fail; nx ]
  | Waitd | In -> [ nx ]
  | Skne | Skeq -> [ nx; (pc + 2) land 0xFF ]
  | Nop | Setp _ | Ldc | Ldd | Lda | Sho _ | Shi _ | Out | Fine | Cnta | Ldb | Stb | Bank _ | Cfg -> [ nx ]
  | Ext_reserved s -> raise (Unhandled (Printf.sprintf "page %d pc %d: reserved EXT operation %d" page pc s))

(* Reachable addresses with, at each, the values the bank pointer can hold and the channels the
   thread's last SEND can name, by a forward data-flow fixpoint from reset (bp 0, acc 0, lsend 0,
   as the RTL resets them). The pointer is a set of the 1024 bank addresses: BANK sets it from
   its immediate and the accumulator (all 256 low bytes when the accumulator is not a known
   constant), LDB and STB add one (mod 1024, so a carry into bank 1 is followed), everything else
   keeps it. The accumulator is tracked only as far as LDA's immediate. SEND sets lsend on every
   path, taken or not (D3). The sets only grow and are finite, so the fixpoint is reached; a
   pointer stepped in a loop grows to every address the loop could reach without a bound on the
   loop count, which over-approximates. *)
let flow ~fetch ~page ~start =
  let bps = Array.init 256 (fun _ -> Array.make 1024 false) and acc = Array.make 256 Any
  and lsend = Array.make 256 0 and seen = Array.make 256 false in
  let work = Queue.create () in
  let join pc (bp : bool array) a l =
    let changed = ref (not seen.(pc)) in
    Array.iteri (fun i v -> if v && not bps.(pc).(i) then (bps.(pc).(i) <- true; changed := true)) bp;
    let a' = if not seen.(pc) then a else join_acc acc.(pc) a in
    if a' <> acc.(pc) then changed := true;
    acc.(pc) <- a';
    let nl = lsend.(pc) lor l in
    if nl <> lsend.(pc) then changed := true;
    lsend.(pc) <- nl;
    if !changed then (seen.(pc) <- true; Queue.push pc work) in
  join start (Array.init 1024 (fun i -> i = 0)) (Known 0) 1;
  while not (Queue.is_empty work) do
    let pc = Queue.pop work in
    let w = fetch ((page lsl 8) lor pc) in
    let i = decode w in
    let bp = bps.(pc) in
    let bp' = match bank_sel i with
      | Some sel ->
        let lows = match acc.(pc) with Known a -> [ a land 0xFF ] | Any -> List.init 256 Fun.id in
        let n = Array.make 1024 false in List.iter (fun lo -> n.((sel lsl 8) lor lo) <- true) lows; n
      | None -> if steps_bp i then Array.init 1024 (fun k -> bp.((k + 1023) land 1023)) else Array.copy bp in
    let a' = acc_after i ~imm:(w land 0xFF) acc.(pc)
    and l = (match send_ch i with Some c -> 1 lsl c | None -> lsend.(pc)) in
    List.iter (fun s -> join s bp' a' l) (successors ~fetch ~page pc)
  done;
  let bits m n = List.filter (fun i -> (m lsr i) land 1 = 1) (List.init n Fun.id) in
  List.filter_map (fun pc ->
      if seen.(pc) then Some (pc, List.filter (fun a -> bps.(pc).(a)) (List.init 1024 Fun.id), bits lsend.(pc) 8) else None)
    (List.init 256 Fun.id)

let uses_of_thread ~fetch ~(decl : decl) t =
  let page, start = decl.boot.(t) in
  let actor = Thread t in
  let at pc = (page lsl 8) lor pc in
  List.concat_map (fun (pc, cells, lsends) ->
      let i = decode (fetch (at pc)) in
      let mk ?(wait = No_wait) ?(cells = []) res kind text = { res; kind; actor; addr = at pc; wait; text; cells } in
      (* one use per bank the pointer can be in, with the addresses in that bank *)
      let per_bank kind text =
        List.filter_map (fun b ->
            match List.filter (fun a -> a lsr 9 = b) cells with
            | [] -> None
            | cs -> Some (mk ~cells:cs (Bankr b) kind text)) [ 0; 1 ] in
      let wc fail = wait_class ~fetch ~page ~self:pc ~fail in
      match i with
      | Setp { mask } -> List.filter_map (fun p -> if (mask lsr p) land 1 = 1 then Some (mk (Pin p) Pin_drive "SETP") else None) [ 0; 1; 2; 3; 4; 5; 6; 7 ]
      | Sho { pin; pair; cap } ->
        [ mk (Pin pin) Pin_drive "SHO" ]
        @ (if pair then [ mk (Pin ((pin + 1) land 7)) Pin_drive "SHO pair" ] else [])
        @ (if cap then [ mk (Pin (pin lxor 1)) Pin_sample "SHO capture" ] else [])
      | Waitp { pin; _ } -> [ mk (Pin pin) Pin_sample "WAITP" ]
      | Shi { pin } -> [ mk (Pin pin) Pin_sample "SHI" ]
      | Ldb -> per_bank Bank_read "LDB"
      | Stb -> per_bank Bank_write "STB"
      | Send { ch; fail } ->
        if ch < 4 then [ mk ~wait:(wc fail) (Inbox ch) Send_k "SEND" ] else [ mk ~wait:(wc fail) (Feed (ch - 4)) Feed_push "SEND port" ]
      | Recv { ch; fail } ->
        if ch < 4 then [ mk ~wait:(wc fail) (Inbox ch) Recv_k "RECV" ] else [ mk ~wait:(wc fail) (Tap (ch - 4)) Tap_pop "RECV port" ]
      | Waitc { cond; fail } ->
        if cond = Isa2.c_inbox then [ mk ~wait:(wc fail) (Inbox t) Poll "WAITC 10" ]
        else if cond = Isa2.c_space then
          List.map (fun ch -> if ch < 4 then mk ~wait:(wc fail) (Inbox ch) Space_wait "WAITC 11"
                     else mk ~wait:(wc fail) (Feed (ch - 4)) Feed_push "WAITC 11 (port)") lsends
        else []
      | Ext_reserved s -> raise (Unhandled (Printf.sprintf "T%d pc %d: reserved EXT operation %d" t pc s))
      | Nop | Ldc | Ldd | Lda | Waitd | Jmp _ | Jnz _ | Out | In | Skne | Skeq | Fine | Cnta | Bank _ | Cfg -> [])
    (flow ~fetch ~page ~start)

let declared_uses (d : decl) =
  List.map (fun (b, period, offset) ->
      { res = Bankr b; kind = Bank_refresh; actor = Refresher; addr = -1; wait = No_wait;
        text = Printf.sprintf "refresh every %d clocks at %d" period offset; cells = [] }) d.refresh
  @ List.map (fun (b, seg) ->
      { res = Bankr b; kind = Bank_stream; actor = Array_seg seg; addr = -1; wait = No_wait; text = "array stream, every clock";
        cells = [] }) d.streams

(* clocks an actor can use a resource in: (period, offset) *)
let clocks (d : decl) u =
  match u.actor with
  | Thread t -> (n_threads, t)
  | Array_seg _ -> (1, 0)
  | Refresher -> (match u.res with
      | Bankr b -> (match List.find_opt (fun (b', _, _) -> b' = b) d.refresh with Some (_, p, o) -> (p, o) | None -> (1, 0))
      | Pin _ | Inbox _ | Feed _ | Tap _ -> (1, 0))
let rec gcd a b = if b = 0 then a else gcd b (a mod b)
let coincide d u v =
  let pa, oa = clocks d u and pb, ob = clocks d v in
  let g = gcd pa pb in ((oa - ob) mod g + g) mod g = 0

(* Is the use within the thread's declaration? Pins: [grants]; everything else: [owns]. A kind
   that does not belong to its resource's class cannot reach here ([check] raises first). *)
let is_declared (d : decl) u =
  match u.actor with
  | Refresher | Array_seg _ -> true
  | Thread t ->
    let o = d.owns.(t) in
    (match u.res, u.kind with
     | Pin _, (Pin_drive | Pin_sample) -> List.exists (fun (r, a, ks) -> r = u.res && a = u.actor && List.mem u.kind ks) d.grants
     | Bankr _, Bank_read -> u.cells <> [] && List.for_all (Ownership.in_ranges o.bank_read) u.cells
     | Bankr _, Bank_write -> u.cells <> [] && List.for_all (Ownership.in_ranges o.bank_write) u.cells
     | Inbox i, (Send_k | Space_wait) -> List.mem i o.inbox_send
     | Inbox i, (Recv_k | Poll) -> List.mem i o.inbox_recv
     | Feed j, Feed_push -> List.mem j o.port_out
     | Tap j, Tap_pop -> List.mem j o.port_in
     | Pin _, (Bank_read | Bank_write | Bank_refresh | Bank_stream | Send_k | Space_wait | Recv_k | Poll | Feed_push | Tap_pop)
     | Bankr _, (Pin_drive | Pin_sample | Bank_refresh | Bank_stream | Send_k | Space_wait | Recv_k | Poll | Feed_push | Tap_pop)
     | Inbox _, (Pin_drive | Pin_sample | Bank_read | Bank_write | Bank_refresh | Bank_stream | Feed_push | Tap_pop)
     | Feed _, (Pin_drive | Pin_sample | Bank_read | Bank_write | Bank_refresh | Bank_stream | Send_k | Space_wait | Recv_k | Poll | Tap_pop)
     | Tap _, (Pin_drive | Pin_sample | Bank_read | Bank_write | Bank_refresh | Bank_stream | Send_k | Space_wait | Recv_k | Poll | Feed_push) ->
       false)

(* the bank addresses of a use outside the declared ranges, as text *)
let cells_outside (d : decl) u =
  match u.actor, u.kind with
  | Thread t, (Bank_read | Bank_write) ->
    let r = if u.kind = Bank_read then d.owns.(t).bank_read else d.owns.(t).bank_write in
    (match List.filter (fun a -> not (Ownership.in_ranges r a)) u.cells with
     | [] -> ""
     | out -> let n = List.length out in
       Printf.sprintf ", addresses %s%s outside %s" (String.concat "," (List.map string_of_int (List.filteri (fun i _ -> i < 8) out)))
         (if n > 8 then Printf.sprintf ",... (%d in all)" n else "") (Ownership.ranges_text r))
  | (Thread _ | Refresher | Array_seg _),
    (Pin_drive | Pin_sample | Bank_refresh | Bank_stream | Send_k | Space_wait | Recv_k | Poll | Feed_push | Tap_pop)
  | (Refresher | Array_seg _), (Bank_read | Bank_write) -> ""

let shared (d : decl) r a b = List.exists (fun (r', g) -> r' = r && List.mem a g && List.mem b g) d.shared

type finding = { rule : string; key : string; where : string }

let where_of u = if u.addr < 0 then Printf.sprintf "%s (%s)" (actor_name u.actor) u.text
  else Printf.sprintf "%s page %d pc %d (%s)" (actor_name u.actor) (u.addr lsr 8) (u.addr land 0xFF) u.text

let last_waived : string list ref = ref []

(* Ownership declarations that overlap where they must not: two threads that may write one bank
   address (like two drivers of one pin), or two threads on one port in the same direction (a
   port is one external device's). A bank address one thread writes and another reads is a
   declared channel, not a fault; it is listed by [channels]. Inboxes need no rule here: two
   senders or two receivers of one inbox are PAIR rejections already, and a declared
   multi-producer inbox is [shared]. *)
let meet r1 r2 = List.exists (fun (a, b) -> List.exists (fun (c, e) -> a <= e && c <= b) r2) r1
let overlaps (d : decl) =
  let o = d.owns in
  List.concat (List.init 4 (fun t -> List.concat (List.init 4 (fun u ->
      if t >= u then [] else
        (if meet o.(t).bank_write o.(u).bank_write then [ Printf.sprintf "T%d and T%d may both write one bank address" t u ] else [])
        @ List.filter_map (fun j -> if List.mem j o.(u).port_out then Some (Printf.sprintf "T%d and T%d may both send to port %d" t u j) else None) o.(t).port_out
        @ List.filter_map (fun j -> if List.mem j o.(u).port_in then Some (Printf.sprintf "T%d and T%d may both receive from port %d" t u j) else None) o.(t).port_in))))

(* What the declaration lets one thread pass to another: bank addresses written by one and read
   by the other, and inboxes. A thread with no incoming channel is isolated from the others'
   bank and mailbox traffic; this is what an isolation argument may assume. *)
let channels (d : decl) =
  let o = d.owns in
  List.concat (List.init 4 (fun t -> List.concat (List.init 4 (fun u ->
      if t = u then [] else
        (if meet o.(t).bank_write o.(u).bank_read then
           [ Printf.sprintf "T%d -> T%d through the bank (T%d writes %s, T%d reads %s)" t u t (Ownership.ranges_text o.(t).bank_write)
               u (Ownership.ranges_text o.(u).bank_read) ] else [])
        @ List.filter_map (fun i -> if List.mem i o.(u).inbox_recv then Some (Printf.sprintf "T%d -> T%d through inbox %d" t u i) else None)
          o.(t).inbox_send))))

let check ?(tables = default_tables) ~fetch (d : decl) =
  Ownership.check_well_formed d.owns;
  List.iter (fun (r, _, _) -> match r with
      | Pin _ -> ()
      | Bankr _ | Inbox _ | Feed _ | Tap _ -> raise (Bad_table ("grants are for pins; declare " ^ res_name r ^ " in owns")))
    d.grants;
  let uses = List.concat (List.init n_threads (uses_of_thread ~fetch ~decl:d)) @ declared_uses d in
  let rejected = ref [] in
  last_waived := [];
  let reject rule key where = rejected := { rule; key; where } :: !rejected in
  (* SOLO *)
  List.iter (fun u ->
      if class_of u.kind <> class_of_res u.res then raise (Unhandled ("use of the wrong class: " ^ where_of u));
      let key = (u.kind, u.wait, (if is_declared d u then Declared else Undeclared)) in
      if not (List.mem_assoc key tables.solo) then
        let k, w, r = key in
        let text = Printf.sprintf "(%s, %s, %s) on %s%s" (kind_name k) (wait_name w) (if r = Declared then "declared" else "UNDECLARED")
            (res_name u.res) (cells_outside d u) in
        match List.find_opt (fun (res, a, kd, _) -> res = u.res && a = u.actor && kd = u.kind) d.waivers with
        | Some (_, _, _, why) -> last_waived := Printf.sprintf "%s at %s -- %s" text (where_of u) why :: !last_waived
        | None -> reject "solo" text (where_of u))
    uses;
  (* PAIRS: one representative per (actor, kind, resource) *)
  let reps = List.sort_uniq (fun a b -> compare (a.res, a.actor, a.kind) (b.res, b.actor, b.kind)) uses in
  let seen = Hashtbl.create 16 in
  List.iter (fun u ->
      List.iter (fun v ->
          if u.res = v.res && u.actor <> v.actor
             && (index u.kind < index v.kind || (u.kind = v.kind && compare u.actor v.actor < 0)) then begin
            let c = coincide d u v and s = shared d u.res u.actor v.actor in
            let key = (u.kind, v.kind, c, s) in
            if not (List.mem_assoc key tables.pairs) && not (Hashtbl.mem seen (u.res, key, u.actor, v.actor)) then begin
              Hashtbl.replace seen (u.res, key, u.actor, v.actor) ();
              reject "pair" (Printf.sprintf "(%s, %s, %s, %s) on %s" (kind_name u.kind) (kind_name v.kind)
                               (if c then "SAME CLOCK possible" else "different clocks") (if s then "declared shared" else "not shared")
                               (res_name u.res)) (where_of u ^ " / " ^ where_of v)
            end
          end) reps) reps;
  (* OWNERSHIP: overlapping declarations *)
  List.iter (fun s -> reject "ownership" s "the declaration") (overlaps d);
  (* COUNTERPART *)
  List.iter (fun u ->
      match counterpart_kinds u.kind with
      | None -> ()
      | Some ks ->
        if not (List.exists (fun v -> v.res = u.res && v.actor <> u.actor && List.mem v.kind ks) reps) then
          reject "counterpart" (Printf.sprintf "%s on %s with no %s by another thread" (kind_name u.kind) (res_name u.res)
                                  (String.concat "/" (List.map kind_name ks))) (where_of u)) reps;
  (uses, List.rev !rejected)

(* ---- reports ---- *)
let print_table oc (t : tables) =
  let p fmt = Printf.fprintf oc fmt in
  p "SOLO table: every (kind, wait class, declaration); a row without a reason is REJECTED\n";
  List.iter (fun k ->
      List.iter (fun w ->
          if waits_apply k <> (w = No_wait) then
            List.iter (fun r ->
                let key = (k, w, r) in
                p "  %-24s %-9s %-10s %s\n" (kind_name k) (wait_name w) (if r = Declared then "declared" else "undeclared")
                  (match List.assoc_opt key t.solo with Some why -> "allowed: " ^ why | None -> "REJECTED"))
              [ Declared; Undeclared ]) [ No_wait; Bounded; Unbounded ]) all_kinds;
  p "\nPAIR table: every two kinds of one resource class used by different actors\n";
  List.iter (fun a ->
      List.iter (fun b ->
          if class_of a = class_of b && index a <= index b then
            List.iter (fun c ->
                List.iter (fun s ->
                    p "  %-22s %-22s %-14s %-10s %s\n" (kind_name a) (kind_name b) (if c then "same clock" else "other clocks")
                      (if s then "shared" else "not shared")
                      (match List.assoc_opt (a, b, c, s) t.pairs with Some why -> "allowed: " ^ why | None -> "REJECTED"))
                  [ false; true ]) [ false; true ]) all_kinds) all_kinds

let summarise uses =
  let by = Hashtbl.create 16 in
  List.iter (fun u ->
      let k = (u.res, u.actor) in
      let l = Option.value ~default:[] (Hashtbl.find_opt by k) in
      let tag = kind_name u.kind ^ (if u.wait = No_wait then "" else "/" ^ wait_name u.wait) in
      if not (List.mem tag l) then Hashtbl.replace by k (tag :: l)) uses;
  Hashtbl.fold (fun (r, a) l acc -> Printf.sprintf "%s %s: %s" (res_name r) (actor_name a) (String.concat ", " (List.rev l)) :: acc) by []
  |> List.sort compare

(* Check one programme set and print what was found; returns the findings. *)
let report ?tables ~name ~fetch (d : decl) =
  Printf.printf "== %s\n" name;
  match check ?tables ~fetch d with
  | uses, findings ->
    List.iter (Printf.printf "   uses: %s\n") (summarise uses);
    List.iter (Printf.printf "   channel: %s\n") (channels d);
    List.iter (Printf.printf "   WAIVED %s\n") (List.rev !last_waived);
    if findings = [] then Printf.printf "   ACCEPTED: no rejected combination\n"
    else List.iter (fun f -> Printf.printf "   REJECTED [%s] %s\n      at %s\n" f.rule f.key f.where) findings;
    print_newline ();
    findings
  | exception Unhandled m -> Printf.printf "   UNHANDLED (fails loudly): %s\n\n" m; [ { rule = "unhandled"; key = m; where = "" } ]

(* the same table with some pair entries removed, to show an entry is load-bearing *)
let without_pairs pred (t : tables) = { t with pairs = List.filter (fun (k, _) -> not (pred k)) t.pairs }

(* Evidence for a drain argument: the waits in thread [t]'s reachable code that can last for
   ever, other than [except] (e.g. its RECV on the inbox in question). IN, and any wait whose
   failure path returns to itself, count. JNZ loops are not judged here (they end when cnt does). *)
let unbounded_waits ~fetch ~(decl : decl) t ~except =
  let page, start = decl.boot.(t) in
  List.filter_map (fun (pc, _, _) ->
      let i = decode (fetch ((page lsl 8) lor pc)) in
      let w = match i with
        | In -> Some "IN"
        | Waitp { fail; _ } -> if wait_class ~fetch ~page ~self:pc ~fail = Unbounded then Some "WAITP" else None
        | Waitc { fail; _ } -> if wait_class ~fetch ~page ~self:pc ~fail = Unbounded then Some "WAITC" else None
        | Send { fail; _ } -> if wait_class ~fetch ~page ~self:pc ~fail = Unbounded then Some "SEND" else None
        | Recv { fail; ch } ->
          if List.mem (Inbox ch) except then None
          else if wait_class ~fetch ~page ~self:pc ~fail = Unbounded then Some "RECV" else None
        | Jmp a -> if a = pc then Some "HALT (JMP self)" else None
        | Nop | Setp _ | Ldc | Ldd | Lda | Waitd | Sho _ | Shi _ | Jnz _ | Out | Skne | Skeq | Fine | Cnta | Ldb | Stb
        | Bank _ | Cfg | Ext_reserved _ -> None in
      Option.map (fun w -> Printf.sprintf "%s at pc %d" w pc) w) (flow ~fetch ~page ~start)
