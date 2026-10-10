(* asm: the assembler, disassembler and verifier driver (README.md).

     asm FILE.s [-o IMAGE] [-I DIR]... [--listing FILE] [--verify] [--certs DIR]
         assemble FILE.s into IMAGE (default FILE.hlk): the host-link byte stream that loads and
         starts the chip. --listing writes every word with its address and source line ("-" for
         standard output). --verify proves each .timing block with the static verifier and
         prints the verdicts; --certs DIR writes each certificate to DIR/NAME.tT.cert. With
         --verify the exit status is 1 if any block is not proved.
     asm --disasm IMAGE [--layout A,B,C,D] [-o FILE.s]
         print the image as assembly source that reassembles to the same bytes.
     asm --roundtrip FILE.s [-I DIR]...
         assemble, disassemble, reassemble, and compare the two images byte for byte. *)

let usage () =
  prerr_endline "usage: asm FILE.s [-o IMAGE] [-I DIR]... [--listing FILE|-] [--verify] [--certs DIR]\n       asm --disasm IMAGE [--layout A,B,C,D] [-o FILE.s]\n       asm --roundtrip FILE.s [-I DIR]...";
  exit 2

let write_text path s = if path = "-" then print_string s else (let oc = open_out path in output_string oc s; close_out oc)

let print_warnings () =
  List.iter (fun (l, m) -> Printf.eprintf "%s: warning: %s\n" (Loc.to_string l) m) (List.rev !Loc.warnings);
  Loc.warnings := []

let default_include () =
  (* lib/ next to the executable's source tree: tools/asm/lib, found from the binary's path *)
  let exe = Sys.executable_name in
  let rec up d n = if n = 0 then d else up (Filename.dirname d) (n - 1) in
  let root = up exe 4 in   (* tools/asm/_build/default/bin/asm.exe -> tools/asm *)
  [ Filename.concat root "lib" ]

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let out = ref None and incs = ref [] and listing = ref None and verify = ref false and certs = ref None in
  let mode = ref `Asm and input = ref None and layout = ref None in
  let rec go = function
    | ("-o" | "--output") :: f :: r -> out := Some f; go r
    | "-I" :: d :: r -> incs := !incs @ [ d ]; go r
    | "--listing" :: f :: r -> listing := Some f; go r
    | "--verify" :: r -> verify := true; go r
    | "--certs" :: d :: r -> certs := Some d; verify := true; go r
    | "--disasm" :: f :: r -> mode := `Disasm; input := Some f; go r
    | "--roundtrip" :: f :: r -> mode := `Roundtrip; input := Some f; go r
    | "--layout" :: l :: r ->
      layout := Some (Array.of_list (List.map int_of_string (String.split_on_char ',' l))); go r
    | f :: r when f.[0] <> '-' && !input = None -> input := Some f; go r
    | [] -> ()
    | x :: _ -> Printf.eprintf "asm: unknown argument %s\n" x; usage () in
  go args;
  let input = match !input with Some f -> f | None -> usage () in
  let include_dirs = !incs @ default_include () in
  try
    match !mode with
    | `Disasm ->
      let text = Disasm.image ?layout:!layout (Image.of_file input) in
      write_text (Option.value !out ~default:"-") text
    | `Roundtrip ->
      let r = Assembler.assemble_file ~include_dirs input in
      let b1 = Image.bytes r.image in
      let text = Disasm.image ~layout:r.image.layout b1 in
      let r2 = Assembler.assemble_string ~include_dirs ~name:(input ^ " (disassembled)") text in
      let b2 = Image.bytes r2.image in
      print_warnings ();
      if b1 = b2 then Printf.printf "%s: round trip identical (%d bytes)\n" input (List.length b1)
      else begin
        Printf.printf "%s: round trip DIFFERS (%d and %d bytes)\n" input (List.length b1) (List.length b2);
        exit 1
      end
    | `Asm ->
      let r = Assembler.assemble_file ~include_dirs input in
      print_warnings ();
      let out = match !out with Some o -> o | None -> Filename.remove_extension input ^ ".hlk" in
      let bytes = Image.bytes r.image in
      Image.to_file out bytes;
      Printf.printf "%s: %d words, %d image bytes -> %s\n" input (List.length r.image.prog) (List.length bytes) out;
      (match !listing with Some f -> write_text f (Assembler.listing_text r) | None -> ());
      if !verify then begin
        if r.timings = [] then print_endline "verify: the source has no .timing block";
        let name = Filename.remove_extension (Filename.basename input) in
        let vs = Verify.verify ~name r in
        List.iter (fun (v : Verify.verdict) ->
            print_string v.text;
            match !certs, v.cert with
            | Some d, Some c ->
              (try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
              let f = Filename.concat d (v.name ^ ".cert") in
              write_text f c; Printf.printf "    certificate: %s\n" f
            | _ -> ()) vs;
        if List.exists (fun (v : Verify.verdict) -> not v.ok) vs then exit 1
      end
  with
  | Loc.Error (l, m) -> print_warnings (); prerr_endline (Loc.message l m); exit 1
  | Image.Bad_image m -> Printf.eprintf "%s: not an image: %s\n" input m; exit 1
  | Disasm.Unsupported m -> Printf.eprintf "%s: cannot disassemble: %s\n" input m; exit 1
