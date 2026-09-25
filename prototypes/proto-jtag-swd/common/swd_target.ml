(* Independent reference model of an SWJ-DP-style Serial Wire Debug target:
   one SW-DP plus one MEM-AP (APSEL 0), written from first principles
   against ARM Debug Interface v5.2 (ADIv5.2).  Stdlib only.  See
   NOTES.txt for the precise edge/turnaround conventions and every place
   this reading had to fill in a gap the task left open. *)

type config = {
  dpidr : int;
  ap_idr : int;
  mem_words : int;
  wait_on_ap : unit -> bool;
  start_in_swd : bool;
}

type phase =
  | Jtag_high1        (* mode = jtag: counting the leading >=50 high cycles *)
  | Jtag_magic        (* shifting in the 16-bit 0xE79E select sequence *)
  | Jtag_high2        (* counting the trailing line-reset >=50 high cycles *)
  | Idle              (* listening for a request start bit / a line reset *)
  | Req               (* shifting in the 8-bit request packet *)
  | Trn_to_ack        (* host -> target turnaround before ACK *)
  | Ack               (* target drives the 3 ACK bits *)
  | Trn_to_data_w     (* target -> host turnaround before write data *)
  | Data_w            (* host drives 32 data bits + 1 parity bit *)
  | Data_r            (* target drives 32 data bits + 1 parity bit *)
  | Trn_to_idle       (* target -> host turnaround after a read, or after WAIT/FAULT *)

type write_target = W_none | W_abort | W_ctrlstat | W_select | W_csw | W_tar | W_drw

type t = {
  cfg : config;
  mutable prev_swclk : int option;
  mutable mode : string;              (* "jtag" | "swd-reset" | "swd" *)
  mutable need_dpidr : bool;
  mutable phase : phase;
  (* line-reset / switch-sequence bookkeeping *)
  mutable high_run : int;             (* consecutive high cycles seen while not driving *)
  mutable magic_idx : int;
  (* request-packet bookkeeping *)
  mutable req_idx : int;
  mutable req_acc : int;
  (* ack bookkeeping *)
  mutable ack_idx : int;
  mutable ack_code : int;             (* 1 = OK, 2 = WAIT, 4 = FAULT *)
  (* data-phase bookkeeping *)
  mutable data_idx : int;
  mutable data_acc : int;             (* accumulator while receiving (write) *)
  mutable out_value : int;            (* value being shifted out (read) *)
  mutable out_parity : int;
  (* decoded-request context, valid from Ack through the end of the txn *)
  mutable is_ap : bool;
  mutable is_read : bool;
  mutable write_target : write_target;
  mutable dpidr_gate_pending : bool;  (* this txn is the DPIDR read that clears need_dpidr *)
  (* DP register state *)
  mutable ctrl_stat : int;
  mutable select_apsel : int;
  mutable select_apbank : int;
  mutable select_dpbank : int;
  mutable ap_read_buffer : int;
  (* AP register state (APSEL 0, a single MEM-AP) *)
  mutable csw : int;
  mutable tar : int;
  mutable mem : int array;
  (* diagnostics *)
  mutable log_rev : string list;
  mutable n_ok : int;
  mutable n_wait : int;
  mutable n_fault : int;
  mutable n_no_response : int;
  mutable n_parity_errors : int;
  mutable n_line_resets : int;
  mutable n_bad_frame : int;
}

let create (cfg : config) =
  {
    cfg;
    prev_swclk = None;
    mode = (if cfg.start_in_swd then "swd" else "jtag");
    need_dpidr = false;
    phase = (if cfg.start_in_swd then Idle else Jtag_high1);
    high_run = 0;
    magic_idx = 0;
    req_idx = 0;
    req_acc = 0;
    ack_idx = 0;
    ack_code = 1;
    data_idx = 0;
    data_acc = 0;
    out_value = 0;
    out_parity = 0;
    is_ap = false;
    is_read = false;
    write_target = W_none;
    dpidr_gate_pending = false;
    ctrl_stat = 0;
    select_apsel = 0;
    select_apbank = 0;
    select_dpbank = 0;
    ap_read_buffer = 0;
    csw = 0;
    tar = 0;
    mem = Array.make (max cfg.mem_words 1) 0;
    log_rev = [];
    n_ok = 0;
    n_wait = 0;
    n_fault = 0;
    n_no_response = 0;
    n_parity_errors = 0;
    n_line_resets = 0;
    n_bad_frame = 0;
  }

let log_event t s = t.log_rev <- s :: t.log_rev

let parity4 a b c d = (a lxor b lxor c lxor d) land 1
let popcount32 v =
  let c = ref 0 in
  for i = 0 to 31 do
    if (v lsr i) land 1 = 1 then incr c
  done;
  !c

(* Reset DP-side register state on a line reset.  The AP (csw/tar) and the
   backing memory are NOT touched: a line reset resets the debug port, not
   the memory system behind the AP -- see NOTES.txt. *)
let reset_dp_state t =
  t.ctrl_stat <- 0;
  t.select_apsel <- 0;
  t.select_apbank <- 0;
  t.select_dpbank <- 0;
  t.ap_read_buffer <- 0

let enter_line_reset t =
  t.n_line_resets <- t.n_line_resets + 1;
  reset_dp_state t;
  t.need_dpidr <- true;
  t.mode <- "swd-reset";
  t.phase <- Idle;
  t.high_run <- 0;
  log_event t "line-reset"

let start_req t =
  t.phase <- Req;
  t.req_idx <- 1;      (* bit 0 (start=1) already consumed *)
  t.req_acc <- 1

(* CTRL/STAT sticky bits that a CTRL/STAT write must never modify directly:
   bit1 STICKYORUN, bit4 STICKYCMP, bit5 STICKYERR, bit7 WDATAERR. *)
let sticky_mask = (1 lsl 1) lor (1 lsl 4) lor (1 lsl 5) lor (1 lsl 7)

let apply_ctrlstat_write t v =
  let kept_sticky = t.ctrl_stat land sticky_mask in
  let incoming = v land (lnot sticky_mask) in
  let base = incoming lor kept_sticky in
  (* Power-up acknowledgements track their requests instantaneously: this
     model has no real power-domain sequencing. *)
  let base = if base land (1 lsl 30) <> 0 then base lor (1 lsl 31) else base land (lnot (1 lsl 31)) in
  let base = if base land (1 lsl 28) <> 0 then base lor (1 lsl 29) else base land (lnot (1 lsl 29)) in
  t.ctrl_stat <- base

let apply_abort_write t v =
  if v land 0x2 <> 0 then t.ctrl_stat <- t.ctrl_stat land (lnot (1 lsl 4)); (* STKCMPCLR *)
  if v land 0x4 <> 0 then t.ctrl_stat <- t.ctrl_stat land (lnot (1 lsl 5)); (* STKERRCLR *)
  if v land 0x8 <> 0 then t.ctrl_stat <- t.ctrl_stat land (lnot (1 lsl 7)); (* WDERRCLR *)
  if v land 0x10 <> 0 then t.ctrl_stat <- t.ctrl_stat land (lnot (1 lsl 1)); (* ORUNERRCLR *)
  if v land 0x1 <> 0 then log_event t "abort: DAPABORT (no in-flight AP transaction to abort in this model)"

let csw_increments t = (t.csw lsr 4) land 0x3 = 1

(* Decide the ACK and, for reads, the value to shift out; for writes, what
   register the (still-to-be-received) data should be applied to.  Returns
   the ack_code (1 OK / 2 WAIT / 4 FAULT).  Also updates the posted-AP-read
   buffer and performs the AP-side effect of a read (or CSW/TAR/SELECT/ABORT
   writes, which are not gated by a further data phase). *)
let decode_and_act t =
  let apndp = (t.req_acc lsr 1) land 1 in
  let rnw = (t.req_acc lsr 2) land 1 in
  let a2 = (t.req_acc lsr 3) land 1 in
  let a3 = (t.req_acc lsr 4) land 1 in
  let parity = (t.req_acc lsr 5) land 1 in
  let stop = (t.req_acc lsr 6) land 1 in
  let park = (t.req_acc lsr 7) land 1 in
  let a32 = (a3 lsl 1) lor a2 in
  let expect_parity = parity4 apndp rnw a2 a3 in
  if stop <> 0 || park <> 1 then begin
    t.n_bad_frame <- t.n_bad_frame + 1;
    t.n_no_response <- t.n_no_response + 1;
    log_event t "protocol-error: bad stop/park bit, request dropped, no response";
    None
  end else if parity <> expect_parity then begin
    t.n_parity_errors <- t.n_parity_errors + 1;
    t.n_no_response <- t.n_no_response + 1;
    log_event t "parity-error: request packet, request dropped, no response";
    None
  end else begin
    t.is_ap <- (apndp = 1);
    t.is_read <- (rnw = 1);
    let is_dpidr_read = (apndp = 0) && (rnw = 1) && (a32 = 0) in
    if t.need_dpidr && not is_dpidr_read then begin
      t.n_no_response <- t.n_no_response + 1;
      log_event t "pre-dpidr access ignored (DP not yet honouring transactions after reset)";
      None
    end else begin
      t.write_target <- W_none;
      t.dpidr_gate_pending <- false;
      let ack =
        if apndp = 0 then begin
          (* DP access *)
          match rnw, a32 with
          | 1, 0 ->
            t.out_value <- t.cfg.dpidr;
            t.dpidr_gate_pending <- t.need_dpidr;
            1
          | 1, 1 ->
            if t.select_dpbank = 0 then (t.out_value <- t.ctrl_stat; 1) else 4
          | 1, 2 -> 4 (* RESEND not modelled *)
          | 1, 3 -> t.out_value <- t.ap_read_buffer; 1
          | 0, 0 -> t.write_target <- W_abort; 1
          | 0, 1 -> if t.select_dpbank = 0 then (t.write_target <- W_ctrlstat; 1) else 4
          | 0, 2 -> t.write_target <- W_select; 1
          | _ -> 4
        end else begin
          (* AP access *)
          if t.cfg.wait_on_ap () then 2
          else if t.select_apsel <> 0 then 4
          else if (rnw = 1) && t.ctrl_stat land (1 lsl 5) <> 0 then 4 (* STICKYERR blocks AP reads *)
          else if (rnw = 0) && t.ctrl_stat land (1 lsl 5) <> 0 then 4 (* and AP writes *)
          else begin
            let addr = t.select_apbank * 16 + a32 * 4 in
            if rnw = 1 then begin
              let fresh =
                match addr with
                | 0x00 -> Some t.csw
                | 0x04 -> Some t.tar
                | 0x0C ->
                  let w = t.tar / 4 in
                  if w >= 0 && w < Array.length t.mem then Some t.mem.(w) else None
                | 0xFC -> Some t.cfg.ap_idr
                | _ -> None
              in
              match fresh with
              | None -> 4
              | Some v ->
                t.out_value <- t.ap_read_buffer;
                t.ap_read_buffer <- v;
                if addr = 0x0C && csw_increments t then t.tar <- t.tar + 4;
                1
            end else begin
              match addr with
              | 0x00 -> t.write_target <- W_csw; 1
              | 0x04 -> t.write_target <- W_tar; 1
              | 0x0C ->
                let w = t.tar / 4 in
                if w >= 0 && w < Array.length t.mem then (t.write_target <- W_drw; 1) else 4
              | _ -> 4
            end
          end
        end
      in
      (* An AP transaction that FAULTs sets STICKYERR (a real AP-transaction
         error); a DP-level FAULT from an unimplemented DP register slot is
         a model limitation, not a real AP error, so it does not. *)
      if ack = 4 && t.is_ap then t.ctrl_stat <- t.ctrl_stat lor (1 lsl 5);
      Some ack
    end
  end

let apply_write_data t data received_parity =
  let expect = popcount32 data land 1 in
  if received_parity <> expect then begin
    t.n_parity_errors <- t.n_parity_errors + 1;
    t.ctrl_stat <- t.ctrl_stat lor (1 lsl 7); (* WDATAERR *)
    log_event t "parity-error: write data, WDATAERR set, write discarded"
  end else begin
    (match t.write_target with
     | W_none -> ()
     | W_abort -> apply_abort_write t data
     | W_ctrlstat -> apply_ctrlstat_write t data
     | W_select ->
       t.select_apsel <- (data lsr 24) land 0xFF;
       t.select_apbank <- (data lsr 4) land 0xF;
       t.select_dpbank <- data land 0xF
     | W_csw -> t.csw <- data
     | W_tar -> t.tar <- data
     | W_drw ->
       let w = t.tar / 4 in
       if w >= 0 && w < Array.length t.mem then t.mem.(w) <- data;
       if csw_increments t then t.tar <- t.tar + 4)
  end

let finish_txn t ~ok =
  (match ok with
   | 1 -> t.n_ok <- t.n_ok + 1
   | 2 -> t.n_wait <- t.n_wait + 1
   | _ -> t.n_fault <- t.n_fault + 1);
  if t.dpidr_gate_pending && ok = 1 then begin
    t.need_dpidr <- false;
    t.mode <- "swd";
    log_event t "dpidr read complete: DP now honouring transactions"
  end;
  t.dpidr_gate_pending <- false

let do_rising_edge t bit =
  match t.phase with
  | Jtag_high1 ->
    if bit = 1 then begin
      t.high_run <- t.high_run + 1;
      if t.high_run >= 50 then begin
        t.magic_idx <- 0;
        t.phase <- Jtag_magic
      end
    end else t.high_run <- 0
  | Jtag_magic ->
    let expect = (0xE79E lsr t.magic_idx) land 1 in
    if bit = expect then begin
      t.magic_idx <- t.magic_idx + 1;
      if t.magic_idx >= 16 then begin
        t.high_run <- 0;
        t.phase <- Jtag_high2
      end
    end else begin
      (* Mismatch: restart the whole switch-sequence detector. *)
      t.high_run <- (if bit = 1 then 1 else 0);
      t.phase <- Jtag_high1
    end
  | Jtag_high2 ->
    if bit = 1 then begin
      t.high_run <- t.high_run + 1;
      if t.high_run >= 50 then begin
        log_event t "jtag-to-swd switch sequence complete";
        enter_line_reset t
      end
    end else begin
      t.high_run <- 0;
      t.phase <- Jtag_high1
    end
  | Idle ->
    t.high_run <- (if bit = 1 then t.high_run + 1 else 0);
    if t.high_run >= 50 then enter_line_reset t
    else if bit = 1 then start_req t
  | Req ->
    t.high_run <- (if bit = 1 then t.high_run + 1 else 0);
    if t.high_run >= 50 then enter_line_reset t
    else begin
      t.req_acc <- t.req_acc lor (bit lsl t.req_idx);
      t.req_idx <- t.req_idx + 1;
      if t.req_idx >= 8 then
        match decode_and_act t with
        | None -> t.phase <- Idle
        | Some ack ->
          t.ack_code <- ack;
          t.ack_idx <- 0;
          t.phase <- Trn_to_ack
    end
  | Trn_to_ack ->
    t.phase <- Ack;
    t.ack_idx <- 0
  | Ack ->
    t.ack_idx <- t.ack_idx + 1;
    if t.ack_idx >= 3 then begin
      if t.ack_code = 1 && t.is_read then begin
        t.out_parity <- popcount32 t.out_value land 1;
        t.data_idx <- 0;
        t.phase <- Data_r
      end else if t.ack_code = 1 && not t.is_read then begin
        t.phase <- Trn_to_data_w
      end else begin
        finish_txn t ~ok:t.ack_code;
        t.phase <- Trn_to_idle
      end
    end
  | Trn_to_data_w ->
    t.data_idx <- 0;
    t.data_acc <- 0;
    t.phase <- Data_w
  | Data_w ->
    if t.data_idx < 32 then begin
      t.data_acc <- t.data_acc lor (bit lsl t.data_idx);
      t.data_idx <- t.data_idx + 1
    end else begin
      let received_parity = bit land 1 in
      apply_write_data t t.data_acc received_parity;
      finish_txn t ~ok:1;
      t.data_idx <- 0;
      t.data_acc <- 0;
      t.phase <- Idle
    end
  | Data_r ->
    t.data_idx <- t.data_idx + 1;
    if t.data_idx >= 33 then begin
      finish_txn t ~ok:1;
      t.phase <- Trn_to_idle
    end
  | Trn_to_idle -> t.phase <- Idle

let step t ~swclk ~swdio =
  (match t.prev_swclk with
   | None -> ()
   | Some p -> if p = 0 && swclk <> 0 then do_rising_edge t (swdio land 1));
  t.prev_swclk <- Some swclk

let drive t =
  match t.phase with
  | Ack -> Some ((t.ack_code lsr t.ack_idx) land 1)
  | Data_r ->
    if t.data_idx < 32 then Some ((t.out_value lsr t.data_idx) land 1)
    else Some (t.out_parity land 1)
  | _ -> None

let mem t = Array.copy t.mem
let ctrl_stat t = t.ctrl_stat
let mode t = t.mode
let log t = List.rev t.log_rev
let stats t =
  [
    ("ok", t.n_ok);
    ("wait", t.n_wait);
    ("fault", t.n_fault);
    ("no_response", t.n_no_response);
    ("parity_errors", t.n_parity_errors);
    ("line_resets", t.n_line_resets);
    ("bad_frame", t.n_bad_frame);
  ]
