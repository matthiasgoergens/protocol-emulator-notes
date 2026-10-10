(* A low-speed USB device (the HID boot keyboard of ../usb-ls) on the combined chip, with the
   bit layer in the bit-path assists instead of firmware.

   ../usb-ls ran the same device as firmware on a sequencer variant: T0, a whole thread, was the
   bit layer (a software DPLL, NRZI, destuffing, EOP and reset detection, 63 words); T1 and T2
   read bits one at a time and streamed replies precomputed as line symbols (sync, stuffing,
   NRZI and EOP done by the controller); a 32-byte reply FIFO and patches to the running
   programme carried the controller's decisions. Here the edge sampler (NRZ), the line decoder
   (NRZI), the destuffer and the framer deliver bytes; the serialiser takes bytes and does sync
   timing, stuffing, NRZI and the EOP; the CRC unit checks CRC-16 over the frame after the PID.
   The firmware sees bytes only:

   - T0, the protocol: receives each packet's PID and bytes from the framer (MBX port 0), checks
     tokens by table lookup in the data bank (the address and endpoint byte and the CRC5 byte,
     whose expected values the controller writes into two 256-byte tables when the address
     changes), forwards SETUP and OUT data to the controller, checks the end of a packet through
     flags (the frame's end, a stuff violation, the CRC residue), and answers: NAK, STALL or the
     staged data packet to an IN; ACK or STALL after data. It sends the sync byte, the PID and the
     bytes to the serialiser; the serialiser ends the packet with SE0, SE0, J when its FIFO runs
     dry.
   - T1, the mailbox: applies the controller's messages from HOSTIN to the data bank (the
     replies, the per-endpoint choices, the tables).
   - T2, bus reset: SE0 (the line-inactive flag) for more than [reset_slots] slots.
   - T3 is free.

   The chip is not allowed to have its programme store or bank written while it runs, so the
   controller cannot patch the running programme as ../usb-ls's did; every decision it makes
   reaches the chip as a message through HOSTIN, and T1 writes it into the bank. A reply the
   controller staged before it saw a SETUP (or an OUT to endpoint 0, or a bus reset) would then be
   stale: T0 (T2 for a reset) sets a "flush" byte when it reports such an event, T1 drops staged
   writes while it is set, and the controller's first message after seeing the event clears it
   and stages everything again. Table writes are never dropped. T0 itself withdraws a data reply
   when the host ACKs it (the choice goes back to NAK before the event is reported), so the
   controller's next message cannot race a repeat of the old data.

   Data bank (page 0): 0 choice for IN on endpoint 0 (0 NAK, 1 STALL, 2 the staged data), 1 the
   same for endpoint 1, 2 the handshake after OUT data on endpoint 0 (0 ACK, 1 STALL), 3 flush,
   0x10 the staged packet's length n (PID, payload, CRC-16), 0x11.. its bytes. Page 1: the
   class of a token's first byte (address and endpoint bit): 1 endpoint 0 of our address, 2
   endpoint 1. Page 2: the class of its second byte (endpoint bits and CRC5) for the same.

   Messages (HOSTIN): 0x01 a n b0 .. b(n-1): a staged write of n bytes at page 0, address a
   (dropped while flush is set); 0x02 p a v: bank[p][a] <- v (a table entry); 0x03: clear flush.

   Events (OUT with tag 1; forwarded bytes with tag 0), as ../usb-ls's where they mean the same. *)

open Regs
module I = Isa2

let ev_reset = 1 and ev_ack0 = 2 and ev_ack1 = 3 and ev_setup = 4 and ev_out = 5 and ev_ok = 6 and ev_bad = 7
let ev_out1 = 8 and ev_data = 9

(* the bit path's MBX port: 4 + p, and the pads: uio[6] is D-, uio[7] is D+ (the open-drain
   pins, which the chip can release) *)
let port = 0
let ch = 4 + port
let pad_dm = 14 and pad_dp = 15

(* ---- a small assembler with labels ---- *)

type item = L of string | W of int | J of (int -> int) * string

let assemble ~base items =
  let labels = Hashtbl.create 64 in
  let pc = ref base in
  List.iter (function L l -> if Hashtbl.mem labels l then failwith ("label twice: " ^ l) else Hashtbl.replace labels l !pc | _ -> incr pc) items;
  let addr l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("no label " ^ l) in
  Array.of_list (List.filter_map (function L _ -> None | W w -> Some w | J (f, l) -> Some (f (addr l))) items)

let fresh = let n = ref 0 in fun p -> incr n; Printf.sprintf "%s~%d" p !n
let w x = W x
let jmp l = J (I.jmp, l)
let jnz l = J (I.jnz, l)
let recv l = J ((fun a -> I.recv ~ch ~fail:a), l)
let waitc f l = J ((fun a -> I.waitc ~cond:(I.c_flag f) ~fail:a), l)
(* a SEND that waits while the serialiser's FIFO is full (with dl = 0 it jumps to itself) *)
let send () = let l = fresh "send" in [ L l; J ((fun a -> I.send ~ch ~fail:a), l) ]
let send_byte b = w (I.lda b) :: send ()
let dec_cnt = w (I.shi ~pin:0 ~msb:0 ())   (* SHI on an unused pin: cnt - 1 (acc is clobbered) *)

(* T0's flags (thread 0's flag inputs 0-3) *)
let f_done = 0 and f_err = 1 and f_crc = 2 and f_active = 3

type cfg = {
  turn : int;          (* slots from the line's return to J to the reply's first byte *)
  ack_wait : int;      (* slots to wait for the host's handshake after a data reply *)
  check_crc : bool;    (* control: false accepts data without the CRC check *)
  reset_slots : int;   (* SE0 longer than this is a bus reset *)
}

(* turn: the host releases the bus at the J after its SE0; the SOP must come 2 to 6.5 bit times
   (80 to 260 clocks) after that edge. The flag sees the J 2 clocks after the pad (the stage),
   T0 is within 4 clocks of it, then WAITD; the first byte reaches the serialiser 1 clock after
   the SEND and its first symbol is on the pad 3 clocks later: about 4 turn + 10 clocks. *)
let default_cfg = { turn = 24; ack_wait = 700; check_crc = true; reset_slots = 60 }

let pid_in = 0x69 and pid_setup = 0x2D and pid_out = 0xE1 and pid_ack = 0xD2 and pid_nak = 0x5A and pid_stall = 0x1E

let t0 c =
  (* the two bytes after a token's PID: page 1 classifies the first, page 2 the second; both must
     give the same endpoint, the packet must then end (SE0) without a third byte or a violation *)
  let byte2 l cls ok =
    [ L l; w (I.ldd 100); recv "idle"; w (I.bank 2); w I.ldb; w (I.skeq cls); jmp "drain";
      w (I.ldd 40); waitc f_done "drain"; w (I.ldd 0); waitc f_err ok; jmp "idle" ] in
  let token p ~ok0 ~ok1 =
    [ L p; w (I.ldd 100); recv "idle"; w (I.bank 1); w I.ldb; w (I.skne 1); jmp (p ^ ".e0") ]
    @ (match ok1 with Some _ -> [ w (I.skne 2); jmp (p ^ ".e1") ] | None -> [])
    @ [ jmp "drain" ]
    @ byte2 (p ^ ".e0") 1 ok0
    @ (match ok1 with Some l -> byte2 (p ^ ".e1") 2 l | None -> []) in
  (* the line back at J after the host's EOP, then the turnaround *)
  let turnaround = [ w (I.ldd 40); waitc f_active "idle"; w (I.ldd c.turn); w I.waitd ] in
  let in_ep k =
    let ks = string_of_int k in
    [ L ("in" ^ ks); w (I.lda k); w (I.bank 0); w I.ldb ] @ turnaround
    @ [ w (I.skne 2); jmp ("data" ^ ks); w (I.skne 1); jmp "stall"; jmp "nak" ]
    (* the staged data packet: sync, then n bytes from the bank *)
    @ [ L ("data" ^ ks) ] @ send_byte 0x80
    @ [ w (I.lda 0x10); w (I.bank 0); w I.ldb; w I.cnta; L ("dl" ^ ks); w I.ldb ] @ send ()
    @ [ dec_cnt; jnz ("dl" ^ ks);
        (* the host's handshake; another packet is handled as one *)
        w (I.ldd c.ack_wait); recv "idle"; w (I.skeq pid_ack); jmp "dispatch";
        w (I.lda k); w (I.bank 0); w (I.lda 0); w I.stb;
        w (I.outi ~tag:1 (if k = 0 then ev_ack0 else ev_ack1)); jmp "idle" ] in
  let hs label pid = [ L label ] @ turnaround @ send_byte 0x80 @ send_byte pid @ [ jmp "idle" ] in
  let set a v = [ w (I.lda a); w (I.bank 0); w (I.lda v); w I.stb ] in
  [ L "idle"; w (I.ldd 0);
    L "wait"; recv "wait";
    L "dispatch";
    w (I.skne pid_in); jmp "in";
    w (I.skne pid_setup); jmp "setup";
    w (I.skne pid_out); jmp "out";
    (* anything else (an ACK outside a wait, a stray data packet): drain it *)
    L "drain"; w (I.ldd 0); recv "drain2"; jmp "drain";
    L "drain2"; waitc f_done "drain"; jmp "idle" ]
  @ token "in" ~ok0:"in0" ~ok1:(Some "in1")
  @ token "setup" ~ok0:"setup0" ~ok1:None
  @ token "out" ~ok0:"out0" ~ok1:(Some "out1")
  @ in_ep 0 @ in_ep 1
  @ [ L "nak" ] @ send_byte 0x80 @ send_byte pid_nak @ [ jmp "idle" ]
  @ [ L "stall" ] @ send_byte 0x80 @ send_byte pid_stall @ [ jmp "idle" ]
  (* SETUP and OUT: the token's kind in cnt (1 SETUP, 2 OUT 0, 3 OUT 1), then one data path *)
  @ [ L "setup0"; w (I.outi ~tag:1 ev_setup); w (I.lda 1); w I.cnta; jmp "data";
      L "out0"; w (I.outi ~tag:1 ev_out); w (I.lda 2); w I.cnta; jmp "data";
      L "out1"; w (I.outi ~tag:1 ev_out1); w (I.lda 3); w I.cnta; jmp "data";
      (* the data packet's PID, then every byte to the controller until the frame ends *)
      L "data"; w (I.ldd 400); recv "idle"; w (I.outi ~tag:1 ev_data); w (I.out ());
      L "fwd"; w (I.ldd 0); recv "fchk"; w (I.out ()); jmp "fwd";
      L "fchk"; waitc f_done "fwd";
      (* the packet has ended: a stuff violation or a bad CRC means silence *)
      waitc f_err "nerr"; jmp "bad";
      L "nerr" ]
  @ (if c.check_crc then [ waitc f_crc "bad" ] else [])
  @ [ w (I.outi ~tag:1 ev_ok); dec_cnt; jnz "notsetup" ]
  (* SETUP: a new control transfer, so a staged endpoint-0 reply is stale; ACK *)
  @ set 0 0 @ set 3 1 @ [ jmp "hs_ack" ]
  @ [ L "notsetup"; dec_cnt; jnz "hs_stall" ]   (* OUT to endpoint 1, which has no OUT direction *)
  (* OUT to endpoint 0: a staged data reply is withdrawn (the transfer is over); the handshake
     the controller staged (STALL while endpoint 0 is stalled) *)
  @ [ w (I.lda 0); w (I.bank 0); w I.ldb; w (I.skeq 2); jmp "o0f" ] @ set 0 0
  @ [ L "o0f" ] @ set 3 1 @ [ w (I.lda 2); w (I.bank 0); w I.ldb; w (I.skne 1); jmp "hs_stall"; jmp "hs_ack";
      L "bad"; w (I.outi ~tag:1 ev_bad); jmp "idle" ]
  @ hs "hs_ack" pid_ack @ hs "hs_stall" pid_stall

let t1 =
  [ L "t1"; w I.in_; w (I.skne 1); jmp "staged"; w (I.skne 2); jmp "table"; w (I.skne 3); jmp "unflush"; jmp "t1";
    L "staged"; w (I.lda 3); w (I.bank 0); w I.ldb; w (I.skeq 0); jmp "discard";
    w I.in_; w (I.bank 0); w I.in_; w I.cnta;
    L "sl"; w I.in_; w I.stb; dec_cnt; jnz "sl"; jmp "t1";
    L "discard"; w I.in_; w I.in_; w I.cnta;
    L "dl"; w I.in_; dec_cnt; jnz "dl"; jmp "t1";
    L "table"; w I.in_; w (I.skne 1); jmp "tp1"; w I.in_; w (I.bank 2); w I.in_; w I.stb; jmp "t1";
    L "tp1"; w I.in_; w (I.bank 1); w I.in_; w I.stb; jmp "t1";
    L "unflush"; w (I.lda 3); w (I.bank 0); w (I.lda 0); w I.stb; jmp "t1" ]

(* T2's flags (thread 2's flag inputs 8-11): 0 the line is inactive (SE0), 1 active *)
let t2 c =
  [ L "t2"; w (I.ldd 0);
    L "w"; waitc 0 "w";
    w (I.ldd c.reset_slots); waitc 1 "rst"; jmp "t2";
    L "rst"; w (I.outi ~tag:1 ev_reset);
    (* NAK on both endpoints, ACK after OUT, and flush until the controller has seen the reset *)
    w (I.lda 0); w (I.bank 0); w (I.lda 0); w I.stb; w I.stb; w I.stb; w (I.lda 1); w I.stb;
    w (I.ldd 0); L "rw"; waitc 1 "rw"; jmp "t2" ]

let t3 = [ L "t3"; jmp "t3" ]

(* where the threads live: pages 0 and 1, the 512-word store of the hardened chip *)
let placement = [| (0, 0x00); (1, 0x00); (1, 0x80); (1, 0xF0) |]

let images c =
  let progs = [| t0 c; t1; t2 c; t3 |] in
  Array.mapi (fun t items -> let page, base = placement.(t) in (page, base, assemble ~base items)) progs

(* ---- the chip's configuration, through the host link while it is stopped ---- *)

let addr_tables addr =
  (* the token's two bytes for endpoints 0 and 1 at [addr] (fw_codec, ../usb-ls) *)
  let a0, c0 = Fw_codec.token_tail ~addr ~ep:0 and a1, c1 = Fw_codec.token_tail ~addr ~ep:1 in
  [ (1, a0, 1); (1, a1, 2); (2, c0, 1); (2, c1, 2) ]

(* [jk_swap]: control, D+ and D- exchanged at the pads *)
let configure ?(jk_swap = false) (h : Host.t) c =
  let wr tgt addr data = Host.submit h (Host.Write { tgt; addr; data }) in
  Host.wreg h r_ctrl 2;
  Array.iter (fun (page, base, words) ->
      wr t_prog (2 * ((page lsl 8) lor base)) (List.concat_map (fun x -> [ x land 0xFF; x lsr 8 ]) (Array.to_list words)))
    (images c);
  wr t_reg (r_boot_pc 0) (Array.to_list (Array.map snd placement)
                          @ [ Array.fold_left ( lor ) 0 (Array.mapi (fun t (p, _) -> p lsl (2 * t)) placement) ]);
  (* the line: the serialiser's line a (idle high: J) on D-, line b on D+; released when idle
     (sequencer pins 6 and 7, never driven) *)
  let dm, dp = if jk_swap then (pad_dp, pad_dm) else (pad_dm, pad_dp) in
  wr t_reg (r_padsel dm) [ src_tx_a ]; wr t_reg (r_padsel dp) [ src_tx_b ];
  wr t_reg (r_flagsel 0) [ fl_rx_done; fl_rx_err; fl_crc_check; fl_line_active; 31; 31; 31; 31; fl_line_inactive; fl_line_active ];
  (* the edge sampler: NRZ on D+ (J low), active while D+ or D- is high (SE0 is inactive); 160
     sub-samples per bit, the sample in the middle; a timeout of 1023 never ends a burst *)
  wr t_reg r_es_mode [ 2 lor 8 lor 16; (dm lsl 4) lor dp; 8; 0; 0xFF; 3; 80; 160 ];
  (* CRC-16/USB, checked over the frame after the PID: residue 0xB001 *)
  let le32 v = List.init 4 (fun k -> (v lsr (8 * k)) land 0xFF) in
  wr t_reg r_crc_ctrl [ 1 ];
  wr t_reg r_crc_poly (le32 0xA001 @ le32 0xFFFF @ le32 0xFFFF @ le32 0xFFFF @ le32 0xB001);
  (* the bit path: port 0; CRC from the frame; half duplex; a frame ends at SE0 and starts after
     the sync (0x80, newest bit in bit 7); NRZI both ways, stuffing after six 1s; 40 clocks per
     bit; the EOP is two symbols of SE0, then one of J; idle shows pins 6 and 7, released *)
  wr t_reg r_bp_ctrl
    [ 1 lor (port lsl 1) lor 8 lor 16 lor 32 lor 128; 0x01; 0x26; 0x80; 0xFF; 8;
      0x05; 0x26; 40; 0; 0x02; 0x11; 0x76 ];
  (* the bank: NAK, NAK, ACK, no flush; the tables for address 0 *)
  wr t_bank 0 [ 0; 0; 0; 0 ];
  List.iter (fun (p, a, v) -> wr t_bank ((p lsl 8) lor a) [ v ]) (addr_tables 0);
  Host.wreg h r_ctrl 1

(* ---- the controller, on the host's side of the link ----

   ../usb-ls's controller.ml, with its transport replaced: it keeps the device's USB state and
   decides every reply, written from the USB and HID specifications separately from the test
   host's reference device; its decisions go to the chip as messages instead of patches. *)

type ep0 =
  | Idle
  | Data_in of { data : int list; pos : int; toggle : int; zlp : bool }
  | Status_in of [ `Addr of int | `Config of int | `Plain ]
  | Status_out
  | Stalled

type ctl = {
  mutable addr : int;
  mutable configured : bool;
  mutable ep0 : ep0;
  mutable ep1_toggle : int;
  reports : int list Queue.t;
  mutable staged : (int * int) option;     (* endpoint, payload length of the staged reply *)
  mutable token : [ `None | `Setup | `Out0 | `Out1 ];
  mutable rx : int list option;
  mutable sent_choices : int list;        (* what the chip's choice bytes were last set to *)
  outq : int Queue.t;                     (* message bytes for HOSTIN *)
  mutable messages : int;
  mutable events : int;
}

let create_ctl () =
  { addr = 0; configured = false; ep0 = Idle; ep1_toggle = 0; reports = Queue.create (); staged = None; token = `None;
    rx = None; sent_choices = [ 0; 0; 0 ]; outq = Queue.create (); messages = 0; events = 0 }

let take n l = List.filteri (fun i _ -> i < n) l
let drop n l = List.filteri (fun i _ -> i >= n) l

let msg c l =
  if Sys.getenv_opt "USB_DEBUG" <> None then Printf.printf "      message %s\n" (String.concat " " (List.map (Printf.sprintf "%02x") l));
  c.messages <- c.messages + 1; List.iter (fun b -> Queue.push b c.outq) l
let staged_write c a bytes = msg c ([ 0x01; a; List.length bytes ] @ bytes)

let choices ?(force = false) c =
  let ch ep = match c.staged with Some (e, _) when e = ep -> 2 | _ -> if ep = 0 && c.ep0 = Stalled then 1 else 0 in
  let l = [ ch 0; ch 1; (if c.ep0 = Stalled then 1 else 0) ] in
  if force || l <> c.sent_choices then (staged_write c 0 l; c.sent_choices <- l)

let stage c ~ep ~pid payload =
  let pkt = Fw_codec.data_bytes pid payload in
  (* the buffer is shared: no endpoint may be answering from it while it is rewritten *)
  if List.exists (( = ) 2) (take 2 c.sent_choices) then (c.staged <- None; choices c);
  c.staged <- Some (ep, List.length payload);
  staged_write c 0x10 (List.length pkt :: pkt);
  choices c

let schedule c =
  (if c.staged = None then
     match c.ep0 with
     | Data_in { data; pos; toggle; _ } -> stage c ~ep:0 ~pid:(if toggle = 1 then 0x4B else 0xC3) (take 8 (drop pos data))
     | Status_in _ -> stage c ~ep:0 ~pid:0x4B []
     | _ ->
       if c.configured && not (Queue.is_empty c.reports) then
         stage c ~ep:1 ~pid:(if c.ep1_toggle = 1 then 0x4B else 0xC3) (Queue.peek c.reports));
  choices c

let set_tables c ~old_addr ~addr =
  List.iter (fun (p, a, _) -> msg c [ 0x02; p; a; 0 ]) (addr_tables old_addr);
  List.iter (fun (p, a, v) -> msg c [ 0x02; p; a; v ]) (addr_tables addr)

(* after a flush: clear it, then stage everything again *)
let restage c =
  msg c [ 0x03 ];
  (match c.staged with
   | Some (ep, n) ->
     let pid, payload =
       match ep, c.ep0 with
       | 0, Data_in { data; pos; toggle; _ } -> ((if toggle = 1 then 0x4B else 0xC3), take 8 (drop pos data))
       | 0, _ -> (0x4B, [])
       | _ -> ((if c.ep1_toggle = 1 then 0x4B else 0xC3), Queue.peek c.reports) in
     ignore n; c.staged <- None; stage c ~ep ~pid payload
   | None -> ());
  choices ~force:true c

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

(* the host ACKed the staged reply of endpoint [ep]; T0 has set its choice back to NAK *)
let acked c ep =
  c.sent_choices <- List.mapi (fun i v -> if i = ep then 0 else v) c.sent_choices;
  match c.staged with
  | Some (e, len) when e = ep ->
    c.staged <- None;
    if ep = 0 then
      (match c.ep0 with
       | Data_in r ->
         let pos = r.pos + len in
         if pos < List.length r.data then c.ep0 <- Data_in { r with pos; toggle = 1 - r.toggle }
         else if len = 8 && r.zlp then c.ep0 <- Data_in { r with pos; toggle = 1 - r.toggle; zlp = false }
         else c.ep0 <- Status_out
       | Status_in a ->
         (match a with
          | `Addr n -> set_tables c ~old_addr:c.addr ~addr:n; c.addr <- n
          | `Config n -> c.configured <- n <> 0; c.ep1_toggle <- 0
          | `Plain -> ());
         c.ep0 <- Idle
       | _ -> ())
    else (ignore (Queue.pop c.reports); c.ep1_toggle <- 1 - c.ep1_toggle)
  | _ -> ()

let debug = Sys.getenv_opt "USB_DEBUG" <> None
let now = ref 0

let handle c (tag, v) =
  if debug then Printf.printf "      [%d] event %s %02x\n" !now (if tag = 0 then "byte" else "tag1") v;
  if tag = 0 then (match c.rx with Some l -> c.rx <- Some (l @ [ v ]) | None -> ())
  else begin
    c.events <- c.events + 1;
    if v = ev_reset then begin
      set_tables c ~old_addr:c.addr ~addr:0;
      c.addr <- 0; c.configured <- false; c.ep0 <- Idle; c.ep1_toggle <- 0; c.staged <- None; c.rx <- None; c.token <- `None;
      c.sent_choices <- [ 0; 0; 0 ];
      restage c
    end
    else if v = ev_ack0 then acked c 0
    else if v = ev_ack1 then acked c 1
    else if v = ev_setup then c.token <- `Setup
    else if v = ev_out then c.token <- `Out0
    else if v = ev_out1 then c.token <- `Out1
    else if v = ev_data then c.rx <- Some []
    else if v = ev_bad then c.rx <- None
    else if v = ev_ok then begin
      (match c.token, c.rx with
       | `Setup, rx ->
         (* T0 has withdrawn endpoint 0's reply and set flush; a staged endpoint-1 report is
            withdrawn too (it is staged again when endpoint 0 has nothing to send) *)
         c.staged <- None; c.sent_choices <- [ 0; List.nth c.sent_choices 1; List.nth c.sent_choices 2 ];
         (match rx with
          | Some (0xC3 :: l) when List.length l = 10 && Fw_codec.crc16 (take 8 l) = (List.nth l 8 lor (List.nth l 9 lsl 8)) -> setup c (take 8 l)
          | _ -> c.ep0 <- Stalled);
         restage c
       | `Out0, _ ->
         (match c.ep0 with
          | Status_out | Data_in _ -> c.ep0 <- Idle; (match c.staged with Some (0, _) -> c.staged <- None | _ -> ())
          | _ -> ());
         restage c
       | _ -> ());
      c.rx <- None; c.token <- `None
    end;
    schedule c
  end

let offer_report c r = Queue.push r c.reports; schedule c

(* ---- the host's side of the link: messages out, events in ---- *)

(* One step of the host program, whenever the link is idle: send what fits in HOSTIN (its
   count read first), else poll HOSTOUT, four entries at a time. *)
let pump c (h : Host.t) =
  if Host.idle h then begin
    if not (Queue.is_empty c.outq) then
      Host.submit h (Host.Read { tgt = t_reg; addr = r_hostin_count; n = 1; k = (fun l ->
          let room = Chip_spec.hostin_depth - List.hd l in
          let k = min room (min 12 (Queue.length c.outq)) in
          if k > 0 then Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init k (fun _ -> Queue.pop c.outq) })) })
    else
      Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 8; k = (fun l ->
          let rec go = function
            | t :: d :: rest -> if t land 0x80 <> 0 then handle c (t land 7, d); go rest
            | _ -> () in
          go l) })
  end
