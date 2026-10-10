(* The loadable image: the exact byte stream a host sends over the chip's host link
   (../../prototypes/chip-top/README.md, "Host link protocol"), as a sequence of write commands.
   Each command is {op = 1, target}, address high, address low, count - 1, then count data bytes,
   at most 256 per command. Nothing else is in the file: replaying it through any host-link driver
   loads the chip and starts it.

   An image is built from a [t], the loaded state, always in this order (the canonical form), so
   that equal states give equal bytes:
     1. REG 0 (control) <- 2: sequencer stopped, assists held;
     2. every other register the source sets, by address, contiguous runs in one command
        (always including the four boot pcs and the boot pages, 0x04..0x08);
     3. PROG: the programme words, two bytes each (low byte first), contiguous runs;
     4. BANK: data bank bytes;
     5. PECFG per segment: the configuration chain, 8 bytes per PE, last PE's byte 7 first;
     6. PEINIT per segment: the init chain, 2 bytes per PE, last PE's high byte first;
     7. PESEG per segment: feed low, feed high, control, repeat, those that are set;
     8. MATCH: the matcher's 37 configuration bits, one byte each;
     9. HOSTIN: bytes for the threads' IN, at most 16 (the FIFO's depth);
    10. REG 0 <- the final control value (run, and whether the assists run);
    11. STREAM: streamer words, three bytes each (after 10, because a held streamer drops them).
   [parse] reads any stream of write commands back into a [t]; [bytes (parse b) = b] holds for
   every image [bytes] made, which test/roundtrip.ml checks. *)

open Regs

type t = {
  layout : int array;                    (* PEs per segment; needed only to split chains into PEs *)
  regs : (int * int) list;               (* REG address -> byte, without the control register *)
  prog : (int * int) list;               (* word address {page, pc} -> word *)
  bank : (int * int) list;               (* byte address -> byte *)
  pecfg : int list array;                (* per segment, the chain bytes in write order *)
  peinit : int list array;
  peseg : (int * int) list array;        (* per segment, (register 0..3, byte) *)
  matcher : int list;                    (* the 37 chain bits in write order, or [] *)
  hostin : int list;
  ctrl : int;                            (* the control register's final value *)
  stream : int list;                     (* streamer bytes, three per word *)
}

let empty = { layout = [| 1; 1; 1; 1 |]; regs = []; prog = []; bank = []; pecfg = Array.make 4 [];
              peinit = Array.make 4 []; peseg = Array.make 4 []; matcher = []; hostin = []; ctrl = 3;
              stream = [] }

let cmd ~tgt ~addr data =
  assert (List.length data >= 1 && List.length data <= 256);
  ((op_write lsl 4) lor tgt) :: ((addr lsr 8) land 0xFF) :: (addr land 0xFF) :: (List.length data - 1) :: data

(* split a list into chunks of at most 256 bytes, advancing the address *)
let rec chunks ~tgt ~addr ?(step = 1) data =
  match data with
  | [] -> []
  | _ ->
    let n = min 256 (List.length data) in
    let now = List.filteri (fun i _ -> i < n) data and rest = List.filteri (fun i _ -> i >= n) data in
    cmd ~tgt ~addr now @ chunks ~tgt ~addr:(addr + (n * step)) ~step rest

(* contiguous runs of (address, byte), sorted by address *)
let runs l =
  let l = List.sort compare l in
  let rec go acc cur = function
    | [] -> List.rev (match cur with Some (a, bs) -> (a, List.rev bs) :: acc | None -> acc)
    | (a, b) :: r ->
      (match cur with
       | Some (a0, bs) when a0 + List.length bs = a -> go acc (Some (a0, b :: bs)) r
       | Some (a0, bs) -> go ((a0, List.rev bs) :: acc) (Some (a, [ b ])) r
       | None -> go acc (Some (a, [ b ])) r) in
  go [] None l

let bytes t =
  let out = ref [] in
  let emit l = out := List.rev_append l !out in
  emit (cmd ~tgt:t_reg ~addr:r_ctrl [ 2 ]);
  List.iter (fun (a, bs) -> emit (chunks ~tgt:t_reg ~addr:a bs)) (runs t.regs);
  let prog_bytes = List.concat_map (fun (w, v) -> [ (2 * w, v land 0xFF); ((2 * w) + 1, (v lsr 8) land 0xFF) ]) t.prog in
  List.iter (fun (a, bs) -> emit (chunks ~tgt:t_prog ~addr:a bs)) (runs prog_bytes);
  List.iter (fun (a, bs) -> emit (chunks ~tgt:t_bank ~addr:a bs)) (runs t.bank);
  Array.iteri (fun sg bs -> if bs <> [] then emit (chunks ~tgt:t_pecfg ~addr:(sg lsl 8) ~step:0 bs)) t.pecfg;
  Array.iteri (fun sg bs -> if bs <> [] then emit (chunks ~tgt:t_peinit ~addr:(sg lsl 8) ~step:0 bs)) t.peinit;
  Array.iteri (fun sg regs ->
      List.iter (fun (a, bs) -> emit (chunks ~tgt:t_peseg ~addr:a bs))
        (runs (List.map (fun (r, b) -> ((sg lsl 2) lor r, b)) regs))) t.peseg;
  if t.matcher <> [] then emit (chunks ~tgt:t_match ~addr:0 ~step:0 t.matcher);
  if t.hostin <> [] then emit (chunks ~tgt:t_hostin ~addr:0 ~step:0 t.hostin);
  emit (cmd ~tgt:t_reg ~addr:r_ctrl [ t.ctrl ]);
  if t.stream <> [] then emit (chunks ~tgt:t_stream ~addr:0 ~step:0 t.stream);
  List.rev !out

(* The commands of an image: (target, address, data). Fails on anything but well-formed write
   commands. *)
exception Bad_image of string

let commands (b : int list) =
  let rec go acc = function
    | [] -> List.rev acc
    | c :: ah :: al :: n :: rest ->
      if c lsr 4 <> op_write then raise (Bad_image (Printf.sprintf "command byte 0x%02x is not a write" c));
      let n = n + 1 in
      if List.length rest < n then raise (Bad_image "truncated command");
      let data = List.filteri (fun i _ -> i < n) rest and rest = List.filteri (fun i _ -> i >= n) rest in
      go ((c land 15, (ah lsl 8) lor al, data) :: acc) rest
    | _ -> raise (Bad_image "truncated command header") in
  go [] b

(* Read commands back into a loaded state. Addresses advance within a command as the chip does:
   REG, PROG, BANK, PESEG by one per byte; PECFG and PEINIT keep their segment (the chain
   shifts); MATCH, HOSTIN and STREAM ignore the address. *)
let parse ?(layout = [| 1; 1; 1; 1 |]) b =
  let regs = Hashtbl.create 64 and progb = Hashtbl.create 512 and bank = Hashtbl.create 64 in
  let pecfg = Array.make 4 [] and peinit = Array.make 4 [] and peseg = Array.init 4 (fun _ -> Hashtbl.create 4) in
  let matcher = ref [] and hostin = ref [] and stream = ref [] and ctrl = ref None and seen_start = ref false in
  List.iter (fun (tgt, addr, data) ->
      List.iteri (fun i v ->
          let a = (addr + i) land 0xFFFF in
          if tgt = t_reg then begin
            if a = r_ctrl then (if not !seen_start then seen_start := true else ctrl := Some v)
            else Hashtbl.replace regs a v
          end
          else if tgt = t_prog then Hashtbl.replace progb a v
          else if tgt = t_bank then Hashtbl.replace bank a v
          else if tgt = t_pecfg then pecfg.((addr lsr 8) land 3) <- pecfg.((addr lsr 8) land 3) @ [ v ]
          else if tgt = t_peinit then peinit.((addr lsr 8) land 3) <- peinit.((addr lsr 8) land 3) @ [ v ]
          else if tgt = t_peseg then Hashtbl.replace peseg.((a lsr 2) land 3) (a land 3) v
          else if tgt = t_match then matcher := !matcher @ [ v ]
          else if tgt = t_hostin then hostin := !hostin @ [ v ]
          else if tgt = t_stream then stream := !stream @ [ v ]
          else raise (Bad_image (Printf.sprintf "write to target %d" tgt))) data) (commands b);
  let sorted h = List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) h []) in
  let words =
    List.filter_map (fun (a, lo) ->
        if a land 1 = 0 then
          match Hashtbl.find_opt progb (a + 1) with
          | Some hi -> Some (a / 2, (hi lsl 8) lor lo)
          | None -> raise (Bad_image (Printf.sprintf "programme byte 0x%04x without its high byte" a))
        else if Hashtbl.mem progb (a - 1) then None
        else raise (Bad_image (Printf.sprintf "programme byte 0x%04x without its low byte" a)))
      (sorted progb) in
  { layout; regs = sorted regs; prog = words; bank = sorted bank; pecfg; peinit;
    peseg = Array.map sorted peseg; matcher = !matcher; hostin = !hostin;
    ctrl = (match !ctrl with Some c -> c | None -> raise (Bad_image "no final control write (run)"));
    stream = !stream }

let to_file path b =
  let oc = open_out_bin path in
  List.iter (fun x -> output_char oc (Char.chr x)) b;
  close_out oc

let of_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  List.init n (fun i -> Char.code s.[i])

(* the whole programme store as an array, unwritten words 0 *)
let store ?(words = 1024) t =
  let m = Array.make words 0 in
  List.iter (fun (a, w) -> if a < words then m.(a) <- w) t.prog;
  m

let reg t a = List.assoc_opt a t.regs

let boot t =
  Array.init 4 (fun th ->
      let page = match reg t r_boot_page with Some v -> (v lsr (2 * th)) land 3 | None -> 0 in
      let pc = Option.value ~default:0 (reg t (r_boot_pc th)) in
      (page, pc))

(* a thread's 256-word page *)
let page_words t page = Array.init Isa2.page_len (fun pc -> Option.value ~default:0 (List.assoc_opt ((page lsl 8) lor pc) t.prog))
