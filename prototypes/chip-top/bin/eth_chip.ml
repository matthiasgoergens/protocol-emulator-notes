(* A 10BASE-T node on the combined chip, with the line coding in the bit-path assists: the ARP /
   ping demo of ../eth10-node, its requests built by host_stack.py (scapy) and its replies judged by
   the same script and by the clause-14 checker.

     eth_chip.exe node REQUESTS REPLIES [GAP_US]     the demo
     eth_chip.exe controls REQUESTS DIR              planted faults; each must fail at the judges

   What the chip does. Receive: the line (comparator and squelch on ui_in[2] and ui_in[3], four
   samples per clock) into the edge sampler (Manchester), the framer (start after the SFD 0xD5, end
   at the burst's end), the CRC unit on the frame (CRC-32 residue); T0 moves every byte to the host
   (OUT) as it arrives and reports a good or a bad frame. Transmit: T2 takes a frame (with its FCS)
   from the host through HOSTIN into the data bank, defers while the line is busy, sends the
   preamble, the SFD and the frame to the serialiser (Manchester at 3 clocks per half-bit, TP_IDL
   as the tail, 6 half-bits of TD+ high), waits for the end and the inter-packet gap, and sends
   link pulses while idle (TD+ is ../eth10-node's pin 0: uo_out[0], TD- uo_out[1]).

   What the host does: the reply decisions. ../eth10-node computed them in a match-and-rewrite
   engine of its own (engine.ml); here the host runs that engine's model on the bytes the chip
   forwards and sends the reply back, so the demo shows the chip's line coding, framing, CRC and
   transmit timing end to end, not the engine (the architecture note places that engine in a PE
   segment, which is not built here).

   The chip's specification and its RTL run in lockstep on the board, every pad compared every
   clock; the transmitted line is the specification's pads. *)

open Regs
module S = Chip_spec
module U = Usb_dev
module I = Isa2

let pr fmt = Printf.printf (fmt ^^ "\n%!")

let pad_rx = 2 and pad_sq = 3 and pad_tdp = 0 and pad_tdn = 1

(* events (OUT tag 1); forwarded bytes are tag 0 *)
let eev_frame = 1 and eev_good = 2 and eev_bad = 3 and eev_sent = 4

type fw = { nlp_rounds : int; tail : int; preamble : int; check_crc : bool }
let default_fw = { nlp_rounds = 60; tail = 6; preamble = 7; check_crc = true }

(* T0, receive: thread 0's flags 0-2 are the frame's end, its error flag, the CRC check *)
let t0 (c : fw) =
  let open U in
  [ L "t0"; w (I.ldd 0);
    L "w"; recv "w";
    w (I.outi ~tag:1 eev_frame); w (I.out ());
    L "fwd"; w (I.ldd 0); recv "fchk"; w (I.out ()); jmp "fwd";
    L "fchk"; waitc 0 "fwd";
    waitc 1 "nerr"; jmp "bad";
    L "nerr" ] @ (if c.check_crc then [ waitc 2 "bad" ] else [])
  @ [ w (I.outi ~tag:1 eev_good); jmp "t0";
      L "bad"; w (I.outi ~tag:1 eev_bad); jmp "t0" ]

(* T2, transmit: thread 2's flags 8-9 are the serialiser active, the line active (squelch) *)
let t2 (c : fw) =
  let open U in
  [ L "t2"; w (I.setp ~mask:3 ~value:0 ~oe:1 ());
    L "idle"; w (I.ldc c.nlp_rounds);
    (* wait for a frame in HOSTIN; every 3,990 slots without one counts down to a link pulse *)
    L "wt"; w (I.ldd 3990); J ((fun a -> I.waitc ~cond:I.c_host ~fail:a), "tick"); jmp "frame";
    L "tick"; dec_cnt; jnz "wt";
    (* a link pulse: TD+ high for two slots (133 ns) *)
    w (I.setp ~mask:1 ~value:1 ~oe:1 ()); w I.nop; w (I.setp ~mask:1 ~value:0 ~oe:1 ()); jmp "idle";
    (* the frame: its length n (1 to 255), its bytes into bank page 1, n again *)
    L "frame"; w I.in_; w I.cnta; w (I.lda 0); w (I.bank 1);
    L "cp"; w I.in_; w I.stb; dec_cnt; jnz "cp";
    w I.in_; w I.cnta;
    (* defer while the line is busy *)
    L "df"; w (I.ldd 0); waitc 1 "go"; jmp "df";
    L "go"; w (I.lda 0); w (I.bank 1) ]
  @ List.concat (List.init c.preamble (fun _ -> send_byte 0x55)) @ send_byte 0xD5
  @ [ L "tx"; w I.ldb ] @ send () @ [ dec_cnt; jnz "tx";
      (* the serialiser's end (TP_IDL included), then the inter-packet gap, 9.6 us *)
      L "td"; w (I.ldd 0); waitc 0 "ipg"; jmp "td";
      L "ipg"; w (I.outi ~tag:1 eev_sent); w (I.ldd 144); w I.waitd; jmp "idle" ]

let placement = [| (0, 0x00); (1, 0xF0); (1, 0x00); (1, 0xF8) |]

let images c =
  let progs = [| t0 c; [ U.L "t1"; U.jmp "t1" ]; t2 c; [ U.L "t3"; U.jmp "t3" ] |] in
  Array.mapi (fun t items -> let page, base = placement.(t) in (page, base, U.assemble ~base items)) progs

(* the chip's configuration: [code] the transmit line code register (a control can break it) *)
let configure ?(tx_code = 0x02) (h : Host.t) c =
  let wr tgt addr data = Host.submit h (Host.Write { tgt; addr; data }) in
  Host.wreg h r_ctrl 2;
  Array.iter (fun (page, base, words) ->
      wr t_prog (2 * ((page lsl 8) lor base)) (List.concat_map (fun x -> [ x land 0xFF; x lsr 8 ]) (Array.to_list words)))
    (images c);
  wr t_reg (r_boot_pc 0) (Array.to_list (Array.map snd placement)
                          @ [ Array.fold_left ( lor ) 0 (Array.mapi (fun t (p, _) -> p lsl (2 * t)) placement) ]);
  (* TD+ and TD-: the serialiser's lines, idle showing sequencer pins 0 and 1 (driven low) *)
  wr t_reg (r_padsel pad_tdp) [ src_tx_a; src_tx_b ];
  wr t_reg (r_flagsel 0) [ fl_rx_done; fl_rx_err; fl_crc_check; 31; 31; 31; 31; 31; fl_tx_active; fl_line_active ];
  (* the edge sampler, Manchester on ui_in[2] with the squelch on ui_in[3]: ../eth10-node's
     configuration at four samples per clock (holdoff 75 ns, timeout 200 ns, in sub-samples) *)
  let sub_ns = 1e9 /. 60e6 /. 4.0 in
  let ho = int_of_float (Float.round (75.0 /. sub_ns)) and tmo = int_of_float (200.0 /. sub_ns) in
  wr t_reg r_es_mode [ 0 lor 8; (pad_sq lsl 4) lor pad_rx; ho land 0xFF; ho lsr 8; tmo land 0xFF; tmo lsr 8; 0; 0 ];
  (* CRC-32 over the frame (after the SFD): residue 0xDEBB20E3 *)
  let le32 v = List.init 4 (fun k -> (v lsr (8 * k)) land 0xFF) in
  wr t_reg r_crc_ctrl [ 1 ];
  wr t_reg r_crc_poly (le32 0xEDB88320 @ le32 0xFFFFFFFF @ le32 0xFFFFFFFF @ le32 0xFFFFFFFF @ le32 0xDEBB20E3);
  (* the bit path: port 0, CRC from the frame, half duplex, a frame ends at the burst end and
     starts after the SFD; pass both ways; Manchester out at 3 clocks per half-bit, TP_IDL *)
  wr t_reg r_bp_ctrl
    [ 1 lor (U.port lsl 1) lor 8 lor 16 lor 64 lor 128; 0x00; 0x00; 0xD5; 0xFF; 0;
      tx_code; 0x00; 3; 0; (c.tail land 15) lor 0x10; 0x00; 0x10 ];
  Host.wreg h r_ctrl 1

let read_requests path =
  let ic = open_in path in
  let rec go acc = match input_line ic with
    | line ->
      (match String.split_on_char ' ' line with
       | hex :: e :: label :: _ ->
         let b = List.init (String.length hex / 2) (fun k -> int_of_string ("0x" ^ String.sub hex (2 * k) 2)) in
         go ((b, e = "1", label) :: acc)
       | _ -> go acc)
    | exception End_of_file -> close_in ic; List.rev acc in
  go []

let hex l = String.concat "" (List.map (Printf.sprintf "%02x") l)

type host = {
  outq : int Queue.t;
  mutable cur : int list option;     (* the frame being forwarded *)
  mutable got : int list list;       (* good frames, newest first *)
  mutable bad : int;
  mutable sent : int;
  mutable too_long : int;
}

(* the host program: answer every good frame with the engine model's reply *)
let now = ref 0
let pump (hs : host) (h : Host.t) =
  let handle (tag, v) =
    if Sys.getenv_opt "ETH_DEBUG" <> None && tag = 1 then
      Printf.printf "    [%d] event %d (frame of %d bytes so far)\n" !now v (match hs.cur with Some l -> List.length l | None -> -1);
    if tag = 0 then (match hs.cur with Some l -> hs.cur <- Some (v :: l) | None -> ())
    else if v = eev_frame then hs.cur <- Some []
    else if v = eev_bad then (hs.bad <- hs.bad + 1; hs.cur <- None)
    else if v = eev_sent then hs.sent <- hs.sent + 1
    else if v = eev_good then begin
      (match hs.cur with
       | Some l ->
         let frame = List.rev l in
         hs.got <- frame :: hs.got;
         (match Engine.reply ~fcs_ok:true frame with
          | Ok rep ->
            let n = List.length rep in
            if n > 255 then hs.too_long <- hs.too_long + 1
            else List.iter (fun b -> Queue.push b hs.outq) ([ n ] @ rep @ [ n ])
          | Error _ -> ())
       | None -> ());
      hs.cur <- None
    end in
  if Host.idle h then begin
    (* while a frame is coming in, the host only reads: OUT has no flow control *)
    if hs.cur = None && not (Queue.is_empty hs.outq) then
      Host.submit h (Host.Read { tgt = t_reg; addr = r_hostin_count; n = 1; k = (fun l ->
          let room = S.hostin_depth - List.hd l in
          let k = min room (min 12 (Queue.length hs.outq)) in
          if k > 0 then Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init k (fun _ -> Queue.pop hs.outq) })) })
    else
      Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 16; k = (fun l ->
          let rec go = function t :: d :: rest -> if t land 0x80 <> 0 then handle (t land 7, d); go rest | _ -> () in
          go l) })
  end

(* The demo. Returns (clause-14 verdict and model agreement, replies attributed to requests). *)
let run ?(fw = default_fw) ?tx_code ?(gap_us = 300.0) ?(tail_ms = 20.0) ?(quiet = false) ~requests ~replies_out () =
  let reqs = read_requests requests in
  let t = ref 2000.0 in
  let bursts = List.map (fun (b, _, _) -> let x = Line.make_burst ~start_ns:!t b in t := Line.end_ns x +. (gap_us *. 1000.0); x) reqs in
  let cycles = int_of_float ((!t +. (tail_ms *. 1e6)) *. 60e-3) in
  let line = Line.sample ~clock_hz:60e6 ~n:4 ~cycles bursts in
  let spec = S.create () and rtl = Chip_sim.create () in
  let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
  let b = Board.create () in
  configure ?tx_code b.host fw;
  let hs = { outq = Queue.create (); cur = None; got = []; bad = 0; sent = 0; too_long = 0 } in
  (* the transmit line, differential, as runs of quarter clocks *)
  let runs = ref [] and cur_l = ref 0 and cur_n = ref 0 in
  let push l = if l = !cur_l then incr cur_n else (if !cur_n > 0 then runs := (!cur_l, !cur_n) :: !runs; cur_l := l; cur_n := 1) in
  let mism = ref 0 and loaded = ref false and t0_clock = ref 0 in
  let moved = Array.make 4 0 and stayed = Array.make 4 0 in
  let c = ref 0 in
  (* load first, the line idle *)
  while !c < 2 || not (Host.idle b.host) do
    ignore (Board.advance b cores ~smp:(Board.samples b ~ext:(Array.make n_pads 0)) ~reset:(!c < 2)); incr c
  done;
  loaded := true; t0_clock := b.clock;
  let tr = match Sys.getenv_opt "ETH_TRACE" with Some w -> Scanf.sscanf w "%d-%d" (fun a b -> Some (a, b)) | None -> None in
  for k = 0 to cycles - 1 do
    now := b.clock;
    (match tr with
     | Some (lo, hi) when b.clock >= lo && b.clock <= hi && spec.seq.thread = 0 ->
       let fl = S.flags spec (S.taps spec) ~line_act:false in
       Printf.printf "      %d T0 pc %02x acc %02x dl %d flags %x frame %b fifo %d crc %08x\n" b.clock spec.seq.pcs.(0) spec.seq.accs.(0)
         spec.seq.dls.(0) (fl land 15) spec.rx.in_frame (Queue.length spec.rx.fifo) spec.crc
     | _ -> ());
    pump hs b.host;
    let w, act = line.(k) in
    let ext = Array.make n_pads 0 in
    ext.(pad_rx) <- w; ext.(pad_sq) <- Board.rep4 (Bool.to_int act);
    let smp = Board.samples b ~ext in
    let th = spec.seq.thread in
    let pc0 = spec.seq.pcs.(th) in
    (match Board.advance b cores ~smp ~reset:false with
     | [ a; o ] -> if a.pad_nib <> o.pad_nib || a.uio_oe <> o.uio_oe then incr mism
     | _ -> assert false);
    if spec.seq.pcs.(th) = pc0 then stayed.(th) <- stayed.(th) + 1 else moved.(th) <- moved.(th) + 1;
    (* the pads during this clock: the line is the board's view of the specification's outputs *)
    let o = b.out in
    for q = 0 to 3 do push (((o.pad_nib.(pad_tdp) lsr q) land 1) - ((o.pad_nib.(pad_tdn) lsr q) land 1)) done
  done;
  push 99;
  let runs = List.rev !runs in
  let tick_ns = 1e9 /. 60e6 /. 4.0 in
  let ck = Clause14.check ~tick_ns runs in
  (* the line's time 0 is the first clock after loading; the requests' times count from there *)
  ignore !t0_clock;
  let ends = List.map Line.end_ns bursts in
  let attributed = List.filter_map (function
      | Clause14.Frame { t_ns; bytes = Some by; _ } ->
        let idx = List.fold_left (fun (k, best) e -> (k + 1, if e < t_ns then k else best)) (0, -1) ends |> snd in
        Some (idx, by)
      | _ -> None) ck.events in
  let oc = open_out replies_out in
  List.iter (fun (i, by) -> Printf.fprintf oc "%d %s\n" i (hex by)) attributed;
  close_out oc;
  let model = List.mapi (fun i (by, _, _) ->
      match Engine.reply ~fcs_ok:(Eth_model.crc32_reg by = Eth_model.residual) by with
      | Ok rep when List.length rep <= 255 -> Some (i, rep) | _ -> None) reqs |> List.filter_map Fun.id in
  let model_agrees = model = attributed in
  if not quiet then begin
    let mn l = List.fold_left Float.min infinity l and mx l = List.fold_left Float.max neg_infinity l in
    pr "  %d requests; the chip forwarded %d good frames and reported %d bad; %d replies sent (%d too long for this firmware)"
      (List.length reqs) (List.length hs.got) hs.bad hs.sent hs.too_long;
    pr "  transmit line: %d link pulses (%.1f..%.1f ns), %d frames, TP_IDL %.1f..%.1f ns, %d clause-14 violations%s"
      (List.length ck.nlp_widths) (mn ck.nlp_widths) (mx ck.nlp_widths) (List.length (Clause14.frames_of ck)) (mn ck.tp_idls) (mx ck.tp_idls)
      (List.length ck.violations) (match ck.violations with v :: _ -> " (first: " ^ v ^ ")" | [] -> "");
    pr "  replies equal to the engine model's, request by request: %b" model_agrees;
    pr "  specification and RTL: %d mismatching clocks in %d; HOSTOUT overflowed: %b; framer FIFO overflowed: %b" !mism cycles
      spec.hout_ovf spec.rx.ovf;
    let lat = List.filter_map (function
        | Clause14.Frame { t_ns; bytes = Some _; _ } ->
          let e = List.fold_left (fun best e -> if e < t_ns then e else best) neg_infinity ends in Some ((t_ns -. e) /. 1e3)
        | _ -> None) ck.events in
    pr "  latency from the end of a request to the start of its reply: %.1f..%.1f us" (mn lat) (mx lat);
    pr "  thread time (slots in which the pc moved on, of all slots):";
    Array.iteri (fun t m -> pr "    T%d: %d of %d (%.2f %%)" t m (m + stayed.(t)) (100.0 *. float m /. float (max 1 (m + stayed.(t))))) moved
  end;
  (ck.violations = [] && model_agrees && !mism = 0, attributed)

let () =
  match Array.to_list Sys.argv with
  | _ :: "node" :: requests :: replies :: rest ->
    let gap_us = match rest with g :: _ -> float_of_string g | [] -> 300.0 in
    let sizes = Array.map (fun (_, _, w) -> Array.length w) (images default_fw) in
    pr "== 10BASE-T ARP/ping on the combined chip (receive T0 %d words, transmit T2 %d words)" sizes.(0) sizes.(2);
    let ok, _ = run ~gap_us ~requests ~replies_out:replies () in
    pr "node: %s" (if ok then "PASS" else "FAIL");
    exit (if ok then 0 else 1)
  | [ _; "controls"; requests; dir ] ->
    let cases = [
      ("TP_IDL of 4 half-bits", (fun out -> run ~fw:{ default_fw with tail = 4 } ~quiet:true ~tail_ms:1.0 ~requests ~replies_out:out ()));
      ("preamble of 6 bytes", (fun out -> run ~fw:{ default_fw with preamble = 6 } ~quiet:true ~tail_ms:1.0 ~requests ~replies_out:out ()));
      ("Manchester inverted (G. E. Thomas)", (fun out -> run ~tx_code:0x06 ~quiet:true ~tail_ms:1.0 ~requests ~replies_out:out ()));
      ("receive CRC not checked", (fun out -> run ~fw:{ default_fw with check_crc = false } ~quiet:true ~tail_ms:1.0 ~requests ~replies_out:out ()));
    ] in
    List.iteri (fun k (name, f) ->
        let out = Filename.concat dir (Printf.sprintf "replies-chip-control%d.txt" k) in
        let ok, _ = f out in
        pr "control %d: %-40s chip-side checks %s; replies in %s" k name (if ok then "pass" else "FAIL") out) cases
  | _ -> prerr_endline "usage: eth_chip.exe node REQUESTS REPLIES [GAP_US] | controls REQUESTS DIR"; exit 2
