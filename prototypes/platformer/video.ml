(* The platformer's chip, built only from generic blocks:
     - the deadline sequencer (sequencer.ml, unchanged) running Vprog's firmware from a ROM;
     - a line buffer, two banks of 256 x 19 bits (a gain-cell bank on silicon; Hardcaml memory
       here), written by the host link and read by the feeder;
     - the feeder, a memory-to-array streamer: on the line event it plays the entries of the
       current bank onto the array link and generates the step (pixel) slots, [period] clocks
       apart, [nsteps] of them, starting [start] clocks after the event;
     - a row of PE-Xs (pex.ml): kcells looped tile cells, then nspr sprite cells, each only a
       configuration of the same PE;
     - the output port: a lookup table (64 x 14, written by class-1 records that fall off the end
       of the array), a hold of [period] clocks per step, and the NCO with a phase input.
   Pins, as ../retro-console's dumps: bits 3:0 luma DAC code, 4 chroma level, 5 chroma enable 1,
   6 chroma enable 2. *)
open Hardcaml
open Signal

let period = 10
let nsteps = Scene.npix
let kcells = Scene.kcells
let nspr = Scene.nspr
let npe = kcells + nspr
let bank_bits = 8                 (* 256 entries per bank *)
let entry_bits = 19
let start = 641                   (* feeder: first step this many clocks after line_go falls *)

(* NCO: 12 clocks per subcarrier cycle; acc starts half a clock in so that no sample sits on a
   phase boundary. Phase in 1/256 cycle; the V-switch reflects the phase about [reflect]. *)
let nco_inc = 357913941           (* floor (2^32 / 12) *)
let nco_acc0 = 178956971          (* 2^32 / 24 *)
let reflect = 235                 (* 11 steps of 256/12: maps hue step p to 11 - p *)

let feeder ~spec ~line_go_n ~rdata =
  let open Always in
  let prev_go = reg spec line_go_n in
  let go = prev_go &: ~:line_go_n in
  let rbank = Variable.reg spec ~width:1 and rptr = Variable.reg spec ~width:bank_bits in
  let active = Variable.reg spec ~width:1 and pix_en = Variable.reg spec ~width:1 in
  let cd = Variable.reg spec ~width:12 and cnt = Variable.reg spec ~width:9 in
  let pix_val = Variable.reg spec ~width:16 in
  let otag = Variable.reg spec ~width:3 and odata = Variable.reg spec ~width:16 in
  let etag = select rdata 18 16 and edata = select rdata 15 0 in
  let slot = (cd.value ==:. 0) &: pix_en.value &: (cnt.value <:. nsteps) in
  let last = cnt.value ==:. (nsteps - 1) in
  compile
    [ otag <--. 0; odata <--. 0
    ; if_ go
        [ rbank <-- ~:(rbank.value); rptr <--. 0; active <-- vdd; pix_en <-- gnd
        ; cd <--. start; cnt <--. 0 ]
        [ if_ slot
            [ otag <--. Pex_model.tag_step
            ; odata <-- (pix_val.value |: concat_msb [ last; zero 15 ])
            ; cnt <-- cnt.value +:. 1; cd <--. (period - 1) ]
            [ when_ (cd.value <>:. 0) [ cd <-- cd.value -:. 1 ]
            ; when_ active.value
                [ switch etag
                    [ of_int ~width:3 Scene.t_wait,
                      [ when_ (uresize cnt.value 16 >: edata) [ rptr <-- rptr.value +:. 1 ] ]
                    ; of_int ~width:3 Scene.t_pixels,
                      [ pix_val <-- edata; pix_en <-- vdd; rptr <-- rptr.value +:. 1 ]
                    ; of_int ~width:3 Scene.t_end, [ active <-- gnd ]
                    ; of_int ~width:3 5, [ active <-- gnd ] ]
                ; when_ (bit etag 1) [ otag <-- etag; odata <-- edata; rptr <-- rptr.value +:. 1 ] ] ] ] ];
  go, rbank.value, rptr.value, otag.value, odata.value

let outport ~clock ~spec ~tag ~data ~seq_pins =
  let open Always in
  let in_rec = Variable.reg spec ~width:1 and waddr = Variable.reg spec ~width:6 in
  let idx = Variable.reg spec ~width:6 and hold = Variable.reg spec ~width:4 in
  let kind = select tag 1 0 in
  let rec1 = bit kind 1 &: bit tag 2 in
  let is_last = kind ==:. 3 in
  let lut_we = rec1 &: in_rec.value in
  compile
    [ when_ rec1
        [ if_ in_rec.value [ waddr <-- waddr.value +:. 1; when_ is_last [ in_rec <-- gnd ] ]
            [ waddr <-- select data 5 0; in_rec <-- ~:is_last ] ]
    ; if_ (kind ==:. Pex_model.tag_step) [ idx <-- select data 5 0; hold <--. period ]
        [ when_ (hold.value <>:. 0) [ hold <-- hold.value -:. 1 ] ] ];
  let burst = bit seq_pins 7 and vs = bit seq_pins 6 in
  let raddr = mux2 burst (ones 6) idx.value in
  let entry =
    (multiport_memory 64
       ~write_ports:[| { write_clock = clock; write_address = waddr.value; write_enable = lut_we;
                         write_data = select data 13 0 } |]
       ~read_addresses:[| raddr |]).(0) in
  let showing = hold.value <>:. 0 in
  let use = showing |: burst in
  (* blanking and sync levels always come from the sequencer; the burst only adds chroma *)
  let luma = mux2 showing (select entry 3 0) (select seq_pins 3 0) in
  let phase = select entry 11 4 in
  let phase = mux2 vs (of_int ~width:8 reflect -: phase) phase in
  let acc = reg_fb spec ~width:32 ~f:(fun a -> a +:. nco_inc) in
  let level = ~:(msb (acc +:. nco_acc0 +: concat_msb [ phase; zero 24 ])) in
  let oe1 = use &: bit entry 12 and oe2 = use &: bit entry 13 in
  reg spec (concat_msb [ oe2; oe1; level; luma ]), lut_we, waddr.value, raddr

let rom ~spec ~addr (mem : int array array) =
  let words = List.concat_map (fun t -> Array.to_list (Array.map (of_int ~width:16) t)) (Array.to_list mem) in
  reg spec (mux addr words)

let create ?(fault = 0) ?(lean = false) ~clock ~clear ~cfg_in ~cfg_strobe ~hw_en ~hw_data () =
  let spec = Reg_spec.create ~clock ~clear () in
  (* sequencer with its programme in a ROM (one-cycle read, as the core expects) *)
  let imem_data = wire 16 in
  let imem_addr, pin_out, _pin_oe, _, _, _, _, _ =
    Sequencer.create ~clock ~clear ~imem_data ~pin_in:(zero 8) ~pin_in4:(zero 32) ~host_in:(zero 8)
      ~host_in_valid:gnd in
  imem_data <== rom ~spec ~addr:imem_addr (Vprog.programme ());
  let line_go_n = bit pin_out 4 in
  (* line buffer: the host writes the bank the feeder is not reading *)
  let rdata = wire entry_bits in
  let go, rbank, rptr, ftag, fdata = feeder ~spec ~line_go_n ~rdata in
  let wptr = reg_fb spec ~width:bank_bits ~f:(fun p -> mux2 go (zero bank_bits) (mux2 hw_en (p +:. 1) p)) in
  let wbank = ~:rbank in
  rdata <== (multiport_memory (2 lsl bank_bits)
               ~write_ports:[| { write_clock = clock; write_address = concat_msb [ wbank; wptr ];
                                 write_enable = hw_en; write_data = hw_data } |]
               ~read_addresses:[| concat_msb [ rbank; rptr ] |]).(0);
  (* the PE row *)
  let tag = ref ftag and data = ref fdata and cfg = ref cfg_in in
  for _ = 1 to npe do
    let o = Pex.create ~fault ~lean ~clock ~clear ~cfg_in:!cfg ~cfg_strobe ~tag:!tag ~data:!data () in
    tag := o.tag; data := o.data; cfg := o.cfg_out
  done;
  let pins, lut_we, lut_waddr, lut_raddr = outport ~clock ~spec ~tag:!tag ~data:!data ~seq_pins:pin_out in
  pins, pin_out, !tag, !data, lut_we, lut_waddr, lut_raddr

let circuit ?fault ?lean () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let hw_en = input "hw_en" 1 and hw_data = input "hw_data" entry_bits in
  let pins, seq, tag, data, we, wa, ra = create ?fault ?lean ~clock ~clear ~cfg_in ~cfg_strobe ~hw_en ~hw_data () in
  Circuit.create_exn ~name:"platformer_video"
    [ output "pins" pins; output "seq_pins" seq; output "arr_tag" tag; output "arr_data" data
    ; output "lut_we" we; output "lut_waddr" wa; output "lut_raddr" ra ]
