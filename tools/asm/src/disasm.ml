(* The disassembler: an image (or a loaded state) back to assembly source. For every image the
   assembler makes, assembling the printed source gives the same bytes (test/roundtrip.ml).
   Instructions that are not canonical (an ignored bit set) are printed as .word, register groups
   whose bytes no named directive reproduces as .reg, so nothing is lost; what cannot be printed at
   all raises [Unsupported]. *)

open Regs

exception Unsupported of string

(* Planted bugs, for test/roundtrip.ml's controls only: each must make the round trip fail.
   "" (the default) plants nothing. *)
let plant = ref ""
let planted b = !plant = b

let label_name page pc = Printf.sprintf "L%d_%02x" page pc

let buf_add = Buffer.add_string

(* ---- the programme ---- *)

let programme b (img : Image.t) ~threads =
  let words = Hashtbl.create 512 in
  List.iter (fun (a, w) -> Hashtbl.replace words a w) img.prog;
  let labels = Hashtbl.create 64 in
  Array.iter (fun (pg, pc) -> Hashtbl.replace labels ((pg lsl 8) lor pc) ()) threads;
  List.iter (fun (a, w) ->
      if Insn.canonical w then
        let pg = a lsr 8 and pc = a land 0xFF in
        List.iter (fun t -> if t <> pc then Hashtbl.replace labels ((pg lsl 8) lor t) ()) (Insn.targets (Insn.decode w)))
    img.prog;
  let has_word a = Hashtbl.mem words a in
  let target page pc a =
    if a = pc then "."
    else if has_word ((page lsl 8) lor a) && Hashtbl.mem labels ((page lsl 8) lor a) then label_name page a
    else string_of_int a in
  Array.iteri (fun th (pg, pc) ->
      if has_word ((pg lsl 8) lor pc) then Printf.bprintf b ".thread %d, %s\n" th (label_name pg pc)
      else Printf.bprintf b ".thread %d, page=%d, pc=%d\n" th pg pc) threads;
  let cur_page = ref (-1) and next = ref (-1) in
  List.iter (fun (a, w) ->
      let pg = a lsr 8 and pc = a land 0xFF in
      if pg <> !cur_page then (Printf.bprintf b "\n.page %d\n" pg; cur_page := pg; next := 0);
      if pc <> !next then Printf.bprintf b ".org %d\n" pc;
      if Hashtbl.mem labels a then Printf.bprintf b "%s:\n" (label_name pg pc);
      let text =
        if Insn.canonical w then
          let i = Insn.decode w in
          let i = if planted "drop_q" then (match i with Insn.Setp x -> Insn.Setp { x with q = 0 } | Insn.Sho x -> Insn.Sho { x with q = 0 } | i -> i) else i in
          Insn.to_asm ~target:(target pg) ~pc i
        else Printf.sprintf ".word 0x%04x" w in
      let comment = if Insn.canonical w then "" else "   ; " ^ Isa2.disasm w ^ " (ignored bits set)" in
      Printf.bprintf b "    %-40s%s\n" text comment;
      next := pc + 1) (List.sort compare img.prog)

(* ---- register groups ---- *)

let group_print regs addrs decode =
  if List.for_all (fun a -> List.mem_assoc a regs) addrs then
    let vs = List.map (fun a -> List.assoc a regs) addrs in
    match decode vs with
    | Some (text, reenc) when reenc = vs -> Some text
    | _ -> None
  else None

let registers b (img : Image.t) =
  let regs = img.regs in
  let used = Hashtbl.create 64 in
  let take addrs text = List.iter (fun a -> Hashtbl.replace used a ()) addrs; buf_add b (text ^ "\n") in
  List.iter (fun a -> Hashtbl.replace used a ()) Config.boot_regs;
  (* pads, input pins, flags *)
  List.iter (fun p ->
      let a = r_padsel p in
      match List.assoc_opt a regs with
      | Some v when v land 0x80 = 0 ->
        let src = v land 31 in
        let name = match Config.name_of Config.pad_sources src with Some n -> n | None -> Printf.sprintf "src=%d" src in
        take [ a ] (Printf.sprintf ".pad %d, %s%s, undriven=%d" p name (if v land 0x20 <> 0 then ", invert" else "") ((v lsr 6) land 1))
      | _ -> ()) general_out_pads;
  for k = 0 to 7 do
    match List.assoc_opt (r_pinin k) regs with
    | Some v when v < 16 -> take [ r_pinin k ] (Printf.sprintf ".pinin %d, %d" k v)
    | _ -> ()
  done;
  for f = 0 to 15 do
    match List.assoc_opt (r_flagsel f) regs with
    | Some v when v < 32 ->
      take [ r_flagsel f ] (Printf.sprintf ".flag %d, %d, %s" (f / 4) (f mod 4)
                              (match Config.name_of Config.flag_sources v with Some n -> n | None -> string_of_int v))
    | _ -> ()
  done;
  let groups = [
    (Config.streamer_regs, fun vs -> match vs with
        | [ a; c; d; e ] ->
          let period = a lor ((c land 15) lsl 8) and width = (c lsr 4) land 15 in
          let od = d land 15 and idle = d lsr 4 and idle_oe = e in
          Some (Printf.sprintf ".streamer period=%d, width=%d, od=%d, idle=%d, idle_oe=%d" period width od idle idle_oe,
                Config.streamer ~period ~width ~od ~idle ~idle_oe)
        | _ -> None);
    (Config.sampler_regs, fun vs -> match vs with
        | [ a; c; d; e; f ] ->
          let period = a lor ((c land 15) lsl 8) and width = (c lsr 4) land 7 and clocked = c land 0x80 <> 0 in
          let offset = d lor ((e land 15) lsl 8) and trig_pin = (e lsr 4) land 3 and trig_val = (e lsr 6) land 1 in
          Some (Printf.sprintf ".sampler period=%d, width=%d%s, offset=%d, trigger=%d, trigger_level=%d, frame=%d"
                  period width (if clocked then ", clocked" else "") offset trig_pin trig_val f,
                Config.sampler ~period ~width ~clocked ~offset ~trig_pin ~trig_val ~frame:f)
        | _ -> None);
    (Config.sampler_pin_regs, fun vs -> match vs with
        | [ a; c; d; e; s ] when s <= 1 ->
          Some (Printf.sprintf ".sampler_pins %d, %d, %d, %d%s" a c d e (if s = 1 then ", recovered" else ""), [ a; c; d; e; s ])
        | _ -> None);
    (Config.es_regs, fun vs -> match vs with
        | [ m; pads; h0; h1; t0; t1; off; per ] ->
          let mode = m land 3 and invert = m land 4 <> 0 and use_active = m land 8 <> 0 in
          let pad = pads land 15 and active = pads lsr 4 in
          let holdoff = h0 lor ((h1 land 3) lsl 8) and timeout = t0 lor ((t1 land 3) lsl 8) in
          (match Config.name_of Config.es_modes mode with
           | Some mn ->
             Some (Printf.sprintf ".edge_sampler mode=%s%s, pad=%d%s, holdoff=%d, timeout=%d, offset=%d, period=%d" mn
                     (if invert then ", invert" else "") pad (if use_active then Printf.sprintf ", active=%d" active else "")
                     holdoff timeout off per,
                   Config.edge_sampler ~mode ~invert ~use_active ~pad ~active:(if use_active then active else 0) ~holdoff ~timeout ~offset:off ~period:per)
           | None -> None)
        | _ -> None);
    (Config.crc_regs, fun vs -> match vs with
        | c :: rest ->
          let w32 k = Config.of_le (List.filteri (fun i _ -> i >= 4 * k && i < 4 * (k + 1)) rest) in
          let poly = w32 0 and init = w32 1 and mask = w32 2 and xorout = w32 3 and residue = w32 4 in
          let rec ones v = if v land 1 = 1 then 1 + ones (v lsr 1) else 0 in
          let width = ones mask in
          if width = 0 then None
          else
            let reflected = c land 1 = 1 and som = c land 2 <> 0 in
            Some (Printf.sprintf ".crc width=%d, poly=0x%x, init=0x%x, xorout=0x%x, residue=0x%x%s%s" width poly init xorout residue
                    (if reflected then ", reflected" else "") (if som then ", start_on_match" else ""),
                  Config.crc ~reflected ~start_on_match:som ~poly ~init ~width ~xorout ~residue)
        | [] -> None);
    (Config.nco_regs, fun vs -> let v = Config.of_le vs in Some (Printf.sprintf ".nco inc=0x%08x" v, Config.le 4 v));
  ] in
  List.iter (fun (addrs, dec) ->
      match group_print regs addrs dec with
      | Some text -> take addrs text
      | None -> ()) groups;
  if not (planted "skip_reg") then
    List.iter (fun (a, v) -> if not (Hashtbl.mem used a) then Printf.bprintf b ".reg 0x%02x, 0x%02x\n" a v) regs

(* ---- the array and the rest ---- *)

let array b (img : Image.t) =
  let lay = img.layout in
  if img.pecfg <> Array.make 4 [] || img.peinit <> Array.make 4 [] || img.peseg <> Array.make 4 [] then
    Printf.bprintf b ".layout %d, %d, %d, %d\n" lay.(0) lay.(1) lay.(2) lay.(3);
  Array.iteri (fun sg bytes ->
      let size = lay.(sg) in
      if bytes <> [] then begin
        if List.length bytes = 8 * size then
          (* write order: PE size-1's byte 7 first *)
          let arr = Array.of_list bytes in
          for i = 0 to size - 1 do
            let pe = Array.init 8 (fun j -> arr.((8 * (size - 1 - i)) + 7 - j)) in
            let op = Upe.Spec.op_of_bytes pe in
            if Upe.Spec.bytes_of_op op = pe then
              Printf.bprintf b ".pe %d, %d%s\n" sg i (match Config.pe_to_string op with "" -> "" | s -> ", " ^ s)
            else
              Printf.bprintf b ".pebytes %d, %d, %s\n" sg i (String.concat ", " (Array.to_list (Array.map (Printf.sprintf "0x%02x") pe)))
          done
        else Printf.bprintf b ".pecfg %d, %s\n" sg (String.concat ", " (List.map (Printf.sprintf "0x%02x") bytes))
      end) img.pecfg;
  Array.iteri (fun sg bytes ->
      let size = lay.(sg) in
      if bytes <> [] then begin
        if List.length bytes <> 2 * size then raise (Unsupported (Printf.sprintf "PEINIT of segment %d: %d bytes for %d PEs" sg (List.length bytes) size));
        let arr = Array.of_list bytes in
        for i = 0 to size - 1 do
          let k = if planted "peinit_order" then i else size - 1 - i in
          Printf.bprintf b ".peinit %d, %d, 0x%04x\n" sg i ((arr.(2 * k) lsl 8) lor arr.((2 * k) + 1))
        done
      end) img.peinit;
  Array.iteri (fun sg regs ->
      if regs <> [] then begin
        match List.assoc_opt 2 regs with
        | Some ctrl when ctrl < 0x80 && (List.mem_assoc 0 regs = List.mem_assoc 1 regs) ->
          Printf.bprintf b ".seg %d, %s%s%s\n" sg (Config.seg_ctrl_to_string ctrl)
            (match List.assoc_opt 3 regs with Some r -> Printf.sprintf ", repeat=%d" r | None -> "")
            (match List.assoc_opt 0 regs, List.assoc_opt 1 regs with
             | Some lo, Some hi -> Printf.sprintf ", feed=0x%04x" ((hi lsl 8) lor lo) | _ -> "")
        | _ -> List.iter (fun (r, v) -> Printf.bprintf b ".segreg %d, %d, 0x%02x\n" sg r v) regs
      end) img.peseg;
  if img.matcher <> [] then begin
    let bits = Array.of_list img.matcher in
    if Array.length bits <> 37 || Array.exists (fun x -> x > 1) bits then raise (Unsupported "matcher chain is not 37 bits");
    let thr = ref 0 in
    for k = 0 to 4 do thr := !thr lor (bits.(k) lsl (4 - k)) done;
    let pat = ref 0 and mask = ref 0 in
    for k = 0 to Eth10.Model.n - 1 do
      let i = Eth10.Model.n - 1 - k in
      pat := !pat lor (bits.(5 + (2 * k)) lsl i);
      mask := !mask lor (bits.(6 + (2 * k)) lsl i)
    done;
    Printf.bprintf b ".matcher pattern=0x%04x, mask=0x%04x, threshold=%d\n" !pat !mask !thr
  end

let bytes_line l = String.concat ", " (List.map (Printf.sprintf "0x%02x") l)

let rec chunks16 = function
  | [] -> []
  | l -> List.filteri (fun i _ -> i < 16) l :: chunks16 (List.filteri (fun i _ -> i >= 16) l)

let state (img : Image.t) =
  let b = Buffer.create 4096 in
  buf_add b "; disassembled image\n";
  let threads = Image.boot img in
  programme b img ~threads;
  buf_add b "\n";
  registers b img;
  (* bank: contiguous runs, 16 a line *)
  List.iter (fun (a, bytes) ->
      List.iteri (fun k l -> Printf.bprintf b ".bankdata %d, %s\n" (a + (16 * k)) (bytes_line l)) (chunks16 bytes))
    (Image.runs img.bank);
  array b img;
  List.iter (fun l -> Printf.bprintf b ".hostin %s\n" (bytes_line l)) (chunks16 img.hostin);
  let rec streams = function
    | lo :: hi :: c :: r ->
      if c > 15 then raise (Unsupported "streamer vector count above 15");
      Printf.bprintf b ".stream 0x%04x, %d\n" ((hi lsl 8) lor lo) c; streams r
    | [] -> ()
    | _ -> raise (Unsupported "streamer bytes not a multiple of three") in
  streams img.stream;
  (match img.ctrl with
   | 3 -> () | 1 -> buf_add b ".run assists\n" | 2 -> buf_add b ".stop\n"
   | c -> Printf.bprintf b ".ctrl %d\n" c);
  Buffer.contents b

let image ?layout bytes = state (Image.parse ?layout bytes)
