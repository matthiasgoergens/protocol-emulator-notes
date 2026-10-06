(* The PE array alone as Verilog, for formal/array_powerup: [emit_array.exe FILE SIZES clear|noclear].
   Module upe_array_pu: the array's inputs, a [clear] input (unused with noclear: the array as it
   was before it had a reset), and as outputs the taps and every register of every PE and segment
   (S, P, valid, F, lane, the 64 configuration bits; feed, control, repeat, counter, committed
   word, feed valid). *)
open Hardcaml
open Signal

let () =
  let file = Sys.argv.(1) in
  let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' Sys.argv.(2))) in
  let with_clear = match Sys.argv.(3) with "clear" -> true | "noclear" -> false | m -> failwith m in
  let layout = Upe.Spec.layout_of_sizes sizes in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let inp : Upe.Upe_rtl.array_in =
    { mbx_wr = input "mbx_wr" 1; mbx_seg = input "mbx_seg" 2; mbx_sel = input "mbx_sel" 2;
      mbx_byte = input "mbx_byte" 8; acfg_wr = input "cfg_wr" 1; acfg_seg = input "cfg_seg" 2;
      acfg_byte = input "cfg_byte" 8; ainit_wr = input "init_wr" 1; ainit_seg = input "init_seg" 2;
      ainit_byte = input "init_byte" 8;
      fixed_d = Array.init 4 (fun j -> input (Printf.sprintf "fixed_d%d" j) 16);
      fixed_v = Array.init 4 (fun j -> input (Printf.sprintf "fixed_v%d" j) 1) } in
  let o =
    if with_clear then Upe.Upe_rtl.array_create ~layout ~clear ~clock inp
    else Upe.Upe_rtl.array_create ~layout ~clock (ignore clear; inp) in
  let state =
    List.concat (Array.to_list (Array.map (fun (p : Upe.Upe_rtl.pe_out) -> [ p.s; p.p; p.pv; p.f; p.l; p.cfg ]) o.pes))
    @ List.concat (Array.to_list (Array.map (fun (r : Upe.Upe_rtl.seg_regs) -> [ r.flo; r.fhi; r.fv0; r.ctrl; r.rep; r.cnt; r.fw ]) o.segs))
    @ Array.to_list o.tap_d @ Array.to_list o.tap_v @ Array.to_list o.tap_f in
  let all = concat_lsb state in
  (* keep the clear input as a port even when unused *)
  let c = Circuit.create_exn ~name:"upe_array_pu" [ output "state" all; output "clear_seen" clear ] in
  let oc = open_out file in
  Rtl.output ~output_mode:(To_channel oc) Verilog c;
  close_out oc;
  Printf.printf "%d state bits\n" (width all)
