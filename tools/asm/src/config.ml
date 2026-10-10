(* The chip's configuration as named fields: register groups of target REG, the PE operation
   word, the segment control register. Each group has an encoder (fields -> bytes) used by the
   assembler and a decoder used by the disassembler; the disassembler prints a group by name only
   when encoding what it decoded gives the same bytes back, and raw bytes otherwise.

   The encodings follow ../../prototypes/chip-top/src/regs.ml (register map) and
   ../../prototypes/unified-pe/verify/spec.ml (PE op word); the configuration reference in
   docs/configuration.md is checked against both by test/docs_drift.ml. *)

open Regs

(* ---- output pad sources and flag sources ---- *)

let pad_sources =
  List.init 8 (fun k -> (Printf.sprintf "seq%d" k, src_seq k))
  @ List.init 4 (fun k -> (Printf.sprintf "stream%d" k, src_stream k))
  @ [ ("nco_quarter", src_nco_quarter); ("nco_half", src_nco_half); ("nco_clock", src_nco_grid) ]
  @ List.init 4 (fun j -> (Printf.sprintf "tapflag%d" j, src_tap_flag j))
  @ List.init 4 (fun j -> (Printf.sprintf "tapbit%d" j, src_tap_bit0 j))
  @ [ ("esbit", src_es_bit); ("zero", 31) ]

let flag_sources =
  List.init 4 (fun j -> (Printf.sprintf "tapflag%d" j, fl_tap_flag j))
  @ List.init 4 (fun j -> (Printf.sprintf "tapvalid%d" j, fl_tap_valid j))
  @ [ ("es_valid", fl_es_valid); ("es_bit", fl_es_bit); ("es_burst", fl_es_in_burst);
      ("es_burst_end", fl_es_burst_end); ("crc_ok", fl_crc_check); ("match", fl_match_hit);
      ("stream_full", fl_stream_full); ("sample_valid", fl_sample_valid); ("nco", fl_nco); ("zero", 31) ]

let name_of l v = List.find_map (fun (n, x) -> if x = v then Some n else None) l

(* ---- PE op word fields (Upe.Spec.op) ---- *)

type pe_field = {
  key : string;                      (* the field's name in .pe *)
  names : (string * int) list;       (* symbolic values; [] for a number or a flag *)
  is_flag : bool;
  width : int;
  get : Upe.Spec.op -> int;
  set : Upe.Spec.op -> int -> Upe.Spec.op;
}

let b2i b = if b then 1 else 0

let pe_fields : pe_field list =
  let f ?(names = []) ?(is_flag = false) key width get set = { key; names; is_flag; width; get; set } in
  Upe.Spec.[
    f "x" 2 (fun o -> o.xsel) (fun o v -> { o with xsel = v }) ~names:[ "s", 0; "a", 1; "shl", 2; "shr", 3 ];
    f "sin" 2 (fun o -> o.sinsel) (fun o v -> { o with sinsel = v }) ~names:[ "g", 0; "lane", 1; "s15", 2; "a0", 3 ];
    f "y" 2 (fun o -> o.ysel) (fun o v -> { o with ysel = v }) ~names:[ "k", 0; "a", 1; "s", 2; "one", 3 ];
    f "ymod" 2 (fun o -> o.ymod) (fun o v -> { o with ymod = v }) ~names:[ "none", 0; "gate", 1; "negg", 2; "neg", 3 ];
    f "g" 3 (fun o -> o.gsel) (fun o v -> { o with gsel = v })
      ~names:[ "one", 0; "abit", 1; "lane", 2; "s15lane", 3; "crc", 4; "f", 5; "window", 6; "gleft", 7 ];
    f "bit" 4 (fun o -> o.bitsel) (fun o v -> { o with bitsel = v });
    f "pairlo" 1 (fun o -> b2i o.pairlo) (fun o v -> { o with pairlo = v = 1 }) ~is_flag:true;
    f "alu" 3 (fun o -> o.alu) (fun o v -> { o with alu = v })
      ~names:[ "sat", 0; "add", 1; "max", 2; "min", 3; "xor", 4; "and", 5; "or", 6; "y", 7 ];
    f "cin_lane" 1 (fun o -> b2i o.cin_lane) (fun o v -> { o with cin_lane = v = 1 }) ~is_flag:true;
    f "s" 2 (fun o -> o.swb) (fun o v -> { o with swb = v }) ~names:[ "hold", 0; "result", 1; "x", 2; "gresult", 3 ];
    f "p" 2 (fun o -> o.pwb) (fun o v -> { o with pwb = v }) ~names:[ "a", 0; "result", 1; "loser", 2; "merge", 3 ];
    f "f" 2 (fun o -> o.fwb) (fun o v -> { o with fwb = v }) ~names:[ "hold", 0; "g", 1; "zero", 2; "hold3", 3 ];
    f "lane" 2 (fun o -> o.lout) (fun o v -> { o with lout = v }) ~names:[ "lane", 0; "s15", 1; "carry", 2; "g", 3 ];
    f "lane_bc" 1 (fun o -> b2i o.lane_bc) (fun o v -> { o with lane_bc = v = 1 }) ~is_flag:true;
    f "del" 1 (fun o -> b2i o.del) (fun o v -> { o with del = v = 1 }) ~is_flag:true;
    f "stream" 1 (fun o -> b2i o.stream) (fun o v -> { o with stream = v = 1 }) ~is_flag:true;
    f "tap_p" 1 (fun o -> b2i o.tap_p) (fun o v -> { o with tap_p = v = 1 }) ~is_flag:true;
    f "follow" 1 (fun o -> b2i o.follow) (fun o v -> { o with follow = v = 1 }) ~is_flag:true;
    f "ashr" 4 (fun o -> o.ashr) (fun o v -> { o with ashr = v });
    f "k" 16 (fun o -> o.k) (fun o v -> { o with k = v land 0xFFFF });
  ]

(* the bit position of each op-word field, for the docs' table (k is bytes 0-1, not in the word) *)
let pe_field_lsb = [ "x", 0; "sin", 2; "y", 4; "ymod", 6; "g", 8; "bit", 11; "pairlo", 15; "alu", 16;
                     "cin_lane", 19; "s", 20; "p", 22; "f", 24; "lane", 26; "lane_bc", 28; "del", 29;
                     "stream", 30; "tap_p", 31; "follow", 32; "ashr", 33 ]

(* .pe's text for an op: the fields that are not zero *)
let pe_to_string (o : Upe.Spec.op) =
  String.concat ", "
    (List.filter_map (fun fd ->
         let v = fd.get o in
         if v = 0 then None
         else if fd.is_flag then Some fd.key
         else match name_of fd.names v with
           | Some n -> Some (Printf.sprintf "%s=%s" fd.key n)
           | None -> Some (Printf.sprintf (if fd.key = "k" then "%s=0x%04x" else "%s=%d") fd.key v)) pe_fields)

(* ---- segment control register (PESEG register 2) ---- *)

let seg_sources = [ "join", 0; "loop", 1; "feed", 2; "fixed", 3; "zero", 4 ]
let seg_flags = [ "bcast", 3; "run", 4; "bcast_prev", 5; "lane_loop", 6 ]

let seg_ctrl_to_string c =
  let src = c land 7 in
  String.concat ", "
    ((match name_of seg_sources src with Some n -> "src=" ^ n | None -> Printf.sprintf "src=%d" src)
     :: List.filter_map (fun (n, b) -> if (c lsr b) land 1 = 1 then Some n else None) seg_flags)

(* ---- register groups ---- *)

(* A group is a set of register addresses with a directive that sets exactly them. *)
let le n v = List.init n (fun k -> (v lsr (8 * k)) land 0xFF)
let of_le l = List.fold_right (fun b acc -> (acc lsl 8) lor b) l 0

let streamer_regs = [ r_str_per; r_str_per + 1; r_str_pins; r_str_idle_oe ]
let sampler_regs = [ r_smp_per; r_smp_per + 1; r_smp_off; r_smp_off + 1; r_smp_frame ]
let sampler_pin_regs = [ r_smp_pin 0; r_smp_pin 1; r_smp_pin 2; r_smp_pin 3; r_smp_src ]
let es_regs = [ r_es_mode; r_es_pads; r_es_holdoff; r_es_holdoff + 1; r_es_timeout; r_es_timeout + 1; r_es_offset; r_es_period ]
let crc_regs = r_crc_ctrl :: List.init 20 (fun k -> r_crc_poly + k)
let nco_regs = List.init 4 (fun k -> r_nco_inc + k)
let boot_regs = [ r_boot_pc 0; r_boot_pc 1; r_boot_pc 2; r_boot_pc 3; r_boot_page ]

let es_modes = [ "manchester", 0; "biphase", 1; "nrz", 2 ]

let streamer ~period ~width ~od ~idle ~idle_oe =
  [ period land 0xFF; ((period lsr 8) land 15) lor (width lsl 4); (od land 15) lor ((idle land 15) lsl 4); idle_oe land 15 ]

let sampler ~period ~width ~clocked ~offset ~trig_pin ~trig_val ~frame =
  [ period land 0xFF; ((period lsr 8) land 15) lor (width lsl 4) lor (b2i clocked lsl 7);
    offset land 0xFF; ((offset lsr 8) land 15) lor (trig_pin lsl 4) lor (trig_val lsl 6); frame ]

let edge_sampler ~mode ~invert ~use_active ~pad ~active ~holdoff ~timeout ~offset ~period =
  [ mode lor (b2i invert lsl 2) lor (b2i use_active lsl 3); pad lor (active lsl 4);
    holdoff land 0xFF; (holdoff lsr 8) land 3; timeout land 0xFF; (timeout lsr 8) land 3; offset; period ]

let crc ~reflected ~start_on_match ~poly ~init ~width ~xorout ~residue =
  let mask = if width >= 32 then 0xFFFF_FFFF else (1 lsl width) - 1 in
  (b2i reflected lor (b2i start_on_match lsl 1))
  :: (le 4 poly @ le 4 init @ le 4 mask @ le 4 xorout @ le 4 residue)
