(* The video-timing thread (T1) shared by the Ethernet-to-TV and CAN-to-TV demos: NTSC at
   17 x fsc, sync and blanking by SETP on the luma pins, burst and line playback by commands to the
   pin stage, every edge on an exact slot. Moved here unchanged from ethtv.ml. *)

let fclk = Video.fclk
let line_slots = 967                     (* 3868 clocks: 227.53 subcarrier cycles *)
let n_lines = 262
let first_active = 21
let src_lines = 120
let active_slot = 172
let field_clocks = 4 * line_slots * n_lines

(* ---------------- T1: video timing ---------------- *)
let luma_all0 = Isa.setp ~mask:0x0F ~value:0 ~oe:1
let sync_on = Isa.setp ~mask:0x04 ~value:0 ~oe:1     (* code 4 -> 0 *)
let sync_off = Isa.setp ~mask:0x04 ~value:1 ~oe:1    (* code 0 -> 4 (blank) *)
let dec_cnt = Isa.shi ~pin:0 ~msb:1                    (* SHI as "decrement cnt": acc is dead here *)

let video_programme ?(extra_slot = false) () =
  let b = Asm.create () in
  let heads = ref [] in
  let stage_cmd t v = [ (t - 1, Asm.W (Isa.lda v)); (t, Asm.W (Isa_mb.send ~ch:7 ~fail:0)) ] in
  (* a group of n identical lines; ev0 is the sync edge at slot 0; slots 1, 2 are reserved for
     LDC and the loop head's JMP; the rest of the events must be at slot >= 3 *)
  let group ?(len = line_slots) name n ev0 events =
    Asm.origin b;
    Asm.at b 0 (Asm.W ev0);
    Asm.at b 1 (Asm.W (Isa.ldc n));
    Asm.at b 2 (Asm.W Isa.nop);
    Asm.label b (name ^ "_rest");
    List.iter (fun (t, w) -> Asm.at b t w) (List.sort compare ((3, Asm.W dec_cnt) :: events));
    Asm.at b (len - 1) (Asm.jnz (name ^ "_head"));
    heads := (name, ev0) :: !heads in
  let burst = stage_cmd 81 Video.cmd_burst_on @ stage_cmd 119 Video.cmd_burst_off in
  let blank_ev = (72, Asm.W sync_off) :: burst in
  let active_ev = blank_ev @ stage_cmd active_slot Video.cmd_active in
  Asm.label b "field";
  group "vs" 3 luma_all0 ([ (412, Asm.W sync_off); (484, Asm.W sync_on); (895, Asm.W sync_off) ] @ stage_cmd 11 Video.cmd_field);
  group "bl" (first_active - 3) sync_on blank_ev;
  group ~len:(if extra_slot then line_slots + 1 else line_slots) "ac" (n_lines - first_active - 1) sync_on active_ev;
  (* bottom line, unrolled, ends with the jump back to the field *)
  Asm.origin b;
  Asm.at b 0 (Asm.W sync_on);
  List.iter (fun (t, w) -> Asm.at b t w) (List.sort compare blank_ev);
  Asm.at b (line_slots - 1) (Asm.jmp "field");
  List.iter (fun (name, ev0) ->
    Asm.label b (name ^ "_head"); Asm.emit b (Asm.W ev0); Asm.emit b (Asm.W Isa.nop); Asm.emit b (Asm.jmp (name ^ "_rest"))) (List.rev !heads);
  let prog, len, _ = Asm.assemble b in
  prog, len

