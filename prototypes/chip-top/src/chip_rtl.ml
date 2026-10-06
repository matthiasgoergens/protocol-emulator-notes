(* The chip core in Hardcaml: the blocks' own RTL, unchanged, and the glue that joins them.
   chip_spec.ml says what every clock must do; this file is checked against it in lockstep.

   Blocks: Sequencer2 (../sequencer-v2), Upe_rtl.array_create (../unified-pe/verify),
   Streamer and Sampler (../pin-streamer, ../pin-sampler), Edge_sampler, Crc_unit and Matcher_en
   (../eth10-node), Nco (../multiphase). The four-phase stage is outside the core (tt_top.ml).

   [bug] plants one integration fault by name (see [bugs]); "" is the design. Memories are
   behavioural by default; [mems] replaces them for hardening. *)
open Hardcaml
open Signal
open Regs

let bug = ref ""
let is b = !bug = b

let bugs =
  [ "pin_lane_swap", "sequencer pins 0 and 1 swapped at the pad source select";
    "quarter_swap", "quarters 1 and 2 of a sequencer pin's nibble swapped";
    "pinin_quarter0", "pin_in takes the quarter-0 sample instead of the latest";
    "pinin_lane_swap", "logical input pins 2 and 3 read each other's pads";
    "mbx_port_swap", "SEND on port 1 writes segment 2's feed";
    "recv_port_swap", "RECV on port 2 reads port 3's holding register";
    "send_order", "a port's first SEND byte goes in as the high byte";
    "tap_seg_miswire", "port p's holding register takes segment p+1's tap";
    "fixed_port_seg1", "the recovered-bit stream goes to segment 1's fixed port";
    "host_mbx_priority", "a host feed write wins over a thread's SEND, which is lost";
    "flag_off_by_one", "flag f uses flag f+1's select";
    "flag_thread_rot", "thread t sees thread t+1's flags";
    "nibble_order", "the host link takes a byte's low nibble first";
    "read_nibble_order", "the host link sends a byte's low nibble first";
    "hostin_ungated", "the threads' IN pops the FIFO while the core is held in clear";
    "bank_ungated", "a STB writes the bank while the core is held in clear";
    "hostout_no_latch", "HOSTOUT pops on the data byte even when the tag byte said empty";
    "smp_pin_swap", "sampler pins 0 and 1 swapped";
    "uio_oe_swap", "the output enables of uio 6 and 7 swapped";
    "boot_pc_swap", "boot pcs of threads 1 and 2 swapped";
    "restart_page", "the restart register's page ignored";
    "es_quarter_rev", "the edge sampler sees the quarters in reverse order";
    "nco_inc_bytes", "the NCO increment's two low bytes swapped";
    "prog_byte_order", "a programme word's bytes swapped";
    "pecfg_seg", "PECFG selects the segment from address bits 10:9";
    "status_not_cleared", "writing STATUS does not clear the sticky bits";
    "hostin_overwrite", "a push into a full HOSTIN FIFO is accepted" ]

let config = Chip_spec.default_config

(* A synchronous single-port memory: [addr], [we] and [wdata] in one clock; the word at [addr]
   is on the output during the next clock. *)
type mem = clock:Signal.t -> size:int -> width:int -> addr:Signal.t -> we:Signal.t -> wdata:Signal.t -> Signal.t

let behavioural_mem : mem =
 fun ~clock ~size ~width:_ ~addr ~we ~wdata ->
  let abits = address_bits_for size in
  let a = select addr (abits - 1) 0 in
  let q = memory size ~write_port:{ write_clock = clock; write_address = a; write_enable = we; write_data = wdata }
      ~read_address:(reg (Reg_spec.create ~clock ()) a) in
  q

type mems = { prog_mem : mem; bank_mem : mem }

let behavioural = { prog_mem = behavioural_mem; bank_mem = behavioural_mem }

type outputs = { pad_nib : Signal.t; uio_oe : Signal.t; dbg : (string * Signal.t) list }

(* a FIFO of [depth] entries; a push into a full FIFO is taken when the head leaves in the same
   clock. Returns head, count, accept. *)
let fifo ~name spec ~depth ~push ~pop ~data =
  let pbits = address_bits_for depth in
  let ( -- ) s n = s -- (name ^ "_" ^ n) in
  let rd = wire pbits -- "rd" and wr = wire pbits -- "wr" and count = wire (pbits + 1) -- "count" in
  let full = count ==:. depth and nonempty = count <>:. 0 in
  let popping = pop &: nonempty in
  let accept = push &: (~:full |: popping) in
  let slots = List.init depth (fun i -> reg spec ~enable:(accept &: (wr ==:. i)) data -- Printf.sprintf "slot%d" i) in
  rd <== reg spec (mux2 popping (rd +:. 1) rd);
  wr <== reg spec (mux2 accept (wr +:. 1) wr);
  count <== reg spec (count +: uresize accept (pbits + 1) -: uresize popping (pbits + 1));
  (mux rd slots, count, accept, full, nonempty)

let onehot_index v = mux2 (bit v 0) (of_int ~width:2 0) (mux2 (bit v 1) (of_int ~width:2 1) (mux2 (bit v 2) (of_int ~width:2 2) (of_int ~width:2 3)))
let rep4 b = repeat b 4
let nib v i = select v (4 * i + 3) (4 * i)

let create ?(cfg = config) ?(mems = behavioural) ~clock ~reset ~smp () =
  let spec = Reg_spec.create ~clock ~clear:reset () in
  let lvl i = bit smp (4 * i + 3) in
  (* ---- the pending host action (decoded last clock), and the register file ---- *)
  let act_valid = wire 1 and act_tgt = wire 4 and act_addr = wire 16 and act_byte = wire 8 in
  let act_is tg = act_valid &: (act_tgt ==:. tg) &: ~:reset in
  let act_reg_at a = act_is t_reg &: (act_addr ==:. a) in
  let regs =
    Array.init reg_space (fun a ->
        let w = rw_bits a in
        if w = 0 then zero 8
        else
          let rs = Reg_spec.override spec ~clear_to:(of_int ~width:8 (reset_value a)) in
          let d = uresize (select act_byte (w - 1) 0) 8 in
          reg rs ~enable:(act_reg_at a) d -- Printf.sprintf "cfgreg_%02x" a)
  in
  let reg32 a = concat_msb [ regs.(a + 3); regs.(a + 2); regs.(a + 1); regs.(a) ] in
  let run = bit regs.(r_ctrl) 0 and hold = bit regs.(r_ctrl) 1 in
  let pulse a = act_reg_at a in
  (* ---- the sequencer ---- *)
  let pin_sel k = select regs.(r_pinin k) 3 0 in
  let pad_nib_in i = nib smp i in
  let sel_pad sel = mux sel (List.init n_pads pad_nib_in) in
  let pin_k k =
    let k = if is "pinin_lane_swap" then (match k with 2 -> 3 | 3 -> 2 | k -> k) else k in
    sel_pad (pin_sel k)
  in
  let pin_in = concat_lsb (List.init 8 (fun k -> bit (pin_k k) (if is "pinin_quarter0" then 0 else 3))) in
  let pin_in4 = concat_lsb (List.init 8 (fun k -> pin_k k)) in
  let imem_data = wire 16 and bank_rdata = wire 8 in
  let hostin_head = wire 8 and hostin_nonempty = wire 1 in
  let port_in = Array.init 4 (fun _ -> wire 8) and port_in_valid = wire 4 in
  let flags = wire 16 in
  let boot_pcs = List.init 4 (fun t -> regs.(r_boot_pc t)) in
  let boot_pcs = if is "boot_pc_swap" then (match boot_pcs with [ a; b; c; d ] -> [ a; c; b; d ] | l -> l) else boot_pcs in
  let restart = pulse r_restart in
  let seq =
    Sequencer2.create ~clock ~clear:(reset |: ~:run) ~imem_data ~pin_in ~pin_in4 ~host_in:hostin_head
      ~host_in_valid:hostin_nonempty ~port_in ~port_in_valid ~port_out_ready:(ones 4) ~flags
      ~ctl_valid:restart ~ctl_thread:(select act_byte 1 0)
      ~ctl_page:(if is "restart_page" then zero 2 else select act_byte 3 2) ~ctl_pc:regs.(r_restart_pc)
      ~boot_page:regs.(r_boot_page) ~boot_pc:(concat_lsb boot_pcs) ~bank_rdata ()
  in
  let gate s = if is "hostin_ungated" then s else s &: run in
  let host_in_ready = gate seq.host_in_ready in
  let port_in_ready = seq.port_in_ready &: repeat run 4 in
  (* the core owns the bank port while it runs; in clear its strobes are combinational of the
     fetched word and must not reach the bank (the planted bug lets them) *)
  let core_owns_bank = if is "bank_ungated" then run |: seq.bank_we else run in
  let core_bank_we = seq.bank_we &: core_owns_bank &: ~:reset in
  (* ---- the host link: input side ---- *)
  let s = lvl pad_hstb and rr = lvl pad_hrd in
  let d = concat_lsb (List.init 4 (fun k -> lvl (pad_hdata + k))) in
  let prev_s = reg (Reg_spec.create ~clock ()) s and prev_r = reg (Reg_spec.create ~clock ()) rr in
  let open Always in
  let nphase = Variable.reg spec ~width:1 and hi_nib = Variable.reg spec ~width:4 in
  let pst = Variable.reg spec ~width:3 in
  let st_idle = 0 and st_ahi = 1 and st_alo = 2 and st_count = 3 and st_wdata = 4 and st_rdata = 5 in
  let is_read = Variable.reg spec ~width:1 and tgt = Variable.reg spec ~width:4 in
  let addr = Variable.reg spec ~width:16 and remaining = Variable.reg spec ~width:9 in
  let rbuf = Variable.reg spec ~width:8 and rphase = Variable.reg spec ~width:1 in
  let fetch_valid = Variable.reg spec ~width:1 and fetch_tgt = Variable.reg spec ~width:4 and fetch_addr = Variable.reg spec ~width:16 in
  let nf_valid = Variable.wire ~default:gnd and nf_addr = Variable.wire ~default:(zero 16) in
  let na_valid = Variable.wire ~default:gnd and na_byte = Variable.wire ~default:(zero 8) in
  let rbuf_zero = Variable.wire ~default:gnd in
  let byte_in = if is "nibble_order" then concat_msb [ d; hi_nib.value ] else concat_msb [ hi_nib.value; d ] in
  let s_edge = s ^: prev_s and r_edge = rr ^: prev_r in
  compile
    [ if_ r_edge
        [ nphase <--. 0; rphase <--. 0; when_ (rr ==:. 0) [ pst <--. st_idle ] ]
        [ when_ s_edge
            [ if_ (rr ==:. 0)
                [ if_ (nphase.value ==:. 0)
                    [ hi_nib <-- d; nphase <--. 1 ]
                    [ nphase <--. 0
                    ; switch pst.value
                        [ of_int ~width:3 st_idle,
                          [ when_ ((select byte_in 7 4 ==:. op_write) |: (select byte_in 7 4 ==:. op_read))
                              [ is_read <-- (select byte_in 7 4 ==:. op_read); tgt <-- select byte_in 3 0
                              ; pst <--. st_ahi ] ]
                        ; of_int ~width:3 st_ahi, [ addr <-- concat_msb [ byte_in; zero 8 ]; pst <--. st_alo ]
                        ; of_int ~width:3 st_alo, [ addr <-- concat_msb [ select addr.value 15 8; byte_in ]; pst <--. st_count ]
                        ; of_int ~width:3 st_count,
                          [ remaining <-- uresize byte_in 9 +:. 1
                          ; if_ is_read.value [ pst <--. st_rdata; nf_valid <-- vdd; nf_addr <-- addr.value ]
                              [ pst <--. st_wdata ] ]
                        ; of_int ~width:3 st_wdata,
                          [ na_valid <-- vdd; na_byte <-- byte_in
                          ; addr <-- addr.value +:. 1; remaining <-- remaining.value -:. 1
                          ; when_ (remaining.value ==:. 1) [ pst <--. st_idle ] ]
                        ; of_int ~width:3 st_rdata, [ pst <--. st_idle ] ] ] ]
                [ if_ (rphase.value ==:. 0) [ rphase <--. 1 ]
                    [ rphase <--. 0
                    ; if_ ((pst.value ==:. st_rdata) &: (remaining.value >:. 1))
                        [ remaining <-- remaining.value -:. 1; addr <-- addr.value +:. 1
                        ; nf_valid <-- vdd; nf_addr <-- addr.value +:. 1 ]
                        [ remaining <--. 0; rbuf_zero <-- vdd
                        ; when_ (pst.value ==:. st_rdata) [ pst <--. st_idle ] ] ] ] ] ] ];
  (* ---- fetches ---- *)
  let next_fetch_tgt = tgt.value in
  let fv = fetch_valid.value and ft = fetch_tgt.value and fa = fetch_addr.value in
  let fetch_is tg = fv &: (ft ==:. tg) in
  (* ---- the array and the ports ---- *)
  let es_bit = wire 1 and es_valid = wire 1 in
  let push_v = seq.port_out_valid and push_d = seq.port_out_data in
  let thread_push = (push_v <>:. 0) &: ~:reset in
  let push_port = onehot_index push_v in
  let push_seg = if is "mbx_port_swap" then mux2 (push_port ==:. 1) (of_int ~width:2 2) push_port else push_port in
  let send_hi = Array.init 4 (fun _ -> wire 1) in
  let send_hi_sel = mux push_port (Array.to_list send_hi) in
  let host_seg = act_is t_peseg in
  let host_wins = if is "host_mbx_priority" then host_seg else gnd in
  let use_thread = thread_push &: ~:host_wins in
  let mbx_wr = use_thread |: host_seg in
  let mbx_seg = mux2 use_thread push_seg (select act_addr 3 2) in
  let send_first_hi = if is "send_order" then ~:send_hi_sel else send_hi_sel in
  let mbx_sel = mux2 use_thread (uresize send_first_hi 2) (select act_addr 1 0) in
  let mbx_byte = mux2 use_thread push_d act_byte in
  let host_mbx_done = host_seg &: ~:use_thread in
  (* the chains' segment is address bits 9:8, so that a multi-byte write stays in its segment *)
  let cfg_seg = if is "pecfg_seg" then select act_addr 10 9 else select act_addr 9 8 in
  let fixed_seg = if is "fixed_port_seg1" then 1 else 0 in
  let arr =
    Upe.Upe_rtl.array_create ~layout:cfg.layout ~clear:reset ~clock
      { mbx_wr; mbx_seg; mbx_sel; mbx_byte;
        acfg_wr = act_is t_pecfg; acfg_seg = cfg_seg; acfg_byte = act_byte;
        ainit_wr = act_is t_peinit; ainit_seg = select act_addr 9 8; ainit_byte = act_byte;
        fixed_d = Array.init 4 (fun j -> if j = fixed_seg then uresize es_bit 16 else zero 16);
        fixed_v = Array.init 4 (fun j -> if j = fixed_seg then es_valid else gnd) }
  in
  (* names for timing reports: the array's per-PE and per-segment state, and its g and step chains *)
  Array.iteri (fun i (pe : Upe.Upe_rtl.pe_out) ->
      let nm f x = ignore (x -- Printf.sprintf "pe%d_%s" i f) in
      nm "s" pe.s; nm "p" pe.p; nm "pv" pe.pv; nm "f" pe.f; nm "l" pe.l; nm "g" pe.g; nm "step" pe.step;
      nm "cfg" pe.cfg; nm "tap" pe.tap) arr.pes;
  Array.iteri (fun j (r : Upe.Upe_rtl.seg_regs) ->
      let nm f x = ignore (x -- Printf.sprintf "seg%d_%s" j f) in
      nm "flo" r.flo; nm "fhi" r.fhi; nm "fv" r.fv0; nm "ctrl" r.ctrl; nm "rep" r.rep; nm "cnt" r.cnt; nm "fw" r.fw) arr.segs;
  let port_reset = mux2 (pulse r_port_reset) (select act_byte 3 0) (zero 4) in
  let holds =
    Array.init 4 (fun p ->
        let st = Variable.reg spec ~width:2 and w = Variable.reg spec ~width:16 in
        ignore (st.value -- Printf.sprintf "hold%d_st" p); ignore (w.value -- Printf.sprintf "hold%d_w" p);
        let src = if is "tap_seg_miswire" then (p + 1) mod 4 else p in
        let pop = bit port_in_ready p in
        let hi = Variable.reg spec ~width:1 in
        ignore (hi.value -- Printf.sprintf "send_hi%d" p);
        send_hi.(p) <== hi.value;
        compile
          [ when_ (thread_push &: (push_port ==:. p)) [ hi <-- ~:(hi.value) ]
          ; if_ (bit port_reset p) [ hi <--. 0; st <--. 0 ]
              [ switch st.value
                  [ of_int ~width:2 0, [ when_ arr.tap_v.(src) [ st <--. 1; w <-- arr.tap_d.(src) ] ]
                  ; of_int ~width:2 1, [ when_ pop [ st <--. 2 ] ]
                  ; of_int ~width:2 2, [ when_ pop [ st <--. 0 ] ]
                  ; of_int ~width:2 3, [] ] ] ];
        (st.value, w.value))
  in
  let holds = if is "recv_port_swap" then Array.init 4 (fun p -> holds.(if p = 2 then 3 else p)) else holds in
  Array.iteri
    (fun p (st, w) -> port_in.(p) <== mux2 (st ==:. 2) (select w 15 8) (select w 7 0))
    holds;
  port_in_valid <== concat_lsb (Array.to_list (Array.map (fun (st, _) -> st <>:. 0) holds));
  (* ---- host FIFOs ---- *)
  let hin_push = act_is t_hostin in
  let hin_head, hin_count, hin_accept, hin_full, hin_ne =
    if is "hostin_overwrite" then begin
      let h, c, _, f, ne = fifo ~name:"hostin" spec ~depth:Chip_spec.hostin_depth ~push:hin_push ~pop:host_in_ready ~data:act_byte in
      (h, c, hin_push, f, ne)
    end
    else fifo ~name:"hostin" spec ~depth:Chip_spec.hostin_depth ~push:hin_push ~pop:host_in_ready ~data:act_byte
  in
  hostin_head <== hin_head; hostin_nonempty <== hin_ne;
  let hout_lat = Variable.reg spec ~width:1 in
  let hout_pop = wire 1 in
  let hout_push = seq.host_out_valid in
  let hout_head, hout_count, hout_accept, _, hout_ne =
    fifo ~name:"hostout" spec ~depth:Chip_spec.hostout_depth ~push:hout_push ~pop:hout_pop ~data:(concat_msb [ seq.host_tag; seq.host_out ])
  in
  (* ---- assists ---- *)
  let aclear = reset |: hold in
  let str_lo = Variable.reg spec ~width:8 and str_hi = Variable.reg spec ~width:8 in
  let str_out, str_oe, str_full =
    Pstream.Streamer.create ~clock ~clear:aclear
      ~period:(concat_msb [ select regs.(r_str_per + 1) 3 0; regs.(r_str_per) ])
      ~width:(select regs.(r_str_per + 1) 6 4) ~od_mask:(select regs.(r_str_pins) 3 0)
      ~idle_out:(select regs.(r_str_pins) 7 4) ~idle_oe:(select regs.(r_str_idle_oe) 3 0)
      ~host_data:(concat_msb [ str_hi.value; str_lo.value ]) ~host_count:(select act_byte 3 0)
      ~host_push:(act_is t_stream &: (select act_addr 1 0 ==:. 2)) ()
  in
  let smp_lat = Variable.reg spec ~width:1 in
  let smp_pop = wire 1 in
  let smp_pins =
    let pin j = bit (sel_pad (select regs.(r_smp_pin j) 3 0)) 3 in
    let pins = List.init 4 pin in
    let pins = if is "smp_pin_swap" then (match pins with a :: b :: rest -> b :: a :: rest | l -> l) else pins in
    mux2 (bit regs.(r_smp_src) 0) (concat_lsb [ es_bit; es_valid; gnd; gnd ]) (concat_lsb pins)
  in
  let smp_data, smp_count, smp_valid, smp_overflows =
    Psample.Sampler.create ~clock ~clear:aclear ~pins:smp_pins ~clocked:(bit regs.(r_smp_per + 1) 7)
      ~period:(concat_msb [ select regs.(r_smp_per + 1) 3 0; regs.(r_smp_per) ])
      ~width:(select regs.(r_smp_per + 1) 6 4) ~trig_pin:(select regs.(r_smp_off + 1) 5 4)
      ~trig_val:(bit regs.(r_smp_off + 1) 6) ~offset:(concat_msb [ select regs.(r_smp_off + 1) 3 0; regs.(r_smp_off) ])
      ~frame_len:regs.(r_smp_frame) ~pop:smp_pop ()
  in
  let es_cfg : Eth10.Edge_sampler.cfg_signals =
    { s_mode = select regs.(r_es_mode) 1 0; s_invert = bit regs.(r_es_mode) 2;
      s_holdoff = concat_msb [ select regs.(r_es_holdoff + 1) 1 0; regs.(r_es_holdoff) ];
      s_timeout = concat_msb [ select regs.(r_es_timeout + 1) 1 0; regs.(r_es_timeout) ];
      s_offset = regs.(r_es_offset); s_period = regs.(r_es_period) }
  in
  let es_pad = sel_pad (select regs.(r_es_pads) 3 0) in
  let es_samples = if is "es_quarter_rev" then reverse es_pad else es_pad in
  let es_active = ~:(bit regs.(r_es_mode) 3) |: bit (sel_pad (select regs.(r_es_pads) 7 4)) 3 in
  let es_b, es_v, es_end, _es_over, es_in_burst =
    Eth10.Edge_sampler.create ~clock ~clear:aclear ~n:4 ~cfg:es_cfg ~samples:es_samples ~active:es_active
  in
  let es_b = es_b -- "es_bit_raw" and es_v = es_v -- "es_valid" and es_end = es_end -- "es_burst_end" in
  let es_in_burst = es_in_burst -- "es_in_burst" in
  (* the bit output is defined only while valid; hold the last one so that it is a level *)
  let es_last = wire 1 in
  let es_lvl = mux2 es_v es_b es_last -- "es_level" in
  es_last <== (reg (Reg_spec.override spec ~clear:aclear) es_lvl -- "es_last_reg");
  es_bit <== es_lvl; es_valid <== es_v;
  let match_y, match_hit =
    Eth10.Matcher_en.create ~clock ~clear:aclear ~enable:es_v ~x:es_b ~cfg_in:(bit act_byte 0)
      ~cfg_shift:(act_is t_match)
  in
  let crc_cfg : Eth10.Crc_unit.cfg_signals =
    { s_poly = reg32 r_crc_poly; s_init = reg32 r_crc_init; s_mask = reg32 r_crc_mask;
      s_refl = bit regs.(r_crc_ctrl) 0; s_xorout = reg32 r_crc_xorout; s_residue = reg32 r_crc_residue }
  in
  let crc_start = pulse r_crc_start |: (bit regs.(r_crc_ctrl) 1 &: match_hit) in
  let crc_raw, _crc_value, crc_check =
    Eth10.Crc_unit.create ~clock ~clear:aclear ~cfg:crc_cfg ~start:crc_start ~bit:es_b ~valid:es_v
  in
  let inc = reg32 r_nco_inc in
  let inc = if is "nco_inc_bytes" then concat_msb [ select inc 31 16; select inc 7 0; select inc 15 8 ] else inc in
  let nco = Mphase.Nco.create ~clock ~clear:aclear ~inc in
  (* ---- flags ---- *)
  let fsrc =
    Array.to_list arr.tap_f @ Array.to_list arr.tap_v
    @ [ es_v; es_lvl; es_in_burst; es_end; crc_check; match_hit; str_full; smp_valid; bit nco 0 ]
  in
  let fsrc = fsrc @ List.init (32 - List.length fsrc) (fun _ -> gnd) in
  let flag f = mux (select regs.(r_flagsel (if is "flag_off_by_one" then (f + 1) mod 16 else f)) 4 0) fsrc in
  let fl = concat_lsb (List.init 16 flag) in
  (* thread t's flags are bits 4t..4t+3; the planted bug hands it thread t+1's *)
  flags <== (if is "flag_thread_rot" then concat_msb [ select fl 3 0; select fl 15 4 ] else fl);
  (* ---- fetch execution ---- *)
  let sticky_err = Variable.reg spec ~width:1 and sticky_hin = Variable.reg spec ~width:1 in
  let sticky_hout = Variable.reg spec ~width:1 and sticky_drop = Variable.reg spec ~width:1 in
  let status =
    concat_lsb [ sticky_err.value; sticky_hin.value; sticky_hout.value; hin_full; hout_ne; smp_valid; str_full;
                 sticky_drop.value ] in
  let read_reg a =
    let cases =
      List.filter_map
        (fun x ->
          let v =
            if rw_bits x > 0 then Some regs.(x)
            else if x = r_status then Some status
            else if x = r_hostin_count then Some (uresize hin_count 8)
            else if x = r_hostout_count then Some (uresize hout_count 8)
            else if x >= r_crc_raw && x < r_crc_raw + 4 then Some (select crc_raw (8 * (x - r_crc_raw) + 7) (8 * (x - r_crc_raw)))
            else if x = r_match then Some (concat_msb [ match_hit; zero 2; match_y ])
            else if x = r_smp_overflows then Some smp_overflows
            else None
          in
          Option.map (fun v -> (x, v)) v)
        (List.init reg_space Fun.id)
    in
    let in_space = select a 15 7 ==:. 0 in
    mux2 in_space (mux (select a 6 0) (List.init reg_space (fun x -> match List.assoc_opt x cases with Some v -> v | None -> zero 8))) (zero 8)
  in
  let prog_q = wire 16 and bank_q = wire 8 in
  let fbyte =
    mux ft
      [ read_reg fa;
        mux2 run (zero 8) (mux2 (bit fa 0) (select prog_q 15 8) (select prog_q 7 0));
        mux2 run (zero 8) bank_q;
        zero 8;
        mux2 (bit fa 0)
          (mux2 (if is "hostout_no_latch" then hout_ne else hout_lat.value) (select hout_head 7 0) (zero 8))
          (mux2 hout_ne (concat_msb [ vdd; zero 4; select hout_head 10 8 ]) (zero 8));
        zero 8; zero 8; zero 8; zero 8;
        mux (select fa 1 0)
          [ mux2 smp_valid (concat_msb [ vdd; zero 3; smp_count ]) (zero 8);
            mux2 (smp_lat.value &: smp_valid) (select smp_data 7 0) (zero 8);
            mux2 (smp_lat.value &: smp_valid) (select smp_data 15 8) (zero 8);
            zero 8 ];
        zero 8; zero 8; zero 8; zero 8; zero 8; zero 8 ]
  in
  hout_pop <== (fetch_is t_hostout &: bit fa 0 &: (if is "hostout_no_latch" then vdd else hout_lat.value));
  smp_pop <== (fetch_is t_sample &: (select fa 1 0 ==:. 2) &: smp_lat.value &: ~:hold);
  let mem_refused = run &: (fetch_is t_prog |: fetch_is t_bank |: act_is t_prog |: act_is t_bank) in
  (* ---- memories ---- *)
  let pwords = cfg.prog_words in
  let host_prog_read = nf_valid.value &: (next_fetch_tgt ==:. t_prog) &: ~:run in
  let host_prog_write = act_is t_prog &: ~:run &: bit act_addr 0 in
  let prog_lo = Variable.reg spec ~width:8 in
  let prog_word = if is "prog_byte_order" then concat_msb [ prog_lo.value; act_byte ] else concat_msb [ act_byte; prog_lo.value ] in
  let prog_addr =
    mux2 host_prog_write (srl act_addr 1) (mux2 host_prog_read (srl nf_addr.value 1) (uresize seq.imem_addr 16)) in
  prog_q <== mems.prog_mem ~clock ~size:pwords ~width:16 ~addr:prog_addr ~we:host_prog_write ~wdata:prog_word;
  imem_data <== prog_q;
  let host_bank_read = nf_valid.value &: (next_fetch_tgt ==:. t_bank) &: ~:run in
  let host_bank_write = act_is t_bank &: ~:run in
  let bank_addr = mux2 core_owns_bank (uresize seq.bank_addr 16) (mux2 host_bank_write act_addr (mux2 host_bank_read nf_addr.value (zero 16))) in
  bank_q <== mems.bank_mem ~clock ~size:Chip_spec.bank_bytes ~width:8 ~addr:bank_addr
      ~we:(mux2 core_owns_bank core_bank_we host_bank_write) ~wdata:(mux2 core_owns_bank seq.bank_wdata act_byte);
  bank_rdata <== bank_q;
  (* ---- the pending action and fetch registers, and the glue registers ---- *)
  let waiting = act_is t_peseg &: ~:host_mbx_done in
  let a_valid = Variable.reg spec ~width:1 and a_tgt = Variable.reg spec ~width:4 in
  let a_addr = Variable.reg spec ~width:16 and a_byte = Variable.reg spec ~width:8 in
  act_valid <== (a_valid.value -- "act_valid"); act_tgt <== (a_tgt.value -- "act_tgt");
  act_addr <== (a_addr.value -- "act_addr"); act_byte <== (a_byte.value -- "act_byte");
  List.iter (fun (v, n) -> ignore (v -- n))
    [ fetch_valid.value, "fetch_valid"; fetch_tgt.value, "fetch_tgt"; fetch_addr.value, "fetch_addr";
      rbuf.value, "link_rbuf"; pst.value, "link_state"; addr.value, "link_addr"; remaining.value, "link_remaining";
      tgt.value, "link_tgt"; hi_nib.value, "link_hi_nib"; prog_lo.value, "prog_lo"; hout_lat.value, "hout_lat";
      smp_lat.value, "smp_lat"; sticky_err.value, "sticky_err"; seq.imem_addr, "seq_imem_addr";
      seq.port_out_valid, "seq_port_out_valid"; seq.port_out_data, "seq_port_out_data"; seq.bank_addr, "seq_bank_addr";
      seq.bank_we, "seq_bank_we"; seq.pin_sub, "seq_pin_sub"; seq.pin_oe, "seq_pin_oe"; flags, "flags";
      prog_q, "prog_q"; bank_q, "bank_q"; nco, "nco"; crc_raw, "crc_raw" ];
  let clear_sticky = pulse r_status &: (if is "status_not_cleared" then gnd else vdd) in
  compile
    [ if_ na_valid.value
        [ a_valid <--. 1; a_tgt <-- tgt.value; a_addr <-- addr.value; a_byte <-- na_byte.value
        ; when_ waiting [ sticky_drop <--. 1 ] ]
        [ a_valid <-- waiting ]
    ; fetch_valid <-- nf_valid.value; fetch_tgt <-- next_fetch_tgt; fetch_addr <-- nf_addr.value
    ; if_ rbuf_zero.value [ rbuf <--. 0 ] [ when_ fv [ rbuf <-- fbyte ] ]
    ; when_ (fetch_is t_hostout)
        [ if_ (bit fa 0) [ hout_lat <--. 0 ] [ hout_lat <-- hout_ne ] ]
    ; when_ (fetch_is t_sample)
        [ when_ (select fa 1 0 ==:. 0) [ smp_lat <-- smp_valid ]
        ; when_ (select fa 1 0 ==:. 2) [ smp_lat <--. 0 ] ]
    ; when_ (act_is t_prog &: ~:run &: ~:(bit act_addr 0)) [ prog_lo <-- act_byte ]
    ; when_ (act_is t_stream &: (select act_addr 1 0 ==:. 0)) [ str_lo <-- act_byte ]
    ; when_ (act_is t_stream &: (select act_addr 1 0 ==:. 1)) [ str_hi <-- act_byte ]
    ; if_ clear_sticky
        [ sticky_err <--. 0; sticky_hin <--. 0; sticky_hout <--. 0; sticky_drop <--. 0 ]
        [ when_ mem_refused [ sticky_err <--. 1 ]
        ; when_ (hin_push &: ~:hin_accept) [ sticky_hin <--. 1 ]
        ; when_ (hout_push &: ~:hout_accept) [ sticky_hout <--. 1 ] ] ];
  (* ---- pads ---- *)
  let taps_f = arr.tap_f and taps_d = arr.tap_d in
  let source sel =
    let seq_pin k = (nib seq.pin_sub k, bit seq.pin_oe k) in
    let seq_pin k = if is "pin_lane_swap" then seq_pin (match k with 0 -> 1 | 1 -> 0 | k -> k) else seq_pin k in
    let seq_pin k =
      let n, oe = seq_pin k in
      if is "quarter_swap" then (concat_lsb [ bit n 0; bit n 2; bit n 1; bit n 3 ], oe) else (n, oe)
    in
    let srcs =
      List.init 8 seq_pin
      @ List.init 4 (fun k -> (rep4 (bit str_out k), bit str_oe k))
      @ [ (select nco 3 0, vdd); (select nco 7 4, vdd); (select nco 11 8, vdd); (zero 4, vdd) ]
      @ List.init 4 (fun j -> (rep4 taps_f.(j), vdd))
      @ List.init 4 (fun j -> (rep4 (lsb taps_d.(j)), vdd))
      @ [ (rep4 es_lvl, vdd) ]
    in
    let srcs = srcs @ List.init (32 - List.length srcs) (fun _ -> (zero 4, vdd)) in
    (mux sel (List.map fst srcs), mux sel (List.map snd srcs))
  in
  let rnib =
    if is "read_nibble_order" then mux2 (rphase.value ==:. 0) (select rbuf.value 3 0) (select rbuf.value 7 4)
    else mux2 (rphase.value ==:. 0) (select rbuf.value 7 4) (select rbuf.value 3 0)
  in
  let pad_out = Array.make n_pads (zero 4) and oes = Array.make 8 gnd in
  List.iter
    (fun p ->
      let sel = regs.(r_padsel p) in
      let n, oe = source (select sel 4 0) in
      let n = mux2 (bit sel 5) (~:n) n in
      if p < 8 then pad_out.(p) <- (mux2 oe n (rep4 (bit sel 6)) -- Printf.sprintf "pad%d_nib" p)
      else (pad_out.(p) <- n; oes.(p - 8) <- oe))
    general_out_pads;
  for k = 0 to 3 do pad_out.(pad_hdata + k) <- rep4 (bit rnib k); oes.(k) <- prev_r done;
  let oes = if is "uio_oe_swap" then (let o = Array.copy oes in o.(6) <- oes.(7); o.(7) <- oes.(6); o) else oes in
  let dbg =
    List.map (fun (n, s) -> ("seq_" ^ n, s)) seq.dbg
    @ List.concat
        (Array.to_list
           (Array.mapi
              (fun i (pe : Upe.Upe_rtl.pe_out) ->
                [ Printf.sprintf "pe_s%d" i, pe.s; Printf.sprintf "pe_p%d" i, pe.p; Printf.sprintf "pe_pv%d" i, pe.pv;
                  Printf.sprintf "pe_f%d" i, pe.f; Printf.sprintf "pe_l%d" i, pe.l; Printf.sprintf "pe_cfg%d" i, pe.cfg ])
              arr.pes))
    @ List.concat
        (Array.to_list
           (Array.mapi
              (fun j (r : Upe.Upe_rtl.seg_regs) ->
                [ Printf.sprintf "seg_flo%d" j, r.flo; Printf.sprintf "seg_fhi%d" j, r.fhi; Printf.sprintf "seg_fv%d" j, r.fv0;
                  Printf.sprintf "seg_ctrl%d" j, r.ctrl; Printf.sprintf "seg_rep%d" j, r.rep;
                  Printf.sprintf "seg_cnt%d" j, r.cnt; Printf.sprintf "seg_fw%d" j, r.fw ])
              arr.segs))
    @ [ "send_hi", concat_lsb (Array.to_list send_hi);
        "holds", concat_lsb (Array.to_list (Array.map (fun (st, w) -> concat_msb [ w; st ]) holds));
        "hin_count", hin_count; "hin_head", hin_head; "hout_head", hout_head;
        "smp_head", concat_msb [ smp_valid; smp_count; smp_data ]; "str_out", concat_msb [ str_full; str_oe; str_out ]; "hout_count", hout_count; "crc", crc_raw; "nco", nco; "match_y", match_y;
        "rbuf", rbuf.value; "es", concat_msb [ es_b &: es_v; es_v; es_end; es_in_burst ]; "es_last", es_last ]
  in
  { pad_nib = concat_lsb (Array.to_list pad_out); uio_oe = concat_lsb (Array.to_list oes); dbg }

let circuit ?cfg ?mems ?(debug = true) () =
  let clock = input "clock" 1 and reset = input "reset" 1 and smp = input "smp" (4 * n_pads) in
  let o = create ?cfg ?mems ~clock ~reset ~smp () in
  Circuit.create_exn ~name:"chip_core"
    ([ output "pad_nib" o.pad_nib; output "uio_oe" o.uio_oe ]
     @ if debug then List.map (fun (n, s) -> output n s) o.dbg else [])
