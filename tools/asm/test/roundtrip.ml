(* Round trip: assemble, disassemble, reassemble must give identical bytes.

   1. Every 16-bit word (all 65,536), as a one-word instruction in an image: canonical words come
      back as instructions, the others as .word; the bytes must be equal either way. Also counts
      how many words are canonical, per opcode.
   2. Every programme the repository's compiler emits in the verifier's sweep, and the verifier's
      planted programmes (prototypes/verifier/programmes.ml: UART, SPI, I2C from
      prototypes/deadline-sequencer/compiler.ml, translated to ISA v2), each as a page of an
      image; and the one-bit DAC's pump programme (prototypes/onebit-dac/sim/dac.ml), the whole
      1,024-word store.
   3. Random images (a property, N of them): random programme words on random pages, random
      register groups, PE configurations, init values, segment registers, matcher, bank bytes,
      HOSTIN bytes, streamer words and run state. Also checks that parsing an image's bytes gives
      back the state it was made from.
   4. The example sources under examples/.
   Usage: roundtrip.exe [N] (default 2000 random images). Exit 1 on any difference. *)

let failures = ref 0
let fail fmt = Printf.ksprintf (fun s -> incr failures; if !failures <= 20 then print_endline ("FAIL " ^ s)) fmt

let threads_at0 = [| (0, 0); (0, 0); (0, 0); (0, 0) |]

let boot_regs threads =
  List.mapi (fun t (_, pc) -> (Regs.r_boot_pc t, pc)) (Array.to_list threads)
  @ [ (Regs.r_boot_page, Array.fold_left ( lor ) 0 (Array.mapi (fun t (pg, _) -> pg lsl (2 * t)) threads)) ]

let image_of_prog ?(threads = threads_at0) prog = { Image.empty with regs = boot_regs threads; prog }

(* bytes -> source -> bytes *)
let roundtrip ~name (img : Image.t) =
  let b1 = Image.bytes img in
  match Disasm.image ~layout:img.layout b1 with
  | exception Disasm.Unsupported m -> fail "%s: disassembler: %s" name m; false
  | text ->
    match Assembler.assemble_string ~name text with
    | exception Loc.Error (l, m) -> fail "%s: reassembly: %s\n--- source ---\n%s" name (Loc.message l m) text; false
    | r ->
      let b2 = Image.bytes r.image in
      if b1 <> b2 then (fail "%s: bytes differ (%d and %d bytes)\n--- source ---\n%s" name (List.length b1) (List.length b2) text; false)
      else true

let all_words () =
  let canon = Array.make 16 0 in
  for batch = 0 to 63 do
    let prog = List.init 1024 (fun i -> let w = (batch * 1024) + i in (i, w)) in
    List.iter (fun (_, w) -> if Insn.canonical w then canon.(w lsr 12) <- canon.(w lsr 12) + 1) prog;
    ignore (roundtrip ~name:(Printf.sprintf "words 0x%04x-0x%04x" (batch * 1024) ((batch * 1024) + 1023)) (image_of_prog prog))
  done;
  Printf.printf "all 65,536 words: round trip checked in 64 images of 1,024 words\n";
  Printf.printf "  canonical words per opcode (the rest have ignored bits set and print as .word):\n";
  Array.iteri (fun op n -> Printf.printf "    %X %-6s %5d of 4096\n" op
                  (match op with 0 -> "NOP" | 1 -> "SETP" | 2 -> "LDC" | 3 -> "LDD" | 4 -> "LDA" | 5 -> "WAITP"
                               | 6 -> "WAITD" | 7 -> "SHO" | 8 -> "SHI" | 9 -> "JMP" | 10 -> "JNZ" | 11 -> "OUT"
                               | 12 -> "IN" | 13 -> "MBX" | 14 -> "WAITC" | _ -> "EXT") n) canon

let compiler_programmes () =
  let imgs = Verif.Programmes.sweep () @ Verif.Programmes.planted () in
  let ok = ref 0 and noncanon = ref 0 in
  List.iter (fun (i : Verif.Programmes.image) ->
      let prog = List.init 256 (fun pc -> (pc, i.words.(pc))) in
      Array.iter (fun w -> if not (Insn.canonical w) then incr noncanon) i.words;
      if roundtrip ~name:i.name (image_of_prog prog) then incr ok) imgs;
  Printf.printf "compiler sweep and planted programmes: %d of %d round trip identical (%d non-canonical words among them)\n"
    !ok (List.length imgs) !noncanon;
  let mem = Dacdemo.Dac.pump_programme () in
  let prog = List.init (Array.length mem) (fun a -> (a, mem.(a))) in
  let threads = [| (0, 0); (0, Dacdemo.Dac.idle_pc); (0, Dacdemo.Dac.idle_pc); (0, Dacdemo.Dac.idle_pc) |] in
  let r = roundtrip ~name:"onebit-dac pump programme" (image_of_prog ~threads prog) in
  Printf.printf "one-bit DAC pump programme (1,024 words): %s\n" (if r then "round trip identical" else "DIFFERS")

(* ---- random images ---- *)

let random_image rng =
  let int n = Random.State.int rng n and bool () = Random.State.bool rng in
  let pick l = List.nth l (int (List.length l)) in
  let threads = Array.init 4 (fun _ -> (int 4, int 256)) in
  (* programme: a few runs of words on random pages; words are any 16-bit value *)
  let prog = Hashtbl.create 256 in
  for _ = 1 to 1 + int 6 do
    let a0 = int 1024 and n = 1 + int 80 in
    for k = 0 to n - 1 do
      let w = if bool () then int 65536 else Insn.encode (Insn.decode (int 65536)) in
      Hashtbl.replace prog ((a0 + k) land 1023) w
    done
  done;
  let regs = Hashtbl.create 64 in
  List.iter (fun (a, v) -> Hashtbl.replace regs a v) (boot_regs threads);
  let set l = List.iter (fun (a, v) -> Hashtbl.replace regs a v) l in
  List.iter (fun p -> if int 3 = 0 then set [ (Regs.r_padsel p, int 128) ]) Regs.general_out_pads;
  for k = 0 to 7 do if int 3 = 0 then set [ (Regs.r_pinin k, int 16) ] done;
  for f = 0 to 15 do if int 4 = 0 then set [ (Regs.r_flagsel f, int 32) ] done;
  let group addrs vs = set (List.combine addrs vs) in
  if bool () then group Config.streamer_regs (Config.streamer ~period:(1 + int 4095) ~width:(pick [ 1; 2; 4 ]) ~od:(int 16) ~idle:(int 16) ~idle_oe:(int 16));
  if bool () then group Config.sampler_regs (Config.sampler ~period:(1 + int 4095) ~width:(pick [ 1; 2; 4 ]) ~clocked:(bool ())
                                               ~offset:(int 4096) ~trig_pin:(int 4) ~trig_val:(int 2) ~frame:(int 256));
  if bool () then group Config.sampler_pin_regs [ int 16; int 16; int 16; int 16; int 2 ];
  if bool () then (let ua = bool () in
                   group Config.es_regs (Config.edge_sampler ~mode:(int 3) ~invert:(bool ()) ~use_active:ua ~pad:(int 16)
                                           ~active:(if ua then int 16 else 0) ~holdoff:(int 1024) ~timeout:(int 1024) ~offset:(int 256) ~period:(int 256)));
  if bool () then group Config.crc_regs (Config.crc ~reflected:(bool ()) ~start_on_match:(bool ()) ~poly:(int 0x3FFFFFFF)
                                           ~init:(int 0x3FFFFFFF) ~width:(1 + int 32) ~xorout:(int 0x3FFFFFFF) ~residue:(int 0x3FFFFFFF));
  if bool () then group Config.nco_regs (Config.le 4 (int 0x3FFFFFFF));
  (* raw registers the named directives do not cover *)
  if bool () then set [ (Regs.r_restart_pc, int 256) ];
  if int 4 = 0 then set [ (Regs.r_padsel 3, 0x80 lor int 128) ];   (* bit 7 set: only .reg can say it *)
  let layout = Array.init 4 (fun _ -> 1 + int 4) in
  let pecfg = Array.init 4 (fun sg ->
      if bool () then
        List.concat (List.init layout.(sg) (fun _ ->
            let op = List.fold_left (fun o (fd : Config.pe_field) -> if int 3 = 0 then fd.set o (int (1 lsl fd.width)) else o)
                Upe.Spec.nop Config.pe_fields in
            let b = Upe.Spec.bytes_of_op op in
            if int 10 = 0 then b.(7) <- b.(7) lor 0x80;      (* an unused op bit: .pebytes *)
            List.init 8 (fun j -> b.(7 - j))))
      else []) in
  let peinit = Array.init 4 (fun sg -> if int 3 = 0 then List.init (2 * layout.(sg)) (fun _ -> int 256) else []) in
  let peseg = Array.init 4 (fun _ ->
      match int 4 with
      | 0 -> []
      | 1 -> [ (2, int 128) ]
      | 2 -> let w = int 65536 in [ (0, w land 0xFF); (1, w lsr 8); (2, int 128); (3, int 256) ]
      | _ -> List.sort_uniq (fun (a, _) (b, _) -> compare a b) (List.init (1 + int 3) (fun _ -> (int 4, int 256)))) in
  let matcher = if bool () then
      Eth10.Model.cfg_bits { t = Array.init Eth10.Model.n (fun _ -> int 2); m = Array.init Eth10.Model.n (fun _ -> int 2); thr = int 32 }
    else [] in
  let bank = Hashtbl.create 32 in
  if bool () then (let a0 = int 1000 in for k = 0 to int 24 do Hashtbl.replace bank (a0 + k) (int 256) done);
  let sorted h = List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) h []) in
  { Image.layout; regs = sorted regs; prog = sorted prog; bank = sorted bank; pecfg; peinit; peseg; matcher;
    hostin = List.init (int 17) (fun _ -> int 256); ctrl = pick [ 1; 2; 3; int 256 ];
    stream = List.concat (List.init (int 4) (fun _ -> let w = int 65536 in [ w land 0xFF; w lsr 8; int 16 ])) }

let random_images n =
  let rng = Random.State.make [| 20261010 |] in
  let ok = ref 0 and parse_ok = ref 0 in
  for i = 1 to n do
    let img = random_image rng in
    let b = Image.bytes img in
    if Image.parse ~layout:img.layout b = img then incr parse_ok
    else fail "random image %d: parse (bytes img) <> img" i;
    if roundtrip ~name:(Printf.sprintf "random image %d" i) img then incr ok
  done;
  Printf.printf "random images: %d of %d round trip identical; %d of %d parse back to their state\n" !ok n !parse_ok n

let examples () =
  let dir = "examples" in
  let files = List.sort compare (List.filter (fun f -> Filename.check_suffix f ".s") (Array.to_list (Sys.readdir dir))) in
  List.iter (fun f ->
      let path = Filename.concat dir f in
      match Assembler.assemble_file ~include_dirs:[ "lib" ] path with
      | exception Loc.Error (l, m) -> fail "%s: %s" path (Loc.message l m)
      | r -> Printf.printf "example %s: %s\n" f (if roundtrip ~name:path r.image then "round trip identical" else "DIFFERS"))
    files

let () =
  let n = try int_of_string Sys.argv.(1) with _ -> 2000 in
  all_words ();
  compiler_programmes ();
  random_images n;
  examples ();
  if !failures = 0 then print_endline "ROUND TRIP: ALL IDENTICAL"
  else (Printf.printf "ROUND TRIP: %d FAILURES\n" !failures; exit 1)
