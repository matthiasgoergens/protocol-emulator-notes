(* SWD host firmware against an independent SW-DP / MEM-AP model (Swd_target), SWDIO wired as one
   bidirectional line: the core's pad (pin_out, pin_oe), the target's driver and a pull-up.
   A clock where both drive is counted as contention.

   The host driver here plays the CPU behind the sequencer: it feeds packets as bytes, reads the
   ACK and data bytes back, retries on WAIT, and records the outcome of every packet. Expected
   values come from the test's own bookkeeping of what was written (a shadow memory) and from the
   ADIv5 rules the test states, not from the target model's state. *)

open Swd_host

type action =
  | Cmd of int                                       (* switch / line reset byte *)
  | Txn of { t : txn; bad_parity : bool; bad_wparity : bool; tag : string }

let txn ?(bad_parity = false) ?(bad_wparity = false) ?(tag = "") t = Txn { t; bad_parity; bad_wparity; tag }

type outcome = { tag : string; t : txn; ack : ack; data : int option; parity_ok : bool; retries : int }

type run = {
  outcomes : outcome list;
  trace : (int * int * int option * bool) array;
  swclk : int array; contention : int; cycles : int; stalls : int;
  target : Swd_target.t; complete : bool; wire_bits : int;
}

let run ?(debug = 0) ?(sync = 2) ?(tco = 0) ?(stall = fun () -> false) ?(max_retries = 64) ~mk ~mem ~cfg script =
  let tg = Swd_target.create cfg in
  let core : Asm.core = mk mem in
  let din = Wire.delay sync 0 and dtco = Wire.delay tco None in
  let pin_in = ref 0b10 in
  let contention = ref 0 and stalls = ref 0 in
  let trace = ref [] and clkt = ref [] in
  let outcomes = ref [] in
  let pending = ref script in
  (* the packet in flight *)
  let inq = Queue.create () in
  let cur = ref None and retries = ref 0 in
  let resp = ref [] and want_resp = ref 0 in
  let start () =
    match !pending with
    | [] -> ()
    | a :: rest ->
      pending := rest;
      (match a with
       | Cmd c -> Queue.push c inq; cur := Some a; want_resp := 0
       | Txn x -> List.iter (fun b -> Queue.push b inq) (bytes_of ~bad_parity:x.bad_parity ~bad_wparity:x.bad_wparity x.t);
         cur := Some a; want_resp := 1; resp := []) in
  let finish () =
    (match !cur with
     | Some (Txn x) ->
       let r = List.rev !resp in
       let ack = ack_of_byte (List.hd r) in
       if ack = Wait && !retries < max_retries then (incr retries; pending := Txn x :: !pending)
       else begin
         let data, parity_ok =
           if x.t.rnw = 1 && ack = Ok then
             let d = List.fold_left (fun (a, i) b -> (a lor (b lsl (8 * i)), i + 1)) (0, 0)
                 (List.filteri (fun i _ -> i >= 1 && i <= 4) r) |> fst in
             let p = (List.nth r 5 lsr 7) land 1 in
             Some d, p = parity d
           else None, true in
         outcomes := { tag = x.tag; t = x.t; ack; data; parity_ok; retries = !retries } :: !outcomes;
         retries := 0
       end
     | _ -> ());
    cur := None in
  let cyc = ref 0 and idle_after = ref 0 in
  let limit = 400_000 + 5_000 * List.length script in
  (* run until the script is done and the engine has been idle at its IN for a while *)
  while (!cur <> None || !pending <> [] || !idle_after < 400) && !cyc < limit do
    if !cur = None then start ();
    if !cur = None then incr idle_after else idle_after := 0;
    let stalled = (not (Queue.is_empty inq)) && stall () in
    if stalled then incr stalls;
    let valid = (not (Queue.is_empty inq)) && not stalled in
    let host_in = if valid then Queue.peek inq else 0 in
    let o = core.step ~pin_in:!pin_in ~host_in ~host_in_valid:valid in
    if o.host_in_ready then ignore (Queue.pop inq);
    (match o.host_out with
     | Some b ->
       resp := b :: !resp;
       if List.length !resp = 1 then
         (match !cur with
          | Some (Txn x) when x.t.rnw = 1 && ack_of_byte b = Ok -> want_resp := 6
          | _ -> ())
     | None -> ());
    trace := (o.pin_out, o.pin_oe, o.host_out, o.host_in_ready) :: !trace;
    let swclk = if Wire.bit o.pin_oe Wire.p_swclk = 1 then Wire.bit o.pin_out Wire.p_swclk else 0 in
    let dev_now = Wire.through dtco (Swd_target.drive tg) in
    let host_oe = Wire.bit o.pin_oe Wire.p_swdio = 1 in
    let swdio = Wire.resolve ~oe:host_oe ~out:(Wire.bit o.pin_out Wire.p_swdio) ~dev:dev_now ~pull:1 ~contention in
    let prev_clk = match !clkt with c :: _ -> c | [] -> 0 in
    if !cyc < debug && (prev_clk = 0 && swclk = 1 || o.host_in_ready || o.host_out <> None) then
      Printf.printf "  pc%-3d c%-6d %s swdio=%d host_oe=%b dev=%s in_ready=%b out=%s\n" !Asm.dbg_pc !cyc
        (if prev_clk = 0 && swclk = 1 then "RISE" else "    ") swdio host_oe
        (match dev_now with Some b -> string_of_int b | None -> "-") o.host_in_ready
        (match o.host_out with Some b -> Printf.sprintf "%02x" b | None -> "-");
    Swd_target.step tg ~swclk ~swdio;
    clkt := swclk :: !clkt;
    pin_in := Wire.through din (swclk lor (swdio lsl 1));
    (* a packet is complete when its bytes are consumed and its responses are in *)
    if !cur <> None && Queue.is_empty inq && List.length !resp >= !want_resp then finish ();
    incr cyc
  done;
  let swclk = Array.of_list (List.rev !clkt) in
  { outcomes = List.rev !outcomes; trace = Array.of_list (List.rev !trace); swclk;
    contention = !contention; cycles = !cyc; stalls = !stalls; target = tg;
    complete = !cur = None && !pending = []; wire_bits = (Wire.clock_stats swclk).rising }

(* ---- Scenarios ---- *)

(* DP and MEM-AP addresses (ADIv5) *)
let dpidr = 0x0 and abort = 0x0 and ctrl_stat = 0x4 and select = 0x8 and rdbuff = 0xC
let csw = 0x0 and tar = 0x4 and drw = 0xC and idr_bank = 0xF0

let bring_up =
  [ Cmd cmd_switch;
    txn ~tag:"dpidr" (dp_read dpidr);
    txn ~tag:"abort" (dp_write abort 0x1E);                 (* clear all sticky flags *)
    txn ~tag:"pwrup" (dp_write ctrl_stat 0x5000_0000);      (* CSYSPWRUPREQ | CDBGPWRUPREQ *)
    txn ~tag:"ctrlstat" (dp_read ctrl_stat);
    txn ~tag:"select0" (dp_write select 0);
    txn ~tag:"csw" (ap_write csw 0x2300_0002) ]              (* 32-bit accesses, no auto-increment *)

let mem_write addr v = [ txn (ap_write tar addr); txn ~tag:(Printf.sprintf "w%08x" addr) (ap_write drw v) ]
let mem_read addr =
  [ txn (ap_write tar addr); txn ~tag:"posted" (ap_read drw); txn ~tag:(Printf.sprintf "r%08x" addr) (dp_read rdbuff) ]

(* Judge a run against the host's own expectations. [expect] maps tags to predicates. *)
let common_fails (r : run) =
  (if r.complete then [] else [ "run did not complete" ])
  @ (if r.contention > 0 then [ Printf.sprintf "%d clocks of SWDIO contention" r.contention ] else [])
  @ List.filter_map (fun o ->
    if not o.parity_ok then Some (Printf.sprintf "%s: read parity error" o.tag) else None) r.outcomes

let ack_fails ?(allow = fun _ -> false) (r : run) =
  List.filter_map (fun o ->
    if o.ack <> Ok && not (allow o) then Some (Printf.sprintf "%s: ACK %s" (if o.tag = "" then "packet" else o.tag) (string_of_ack o.ack))
    else None) r.outcomes

let find_tag (r : run) tag = List.find_opt (fun o -> o.tag = tag) r.outcomes
