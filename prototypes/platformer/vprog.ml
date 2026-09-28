(* The video timing firmware for the deadline sequencer (ISA in isa.ml, unchanged). Thread 0 makes
   the sync pulses, the line event and the burst gate; thread 1 makes the PAL V-switch; threads 2
   and 3 are free.

   Sequencer pins (the luma DAC pins are overridden by the array's output while it shows pixels):
     0-3 luma DAC code (0 sync tip, 4 blank), 4 line_go (active low: falls at the start of every
     line), 5 field (active low on the three vsync lines), 6 V-switch, 7 burst gate.

   A thread issues once every 4 clocks, so a line is 3404 clocks (851 slots) rather than PAL's
   3405.02 at 12 x fsc: the line rate is 294 ppm fast, which a TV's line oscillator follows
   without noticing; the colour burst is regenerated on every line, so hue is unaffected.

   Each line body is written as events at slots 0-850 and assembled by [timed], which fills gaps
   with LDD n; WAITD (n + 2 slots) or NOP, so every body is exactly 851 slots. *)
open Isa

let slots_per_line = 851
let cpl = 4 * slots_per_line
let lpf = 312

(* [events]: (slot, instruction), sorted, first at slot 0. [end_slot]: where the next body starts
   (for a loop body, the JNZ is the last event at end_slot - 1). *)
let timed events ~end_slot =
  let code = ref [] and cursor = ref 0 in
  let emit i = code := i :: !code; incr cursor in
  let gap_to e =
    let g = e - !cursor in
    if g < 0 then failwith (Printf.sprintf "event at slot %d but cursor at %d" e !cursor);
    if g = 1 then emit nop
    else if g >= 2 then (code := waitd :: ldd (g - 2) :: !code; cursor := e) in
  List.iter (fun (e, i) -> gap_to e; emit i) events;
  gap_to end_slot;
  List.rev !code

let luma_sync = setp ~mask:0x0F ~value:0 ~oe:1
let sho_dec = shi ~pin:0 ~msb:0          (* SHI only to decrement the loop counter *)

(* Thread 0. Layout: V0 at 0 (first vsync line, sets the count), V (loops), N0 (first normal line),
   N0 jumps to N, which ends at address 63 so that falling out of it wraps to V0; the padding
   between them never runs. *)
let thread0 () =
  let v_events ~first ~loop_to =
    [ 0, setp ~mask:0x3F ~value:0 ~oe:1 ]                      (* sync tip, line_go, field *)
    @ (if first then [ 1, ldc 2 ] else [])
    @ [ 363, setp ~mask:0x14 ~value:1 ~oe:1                     (* h 1452: blank, line_go up *)
      ; 425, luma_sync                                         (* h 1700: second broad pulse *)
      ; 788, setp ~mask:0x04 ~value:1 ~oe:1 ]                   (* h 3152 *)
    @ (match loop_to with Some a -> [ 789, sho_dec; 850, jnz a ] | None -> []) in
  let n_events ~first ~loop_to =
    [ 0, setp ~mask:0x1F ~value:0 ~oe:1 ]                      (* sync tip and line_go *)
    @ (if first then [ 1, ldc 308 ] else [])
    @ [ 62, setp ~mask:0x34 ~value:1 ~oe:1                      (* h 248: blank, line_go, field up *)
      ; 74, setp ~mask:0x80 ~value:1 ~oe:1                      (* h 296: burst on *)
      ; 104, setp ~mask:0x80 ~value:0 ~oe:1 ]                   (* h 416: burst off *)
    @ (match loop_to with Some a -> [ 105, sho_dec; 850, jnz a ] | None -> []) in
  let v0 = timed (v_events ~first:true ~loop_to:None) ~end_slot:851 in
  let v_addr = List.length v0 in
  let v = timed (v_events ~first:false ~loop_to:(Some v_addr)) ~end_slot:851 in
  let n_len = List.length (timed (n_events ~first:false ~loop_to:(Some 0)) ~end_slot:851) in
  let n_addr = prog_len - n_len in
  (* N0 jumps to N (in its last slot), so the padding before N is never executed *)
  let n0 = timed (n_events ~first:true ~loop_to:None @ [ 850, jmp n_addr ]) ~end_slot:851 in
  let n = timed (n_events ~first:false ~loop_to:(Some n_addr)) ~end_slot:851 in
  let used = v0 @ v @ n0 in
  if List.length used > n_addr then failwith "thread 0 programme too long";
  Array.of_list (used @ List.init (n_addr - List.length used) (fun _ -> nop) @ n)

(* Thread 1: the V-switch, a two-line loop in lockstep with thread 0 (312 lines per field is even). *)
let thread1 () =
  let code = timed [ 0, setp ~mask:0x40 ~value:1 ~oe:1; 851, setp ~mask:0x40 ~value:0 ~oe:1; 1701, jmp 0 ]
      ~end_slot:1702 in
  Array.of_list (code @ List.init (prog_len - List.length code) (fun _ -> nop))

let programme () =
  [| thread0 (); thread1 (); Array.make prog_len halt; Array.make prog_len halt |]

(* Run the interpreter for [fields] fields and check the timing of every pin edge. *)
let check ?(fields = 2) () =
  let mem = programme () in
  let st = Isa.init () in
  let cycles = fields * lpf * cpl + 8 in
  let prev = ref 0 in
  let falls = ref [] and go = ref [] and burst = ref [] and vs = ref [] in
  for c = 0 to cycles - 1 do
    ignore (Isa.step st ~mem ~pin_in:0 ~host_in:0 ~host_in_valid:false);
    let p = st.pin_out in
    let fell b = (!prev lsr b) land 1 = 1 && (p lsr b) land 1 = 0 in
    let rose b = (!prev lsr b) land 1 = 0 && (p lsr b) land 1 = 1 in
    if !prev land 0xF <> 0 && p land 0xF = 0 then falls := c :: !falls;
    if fell 4 then go := c :: !go;
    if rose 7 then burst := c :: !burst;
    if rose 6 || fell 6 then vs := c :: !vs;
    prev := p
  done;
  let diffs l = let l = List.rev l in List.map2 ( - ) (List.tl l) (List.rev (List.tl (List.rev l))) in
  let hist l =
    let h = Hashtbl.create 8 in
    List.iter (fun d -> Hashtbl.replace h d (1 + try Hashtbl.find h d with Not_found -> 0)) (diffs l);
    Hashtbl.fold (fun k v acc -> Printf.sprintf "%s %d x%d" acc k v) h "" in
  Printf.sprintf "sync falls: %d, spacing:%s\nline_go falls: %d, spacing:%s\nburst starts: %d, spacing:%s\nV-switch edges: %d, spacing:%s\n"
    (List.length !falls) (hist !falls) (List.length !go) (hist !go) (List.length !burst) (hist !burst)
    (List.length !vs) (hist !vs)
