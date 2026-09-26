(* Replacement for ../../../multi-proto/isa_mb.ml backed by ISA v2, for the bridges.

   The interface bridge_lib.ml and the bench use is kept: cfg, the interpreter-only faults, io,
   effects, a state with pcs/accs/cnts/dls/pin_out/pin_oe/thread and each inbox as a list. The
   state wraps v2's (field [v]); the arrays are v2's own, and the scalar fields and the inbox
   lists are refreshed after every step.

   Differences, each loud rather than silent:
   - v2's inboxes hold one byte: [init] refuses a cfg with depth <> 1.
   - Faults: Drop_push n is implemented (the n-th successful push into an inbox is lost). Lifo is
     the identity at depth 1, and Swap_pair needs two bytes in one inbox, so both are refused.
   - Every execution of a WAITC 11 that the assembler put in place of "inbox i not full" checks
     that the thread's last SEND went to inbox i ([lsend_violations] counts the failures). *)

let n_threads = 4

type fault = No_fault | Drop_push of int | Lifo | Swap_pair of int
type cfg = { pc_bits : int; depth : int; fault : fault }

let cfg ?(pc_bits = 7) ?(depth = 1) ?(fault = No_fault) () = { pc_bits; depth; fault }
let prog_len c = 1 lsl c.pc_bits

let cond_full i = 8 + i
let cond_flag i = 12 + i
let shx ?(msb = 1) ~pin ~cpin () =
  (7 lsl 12) lor ((pin land 7) lsl 9) lor (msb lsl 8) lor (1 lsl 6) lor ((cpin land 7) lsl 3)

type io = {
  pin_in : int; host_in : int; host_in_valid : bool;
  port_in : int array; port_in_valid : bool array; port_out_ready : bool array;
  flags : int;
}

let idle_io = { pin_in = 0; host_in = 0; host_in_valid = false; port_in = Array.make 4 0;
                port_in_valid = Array.make 4 false; port_out_ready = Array.make 4 false; flags = 0 }

type effects = {
  host_out : int option; host_in_ready : bool;
  port_pop : int option; port_push : (int * int) option;
  mb : [ `Push of int * int | `Pop of int * int | `None ];
}

type state = {
  v : Isa2.state; c : cfg;
  pcs : int array; accs : int array; cnts : int array; dls : int array;
  mutable pin_out : int; mutable pin_oe : int; mutable thread : int;
  inbox : int list array;
  mutable pushes : int;
  mutable swapped : (int * int) option;
  mutable memo : (int array array * (int -> int) * (int * int, int) Hashtbl.t) option;
}

let lsend_violations = ref 0
let lsend_checked = ref 0

let init c =
  if c.depth <> 1 then failwith (Printf.sprintf "v2 inboxes hold one byte; depth %d requested" c.depth);
  (match c.fault with Lifo | Swap_pair _ -> failwith "ordering faults need an inbox of depth >= 2" | _ -> ());
  let v = Isa2.init ~boot:Compat.boot_by_thread () in
  { v; c; pcs = v.pcs; accs = v.accs; cnts = v.cnts; dls = v.dls; pin_out = 0; pin_oe = 0; thread = 0;
    inbox = Array.make n_threads []; pushes = 0; swapped = None; memo = None }

let counts st = Array.map List.length st.inbox

(* v2 words from Asm, or raw base-ISA words (the benches' all-HALT threads) translated here *)
let fetch_of (mem : int array array) =
  let v2 = Array.map Asm.is_v2 mem in
  fun a ->
    let t = a lsr Isa2.pc_bits and pc = a land (Isa2.page_len - 1) in
    if pc >= Array.length mem.(t) then 0
    else if v2.(t) then mem.(t).(pc) else Compat.of_base ~pc_bits:7 ~addr:pc mem.(t).(pc)

let checks_of (mem : int array array) =
  let h = Hashtbl.create 8 in
  List.iter (fun (p, a, i) -> Array.iteri (fun t q -> if q == p then Hashtbl.replace h (t, a) i) mem) !Asm.space_checks;
  h

let to_v2_io (io : io) =
  let f = io.flags land 15 in
  Isa2.io ~host_in:io.host_in ~host_in_valid:io.host_in_valid ~port_in:io.port_in
    ~port_in_valid:io.port_in_valid ~port_out_ready:io.port_out_ready
    ~flags:(f lor (f lsl 4) lor (f lsl 8) lor (f lsl 12)) io.pin_in

let step st ~(mem : int array array) (io : io) =
  let fetch, checks = match st.memo with
    | Some (m, f, h) when m == mem -> f, h
    | _ -> let f = fetch_of mem and h = checks_of mem in st.memo <- Some (mem, f, h); f, h in
  let v = st.v in
  let t = v.thread in
  (match Hashtbl.find_opt checks (t, v.pcs.(t)) with
   | Some i -> incr lsend_checked; if v.lsend.(t) <> i then incr lsend_violations
   | None -> ());
  let full0 = Array.copy v.full in
  let e = Isa2.step_f v ~fetch (to_v2_io io) in
  let mb = ref `None in
  Array.iteri (fun i f0 ->
      if f0 = 0 && v.full.(i) = 1 then begin
        st.pushes <- st.pushes + 1;
        mb := `Push (i, v.inbox.(i));
        (match st.c.fault with Drop_push n when st.pushes = n -> v.full.(i) <- 0 | _ -> ())
      end else if f0 = 1 && v.full.(i) = 0 then mb := `Pop (i, v.inbox.(i))) full0;
  st.pin_out <- v.pin_out; st.pin_oe <- v.pin_oe; st.thread <- v.thread;
  Array.iteri (fun i f -> st.inbox.(i) <- (if f = 1 then [ v.inbox.(i) ] else [])) v.full;
  { host_out = Option.map snd e.host_out; host_in_ready = e.host_in_ready; port_pop = e.port_pop;
    port_push = e.port_push; mb = !mb }
