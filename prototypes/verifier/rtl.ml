(* Certificates on the RTL: SymbiYosys properties generated from a timing certificate, which the
   sequencer-v2 core (../sequencer-v2/sequencer2.ml, the Verilog of tt/src) must meet while it
   runs the certified image (README.md, section 8).

   The input is the certificate's text, as `certs` writes it and the ledger hashes it, parsed
   back here, and the image whose SHA-256 the certificate names. Nothing of the analysis is used:
   a property comes from a line of the certificate or from its header.

   What the generated monitor watches. Thread T runs the image from pc 0 of page T; every other
   thread executes an arbitrary instruction word on each of its clocks (the store is not
   modelled for them), constrained only not to write the channel's pins (A5, which `compose`
   checks for real programmes). Every input of the core is free on every clock (A1); the host
   control port never addresses thread T (A2); the page is fixed (A3, asserted). Clear is high
   for exactly the first clock. After it, thread t executes on clocks c with (c - 1) mod 4 = t,
   so slot s of thread T is clock 4s + T + 1 here (4s + T counted from the first clock after
   clear, as in the certificate).

   The monitor reads only the core's ports: the store address the core presents one clock before
   thread T executes is T's pc for that slot (imem_addr, as the store sees it), and pin_out,
   pin_oe and pin_sub after the slot are what the slot did to the pins. From the pc sequence it
   classifies each slot of T: an event when the instruction at that pc is one that touches the
   channel (a SETP or SHO writing a channel pin, a WAITP on one, an SHI of one) and it did not
   stay (a WAITP that stays has made no event yet); the outcome is told apart by the next pc
   (pc + 1 when a WAITP proceeds, its fail target when it times out). It then keeps the
   specification state and the slots since the previous event as ghost state, and asserts:

   events    every event is a line of the certificate: from the current state, at that pc, with
             that outcome, with its slot and its gap inside the line's intervals
   levels    every channel pin a write event touches is left at the line's level (driven 0,
             driven 1, released), and every channel pin it does not touch is unchanged; no other
             slot of T changes a channel pin
   data      where the line declares its data ("data byteI.bitB"), the data pin is left at that
             bit of input byte I, the image's I-th LDA immediate, which is free (anyconst): the
             proof covers every byte value at once
   subslot   the quarter-clock levels (pin_sub) of the channel pins after a write switch to the
             new level at the line's q and are steady otherwise
   deadline  the slots since the last event never exceed the current state's deadline (the
             certificate's "# deadlines" line)
   quiet     no clock that is not thread T's changes a channel pin, or shows a quarter-clock
             level different from the pin's
   page      every store address presented for thread T is on page T

   Each assertion has an antecedent cover, [<name>_ante] (README.md of ../formal, section 6):
   the specification's last state, the end of the certified frame, is reached. It is decided by
   a separate bounded run with the antecedent asserted negated ([done_reach]), whose failure at
   step n means reachable at step n. *)

type level = L | H | Z | Unknown

type line = {
  pc : int;
  outcome : [ `Write | `Seen | `Timeout | `Sample ];
  writes : (int * level) list;     (* channel pins this line's event writes, with their levels *)
  from_ : int; to_ : int;
  slot : Interval.t; gap : Interval.t; q : int;
  data : (int * int) option;
  text : string;                   (* the certificate's line, for the generated comments *)
}

type cert = {
  image : string; sha : string; pins : int list; bytes : int array;
  deadlines : (int * int) list; lines : line list;
}

let fail fmt = Printf.ksprintf failwith fmt

let interval_of s =
  match String.index_opt s '.' with
  | None -> Interval.exactly (int_of_string s)
  | Some i ->
    let lo = int_of_string (String.sub s 0 i) and hi = String.sub s (i + 2) (String.length s - i - 2) in
    if hi = "?" then Interval.at_least lo else Interval.range lo (int_of_string hi)

let words s = List.filter (fun x -> x <> "") (String.split_on_char ' ' s)

let starts_with p s = String.length s >= String.length p && String.sub s 0 (String.length p) = p

(* "p5:seen=1", "p4:set=z", "p0:sho=1", "p5:timeout(1)", "p4:sample" *)
let is_pin_token t = String.length t >= 3 && t.[0] = 'p' && t.[1] >= '0' && t.[1] <= '7' && t.[2] = ':'

let parse text =
  let image = ref "" and sha = ref "" and pins = ref [] and bytes = ref [||] and deadlines = ref [] in
  let lines = ref [] in
  List.iter (fun raw ->
      let ws = words raw in
      match ws with
      | "#" :: "image" :: name :: "sha256" :: h :: _ -> image := name; sha := h
      | "#" :: "specification:" :: rest ->
        (match List.rev rest with
         | p :: "pins" :: "channel" :: _ -> pins := List.map int_of_string (String.split_on_char ',' p)
         | _ -> fail "certificate: no channel pins in %S" raw)
      | "#" :: "input" :: "bytes:" :: bs ->
        bytes := Array.of_list (List.map (fun b -> Scanf.sscanf b "byte%d=0x%x" (fun _ v -> v)) bs)
      | "#" :: "deadlines:" :: ds -> deadlines := List.map (fun d -> Scanf.sscanf d "%d:%d" (fun a b -> (a, b))) ds
      | "VIOLATION" :: _ -> fail "certificate %s is not a proof" !image
      | "#" :: _ | [] -> ()
      | pc :: rest ->
        (* pc, the instruction (several words), the pins touched, from -> to, slot S [qN],
           gap G, declared D [data byteI.bitB] *)
        let rec split_instr acc = function
          | t :: r when not (is_pin_token t) -> split_instr (t :: acc) r
          | r -> List.rev acc, r in
        let _instr, r = split_instr [] rest in
        let rec split_ev acc = function
          | t :: r when is_pin_token t -> split_ev (t :: acc) r
          | r -> List.rev acc, r in
        let ev, r = split_ev [] r in
        (match r with
         | _ :: "->" :: "-" :: _ -> ()          (* not a channel event *)
         | from_ :: "->" :: to_ :: "slot" :: slot :: r ->
           let q, r = match r with t :: r when starts_with "q" t -> int_of_string (String.sub t 1 (String.length t - 1)), r | r -> 0, r in
           (match r with
            | "gap" :: gap :: "declared" :: _declared :: r ->
              let data = match r with
                | [ "data"; d ] -> Some (Scanf.sscanf d "byte%d.bit%d" (fun i b -> (i, b)))
                | [] -> None
                | _ -> fail "certificate: trailing %S" raw in
              let pin_of t = Char.code t.[1] - Char.code '0' in
              let kind_of t = String.sub t 3 (String.length t - 3) in
              let chan = List.filter (fun t -> List.mem (pin_of t) !pins) ev in
              let level_of s = match s with
                | "0" -> L | "1" -> H | "z" -> Z | "d" | "dz" | "x" -> Unknown
                | _ -> fail "certificate: level %S" s in
              let outcome, writes =
                match chan with
                | [ t ] when starts_with "seen=" (kind_of t) -> `Seen, []
                | [ t ] when starts_with "timeout(" (kind_of t) -> `Timeout, []
                | [ t ] when kind_of t = "sample" -> `Sample, []
                | ts -> `Write, List.map (fun t ->
                    match String.split_on_char '=' (kind_of t) with
                    | [ ("set" | "sho"); l ] -> (pin_of t, level_of l)
                    | _ -> fail "certificate: event %S" raw) ts in
              lines := { pc = int_of_string pc; outcome; writes; from_ = int_of_string from_; to_ = int_of_string to_;
                         slot = interval_of slot; gap = interval_of gap; q; data; text = String.trim raw } :: !lines
            | _ -> fail "certificate: line %S" raw)
         | _ -> fail "certificate: line %S" raw)) (String.split_on_char '\n' text);
  if !image = "" then fail "certificate: no image line";
  { image = !image; sha = !sha; pins = List.sort compare !pins; bytes = !bytes; deadlines = !deadlines;
    lines = List.rev !lines }

(* ---- controls: the certificate's text, edited ---- *)

(* the [n]-th channel-event line (from 0) with its gap replaced by [gap] *)
let edit_gap text n gap =
  let k = ref (-1) in
  String.concat "\n" (List.map (fun raw ->
      let ws = words raw in
      let is_event = match ws with
        | "#" :: _ | [] | "VIOLATION" :: _ -> false
        | _ -> not (List.exists (fun i -> i + 2 < List.length ws && List.nth ws i = "->" && List.nth ws (i + 1) = "-")
                      (List.init (List.length ws) Fun.id)) in
      if not is_event then raw
      else begin
        incr k;
        if !k <> n then raw
        else
          let rec go = function
            | "gap" :: _ :: r -> "gap" :: gap :: r
            | t :: r -> t :: go r
            | [] -> fail "edit_gap: no gap in %S" raw in
          String.concat " " (go ws)
      end) (String.split_on_char '\n' text))

(* every "data byteI.bitB" replaced by bit B + 1 (mod 8) of the same byte *)
let edit_data text =
  String.concat "\n" (List.map (fun raw ->
      match List.rev (words raw) with
      | d :: "data" :: rest -> String.concat " " (List.rev rest) ^ " data "
                              ^ Scanf.sscanf d "byte%d.bit%d" (fun i b -> Printf.sprintf "byte%d.bit%d" i ((b + 1) land 7))
      | _ -> raw) (String.split_on_char '\n' text))

(* ---- the generator ---- *)

let opcode w = (w lsr 12) land 15

(* the instructions that may issue more than once (Isa2: WAITP, WAITD, IN, MBX, WAITC) *)
let can_stay w = List.mem (opcode w) [ 5; 6; 12; 13; 14 ]

(* the pcs whose instruction touches a channel pin, by the kernel's step from an unknown state *)
let channel_pcs ~pins (words : int array) =
  List.filter (fun pc ->
      let k = { Kernel.pc; astate = 0; cnt = Any; acc = Any; oe_known = 0; oe = 0 } in
      List.exists (fun (r : Kernel.raw) -> List.exists (fun (p, _) -> List.mem p pins) r.ev)
        (Kernel.transfer words.(pc) k (Interval.range 0 4095)))
    (List.init Isa2.page_len Fun.id)

let successor (words : int array) l =
  match l.outcome with
  | `Timeout -> words.(l.pc) land 0xFF
  | `Write | `Seen | `Sample -> (l.pc + 1) land 0xFF

let bits_for n = let rec go b = if 1 lsl b > n then b else go (b + 1) in max 1 (go 1)

let vlit w n = Printf.sprintf "%d'd%d" w n

(* the SystemVerilog of the check: module cert_check (the environment, the store, the monitor)
   and the store's contents. [symbolic]: the image's LDA immediates that carry the input bytes
   are free constants. *)
let generate ~thread:t ~(words : int array) (c : cert) =
  let b = Buffer.create 65536 in
  let p fmt = Printf.bprintf b fmt in
  let pins = c.pins in
  let ch_mask = List.fold_left (fun m x -> m lor (1 lsl x)) 0 pins in
  let symbolic = Array.length c.bytes > 0 && List.exists (fun l -> l.data <> None) c.lines in
  (* the input bytes: the image's LDA immediates in pc order must be the certificate's bytes *)
  let lda_pcs = List.filter (fun pc -> opcode words.(pc) = Isa2.op_lda) (List.init Isa2.page_len Fun.id) in
  if symbolic then begin
    let imms = List.map (fun pc -> words.(pc) land 0xFF) lda_pcs in
    if imms <> Array.to_list c.bytes then
      fail "image %s: LDA immediates %s are not the certificate's input bytes" c.image
        (String.concat "," (List.map string_of_int imms))
  end;
  let nlines = List.length c.lines in
  let max_state = List.fold_left (fun m l -> max m (max l.from_ l.to_)) 0 c.lines in
  let sw = bits_for (max_state + 1) in
  let finite_hi (i : Interval.t) = match i.hi with Some h -> h | None -> i.lo in
  let max_deadline = List.fold_left (fun m (_, d) -> max m d) 0 c.deadlines in
  let max_gap = List.fold_left (fun m l -> max m (finite_hi l.gap)) 0 c.lines in
  let since_cap = max max_deadline max_gap + 2 in
  let max_slot = List.fold_left (fun m l -> max m (finite_hi l.slot)) 0 c.lines in
  let slot_cap = max_slot + 2 in
  let gw = bits_for since_cap and slw = bits_for slot_cap in
  let final = List.fold_left (fun m l -> max m l.to_) 0 c.lines in
  (* the final states: reached by a line, left by none (the end of the frame, or of a timeout) *)
  let finals = List.sort_uniq compare (List.filter_map (fun l ->
      if List.exists (fun l' -> l'.from_ = l.to_) c.lines then None else Some l.to_) c.lines) in
  (* lines that agree on state, pc and outcome must agree on the state they lead to *)
  List.iter (fun l -> List.iter (fun l' ->
      if l.from_ = l'.from_ && l.pc = l'.pc && successor words l = successor words l' && l.to_ <> l'.to_ then
        fail "lines %S and %S lead to different states" l.text l'.text) c.lines) c.lines;
  let ev_pcs = channel_pcs ~pins words in
  (* an event pc whose fail target is itself or pc + 1 could not be told apart by the next pc *)
  List.iter (fun l -> if l.outcome = `Timeout && (successor words l = l.pc || successor words l = (l.pc + 1) land 0xFF) then
                fail "pc %d: the timeout's target cannot be told from a stay or a proceed" l.pc) c.lines;
  p "// Generated by prototypes/verifier main.exe rtl from the timing certificate of %s\n" c.image;
  p "// (sha256 of the image %s); do not edit. rtl.ml says what each property means.\n" c.sha;
  p "// Thread %d, channel pins %s (mask 8'h%02x); %d certificate lines.\n" t
    (String.concat "," (List.map string_of_int pins)) ch_mask nlines;
  p "module cert_check (input clock);\n";
  p "  localparam T = %d;\n" t;
  p "  localparam [7:0] CH = 8'h%02x;\n" ch_mask;
  (* environment *)
  p "  // A1: every input free on every clock\n";
  List.iter (fun (n, w) -> p "  (* anyseq *) reg [%d:0] %s;\n" (w - 1) n)
    [ "pin_in", 8; "pin_in4", 32; "flags", 16; "host_in", 8; "host_in_valid", 1; "port_in0", 8; "port_in1", 8;
      "port_in2", 8; "port_in3", 8; "port_in_valid", 4; "port_out_ready", 4; "bank_rdata", 8;
      "ctl_valid", 1; "ctl_thread", 2; "ctl_page", 2; "ctl_pc", 8; "other_word", 16 ];
  if symbolic then
    Array.iteri (fun i _ -> p "  (* anyconst *) reg [7:0] byte%d;   // input byte %d: the image's LDA %d immediate\n" i i i) c.bytes;
  p "  reg started = 1'b0;\n  always @(posedge clock) started <= 1'b1;\n  wire clear = !started;\n";
  p "  // the thread that executes on this clock; 3 during clear, so 0 on the first clock after it\n";
  p "  reg [1:0] phase = 2'd3;\n  always @(posedge clock) phase <= phase + 2'd1;\n";
  (* store *)
  p "  // the store: thread T's page holds the image%s; a one-clock synchronous read\n"
    (if symbolic then ", its LDA immediates the free input bytes" else "");
  p "  function [15:0] image_word(input [7:0] a);\n    case (a)\n";
  Array.iteri (fun pc w ->
      if w <> 0 then begin
        match List.find_index (fun x -> x = pc) lda_pcs with
        | Some i when symbolic -> p "      8'd%d: image_word = {8'h%02x, byte%d};  // %s\n" pc (w lsr 8) i (Isa2.disasm w)
        | _ -> p "      8'd%d: image_word = 16'h%04x;  // %s\n" pc w (Isa2.disasm w)
      end) words;
  p "      default: image_word = 16'h0000;  // nop\n    endcase\n  endfunction\n";
  p "  wire [9:0] imem_addr;\n  reg [15:0] store_q;\n  always @(posedge clock) store_q <= image_word(imem_addr[7:0]);\n";
  p "  wire [15:0] imem_data = (started && phase == T) ? store_q : other_word;\n";
  p "  // A5: the other threads' words do not write the channel (SETP's mask, SHO's pin and pair partner)\n";
  p "  wire [3:0] o_op = other_word[15:12];\n  wire [2:0] o_pin = other_word[11:9];\n";
  p "  wire [7:0] o_sho = (8'd1 << o_pin) | (other_word[6] ? (8'd1 << (o_pin + 3'd1)) : 8'd0);\n";
  p "  always @(*) if (started && phase != T) begin\n";
  p "    assume (!(o_op == 4'd%d && (other_word[11:4] & CH) != 8'd0));\n" Isa2.op_setp;
  p "    assume (!(o_op == 4'd%d && (o_sho & CH) != 8'd0));\n  end\n" Isa2.op_sho;
  p "  // A2: the host control port never addresses thread T\n";
  p "  always @(*) assume (!(ctl_valid && ctl_thread == T));\n";
  (* the core *)
  p "  wire [7:0] pin_out, pin_oe;\n  wire [31:0] pin_sub;\n";
  p "  deadline_sequencer_v2 core (\n";
  p "    .clock(clock), .clear(clear), .imem_data(imem_data), .pin_in(pin_in), .pin_in4(pin_in4),\n";
  p "    .host_in(host_in), .host_in_valid(host_in_valid), .port_in0(port_in0), .port_in1(port_in1),\n";
  p "    .port_in2(port_in2), .port_in3(port_in3), .port_in_valid(port_in_valid), .port_out_ready(port_out_ready),\n";
  p "    .flags(flags), .ctl_valid(ctl_valid), .ctl_thread(ctl_thread), .ctl_page(ctl_page), .ctl_pc(ctl_pc),\n";
  p "    .boot_page(8'b11_10_01_00), .boot_pc(32'd0), .bank_rdata(bank_rdata),\n";
  p "    .imem_addr(imem_addr), .pin_out(pin_out), .pin_oe(pin_oe), .pin_sub(pin_sub));\n";
  (* the visible state of the channel *)
  p "  // a pin as the wire sees it: {enable, driven level}\n";
  p "  wire [15:0] vis;\n";
  for i = 0 to 7 do p "  assign vis[%d:%d] = {pin_oe[%d], pin_oe[%d] & pin_out[%d]};\n" (2 * i + 1) (2 * i) i i i done;
  p "  wire [15:0] VCH = 16'h%04x;\n" (List.fold_left (fun m x -> m lor (3 lsl (2 * x))) 0 pins);
  (* sampling around thread T's slot *)
  p "  // thread T's slot: the address presented the clock before (phase T - 1) is its pc; the pins\n";
  p "  // one clock after (phase T + 1) show what it did\n";
  p "  wire fetch_t = phase == 2'd%d;\n" ((t + 3) land 3);
  p "  reg have = 1'b0;          // a slot of T has executed since the last fetch_t clock\n";
  p "  reg [7:0] pc_s = 8'd0;    // its pc\n";
  p "  reg [15:0] vis_b = 16'd0, vis_a = 16'd0, vis_prev = 16'd0;\n  reg [7:0] out_b = 8'd0, out_a = 8'd0;\n  reg [31:0] sub_a = 32'd0;\n";
  p "  reg past1 = 1'b0;         // vis_prev holds a clock after clear\n";
  p "  always @(posedge clock) begin\n";
  p "    vis_prev <= vis; past1 <= started;\n";
  p "    if (fetch_t) pc_s <= imem_addr[7:0];\n";
  p "    if (started && phase == T) begin vis_b <= vis; out_b <= pin_out; have <= 1'b1; end\n";
  p "    if (started && phase == 2'd%d) begin vis_a <= vis; out_a <= pin_out; sub_a <= pin_sub; end\n" ((t + 1) land 3);
  p "  end\n";
  p "  wire step = started && fetch_t && have;   // slot s of T is complete; imem_addr is the pc of slot s + 1\n";
  p "  wire [7:0] P = pc_s, P2 = imem_addr[7:0];\n";
  (* ghost state *)
  p "  reg [%d:0] astate = %s;\n  reg [%d:0] since = %s;\n  reg [%d:0] slot = %s;\n" (sw - 1) (vlit sw 0) (gw - 1) (vlit gw 0) (slw - 1) (vlit slw 0);
  p "  reg done = 1'b0;          // the certificate's last state has been reached\n";
  List.iter (fun a -> p "  reg fin_%d = 1'b0;         // final state %d has been reached\n" a a) finals;
  (* event classification *)
  p "  // the pcs whose instruction touches the channel; those that may stay (WAITP) make no event\n  // on a slot after which the pc is unchanged\n";
  p "  reg ev_pc, stays;\n  always @(*) begin\n    case (P)\n";
  List.iter (fun pc -> p "      8'd%d: begin ev_pc = 1'b1; stays = %s; end  // %s\n" pc (if can_stay words.(pc) then "P2 == P" else "1'b0")
                (Isa2.disasm words.(pc))) ev_pcs;
  p "      default: begin ev_pc = 1'b0; stays = 1'b0; end\n    endcase\n  end\n";
  p "  wire event_ = step && ev_pc && !stays;\n";
  (* the lines *)
  p "  // one match per certificate line: state, pc, outcome (by the next pc), slot and gap\n";
  p "  wire [%d:0] m_where, m_time;\n" (nlines - 1);
  List.iteri (fun j l ->
      let cond_iv name (iv : Interval.t) w =
        let lo = if iv.lo > 0 then Some (Printf.sprintf "%s >= %s" name (vlit w iv.lo)) else None in
        let hi = match iv.hi with Some h -> Some (Printf.sprintf "%s <= %s" name (vlit w h)) | None -> None in
        match List.filter_map Fun.id [ lo; hi ] with [] -> "1'b1" | l -> String.concat " && " l in
      p "  // %s\n" l.text;
      p "  assign m_where[%d] = astate == %s && P == 8'd%d && P2 == 8'd%d;\n" j (vlit sw l.from_) l.pc (successor words l);
      p "  assign m_time[%d] = %s && %s;\n" j (cond_iv "slot" l.slot slw) (cond_iv "since" l.gap gw)) c.lines;
  (* levels, data and sub-slot per line *)
  let level_expr pin = function
    | L -> Some (Printf.sprintf "vis_a[%d:%d] == 2'b10" (2 * pin + 1) (2 * pin))
    | H -> Some (Printf.sprintf "vis_a[%d:%d] == 2'b11" (2 * pin + 1) (2 * pin))
    | Z -> Some (Printf.sprintf "vis_a[%d:%d] == 2'b00" (2 * pin + 1) (2 * pin))
    | Unknown -> None in
  let data_pin l = match l.data, l.writes with
    | Some _, [ (pin, _) ] -> Some pin
    | Some _, _ -> fail "line %S declares data but writes %d pins" l.text (List.length l.writes)
    | None, _ -> None in
  p "  // levels: the pins the line writes at its level (not the data pin of a line with data), the\n  // other channel pins unchanged\n";
  p "  wire [%d:0] m_level, m_data, m_sub;\n" (nlines - 1);
  List.iteri (fun j l ->
      let written = List.map fst l.writes in
      let unchanged = List.filter (fun x -> not (List.mem x written)) pins in
      let conds =
        List.filter_map (fun (pin, lv) -> if Some pin = data_pin l && symbolic then None else level_expr pin lv) l.writes
        @ List.map (fun x -> Printf.sprintf "vis_a[%d:%d] == vis_b[%d:%d]" (2 * x + 1) (2 * x) (2 * x + 1) (2 * x)) unchanged in
      p "  assign m_level[%d] = %s;\n" j (match conds with [] -> "1'b1" | l -> String.concat " && " l);
      (match l.data, data_pin l with
       | Some (i, bit), Some pin when symbolic ->
         let od = opcode words.(l.pc) = Isa2.op_sho && (words.(l.pc) lsr 7) land 1 = 1 in
         p "  assign m_data[%d] = vis_a[%d:%d] == %s;  // byte%d.bit%d, %s\n" j (2 * pin + 1) (2 * pin)
           (if od then Printf.sprintf "(byte%d[%d] ? 2'b00 : 2'b10)" i bit else Printf.sprintf "{1'b1, byte%d[%d]}" i bit)
           i bit (if od then "open drain" else "push-pull")
       | _ -> p "  assign m_data[%d] = 1'b1;\n" j);
      let subs = List.concat_map (fun x -> List.init 4 (fun q ->
          Printf.sprintf "sub_a[%d] == %s" (4 * x + q) (if q < l.q then Printf.sprintf "out_b[%d]" x else Printf.sprintf "out_a[%d]" x))) pins in
      p "  assign m_sub[%d] = %s;\n" j (String.concat " && " subs)) c.lines;
  let steady name = String.concat " && " (List.concat_map (fun x -> List.init 4 (fun q ->
      Printf.sprintf "%s[%d] == %s[%d]" name (4 * x + q) (if name = "sub_a" then "out_a" else "pin_out") x)) pins) in
  (* deadlines *)
  p "  reg [%d:0] deadline; reg has_deadline;\n  always @(*) begin\n    has_deadline = 1'b1;\n    case (astate)\n" (gw - 1);
  List.iter (fun (a, d) -> p "      %s: deadline = %s;\n" (vlit sw a) (vlit gw d)) c.deadlines;
  p "      default: begin deadline = %s; has_deadline = 1'b0; end\n    endcase\n  end\n" (vlit gw 0);
  (* the next state *)
  p "  reg [%d:0] next_state;\n  always @(*) begin\n    next_state = astate;\n" (sw - 1);
  List.iteri (fun j l -> p "    if (m_where[%d]) next_state = %s;\n" j (vlit sw l.to_)) c.lines;
  p "  end\n";
  p "  always @(posedge clock) if (step) begin\n";
  p "    if (event_) begin astate <= next_state; since <= %s; end\n" (vlit gw 1);
  p "    else if (since != %s) since <= since + %s;\n" (vlit gw since_cap) (vlit gw 1);
  p "    if (slot != %s) slot <= slot + %s;\n" (vlit slw slot_cap) (vlit slw 1);
  p "    if (event_ && next_state == %s) done <= 1'b1;\n" (vlit sw final);
  List.iter (fun a -> p "    if (event_ && next_state == %s) fin_%d <= 1'b1;\n" (vlit sw a) a) finals;
  p "  end\n";
  (* properties *)
  p "  // ---- properties ----\n";
  p "  always @(*) if (step) begin\n";
  p "    events: assert (!event_ || (m_where & m_time) != %d'd0);\n" nlines;
  p "    levels: assert (event_ ? (m_where & m_level) != %d'd0 : (vis_a & VCH) == (vis_b & VCH));\n" nlines;
  (* without declared data there is nothing to assert: no data property, rather than a vacuous one *)
  if symbolic then p "    data: assert (!event_ || (m_where & m_data) != %d'd0);\n" nlines;
  p "    subslot: assert (event_ ? (m_where & m_sub) != %d'd0 : (%s));\n" nlines (steady "sub_a");
  p "    deadline_: assert (!has_deadline || since <= deadline);\n";
  p "  end\n";
  p "  always @(*) if (past1 && phase != 2'd%d) quiet: assert ((vis & VCH) == (vis_prev & VCH) && %s);\n" ((t + 1) land 3) (steady "pin_sub");
  p "  always @(*) if (fetch_t && started) page: assert (imem_addr[9:8] == T);\n";
  p "  // antecedents: the certificate's last state (state %d) is reached\n" final;
  List.iter (fun n -> p "  always @(*) %s_ante: cover (done);\n" n)
    ([ "events"; "levels" ] @ (if symbolic then [ "data" ] else []) @ [ "subslot"; "deadline_"; "quiet"; "page" ]);
  List.iter (fun a -> p "  always @(*) final_%d: cover (fin_%d);\n" a a) finals;
  p "  // the same as one negated assertion, for a bit-level BMC (abc bmc3): failing at step n is\n";
  p "  // reachable at step n. REACH names the signal (done, or fin_N)\n";
  p "`ifdef REACH\n  always @(*) reach: assert (!`REACH);\n`endif\n";
  p "endmodule\n";
  Buffer.contents b, (4 * (slot_cap + 2) + t + 8), finals
