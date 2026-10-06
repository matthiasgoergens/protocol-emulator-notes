(* The chip's host-visible encoding: host-link targets, the register map of target REG, the pad
   numbering and the source and flag codes. This is an encoding shared by the specification
   (chip_spec.ml), the RTL (chip_rtl.ml) and the host-side tools, as spec.ml is for the PE array;
   the behaviour behind it is written separately in each.

   Every register below is one byte at a byte address of target REG. Multi-byte fields are little
   endian. "rw" registers read back what was written; "w" registers are pulses and read 0; "r"
   registers are status. Reset value 0 unless a [reset] is given. *)

(* host-link targets *)
let t_reg = 0 and t_prog = 1 and t_bank = 2 and t_hostin = 3 and t_hostout = 4
let t_pecfg = 5 and t_peinit = 6 and t_peseg = 7 and t_stream = 8 and t_sample = 9 and t_match = 10

(* host-link command ops (the high nibble of a command byte) *)
let op_write = 1 and op_read = 2

(* pads: inputs 0-7 are ui_in, 8-15 uio_in; outputs 0-7 uo_out, 8-15 uio_out *)
let n_pads = 16
let pad_hdata = 8 (* 8..11: host data *) and pad_hstb = 12 and pad_hrd = 13
let general_out_pads = [ 0; 1; 2; 3; 4; 5; 6; 7; 14; 15 ]
let is_uio_general p = p = 14 || p = 15

(* output pad sources (5 bits) *)
let src_seq k = k            (* 0..7: sequencer logical pin k *)
let src_stream k = 8 + k     (* 8..11: streamer pin k *)
let src_nco_quarter = 12 and src_nco_half = 13 and src_nco_grid = 14
let src_tap_flag j = 16 + j  (* 16..19 *)
let src_tap_bit0 j = 20 + j  (* 20..23 *)
let src_es_bit = 24          (* 25..31: constant 0 *)

(* flag sources (5 bits) for the 16 flag inputs, thread t's flags are 4t..4t+3 *)
let fl_tap_flag j = j        (* 0..3 *)
let fl_tap_valid j = 4 + j   (* 4..7 *)
let fl_es_valid = 8 and fl_es_bit = 9 and fl_es_in_burst = 10 and fl_es_burst_end = 11
let fl_crc_check = 12 and fl_match_hit = 13 and fl_stream_full = 14 and fl_sample_valid = 15
let fl_nco = 16              (* 17..31: constant 0 *)

(* ---- the register map of target REG ---- *)
let r_ctrl = 0x00            (* rw: bit 0 run, bit 1 hold the assists (streamer, sampler, edge
                                sampler, CRC, matcher, NCO) in clear. reset: 2 *)
let r_status = 0x01          (* r: bit 0 memory access refused (sticky), 1 HOSTIN overflow (sticky),
                                2 HOSTOUT overflow (sticky), 3 HOSTIN full, 4 HOSTOUT non-empty,
                                5 sampler FIFO non-empty, 6 streamer FIFO full;
                                w: any write clears the sticky bits *)
let r_hostin_count = 0x02    (* r *)
let r_hostout_count = 0x03   (* r *)
let r_boot_pc t = 0x04 + t   (* rw, t = 0..3 *)
let r_boot_page = 0x08       (* rw: 2 bits per thread, thread 0 in bits 1:0 *)
let r_restart = 0x09         (* w: thread [1:0], page [3:2]; pc from r_restart_pc: the core's
                                host-control write (sequencer-v2 D1) *)
let r_restart_pc = 0x0A      (* rw *)
let r_port_reset = 0x0B      (* w: bit j empties port j's RECV holding register and resets its
                                SEND byte order to "low byte next" *)
let r_crc_start = 0x0C       (* w: loads the CRC register with its init value *)
let r_padsel p = 0x10 + p    (* rw, pads 0..15 (only the general output pads are implemented):
                                bits 4:0 source, bit 5 invert, bit 6 level when not driven *)
let r_pinin k = 0x20 + k     (* rw, logical pin k = 0..7: bits 3:0 input pad. reset: k *)
let r_smp_pin j = 0x28 + j   (* rw, sampler pin j = 0..3: bits 3:0 input pad *)
let r_smp_src = 0x2C         (* rw: bit 0: the sampler's pins are the recovered-bit stream
                                {0, 0, valid, bit} instead of the pads *)
let r_flagsel f = 0x30 + f   (* rw, flag f = 0..15: bits 4:0 flag source. reset: 31 (zero) *)
let r_str_per = 0x40         (* rw, 2 bytes: bits 11:0 period; 0x41 bits 6:4 width (1, 2, 4) *)
let r_str_pins = 0x42        (* rw: bits 3:0 open-drain mask, 7:4 idle level *)
let r_str_idle_oe = 0x43     (* rw: bits 3:0 *)
let r_smp_per = 0x44         (* rw, 2 bytes: bits 11:0 period; 0x45 bits 6:4 width, bit 7 clocked *)
let r_smp_off = 0x46         (* rw, 2 bytes: bits 11:0 offset; 0x47 bits 5:4 trigger pin, bit 6
                                trigger value *)
let r_smp_frame = 0x48       (* rw: frame length *)
let r_es_mode = 0x4C         (* rw: bits 1:0 mode (0 Manchester, 1 biphase mark, 2 NRZ), bit 2
                                invert, bit 3 use the active pad (else always active) *)
let r_es_pads = 0x4D         (* rw: bits 3:0 data pad, 7:4 active pad *)
let r_es_holdoff = 0x4E      (* rw, 2 bytes, 10 bits *)
let r_es_timeout = 0x50      (* rw, 2 bytes, 10 bits *)
let r_es_offset = 0x52       (* rw *)
let r_es_period = 0x53       (* rw *)
let r_crc_ctrl = 0x54        (* rw: bit 0 reflected, bit 1 start on a matcher hit *)
let r_crc_poly = 0x58        (* rw, 4 bytes each *)
let r_crc_init = 0x5C
let r_crc_mask = 0x60
let r_crc_xorout = 0x64
let r_crc_residue = 0x68
let r_nco_inc = 0x6C         (* rw, 4 bytes *)
let r_crc_raw = 0x70         (* r, 4 bytes: the CRC register *)
let r_match = 0x74           (* r: bits 4:0 the matcher's sum, bit 7 hit *)
let r_smp_overflows = 0x75   (* r *)

let reg_space = 0x80

(* reset values of the rw registers that are not 0 *)
let reset_value a =
  if a = r_ctrl then 2                         (* stopped, the assists held until configured *)
  else if a = r_str_per || a = r_smp_per then 1          (* period 1 *)
  else if a = r_str_per + 1 || a = r_smp_per + 1 then 0x10   (* width 1: the models need 1, 2 or 4 *)
  else if a >= r_pinin 0 && a <= r_pinin 7 then a - r_pinin 0
  else if a >= r_flagsel 0 && a <= r_flagsel 15 then 31
  else 0

(* Which addresses hold rw storage, and how many bits of the byte are kept. Writes to other
   addresses are ignored; reads of them return 0 (or status for the "r" registers). *)
let rw_bits a =
  if a = r_ctrl then 2
  else if a >= r_boot_pc 0 && a <= r_boot_pc 3 then 8
  else if a = r_boot_page then 8
  else if a = r_restart_pc then 8
  else if a >= 0x10 && a <= 0x1F then (if List.mem (a - 0x10) general_out_pads then 7 else 0)
  else if a >= r_pinin 0 && a <= r_pinin 7 then 4
  else if a >= r_smp_pin 0 && a <= r_smp_pin 3 then 4
  else if a = r_smp_src then 1
  else if a >= r_flagsel 0 && a <= r_flagsel 15 then 5
  else if a = r_str_per then 8 else if a = r_str_per + 1 then 7
  else if a = r_str_pins then 8 else if a = r_str_idle_oe then 4
  else if a = r_smp_per then 8 else if a = r_smp_per + 1 then 8
  else if a = r_smp_off then 8 else if a = r_smp_off + 1 then 7
  else if a = r_smp_frame then 8
  else if a = r_es_mode then 4 else if a = r_es_pads then 8
  else if a = r_es_holdoff || a = r_es_timeout then 8
  else if a = r_es_holdoff + 1 || a = r_es_timeout + 1 then 2
  else if a = r_es_offset || a = r_es_period then 8
  else if a = r_crc_ctrl then 2
  else if a >= r_crc_poly && a < r_crc_residue + 4 then 8
  else if a >= r_nco_inc && a < r_nco_inc + 4 then 8
  else 0

let rw_addresses = List.filter (fun a -> rw_bits a > 0) (List.init reg_space Fun.id)
