(* The controller: the device's USB logic that is not real-time, running beside the sequencer
   (on the chip's host side). It receives the firmware's events and forwarded bytes, keeps the
   device state (address, configuration, control transfer, data toggles, reports), precomputes
   every reply as a symbol stream (fw_codec.ml) and queues it into the reply FIFO, and patches
   the programme: the token bytes after an address change, and the per-state reply choices.

   Written from the USB and HID specifications, separately from the reference model the test
   host uses (ref_device.ml).

   Timing model: each event reaches the controller [latency] clocks after the sequencer emits
   it, and the controller moves one byte into the FIFO every [refill] clocks while the FIFO has
   room ([depth] bytes). The firmware NAKs IN tokens until a reply is in the FIFO, so latency
   costs retries, never correctness; only the FIFO must not run dry mid-reply, which one byte
   per four bit times (160 clocks) guarantees. *)

module F = Firmware

type ep0 =
  | Idle
  | Data_in of { data : int list; pos : int; toggle : int; zlp : bool }
  | Status_in of [ `Addr of int | `Config of int | `Plain ]
  | Status_out
  | Stalled

type queued = { ep : int; bytes : int list; pkt_len : int }

type t = {
  img : F.images;
  jk_swap : bool;
  latency : int; refill : int; depth : int;
  fifo : int Queue.t;                  (* the hardware FIFO in front of host_in *)
  staged : int Queue.t;                (* bytes of the queued reply not yet in the FIFO *)
  mutable next_refill : int;
  events : (int * (int * bool)) Queue.t;   (* arrival clock, (byte, tag) *)
  mutable now : int;
  mutable addr : int;
  mutable configured : bool;
  mutable ep0 : ep0;
  mutable ep1_toggle : int;
  reports : int list Queue.t;
  mutable queued : queued option;       (* reply in or on its way into the FIFO *)
  mutable sent : queued option;         (* reply transmitted, handshake not yet seen *)
  mutable sent_at : int;
  mutable token : [ `None | `Setup | `Out0 | `Out1 ];   (* the last SETUP/OUT token *)
  mutable rx : int list option;         (* bytes of the data packet being forwarded, PID first *)
  mutable patches : int;
  mutable max_fifo : int;
  mutable popped : int;                 (* bytes of the queued reply the firmware has taken *)
  mutable forget : bool;                (* the reply being sent was withdrawn *)
  log : Buffer.t;
}

let create ?(jk_swap = false) ?(latency = 200) ?(refill = 40) ?(depth = 4) img =
  let c = { img; jk_swap; latency; refill; depth; fifo = Queue.create (); staged = Queue.create (); next_refill = 0;
            events = Queue.create (); now = 0; addr = 0; configured = false; ep0 = Idle; ep1_toggle = 0;
            reports = Queue.create (); queued = None; sent = None; sent_at = 0; token = `None; rx = None; patches = 0; max_fifo = 0; popped = 0; forget = false;
            log = Buffer.create 256 } in
  c

let patch c thread label word =
  let p = match thread with 1 -> c.img.p1 | 2 -> c.img.p2 | _ -> assert false in
  let a = Asm.addr p label in
  if c.img.mem.(thread).(a) <> word then (c.img.mem.(thread).(a) <- word; c.patches <- c.patches + 1)

let jmp_to c thread label target =
  let p = match thread with 1 -> c.img.p1 | 2 -> c.img.p2 | _ -> assert false in
  patch c thread label (Isa_ls.jmp (Asm.addr p target))

(* token bytes for the current address *)
let patch_address c =
  let a0, c0 = Fw_codec.token_tail ~addr:c.addr ~ep:0 and a1, c1 = Fw_codec.token_tail ~addr:c.addr ~ep:1 in
  List.iter (fun (th, l, v) -> patch c th l (Isa_ls.skne v))
    [ 1, "p_ia0", a0; 1, "p_ia1", a1; 1, "p_ic0", c0; 1, "p_ic1", c1;
      2, "p_sa0", a0; 2, "p_sc0", c0; 2, "p_oa0", a0; 2, "p_oc0", c0; 2, "p_oa1", a1; 2, "p_oc1", c1 ]

(* the per-state reply choices *)
let patch_choices c =
  let q = match c.queued with Some q -> Some q.ep | None -> None in
  jmp_to c 1 "p_ep0_rdy" (if q = Some 0 then "send_data" else if c.ep0 = Stalled then "send_stall" else "send_nak");
  jmp_to c 1 "p_ep1_rdy" (if q = Some 1 then "send_data" else "send_nak");
  jmp_to c 1 "p_ep0_nr" (if c.ep0 = Stalled then "send_stall" else "send_nak");
  (* the handshake after a data packet, by the token that announced it *)
  jmp_to c 2 "p_hs" (match c.token with
      | `Setup -> "send_ack"
      | `Out1 -> "send_stall2"
      | `Out0 | `None -> if c.ep0 = Stalled then "send_stall2" else "send_ack")

let take n l = List.filteri (fun i _ -> i < n) l
let drop n l = List.filteri (fun i _ -> i >= n) l

(* withdraw a queued reply. One the firmware has started to send cannot be withdrawn (it would
   stall on an empty FIFO); it is left to finish and then forgotten. *)
let flush c =
  if c.popped = 0 then (Queue.clear c.fifo; Queue.clear c.staged; c.queued <- None)
  else c.forget <- true;
  c.sent <- None

(* put a data reply into the FIFO path; the choices are patched before any byte can reach the
   FIFO, so RDY never rises before the firmware jumps to the right place *)
let queue_reply c ~ep ~pid payload =
  let pkt = Fw_codec.data_bytes pid payload in
  let bytes = Fw_codec.reply ~jk_swap:c.jk_swap pkt @ [ Fw_codec.terminator ] in
  c.queued <- Some { ep; bytes; pkt_len = List.length payload };
  c.popped <- 0;
  patch_choices c;
  List.iter (fun b -> Queue.push b c.staged) bytes;
  c.next_refill <- c.now + c.refill

(* decide what should be queued next *)
let schedule c =
  if c.queued = None && c.sent = None then begin
    match c.ep0 with
    | Data_in { data; pos; toggle; _ } -> queue_reply c ~ep:0 ~pid:(if toggle = 1 then 0x4B else 0xC3) (take 8 (drop pos data))
    | Status_in _ -> queue_reply c ~ep:0 ~pid:0x4B []
    | _ ->
      if c.configured && not (Queue.is_empty c.reports) then
        queue_reply c ~ep:1 ~pid:(if c.ep1_toggle = 1 then 0x4B else 0xC3) (Queue.peek c.reports)
      else patch_choices c
  end

let setup c s =
  let b i = List.nth s i in
  let wlen = b 6 lor (b 7 lsl 8) in
  let desc = match b 0, b 1, b 3 with
    | 0x80, 0x06, 1 -> Some Descriptors.device
    | 0x80, 0x06, 2 -> Some Descriptors.config
    | 0x81, 0x06, 0x22 -> Some Descriptors.report
    | _ -> None in
  c.ep0 <-
    (match desc with
     | Some d -> let data = take wlen d in Data_in { data; pos = 0; toggle = 1; zlp = List.length data < wlen && List.length data mod 8 = 0 }
     | None -> match b 0, b 1 with
       | 0x00, 0x05 -> Status_in (`Addr (b 2 land 0x7F))
       | 0x00, 0x09 -> Status_in (`Config (b 2))
       | 0x21, 0x0A -> Status_in `Plain
       | _ -> Stalled)

(* the host acknowledged the reply we sent *)
let acked c q =
  (match q.ep with
   | 0 ->
     (match c.ep0 with
      | Data_in r ->
        let pos = r.pos + q.pkt_len in
        if pos < List.length r.data then c.ep0 <- Data_in { r with pos; toggle = 1 - r.toggle }
        else if q.pkt_len = 8 && r.zlp then c.ep0 <- Data_in { r with pos; toggle = 1 - r.toggle; zlp = false }
        else c.ep0 <- Status_out
      | Status_in a ->
        (match a with
         | `Addr n -> c.addr <- n; patch_address c
         | `Config n -> c.configured <- n <> 0; c.ep1_toggle <- 0
         | `Plain -> ());
        c.ep0 <- Idle
      | _ -> ())
   | _ -> ignore (Queue.pop c.reports); c.ep1_toggle <- 1 - c.ep1_toggle)

(* no handshake for the reply we sent: queue the same bytes again (same toggle) *)
let unacked c = match c.sent with
  | Some q ->
    c.sent <- None; c.queued <- Some q; c.popped <- 0; patch_choices c;
    List.iter (fun b -> Queue.push b c.staged) q.bytes; c.next_refill <- c.now + c.refill
  | None -> ()

let handle c (v, tag) =
  if not tag then (match c.rx with Some l -> c.rx <- Some (l @ [ v ]) | None -> ())
  else begin
    (* any event other than the host's ACK ends the wait for it *)
    if v <> F.ev_ack then unacked c;
    if v = F.ev_reset then begin
      Printf.bprintf c.log "reset@%d " c.now;
      c.addr <- 0; c.configured <- false; c.ep0 <- Idle; c.ep1_toggle <- 0; flush c; patch_address c;
      c.rx <- None; c.token <- `None
    end
    else if v = F.ev_sent then begin
      (if c.forget then c.sent <- None else c.sent <- c.queued);
      c.forget <- false; c.queued <- None; c.popped <- 0; c.sent_at <- c.now
    end
    else if v = F.ev_ack then
      (match c.sent with Some q -> c.sent <- None; acked c q | None -> ())
    else if v = F.ev_setup then c.token <- `Setup
    else if v = F.ev_out then c.token <- `Out0
    else if v = F.ev_out1 then c.token <- `Out1
    else if v = F.ev_data then c.rx <- Some []
    else if v = F.ev_bad then c.rx <- None
    else if v = F.ev_ok then begin
      (match c.token, c.rx with
       | `Setup, Some (0xC3 :: l) when List.length l = 10 && Fw_codec.crc16 (take 8 l) = (List.nth l 8 lor (List.nth l 9 lsl 8)) ->
         (* a new SETUP aborts whatever EP0 or EP1 reply was waiting; EP1 is requeued later *)
         flush c; setup c (take 8 l)
       | `Setup, l ->
         Printf.bprintf c.log "bad-setup[%s] " (String.concat " " (List.map (Printf.sprintf "%02x") (Option.value l ~default:[])));
         flush c; c.ep0 <- Stalled
       | `Out0, _ ->
         (match c.ep0 with
          | Status_out | Data_in _ -> c.ep0 <- Idle; (match c.queued with Some { ep = 0; _ } -> flush c | _ -> ())
          | _ -> ())
       | _ -> ());
      c.rx <- None; c.token <- `None
    end;
    schedule c; patch_choices c
  end

(* one clock. [emitted]: the sequencer's host_out this clock; [popped]: it took the FIFO head *)
let tick c ~emitted ~popped =
  c.now <- c.now + 1;
  if popped then (ignore (Queue.pop c.fifo); c.popped <- c.popped + 1);
  (match emitted with Some e -> Queue.push (c.now + c.latency, e) c.events | None -> ());
  while not (Queue.is_empty c.events) && fst (Queue.peek c.events) <= c.now do
    handle c (snd (Queue.pop c.events))
  done;
  (* no ACK within 30 bit times of a reply being sent: it was lost, send again *)
  if c.sent <> None && c.now - c.sent_at > 1200 then unacked c;
  if (not (Queue.is_empty c.staged)) && Queue.length c.fifo < c.depth && c.now >= c.next_refill then begin
    Queue.push (Queue.pop c.staged) c.fifo; c.next_refill <- c.now + c.refill
  end;
  c.max_fifo <- max c.max_fifo (Queue.length c.fifo)

let offer_report c r = Queue.push r c.reports; schedule c

let rdy c = if Queue.is_empty c.fifo then 0 else 1
let head c = if Queue.is_empty c.fifo then 0 else Queue.peek c.fifo

let init c = patch_address c; patch_choices c
