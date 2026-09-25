(* The SWD checks. Needs the wide ISA (the engine does not fit 64 words). *)

open Swd_host
open Swd_test

let pr fmt = Printf.printf (fmt ^^ "\n%!")

let trace_diff (a : run) (b : run) =
  let n = min (Array.length a.trace) (Array.length b.trace) in
  let d = ref (abs (Array.length a.trace - Array.length b.trace)) in
  for i = 0 to n - 1 do if a.trace.(i) <> b.trace.(i) then incr d done;
  n, !d

let the_dpidr = 0x2BA01477 and the_ap_idr = 0x24770011

let cfg ?(wait_p = 0.0) ~seed () =
  let st = Random.State.make [| seed; 3 |] in
  { Swd_target.dpidr = the_dpidr; ap_idr = the_ap_idr; mem_words = 256;
    wait_on_ap = (fun () -> wait_p > 0.0 && Random.State.float st 1.0 < wait_p); start_in_swd = false }

(* A scenario: the actions and a judge over the run. *)
type scenario = { actions : action list; judge : run -> string list }

let expect_value tag v (r : run) =
  match find_tag r tag with
  | None -> [ tag ^ ": missing" ]
  | Some o when o.ack <> Ok -> [ Printf.sprintf "%s: ACK %s" tag (string_of_ack o.ack) ]
  | Some o -> if o.data = Some v then [] else
      [ Printf.sprintf "%s: read %s want %08x" tag (match o.data with Some d -> Printf.sprintf "%08x" d | None -> "-") v ]

(* Directed: bring-up, CTRL/STAT power-up handshake, memory, the AP's IDR through bank 0xF. *)
let directed =
  let words = [ 0x10, 0xDEADBEEF; 0x14, 0x01234567; 0x3FC, 0x80000001 ] in
  let actions =
    bring_up
    @ List.concat_map (fun (a, v) -> mem_write a v) words
    @ List.concat_map (fun (a, _) -> mem_read a) words
    @ [ txn (dp_write select idr_bank); txn ~tag:"idr posted" (ap_read 0xC); txn ~tag:"idr" (dp_read rdbuff);
        txn (dp_write select 0) ] in
  { actions;
    judge = (fun r ->
      common_fails r @ ack_fails r
      @ expect_value "dpidr" the_dpidr r
      @ (match find_tag r "ctrlstat" with
         | Some { data = Some d; _ } when d land 0xA000_0000 = 0xA000_0000 -> []
         | Some { data = Some d; _ } -> [ Printf.sprintf "CTRL/STAT %08x lacks the power-up ACKs" d ]
         | _ -> [ "ctrlstat: no data" ])
      @ List.concat_map (fun (a, v) -> expect_value (Printf.sprintf "r%08x" a) v r) words
      @ expect_value "idr" the_ap_idr r
      @ List.concat_map (fun (a, v) ->
          let m = (Swd_target.mem r.target).(a / 4) in
          if m = v then [] else [ Printf.sprintf "target memory [%x] = %08x want %08x" a m v ]) words) }

(* FAULT and recovery. A write whose data parity is wrong is ACKed OK (the ACK comes before the
   data) and must be discarded with WDATAERR set; the next AP access then gets FAULT; ABORT with
   WDERRCLR clears it. A request with a parity error gets no response at all; a line reset and a
   DPIDR read bring the link back. *)
let faults =
  let actions =
    bring_up @ mem_write 0x20 0x11111111
    @ [ txn (ap_write tar 0x20); txn ~bad_wparity:true ~tag:"badpar" (ap_write drw 0x22222222);
        txn ~tag:"faulted" (ap_write tar 0x24);
        txn ~tag:"ctrlstat after" (dp_read ctrl_stat);
        txn ~tag:"abort" (dp_write abort 0x08);   (* WDERRCLR *)
        txn ~bad_parity:true ~tag:"badreq" (dp_read dpidr);
        Cmd cmd_line_reset; txn ~tag:"dpidr again" (dp_read dpidr) ]
    @ mem_read 0x20 in
  { actions;
    judge = (fun r ->
      let allow (o : outcome) = List.mem o.tag [ "faulted"; "badreq" ] in
      common_fails r @ ack_fails ~allow r
      @ (match find_tag r "faulted" with Some { ack = Fault; _ } -> [] | Some o -> [ "faulted: ACK " ^ string_of_ack o.ack ] | None -> [ "faulted missing" ])
      @ (match find_tag r "badreq" with Some { ack = Other 7; _ } -> [] | Some o -> [ "badreq: ACK " ^ string_of_ack o.ack ^ ", want no response" ] | None -> [ "badreq missing" ])
      @ (match find_tag r "ctrlstat after" with
         | Some { data = Some d; _ } when d land 0x80 <> 0 -> []
         | _ -> [ "CTRL/STAT does not show WDATAERR" ])
      @ expect_value "dpidr again" the_dpidr r
      @ expect_value "r00000020" 0x11111111 r) }

(* Constrained random memory traffic with a shadow memory. *)
let random_traffic st ~n =
  let shadow = Hashtbl.create 64 in
  let expects = ref [] in
  let acts = ref [] in
  for i = 1 to n do
    let addr = 4 * Random.State.int st 256 in
    if Random.State.bool st || not (Hashtbl.mem shadow addr) then begin
      let v = (Random.State.bits st lor (Random.State.bits st lsl 30)) land 0xFFFFFFFF in
      Hashtbl.replace shadow addr v;
      acts := !acts @ mem_write addr v
    end else begin
      let tag = Printf.sprintf "rd%d" i in
      expects := (tag, Hashtbl.find shadow addr) :: !expects;
      acts := !acts @ [ txn (ap_write tar addr); txn (ap_read drw); txn ~tag (dp_read rdbuff) ]
    end
  done;
  { actions = bring_up @ !acts;
    judge = (fun r ->
      common_fails r @ ack_fails r
      @ expect_value "dpidr" the_dpidr r
      @ List.concat_map (fun (tag, v) -> expect_value tag v r) !expects
      @ Hashtbl.fold (fun a v acc ->
          let m = (Swd_target.mem r.target).(a / 4) in
          if m = v then acc else Printf.sprintf "target memory [%x] = %08x want %08x" a m v :: acc) shadow []) }

(* One scenario on both cores. *)
let both ?(knobs = Swd_host.fastest) ?(sync = 2) ?(tco = 0) ?(stall_p = 0.0) ?(wait_p = 0.0) ~seed sc =
  let mem, _ = Swd_host.programmes knobs in
  let go mk =
    let sst = Random.State.make [| seed; 9 |] in
    let stall = Jtag_suite.stall_fn sst stall_p in
    let r = run ~sync ~tco ~stall ~mk ~mem ~cfg:(cfg ~wait_p ~seed ()) sc.actions in
    sc.judge r, r in
  let fi, ri = go Asm.interp and fr, rr = go Asm.rtl in
  let n, d = trace_diff ri rr in
  fi, fr, n, d, ri

let show f = if f = [] then "PASS" else String.concat " | " (List.filteri (fun i _ -> i < 3) f)

let waits (r : run) = List.fold_left (fun a o -> a + o.retries) 0 r.outcomes

let main () =
  let ok = ref true in
  let _, len = Swd_host.programmes Swd_host.fastest in
  pr "SWD engine: %d words (store: %d per thread)" len Isa.prog_len;
  let fi, fr, n, d, ri = both ~seed:1 directed in
  pr "directed bring-up (switch, DPIDR, power-up, SELECT, CSW, 3 writes, 3 posted reads, AP IDR):";
  pr "  interpreter %s; RTL %s; %d clocks compared, %d differ; %d SWCLK cycles, %d packets"
    (show fi) (show fr) n d ri.wire_bits (List.length ri.outcomes);
  if fi <> [] || fr <> [] || d <> 0 then ok := false;
  let fi, fr, n, d, ri = both ~seed:2 faults in
  pr "FAULT and recovery (bad write parity -> WDATAERR -> FAULT -> ABORT; bad request parity -> no ACK -> line reset):";
  pr "  interpreter %s; RTL %s; %d clocks compared, %d differ; target log tail: %s"
    (show fi) (show fr) n d
    (String.concat "; " (let l = Swd_target.log ri.target in List.filteri (fun i _ -> i >= List.length l - 4) l));
  if fi <> [] || fr <> [] || d <> 0 then ok := false;
  (* constrained random *)
  let st = Random.State.make [| 5 |] in
  let runs = 40 in
  let pass = ref 0 and clocks = ref 0 and differ = ref 0 and wbits = ref 0 and nwait = ref 0 and pk = ref 0 in
  let first = ref None in
  for i = 1 to runs do
    let sc = random_traffic st ~n:(10 + Random.State.int st 30) in
    let sync = Random.State.int st 4 and tco = Random.State.int st 4 in
    let wait_p = Random.State.float st 0.5 in
    let fi, fr, n, d, ri = both ~sync ~tco ~stall_p:0.02 ~wait_p ~seed:(100 + i) sc in
    clocks := !clocks + n; differ := !differ + d; wbits := !wbits + ri.wire_bits;
    nwait := !nwait + waits ri; pk := !pk + List.length ri.outcomes;
    if fi = [] && fr = [] && d = 0 then incr pass
    else if !first = None then first := Some (i, fi @ fr)
  done;
  pr "constrained random: %d/%d sessions pass on both cores (random addresses and data, WAIT injected" !pass runs;
  pr "  with p in [0,0.5), sync 0-3, target delay 0-3, host stalls); %d packets, %d WAITs retried;"
    !pk !nwait;
  pr "  %d clocks compared, %d differ; %d SWCLK cycles" !clocks !differ !wbits;
  (match !first with Some (i, f) -> pr "  first failure: run %d: %s" i (show f) | None -> ());
  if !pass <> runs then ok := false;
  (* controls *)
  pr "controls (each must fail on both cores, on random traffic):";
  let control name ?(knobs = Swd_host.fastest) ?(mutate = fun a -> a) () =
    let st = Random.State.make [| 6 |] in
    let caught = ref 0 and total = 10 and why = ref "" in
    for i = 1 to total do
      let sc = random_traffic st ~n:12 in
      let sc = { sc with actions = mutate sc.actions } in
      let fi, fr, _, _, _ = both ~knobs ~wait_p:0.2 ~seed:(300 + i) sc in
      if fi <> [] && fr <> [] then (incr caught; if !why = "" then why := List.hd fi)
    done;
    pr "  %-40s caught %d/%d  (e.g. %s)" name !caught total !why;
    if !caught <> total then ok := false in
  (* plant into the first packet from the ninth action on (after bring-up) *)
  let plant_req acts =
    let hit = ref false in
    List.mapi (fun i a -> match a with
      | Txn x when i >= 8 && not !hit -> hit := true; Txn { x with bad_parity = true }
      | a -> a) acts in
  let plant_wpar acts =
    let hit = ref false in
    List.mapi (fun i a -> match a with
      | Txn x when i >= 8 && not !hit && x.t.rnw = 0 -> hit := true; Txn { x with bad_wparity = true }
      | a -> a) acts in
  control "request parity flipped (one packet)" ~mutate:plant_req ();
  control "write-data parity flipped (one packet)" ~mutate:plant_wpar ();
  control "turnaround before ACK missing" ~knobs:{ Swd_host.fastest with no_trn = true } ();
  control "turnaround after write ACK missing" ~knobs:{ Swd_host.fastest with no_trn_write = true } ();
  control "sampling after the rising edge" ~knobs:{ Swd_host.fastest with late_sample = true } ();
  control "one wrong bit in the switch sequence" ~knobs:{ Swd_host.fastest with bad_switch = true } ();
  (* clock rate *)
  pr "SWCLK at a 60 MHz core clock (characterisation, not gated; directed scenario, interpreter and RTL):";
  List.iter (fun (lo, hi, sync, tco) ->
    let knobs = { Swd_host.fastest with lo; hi } in
    match both ~knobs ~sync ~tco ~seed:1 directed with
    | exception Failure m -> pr "  lo %d hi %d: %s" lo hi m
    | fi, fr, _, d, ri ->
    let s = Wire.clock_stats ri.swclk in
    pr "  lo %d hi %d sync %d tco %d: high >= %d, low >= %d, period %d-%d clocks -> %.2f MHz max: %s"
      lo hi sync tco s.min_high s.min_low s.min_period s.max_period (60.0 /. float_of_int s.min_period)
      (if fi = [] && fr = [] && d = 0 then "pass" else "FAIL " ^ show (fi @ fr)))
    [ 1, 1, 0, 0; 1, 1, 2, 0; 1, 1, 3, 3; 1, 1, 2, 8; 1, 1, 2, 9; 1, 1, 2, 10; 1, 1, 2, 12;
      1, 2, 2, 12; 1, 2, 2, 13; 1, 2, 2, 14; 1, 3, 2, 18 ];
  !ok
