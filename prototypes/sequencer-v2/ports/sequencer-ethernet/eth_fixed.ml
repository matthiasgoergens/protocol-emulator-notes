(* The fixed 10BASE-T transmitter firmware (see ../../../verif-oracles/stall/eth_stall.ml's
   header): the original 24-slot loop with WAITC 9 two slots before IN, and an underrun handler
   that releases the line and reports. It lives here, with the v2 port of sequencer-ethernet, whose
   main_fixed.exe tests it; verif-oracles uses it through a symlink. It needs v2: the base ISA of
   ../../../sequencer-ethernet has no way to see whether a host byte is waiting (IN blocks). *)
open Eth_fw

let n_threads = Isa2.n_threads

(* ---- the fixed firmware, in v2 words ---- *)
type item = W of int | L of string | Waitc of int * string | Jnz of string | Jmp of string | Halt

let assemble items =
  let labels = Hashtbl.create 8 and pos = ref 0 in
  List.iter (function L l -> Hashtbl.replace labels l !pos | _ -> incr pos) items;
  let find l = Hashtbl.find labels l in
  let out = ref [] and pos = ref 0 in
  List.iter (fun it ->
      let w = match it with
        | L _ -> None
        | W w -> Some w
        | Waitc (cond, l) -> Some (Isa2.waitc ~cond ~fail:(find l))
        | Jnz l -> Some (Isa2.jnz (find l))
        | Jmp l -> Some (Isa2.jmp (find l))
        | Halt -> Some (Isa2.halt_at !pos) in
      match w with Some w -> out := w :: !out; incr pos | None -> ()) items;
  Array.of_list (List.rev !out)

type plant = Sound | No_release | No_report

let program_fixed ?(plant = Sound) t =
  let k0 = let rec f k = if owner k = t then k else f (k + 1) in f 0 in
  let first_sho_slot = (s + h * k0 - t) / n_threads in
  let nbits = 8 * Array.length streams.(t) in
  let pro =
    (if t = 0 then [ W (Isa2.setp ~mask:1 ~value:0 ~oe:1 ()) ] else [])
    @ [ W (Isa2.ldc nbits); Waitc (Isa2.c_host, "under_real"); W Isa2.in_ ] in
  let pad = first_sho_slot - List.length pro in
  assert (pad >= 0);
  let sho = W (Isa2.sho ~pin:0 ~msb:0 ()) and nop = W Isa2.nop in
  let body =
    [ L "body" ]
    @ List.concat (List.init 6 (fun _ -> [ sho; nop; nop ]))
    @ [ sho; nop; Waitc (Isa2.c_host, "under") ]
    @ [ sho; W Isa2.in_; Jmp "body" ] in
  let handler =
    [ L "under"; sho; Jnz "under_real"; Halt;          (* the byte's last bit on time; cnt = 0: end of stream *)
      L "under_real" ]
    @ (if plant = No_release then [ nop ] else [ W (Isa2.setp ~mask:1 ~value:0 ~oe:0 ()) ])
    @ (if plant = No_report then [ nop ] else [ W (Isa2.outi ~tag:7 t) ])
    @ [ Halt ] in
  assemble (pro @ List.init pad (fun _ -> nop) @ body @ handler)

