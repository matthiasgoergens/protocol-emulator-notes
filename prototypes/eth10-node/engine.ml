(* Match-and-rewrite engine: a generic request/response block. It is not an IP stack; it knows
   nothing of ARP or ICMP. The host precomputes, for each kind of request the node answers:

   - a template: for the first [tlen] bytes of a frame, a value and a mask per byte; a frame matches
     if every masked bit agrees (what the systolic matcher does for bits, here on bytes as they are
     stored);
   - a rewrite programme that builds the reply byte by byte from constants and bytes of the
     request: CONST c, COPY i (request byte i), ADJ_HI/ADJ_LO i k (the high or low byte of the
     16-bit big-endian word at i plus k in ones' complement, i.e. an incrementally updated
     Internet checksum, RFC 1624), TAIL i (request bytes from i to the end, FCS excluded), END.

   Then the generic CRC unit appends the FCS and the transmit feeder hands the frame to the
   sequencer. Requests that fail the FCS, are shorter than 64 bytes (runts) or longer than the
   buffer, match no template, or arrive while a reply is still pending are dropped and counted.

   For this node the templates are ARP request (broadcast or to our MAC) for our IP, and ICMP echo
   request to our MAC and IP (IPv4 without options, not fragmented). The replies:
   - ARP: 60 bytes, everything constant except the requester's MAC and IP, copied (10 COPYs + 6);
   - ICMP echo: the request with MACs and IP addresses swapped, type 8 -> 0, and the ICMP checksum
     updated by +0x0800 (the only arithmetic). The IP header checksum is unchanged because swapping
     source and destination does not change the sum; TTL and identification are kept.
   The same engine answers a UDP echo, a Modbus read of constant registers, or a DHCP-less
   "who is there" beacon with other tables. *)

type op = Const of int | Copy of int | Adj_hi of int * int | Adj_lo of int * int | Tail of int | End

let tlen = 42

type template = { value : int array; mask : int array; prog : op list }

let our_mac = [ 0x02; 0x00; 0x00; 0x00; 0x00; 0x10 ]
let our_ip = [ 10; 0; 0; 2 ]

let tmpl l =
  let value = Array.make tlen 0 and mask = Array.make tlen 0 in
  List.iter (fun (off, bytes, m) -> List.iteri (fun k v -> value.(off + k) <- v; mask.(off + k) <- m) bytes) l;
  (value, mask)

let arp_prog =
  List.init 6 (fun i -> Copy (6 + i))                        (* to the requester's MAC *)
  @ List.map (fun b -> Const b) our_mac
  @ List.map (fun b -> Const b) [ 0x08; 0x06; 0x00; 0x01; 0x08; 0x00; 0x06; 0x04; 0x00; 0x02 ]
  @ List.map (fun b -> Const b) our_mac @ List.map (fun b -> Const b) our_ip   (* sender: us *)
  @ List.init 10 (fun i -> Copy (22 + i))                    (* target: requester's MAC and IP *)
  @ List.init 18 (fun _ -> Const 0)                          (* pad to 60 *)
  @ [ End ]

let arp_fields = [ (12, [ 0x08; 0x06 ], 0xFF); (14, [ 0x00; 0x01; 0x08; 0x00; 0x06; 0x04; 0x00; 0x01 ], 0xFF); (38, our_ip, 0xFF) ]

let arp_bcast = let value, mask = tmpl ((0, [ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ], 0xFF) :: arp_fields) in { value; mask; prog = arp_prog }
let arp_ucast = let value, mask = tmpl ((0, our_mac, 0xFF) :: arp_fields) in { value; mask; prog = arp_prog }

let icmp_echo =
  let value, mask =
    tmpl [ (0, our_mac, 0xFF); (12, [ 0x08; 0x00 ], 0xFF); (14, [ 0x45 ], 0xFF);
           (20, [ 0x00; 0x00 ], 0x3F);   (* MF clear, fragment offset 0; DF may be set *)
           (23, [ 0x01 ], 0xFF); (30, our_ip, 0xFF); (34, [ 0x08; 0x00 ], 0xFF) ] in
  let prog =
    List.init 6 (fun i -> Copy (6 + i)) @ List.init 6 (fun i -> Copy i)   (* MACs swapped *)
    @ List.init 14 (fun i -> Copy (12 + i))                                (* type, IP header to checksum *)
    @ List.init 4 (fun i -> Copy (30 + i)) @ List.init 4 (fun i -> Copy (26 + i))   (* IPs swapped *)
    @ [ Const 0x00; Copy 35; Adj_hi (36, 0x0800); Adj_lo (36, 0x0800); Tail 38; End ] in
  { value; mask; prog }

let templates = [ arp_bcast; arp_ucast; icmp_echo ]

let oc_add a b = let s = a + b in let s = (s land 0xFFFF) + (s lsr 16) in s land 0xFFFF

type drop = Bad_fcs | Runt | Too_long | No_match | Busy

let rx_max = 256
let min_len = 64

(* ---- model: the reply to a received frame (bytes including the FCS), or why it was dropped ---- *)
let reply ?(templates = templates) ~fcs_ok (frame : int list) =
  let len = List.length frame in
  if not fcs_ok then Error Bad_fcs
  else if len < min_len then Error Runt
  else if len > rx_max then Error Too_long
  else begin
    let a = Array.of_list frame in
    let matches t = let ok = ref true in for i = 0 to tlen - 1 do if (a.(i) lxor t.value.(i)) land t.mask.(i) <> 0 then ok := false done; !ok in
    match List.find_opt matches templates with
    | None -> Error No_match
    | Some t ->
      let w i = (a.(i) lsl 8) lor a.(i + 1) in
      let out = List.concat_map (function
          | Const c -> [ c ] | Copy i -> [ a.(i) ]
          | Adj_hi (i, k) -> [ oc_add (w i) k lsr 8 ] | Adj_lo (i, k) -> [ oc_add (w i) k land 0xFF ]
          | Tail i -> List.init (max 0 (len - 4 - i)) (fun j -> a.(i + j)) | End -> []) t.prog in
      Ok (out @ Eth_model.fcs_bytes out)
  end

(* ---- ROM images ---- *)
let op_word = function
  | Const c -> (0 lsl 24) lor c | Copy i -> (1 lsl 24) lor (i lsl 16)
  | Adj_hi (i, k) -> (2 lsl 24) lor (i lsl 16) lor k | Adj_lo (i, k) -> (3 lsl 24) lor (i lsl 16) lor k
  | Tail i -> (4 lsl 24) lor (i lsl 16) | End -> 5 lsl 24

let prog_image templates =
  let starts = ref [] and words = ref [] and pos = ref 0 in
  List.iter (fun t -> starts := !pos :: !starts; List.iter (fun o -> words := op_word o :: !words; incr pos) t.prog) templates;
  (List.rev !starts, Array.of_list (List.rev !words))

(* ---- RTL ---- *)

(* for planted-fault controls only *)
let templates_override : template list option ref = ref None
let fcs_reversed = ref false

open Hardcaml
open Signal

type io = { tx_len : Signal.t; tx_ready : Signal.t; tx_rdata : Signal.t array; drops : Signal.t array; replies : Signal.t }

(* [tx_raddr]: read addresses into the transmit buffer (the feeder's); [tx_done]: the feeder has
   finished with the buffer *)
let create ?(templates = templates) ~clock ~clear ~(rx : Rx_path.outputs) ~tx_raddr ~tx_done () =
  let templates = Option.value !templates_override ~default:templates in
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let nt = List.length templates in
  let starts, words = prog_image templates in
  let prog_rom = Array.to_list (Array.map (of_int ~width:27) words) in
  (* receive side: store bytes, track template matches *)
  let idx = Variable.reg spec ~width:12 in
  let matched = Array.init nt (fun _ -> Variable.reg spec ~width:1) in
  let rx_we = rx.byte_valid &: (idx.value <:. rx_max) in
  let rxbuf_raddr = wire 8 in
  let rx_rd = (multiport_memory rx_max
                 ~write_ports:[| { Write_port.write_clock = clock; write_address = select idx.value 7 0; write_enable = rx_we; write_data = rx.byte } |]
                 ~read_addresses:[| rxbuf_raddr; rxbuf_raddr +:. 1 |]) in
  let byte_ok t =
    let tv = mux (select idx.value 5 0) (List.init 64 (fun i -> of_int ~width:8 (if i < tlen then t.value.(i) else 0))) in
    let tm = mux (select idx.value 5 0) (List.init 64 (fun i -> of_int ~width:8 (if i < tlen then t.mask.(i) else 0))) in
    ((rx.byte ^: tv) &: tm) ==:. 0 in
  (* engine state *)
  let s_idle = 0 and s_rewrite = 1 and s_fcs = 2 and s_append = 3 in
  let state = Variable.reg spec ~width:2 in
  let pc = Variable.reg spec ~width:8 and outp = Variable.reg spec ~width:9 and tailj = Variable.reg spec ~width:9 in
  let rx_len = Variable.reg spec ~width:12 in
  let busy = Variable.reg spec ~width:1 and tx_ready = Variable.reg spec ~width:1 and tx_len = Variable.reg spec ~width:9 in
  let drops = Array.init 5 (fun _ -> Variable.reg spec ~width:16) and replies = Variable.reg spec ~width:16 in
  let fidx = Variable.reg spec ~width:9 and fbit = Variable.reg spec ~width:3 in
  let tx_waddr = Variable.wire ~default:(zero 9) and tx_we = Variable.wire ~default:gnd and tx_wdata = Variable.wire ~default:(zero 8) in
  let crc_start = Variable.wire ~default:gnd and crc_valid = Variable.wire ~default:gnd in
  let tx_raddrs = Array.append [| fidx.value |] tx_raddr in
  let tx_rd = multiport_memory 512
      ~write_ports:[| { Write_port.write_clock = clock; write_address = tx_waddr.value; write_enable = tx_we.value; write_data = tx_wdata.value } |]
      ~read_addresses:tx_raddrs in
  let fcs_byte_in = tx_rd.(0) in
  let crc_bit = mux fbit.value (bits_lsb fcs_byte_in) in
  let _, crc_value, _ = Crc_unit.create ~clock ~clear ~cfg:(Rx_path.crc_consts Rx_path.crc32) ~start:crc_start.value ~bit:crc_bit ~valid:crc_valid.value in
  let op = mux pc.value prog_rom in
  let kind = select op 26 24 and oi = select op 23 16 and ok = select op 15 0 and oc = select op 7 0 in
  let tail_mode = Variable.reg spec ~width:1 in
  let w16 = concat_msb [ rx_rd.(0); rx_rd.(1) ] in
  let sum = uresize w16 17 +: uresize ok 17 in
  let adj = select sum 15 0 +: uresize (msb sum) 16 in
  let any = Array.fold_left (fun acc m -> acc |: m.Variable.value) gnd matched in
  let first_prog = List.fold_right2 (fun m st acc -> mux2 m.Variable.value (of_int ~width:8 st) acc) (Array.to_list matched) starts (of_int ~width:8 0) in
  let drop k = drops.(k) <-- drops.(k).value +:. 1 in
  compile
    [ (* receive bookkeeping *)
      when_ rx.byte_valid
        [ idx <-- idx.value +:. 1
        ; proc (List.mapi (fun t tp ->
              let m = matched.(t) in
              if_ (idx.value ==:. 0) [ m <-- byte_ok tp ] [ when_ (idx.value <:. tlen) [ m <-- (m.value &: byte_ok tp) ] ]) templates) ]
    ; when_ rx.frame_end
        [ idx <--. 0
        ; if_ (~:(rx.frame_ok)) [ drop 0 ]
          @@ elif (rx.length <:. min_len) [ drop 1 ]
          @@ elif (rx.length >:. rx_max) [ drop 2 ]
          @@ elif (~:any) [ drop 3 ]
          @@ elif (busy.value |: (state.value <>:. s_idle)) [ drop 4 ]
          @@ [ busy <-- vdd; state <--. s_rewrite; pc <-- first_prog; outp <--. 0; rx_len <-- rx.length; tail_mode <-- gnd ] ]
    ; when_ tx_done [ busy <-- gnd; tx_ready <-- gnd ]
    ; switch state.value
        [ (of_int ~width:2 s_rewrite,
           [ tx_waddr <-- outp.value; tx_we <-- vdd
           ; switch kind
               [ (of_int ~width:3 0, [ tx_wdata <-- oc; outp <-- outp.value +:. 1; pc <-- pc.value +:. 1 ])
               ; (of_int ~width:3 1, [ tx_wdata <-- rx_rd.(0); outp <-- outp.value +:. 1; pc <-- pc.value +:. 1 ])
               ; (of_int ~width:3 2, [ tx_wdata <-- select adj 15 8; outp <-- outp.value +:. 1; pc <-- pc.value +:. 1 ])
               ; (of_int ~width:3 3, [ tx_wdata <-- select adj 7 0; outp <-- outp.value +:. 1; pc <-- pc.value +:. 1 ])
               ; (of_int ~width:3 4,
                  [ if_ (~:(tail_mode.value)) [ tail_mode <-- vdd; tailj <-- uresize oi 9; tx_we <-- gnd ]
                      [ if_ (uresize tailj.value 12 >=: rx_len.value -:. 4) [ tx_we <-- gnd; pc <-- pc.value +:. 1 ]
                          [ tx_wdata <-- rx_rd.(0); outp <-- outp.value +:. 1; tailj <-- tailj.value +:. 1 ] ] ])
               ; (of_int ~width:3 5, [ tx_we <-- gnd; state <--. s_fcs; fidx <--. 0; fbit <--. 0; crc_start <-- vdd ]) ] ])
        ; (of_int ~width:2 s_fcs,
           [ if_ (fidx.value ==: outp.value) [ state <--. s_append; fidx <--. 0 ]
               [ crc_valid <-- vdd; fbit <-- fbit.value +:. 1; when_ (fbit.value ==:. 7) [ fidx <-- fidx.value +:. 1 ] ] ])
        ; (of_int ~width:2 s_append,
           [ tx_waddr <-- outp.value +: uresize (select fidx.value 1 0) 9; tx_we <-- vdd
           ; tx_wdata <-- mux (select fidx.value 1 0) (List.init 4 (fun i -> let i = if !fcs_reversed then 3 - i else i in select crc_value (8 * i + 7) (8 * i)))
           ; fidx <-- fidx.value +:. 1
           ; when_ (fidx.value ==:. 3) [ state <--. s_idle; tx_len <-- outp.value +:. 4; tx_ready <-- vdd; replies <-- replies.value +:. 1 ] ]) ] ];
  (* the rewrite reads the request at the op's index, or at the tail pointer *)
  rxbuf_raddr <== mux2 (tail_mode.value &: (kind ==:. 4)) (select tailj.value 7 0) oi;
  { tx_len = tx_len.value; tx_ready = tx_ready.value; tx_rdata = Array.sub tx_rd 1 (Array.length tx_raddr);
    drops = Array.map (fun d -> d.Variable.value) drops; replies = replies.value }
