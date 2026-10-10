(* The docs cannot drift from the executable specification: this test reads the tables and the
   checked code blocks of docs/*.md and compares them with the code.

   docs/isa.md
   - the encoding table: every row's opcode and fixed fields against Isa2's constants; every
     field's bit positions against Isa2's encoder (through Insn, the assembler's path to it),
     bit by bit; the fields, fixed bits and ignored bits cover bits 11..0 exactly once; and,
     semantically, on Isa2.Spec.exec over random states and inputs: flipping an ignored bit never
     changes the next state or the clock's effects, and flipping a field bit does in some trial;
   - the WAITC condition table and the channel table: their numbers and names against Isa2 and
     the assembler, and each condition's meaning by running WAITC in states built to make it
     hold and not hold;
   - every ```asm block with "; expect:" lines, assembled and run on the interpreter.
   docs/configuration.md and docs/host-link.md
   - the register map (address, width, reset value) against prototypes/chip-top/src/regs.ml; the
     pad and flag source codes against regs.ml and the assembler's names; the PE op word fields
     against prototypes/unified-pe/verify/spec.ml (bytes_of_op) and the assembler; the segment
     control bits; the host-link targets and command ops.
   Run from tools/asm: _build/default/test/docs_drift.exe [DOCS_DIR] (default ../../docs). *)

let failures = ref 0
let checks = ref 0
let fail fmt = Printf.ksprintf (fun s -> incr failures; print_endline ("FAIL " ^ s)) fmt
let ok cond fmt = Printf.ksprintf (fun s -> incr checks; if not cond then (incr failures; print_endline ("FAIL " ^ s))) fmt

let read path = let ic = open_in_bin path in let s = really_input_string ic (in_channel_length ic) in close_in ic; s
let lines s = String.split_on_char '\n' s
let trim = String.trim

(* the rows of the table between "<!-- NAME table" and "<!-- end NAME table -->" *)
let table doc name =
  let ls = lines doc in
  let rec skip = function
    | l :: r -> if String.length (trim l) >= 9 && String.starts_with ~prefix:("<!-- " ^ name ^ " table") (trim l) then r else skip r
    | [] -> failwith ("no table " ^ name) in
  let rec take acc = function
    | l :: r when not (String.starts_with ~prefix:("<!-- end " ^ name) (trim l)) -> take (l :: acc) r
    | _ -> List.rev acc in
  let rows = take [] (skip ls) |> List.filter (fun l -> String.length (trim l) > 0 && (trim l).[0] = '|') in
  let cells l =
    let l = trim l in
    let parts = String.split_on_char '|' (String.sub l 1 (String.length l - 2)) in
    List.map trim parts in
  match rows with
  | _ :: _ :: data -> List.map cells data            (* header, separator *)
  | _ -> failwith ("empty table " ^ name)

(* ---- bit fields: "name[hi:lo]", "name[b]", optionally "=v" or "=a..b" ---- *)

type field = { fname : string; hi : int; lo : int; fixed : (int * int) option }

let parse_bits s =
  (* "[hi:lo]" or "[b]" *)
  let inner = String.sub s 1 (String.length s - 2) in
  match String.split_on_char ':' inner with
  | [ h; l ] -> (int_of_string h, int_of_string l)
  | [ b ] -> let b = int_of_string b in (b, b)
  | _ -> failwith ("bad bit range " ^ s)

let parse_field tok =
  let i = String.index tok '[' and j = String.index tok ']' in
  let name = String.sub tok 0 i and bits = String.sub tok i (j - i + 1) in
  let hi, lo = parse_bits bits in
  let rest = String.sub tok (j + 1) (String.length tok - j - 1) in
  let fixed =
    if rest = "" then None
    else if rest.[0] = '=' then
      let v = String.sub rest 1 (String.length rest - 1) in
      match String.index_opt v '.' with
      | Some k -> Some (int_of_string (String.sub v 0 k), int_of_string (String.sub v (k + 2) (String.length v - k - 2)))
      | None -> let x = int_of_string v in Some (x, x)
    else failwith ("bad field " ^ tok) in
  { fname = name; hi; lo; fixed }

let words s = List.filter (( <> ) "") (String.split_on_char ' ' s)

(* ---- the forms of the encoding table, built through Insn (and so Isa2's encoders) ---- *)

let build form (f : string -> int) : Insn.t =
  let b n = f n = 1 in
  match form with
  | "NOP" -> Nop
  | "SETP" -> Setp { mask = f "mask"; v = f "val"; oe = f "oe"; q = f "q" }
  | "LDC" -> Ldc (f "imm") | "LDD" -> Ldd (f "imm") | "LDA" -> Lda (f "imm")
  | "WAITP" -> Waitp { pin = f "pin"; v = f "val"; fail = f "fail" }
  | "WAITD" -> Waitd
  | "SHO" -> Sho { pin = f "pin"; msb = b "msb"; od = b "od"; pair = b "pair"; psel = b "psel"; cap = b "cap"; q = f "q" }
  | "SHI" -> Shi { pin = f "pin"; msb = b "msb"; quad = b "quad" }
  | "JMP" -> Jmp (f "addr") | "JNZ" -> Jnz (f "addr")
  | "OUT" -> Out { tag = f "tag" } | "OUTI" -> Outi { tag = f "tag"; v = f "imm" }
  | "IN" -> In
  | "SEND" -> Send { ch = f "ch"; fail = f "fail" } | "RECV" -> Recv { ch = f "ch"; fail = f "fail" }
  | "WAITC" -> Waitc { cond = f "cond"; fail = f "fail" }
  | "SKNE" | "SKEQ" | "FINE" | "CNTA" | "LDB" | "STB" | "BANK" | "CFG" ->
    Ext { sub = List.assoc (String.lowercase_ascii form) Insn.ext_names; imm = f "imm" }
  | "EXT" -> Ext { sub = f "sub"; imm = 0 }
  | _ -> failwith ("unknown form " ^ form)

(* Isa2's constant for a form: its opcode, and for EXT forms the sub-operation *)
let isa2_code form =
  let open Isa2 in
  match form with
  | "NOP" -> (op_nop, None) | "SETP" -> (op_setp, None) | "LDC" -> (op_ldc, None) | "LDD" -> (op_ldd, None)
  | "LDA" -> (op_lda, None) | "WAITP" -> (op_waitp, None) | "WAITD" -> (op_waitd, None) | "SHO" -> (op_sho, None)
  | "SHI" -> (op_shi, None) | "JMP" -> (op_jmp, None) | "JNZ" -> (op_jnz, None) | "OUT" | "OUTI" -> (op_out, None)
  | "IN" -> (op_in, None) | "SEND" | "RECV" -> (op_mbx, None) | "WAITC" -> (op_waitc, None)
  | "SKNE" -> (op_ext, Some x_skne) | "SKEQ" -> (op_ext, Some x_skeq) | "FINE" -> (op_ext, Some x_fine)
  | "CNTA" -> (op_ext, Some x_cnta) | "LDB" -> (op_ext, Some x_ldb) | "STB" -> (op_ext, Some x_stb)
  | "BANK" -> (op_ext, Some x_bank) | "CFG" -> (op_ext, Some x_cfg) | "EXT" -> (op_ext, None)
  | _ -> failwith form

(* ---- random states for the semantic checks ---- *)

let random_state rng ~word =
  let int n = Random.State.int rng n and bool () = Random.State.bool rng in
  let boot = Array.init 4 (fun _ -> (int 4, int 256)) in
  let bank = Array.init Isa2.bank_len (fun _ -> int 256) in
  let st = Isa2.init ~boot ~bank () in
  let imm8 = word land 0xFF in
  for t = 0 to 3 do
    st.accs.(t) <- (if bool () then imm8 else int 256);
    st.cnts.(t) <- (match int 3 with 0 -> 0 | 1 -> int 16 | _ -> int 4096);
    st.dls.(t) <- (match int 3 with 0 -> 0 | 1 -> 1 + int 4 | _ -> int 4096);
    st.bps.(t) <- int 1024; st.fines.(t) <- int 256; st.armed.(t) <- int 2; st.cfgs.(t) <- int 256;
    st.lsend.(t) <- int 8; st.inbox.(t) <- int 256; st.full.(t) <- int 2
  done;
  st.pin_out <- int 256; st.pin_oe <- int 256; st.latch <- int 256; st.pin_sub <- Random.State.full_int rng 0x1_0000_0000;
  st.thread <- int 4;
  let io = Isa2.io ~pin_in4:(Random.State.full_int rng 0x1_0000_0000) ~host_in:(int 256) ~host_in_valid:(bool ())
      ~port_in:(Array.init 4 (fun _ -> int 256)) ~port_in_valid:(Array.init 4 (fun _ -> bool ()))
      ~port_out_ready:(Array.init 4 (fun _ -> bool ())) ~flags:(int 0x10000) (int 256) in
  (st, io)

(* An effect whose enable is false carries whatever its other fields compute, which means
   nothing: compare effects with those fields cleared. *)
let norm (e : Isa2.Spec.effects) : Isa2.Spec.effects =
  let o (b, x) = if b then (true, x) else (false, 0) in
  let o2 (b, x, y) = if b then (true, x, y) else (false, 0, 0) in
  { e with host_out = o2 e.host_out; port_pop = o e.port_pop; port_push = o2 e.port_push; bank_write = o2 e.bank_write;
           bank_read = o e.bank_read; fine_out = o e.fine_out }

let exec_on st io w =
  let s = Isa2.copy st in
  let e = Isa2.Spec.exec s ~instr:w io in
  (s, norm e)

let differs rng ~word ~flip trials =
  let found = ref false and k = ref 0 in
  while not !found && !k < trials do
    let st, io = random_state rng ~word in
    let a = exec_on st io word and b = exec_on st io (word lxor flip) in
    if a <> b then found := true;
    incr k
  done;
  !found

(* ---- docs/isa.md: the encoding table ---- *)

let encoding_table isa =
  let rng = Random.State.make [| 42 |] in
  let rows = table isa "encoding" in
  let forms = ref [] in
  List.iter (function
      | [ opc; form; fields; ignored ] ->
        let opc = int_of_string ("0x" ^ opc) in
        forms := form :: !forms;
        let fs = List.map parse_field (words fields) in
        let ign = List.map parse_bits (words ignored) in
        (* coverage of bits 11..0 *)
        let cover = Array.make 12 0 in
        List.iter (fun f -> for b = f.lo to f.hi do cover.(b) <- cover.(b) + 1 done) fs;
        List.iter (fun (h, l) -> for b = l to h do cover.(b) <- cover.(b) + 1 done) ign;
        ok (Array.for_all (( = ) 1) cover) "%s: fields and ignored bits cover 11..0 exactly once (counts %s)" form
          (String.concat "" (Array.to_list (Array.map string_of_int cover)));
        (* opcode and fixed fields against Isa2 *)
        let op, sub = isa2_code form in
        ok (op = opc) "%s: opcode %X in the docs, %X in isa2.ml" form opc op;
        (match sub with
         | Some x -> ok (List.exists (fun f -> f.fname = "sub" && f.fixed = Some (x, x)) fs)
                       "%s: sub-operation in the docs is not isa2.ml's %d" form x
         | None -> ());
        let fixed_lo f = match f.fixed with Some (a, _) -> a | None -> 0 in
        let value_of name v = List.fold_left (fun acc f -> if f.fname = name then v else acc) 0 fs in
        let base_value name = match List.find_opt (fun f -> f.fname = name) fs with
          | Some f -> fixed_lo f | None -> 0 in
        let word_of overrides =
          Insn.encode (build form (fun n -> match List.assoc_opt n overrides with Some v -> v | None -> base_value n)) in
        let expected_base = (opc lsl 12) lor List.fold_left (fun acc f -> acc lor (fixed_lo f lsl f.lo)) 0 fs in
        let base = word_of [] in
        ok (base = expected_base) "%s: the word with every field 0 is %04x, the docs give %04x" form base expected_base;
        (* every named field: each bit lands where the docs say *)
        List.iter (fun f ->
            match f.fixed with
            | Some (a, b) when a <> b ->
              (* a range of fixed values (reserved sub-operations): each must encode there *)
              for v = a to b do
                let w = word_of [ (f.fname, v) ] in
                ok ((w lsr f.lo) land ((1 lsl (f.hi - f.lo + 1)) - 1) = v) "%s: %s=%d not at [%d:%d]" form f.fname v f.hi f.lo
              done
            | Some _ -> ()
            | None ->
              for k = 0 to f.hi - f.lo do
                let w = word_of [ (f.fname, 1 lsl k) ] in
                ok (w = base lor (1 lsl (f.lo + k))) "%s: %s bit %d encodes as %04x, the docs say bit %d (word %04x)" form f.fname k w (f.lo + k)
                  (base lor (1 lsl (f.lo + k)))
              done) fs;
        ignore value_of;
        (* semantics: ignored bits never matter; field bits do *)
        List.iter (fun (h, l) ->
            for b = l to h do
              let any = ref false in
              for _ = 1 to 20 do
                let fv = List.map (fun f -> match f.fixed with
                    | Some (a, c) -> (f.fname, a + Random.State.int rng (c - a + 1))
                    | None -> (f.fname, Random.State.int rng (1 lsl (f.hi - f.lo + 1)))) fs in
                let w = word_of fv in
                if differs rng ~word:w ~flip:(1 lsl b) 100 then any := true
              done;
              ok (not !any) "%s: ignored bit %d changes what the instruction does (isa2.ml)" form b
            done) ign;
        List.iter (fun f ->
            if f.fixed = None then
              for k = 0 to f.hi - f.lo do
                let any = ref false and tries = ref 0 in
                while not !any && !tries < 200 do
                  let fv = List.map (fun g -> match g.fixed with
                      | Some (a, c) -> (g.fname, a + Random.State.int rng (c - a + 1))
                      | None -> (g.fname, Random.State.int rng (1 lsl (g.hi - g.lo + 1)))) fs in
                  if differs rng ~word:(word_of fv) ~flip:(1 lsl (f.lo + k)) 20 then any := true;
                  incr tries
                done;
                ok !any "%s: field bit %s[%d] (word bit %d) never changed what the instruction does" form f.fname k (f.lo + k)
              done) fs
      | r -> fail "encoding table row with %d cells: %s" (List.length r) (String.concat "|" r)) rows;
  (* every opcode appears *)
  ok (List.length (List.sort_uniq compare (List.map (fun r -> List.hd r) rows)) = 16) "the encoding table lists all 16 opcodes";
  (* the reserved EXT sub-operations do nothing: like NOP *)
  let same = ref true in
  for sub = 8 to 15 do
    for _ = 1 to 200 do
      let w = Isa2.ext sub (Random.State.int rng 256) in
      let st, io = random_state rng ~word:w in
      let a = exec_on st io w and b = exec_on st io Isa2.nop in
      if fst a <> fst b then same := false
    done
  done;
  ok !same "EXT 8..15 leave the same state as NOP";
  Printf.printf "encoding table: %d rows (%d forms) compared with isa2.ml\n" (List.length rows) (List.length !forms)

(* ---- the WAITC and channel tables ---- *)

let expand_names cell_num cell_name =
  (* "0..7" with "acc0..acc7", or a single number and name *)
  match String.index_opt cell_num '.' with
  | Some i ->
    let a = int_of_string (String.sub cell_num 0 i) and b = int_of_string (String.sub cell_num (i + 2) (String.length cell_num - i - 2)) in
    let j = String.index cell_name '.' in
    let prefix_a = String.sub cell_name 0 j in
    let stem = String.sub prefix_a 0 (String.length prefix_a - 1) in
    let first = int_of_string (String.make 1 prefix_a.[String.length prefix_a - 1]) in
    List.init (b - a + 1) (fun k -> (a + k, Printf.sprintf "%s%d" stem (first + k)))
  | None -> [ (int_of_string cell_num, cell_name) ]

let waitc_table isa =
  let rows = table isa "waitc" in
  let pairs = List.concat_map (function [ n; name; _ ] -> expand_names n name | _ -> []) rows in
  ok (List.length pairs = 16) "the WAITC table lists 16 conditions";
  List.iter (fun (c, name) ->
      ok (List.assoc_opt name Insn.cond_names = Some c) "WAITC %s = %d in the docs, the assembler says %s" name c
        (match List.assoc_opt name Insn.cond_names with Some x -> string_of_int x | None -> "nothing")) pairs;
  ok (Isa2.c_byte = 8 && Isa2.c_host = 9 && Isa2.c_inbox = 10 && Isa2.c_space = 11 && Isa2.c_flag 0 = 12 && Isa2.c_flag 3 = 15
      && Isa2.c_acc 5 = 5) "WAITC constants in isa2.ml";
  (* each condition's meaning: build a state where it holds and one where it does not *)
  let run ~t ~cond ?(acc = 0) ?(cnt = 0) ?(host = false) ?(full = [||]) ?(lsend = 0) ?(ready = [||]) ?(flags = 0) () =
    let st = Isa2.init () in
    st.thread <- t; st.accs.(t) <- acc; st.cnts.(t) <- cnt; st.lsend.(t) <- lsend;
    Array.iteri (fun i f -> st.full.(i) <- f) full;
    let io = Isa2.io ~host_in_valid:host ~port_out_ready:(if ready = [||] then Array.make 4 false else ready) ~flags 0 in
    st.pcs.(t) <- 10;
    ignore (Isa2.Spec.exec st ~instr:(Isa2.waitc ~cond ~fail:99) io);
    st.pcs.(t) = 11 in   (* proceeded; else it jumped to 99 (dl = 0) *)
  for k = 0 to 7 do
    ok (run ~t:1 ~cond:k ~acc:(1 lsl k) () && not (run ~t:1 ~cond:k ~acc:(0xFF lxor (1 lsl k)) ())) "WAITC acc%d: bit %d of acc" k k
  done;
  ok (run ~t:0 ~cond:8 ~cnt:16 () && not (run ~t:0 ~cond:8 ~cnt:17 ())) "WAITC byte: cnt[2:0] = 0";
  ok (run ~t:2 ~cond:9 ~host:true () && not (run ~t:2 ~cond:9 ())) "WAITC host: a host byte waiting";
  ok (run ~t:2 ~cond:10 ~full:[| 0; 0; 1; 0 |] () && not (run ~t:2 ~cond:10 ~full:[| 1; 1; 0; 1 |] ())) "WAITC inbox: the thread's own inbox full";
  ok (run ~t:3 ~cond:11 ~lsend:2 ~full:[| 1; 1; 0; 1 |] () && not (run ~t:3 ~cond:11 ~lsend:2 ~full:[| 0; 0; 1; 0 |] ())
      && run ~t:3 ~cond:11 ~lsend:5 ~ready:[| false; true; false; false |] ()
      && not (run ~t:3 ~cond:11 ~lsend:5 ~ready:[| true; false; true; true |] ()))
    "WAITC space: inbox lsend empty, or port lsend - 4 ready";
  for t = 0 to 3 do
    for k = 0 to 3 do
      ok (run ~t ~cond:(12 + k) ~flags:(1 lsl ((4 * t) + k)) () && not (run ~t ~cond:(12 + k) ~flags:(0xFFFF lxor (1 lsl ((4 * t) + k))) ()))
        "WAITC flag%d on thread %d: chip flag input %d" k t ((4 * t) + k)
    done
  done;
  print_endline "WAITC table: names, numbers and meanings compared with isa2.ml"

let channel_table isa =
  let rows = table isa "channel" in
  let pairs = List.concat_map (function [ n; name; _ ] -> expand_names n name | _ -> []) rows in
  ok (List.length pairs = 8) "the channel table lists 8 channels";
  List.iter (fun (c, name) -> ok (List.assoc_opt name Insn.chan_names = Some c) "channel %s = %d in the docs" name c) pairs;
  (* SEND on 0..3 fills that inbox; on 4..7 pushes to port ch - 4 *)
  for ch = 0 to 7 do
    let st = Isa2.init () in
    st.accs.(0) <- 0x5C;
    let io = Isa2.io ~port_out_ready:(Array.make 4 true) 0 in
    let e = Isa2.step st ~mem:(Array.make 1024 (Isa2.send ~ch ~fail:0)) io in
    if ch < 4 then ok (st.full.(ch) = 1 && st.inbox.(ch) = 0x5C && e.port_push = None) "SEND inbox%d fills inbox %d" ch ch
    else ok (e.port_push = Some (ch - 4, 0x5C) && Array.for_all (( = ) 0) st.full) "SEND port%d pushes to port %d" (ch - 4) (ch - 4)
  done;
  print_endline "channel table: names and meanings compared with isa2.ml"

(* ---- the checked code blocks ---- *)

type block = { bfile : string; bline : int; text : string list }

let blocks file doc =
  let ls = Array.of_list (lines doc) in
  let out = ref [] and i = ref 0 in
  while !i < Array.length ls do
    if trim ls.(!i) = "```asm" then begin
      let start = !i + 1 in
      let j = ref start in
      while !j < Array.length ls && trim ls.(!j) <> "```" do incr j done;
      let text = Array.to_list (Array.sub ls start (!j - start)) in
      if List.exists (fun l -> String.starts_with ~prefix:"; expect:" (trim l)) text then
        out := { bfile = file; bline = start; text } :: !out;
      i := !j + 1
    end else incr i
  done;
  List.rev !out

let after prefix l = let l = trim l in String.sub l (String.length prefix) (String.length l - String.length prefix) |> trim

let ints_of s = List.filter_map (fun x -> let x = trim x in if x = "" then None else Some (int_of_string x)) (String.split_on_char ',' s)

let run_block (b : block) =
  let where = Printf.sprintf "%s:%d" b.bfile b.bline in
  let src = String.concat "\n" b.text in
  let has_thread = List.exists (fun l -> String.starts_with ~prefix:".thread" (trim l)) b.text in
  let wrapped = (if has_thread then "" else ".thread 0, start\n") ^ src
                ^ "\n.page 3\n__idle:\n    halt\n" ^ (if has_thread then "" else ".thread 1, __idle\n.thread 2, __idle\n.thread 3, __idle\n") in
  match Assembler.assemble_string ~include_dirs:[ "lib" ] ~name:where wrapped with
  | exception Loc.Error (l, m) -> fail "%s: does not assemble: %s" where (Loc.message l m)
  | r ->
    let pin_in = ref 0xFF and host = Queue.create () in
    List.iter (fun l ->
        if String.starts_with ~prefix:"; input:" (trim l) then
          List.iter (fun kv ->
              match String.split_on_char '=' (trim kv) with
              | [ k; v ] when String.starts_with ~prefix:"pin" k ->
                let p = int_of_string (String.sub k 3 (String.length k - 3)) in
                pin_in := if int_of_string v = 1 then !pin_in lor (1 lsl p) else !pin_in land lnot (1 lsl p)
              | [ "host"; v ] -> List.iter (fun x -> Queue.push x host) (ints_of v)
              | _ -> fail "%s: bad input %s" where kv) (String.split_on_char ' ' (after "; input:" l))) b.text;
    let expects = List.filter_map (fun l -> if String.starts_with ~prefix:"; expect:" (trim l) then Some (after "; expect:" l) else None) b.text in
    let slots = 250 in
    let bank = Array.make Isa2.bank_len 0 in
    let st = Isa2.init ~boot:(Image.boot r.image) ~bank () in
    let mem = Image.store r.image in
    let states = Array.make (slots + 1) (0, 0, 0, 0, 0) in
    let edges = Array.make 8 [] and outs = ref [] in
    for c = 0 to (4 * slots) + 3 do
      let t = st.thread in
      let s = c / 4 in
      if t = 0 && s <= slots then states.(s) <- (st.pcs.(0), st.accs.(0), st.cnts.(0), st.dls.(0), st.bps.(0));
      let before = st.pin_out in
      let io = Isa2.io ~host_in:(Option.value ~default:0 (Queue.peek_opt host)) ~host_in_valid:(not (Queue.is_empty host)) !pin_in in
      let e = Isa2.step st ~mem io in
      if e.host_in_ready then ignore (Queue.pop host);
      if t = 0 then begin
        for p = 0 to 7 do if (before lxor st.pin_out) land (1 lsl p) <> 0 then edges.(p) <- s :: edges.(p) done;
        match e.host_out with Some (tag, by) -> outs := (by, tag, s) :: !outs | None -> ()
      end
    done;
    List.iter (fun ex ->
        incr checks;
        let bad fmt = Printf.ksprintf (fun m -> incr failures; Printf.printf "FAIL %s: expect %s: %s\n" where ex m) fmt in
        if String.starts_with ~prefix:"pin" ex then begin
          (* pinP edges at slots A, B, ... *)
          let p = int_of_string (String.sub ex 3 1) in
          let i = try Str.search_forward (Str.regexp "at slots") ex 0 with Not_found -> -1 in
          let want = if i < 0 then [] else ints_of (String.sub ex (i + 8) (String.length ex - i - 8)) in
          let got = List.rev edges.(p) in
          if got <> want then bad "pin %d changes at slots %s" p (String.concat ", " (List.map string_of_int got))
        end
        else if String.starts_with ~prefix:"at slot" ex then begin
          let rest = after "at slot" ex in
          let k = String.index rest ':' in
          let s = int_of_string (trim (String.sub rest 0 k)) in
          let pc, acc, cnt, dl, bp = states.(s) in
          List.iter (fun kv ->
              match String.split_on_char '=' kv with
              | [ key; v ] ->
                let v = int_of_string v in
                let got = match key with "pc" -> pc | "acc" -> acc | "cnt" -> cnt | "dl" -> dl | "bp" -> bp | _ -> -1 in
                if got <> v then bad "%s is %d" key got
              | _ -> bad "malformed") (words (String.sub rest (k + 1) (String.length rest - k - 1)))
        end
        else if String.starts_with ~prefix:"out" ex then begin
          let items = String.split_on_char ',' (after "out" ex) in
          let want = List.map (fun it ->
              match words it with
              | [ bt; "at"; "slot"; s ] ->
                (match String.split_on_char '/' bt with
                 | [ by; tag ] -> (int_of_string by, int_of_string tag, int_of_string s)
                 | _ -> (-1, -1, -1))
              | _ -> (-1, -1, -1)) items in
          if List.rev !outs <> want then
            bad "OUTs %s" (String.concat ", " (List.map (fun (b, t, s) -> Printf.sprintf "0x%02x/%d at slot %d" b t s) (List.rev !outs)))
        end
        else bad "unknown expectation") expects

let code_blocks docs_dir =
  let n = ref 0 in
  List.iter (fun f ->
      let path = Filename.concat docs_dir f in
      if Sys.file_exists path then begin
        let bs = blocks f (read path) in
        n := !n + List.length bs;
        List.iter run_block bs
      end) [ "isa.md"; "assembly.md"; "architecture.md"; "configuration.md"; "host-link.md"; "tutorial.md" ];
  Printf.printf "checked code blocks: %d run on the interpreter\n" !n

(* ---- docs/configuration.md and docs/host-link.md ---- *)

let num s = int_of_string (trim s)

let register_table cfg =
  let rows = table cfg "register" in
  List.iter (function
      | [ addr; name; bits; reset; _ ] ->
        let addrs = match String.index_opt addr '.' with
          | Some i -> let a = num (String.sub addr 0 i) and b = num (String.sub addr (i + 2) (String.length addr - i - 2)) in List.init (b - a + 1) (( + ) a)
          | None -> [ num addr ] in
        List.iteri (fun k a ->
            let rw = Regs.rw_bits a in
            if bits = "r" || bits = "w" || bits = "none" then ok (rw = 0) "register %s (0x%02x): documented %s, regs.ml keeps %d bits" name a bits rw
            else begin
              let bs = List.map num (String.split_on_char ',' bits) in
              let want = if List.length bs = List.length addrs then List.nth bs k else List.hd bs in
              ok (rw = want) "register %s (0x%02x): documented %d bits, regs.ml keeps %d" name a want rw
            end;
            if reset <> "-" then begin
              let resets = List.map num (String.split_on_char ',' reset) in
              let want = if List.length resets = List.length addrs then List.nth resets k else List.hd resets in
              ok (Regs.reset_value a = want) "register %s (0x%02x): documented reset %d, regs.ml %d" name a want (Regs.reset_value a)
            end) addrs
      | r -> fail "register table row: %s" (String.concat "|" r)) rows;
  (* every stored register is in the table *)
  let documented = List.concat_map (function
      | addr :: _ -> (match String.index_opt addr '.' with
          | Some i -> let a = num (String.sub addr 0 i) and b = num (String.sub addr (i + 2) (String.length addr - i - 2)) in List.init (b - a + 1) (( + ) a)
          | None -> [ num addr ])
      | [] -> []) rows in
  List.iter (fun a -> ok (List.mem a documented) "register 0x%02x (stored by regs.ml) is not in the docs" a) Regs.rw_addresses;
  ok (List.mem Regs.r_ctrl documented && List.mem Regs.r_status documented && List.mem Regs.r_restart documented)
    "control, status and restart registers documented";
  ok (Regs.r_ctrl = 0 && Regs.r_status = 1 && Regs.r_hostin_count = 2 && Regs.r_hostout_count = 3 && Regs.r_restart = 9
      && Regs.r_restart_pc = 0x0A && Regs.r_port_reset = 0x0B && Regs.r_crc_start = 0x0C && Regs.r_crc_raw = 0x70 && Regs.r_match = 0x74
      && Regs.r_smp_overflows = 0x75) "status and pulse register addresses";
  Printf.printf "register table: %d rows compared with regs.ml\n" (List.length rows)

let code_table doc name (assembler : (string * int) list) (spec : string -> int option) =
  let rows = table doc name in
  let pairs = List.concat_map (function
      | n :: nm :: _ -> (try expand_names n nm with _ -> [ (num n, nm) ])
      | _ -> []) rows in
  List.iter (fun (c, nm) ->
      ok (List.assoc_opt nm assembler = Some c) "%s %s = %d in the docs, the assembler says %s" name nm c
        (match List.assoc_opt nm assembler with Some x -> string_of_int x | None -> "nothing");
      match spec nm with Some x -> ok (x = c) "%s %s = %d in the docs, regs.ml says %d" name nm c x | None -> ()) pairs;
  ok (List.length pairs = List.length assembler) "%s: the docs list %d codes, the assembler knows %d" name (List.length pairs) (List.length assembler);
  Printf.printf "%s table: %d codes compared\n" name (List.length pairs)

let pad_spec nm =
  let k () = Char.code nm.[String.length nm - 1] - 48 in
  if String.starts_with ~prefix:"seq" nm then Some (Regs.src_seq (k ()))
  else if String.starts_with ~prefix:"stream" nm then Some (Regs.src_stream (k ()))
  else if String.starts_with ~prefix:"tapflag" nm then Some (Regs.src_tap_flag (k ()))
  else if String.starts_with ~prefix:"tapbit" nm then Some (Regs.src_tap_bit0 (k ()))
  else match nm with
    | "nco_quarter" -> Some Regs.src_nco_quarter | "nco_half" -> Some Regs.src_nco_half
    | "nco_clock" -> Some Regs.src_nco_grid | "esbit" -> Some Regs.src_es_bit | _ -> None

let flag_spec nm =
  let k () = Char.code nm.[String.length nm - 1] - 48 in
  if String.starts_with ~prefix:"tapflag" nm then Some (Regs.fl_tap_flag (k ()))
  else if String.starts_with ~prefix:"tapvalid" nm then Some (Regs.fl_tap_valid (k ()))
  else match nm with
    | "es_valid" -> Some Regs.fl_es_valid | "es_bit" -> Some Regs.fl_es_bit | "es_burst" -> Some Regs.fl_es_in_burst
    | "es_burst_end" -> Some Regs.fl_es_burst_end | "crc_ok" -> Some Regs.fl_crc_check | "match" -> Some Regs.fl_match_hit
    | "stream_full" -> Some Regs.fl_stream_full | "sample_valid" -> Some Regs.fl_sample_valid | "nco" -> Some Regs.fl_nco
    | _ -> None

let pe_table cfg =
  let rows = table cfg "pe" in
  List.iter (function
      | [ key; bits; values; _ ] ->
        (match List.find_opt (fun (f : Config.pe_field) -> f.key = key) Config.pe_fields with
         | None -> fail "PE field %s is not a .pe field" key
         | Some fd ->
           if key = "k" then ok (bits = "K") "PE field k is K (bytes 0-1)"
           else begin
             let hi, lo = parse_bits bits in
             ok (hi - lo + 1 = fd.width) "PE field %s: %d bits in the docs, %d in the assembler" key (hi - lo + 1) fd.width;
             (* each bit lands in op word bit lo+k: bytes 2..7 are the op word *)
             for k = 0 to hi - lo do
               let b = Upe.Spec.bytes_of_op (fd.set Upe.Spec.nop (1 lsl k)) in
               let word = ref 0 in
               for j = 7 downto 2 do word := (!word lsl 8) lor b.(j) done;
               ok (!word = 1 lsl (lo + k)) "PE field %s bit %d: Upe.Spec puts it at op bit %d's word %x" key k (lo + k) !word
             done
           end;
           (* symbolic values *)
           let vals = List.filter_map (fun v -> match String.split_on_char '=' (trim v) with
               | [ n; x ] -> Some (trim n, num x) | _ -> None) (String.split_on_char ',' values) in
           ok (List.sort compare vals = List.sort compare fd.names) "PE field %s: values in the docs differ from the assembler's" key)
      | r -> fail "PE table row: %s" (String.concat "|" r)) rows;
  ok (List.length rows = List.length Config.pe_fields) "PE table: %d fields in the docs, %d in the assembler" (List.length rows) (List.length Config.pe_fields);
  Printf.printf "PE op table: %d fields compared with unified-pe/verify/spec.ml\n" (List.length rows)

let seg_table cfg =
  let rows = table cfg "segment" in
  List.iter (function
      | [ bits; name; _ ] ->
        let hi, lo = parse_bits bits in
        if name = "src" then ok (hi = 2 && lo = 0) "segment src at [2:0]"
        else ok (List.assoc_opt name Config.seg_flags = Some lo && hi = lo) "segment flag %s at bit %d" name lo
      | r -> fail "segment table row: %s" (String.concat "|" r)) rows;
  print_endline "segment control table compared"

let target_table hl =
  let rows = table hl "target" in
  let want = Regs.[ "REG", t_reg; "PROG", t_prog; "BANK", t_bank; "HOSTIN", t_hostin; "HOSTOUT", t_hostout; "PECFG", t_pecfg;
                    "PEINIT", t_peinit; "PESEG", t_peseg; "STREAM", t_stream; "SAMPLE", t_sample; "MATCH", t_match ] in
  List.iter (function
      | n :: name :: _ -> ok (List.assoc_opt name want = Some (num n)) "host-link target %s = %s in the docs" name n
      | _ -> ()) rows;
  ok (List.length rows = List.length want) "host-link targets: %d in the docs, %d in regs.ml" (List.length rows) (List.length want);
  let ops = table hl "op" in
  List.iter (function
      | n :: name :: _ -> ok ((name = "write" && num n = Regs.op_write) || (name = "read" && num n = Regs.op_read)) "host-link op %s = %s" name n
      | _ -> ()) ops;
  ok (Host.write_setup = 2 && Host.write_hold = 2 && Host.read_gap = 8 && Host.turnaround = 8)
    "host-link timing margins (Host: setup 2, hold 2, read gap 8, turnaround 8)";
  ok (Chip_spec.hostin_depth = 16 && Chip_spec.hostout_depth = 8) "FIFO depths: HOSTIN 16, HOSTOUT 8";
  print_endline "host-link tables compared with regs.ml and host.ml"

(* ---- controls: the test must notice a wrong doc ---- *)

let replace_once s a b =
  match Str.search_forward (Str.regexp_string a) s 0 with
  | i -> String.sub s 0 i ^ b ^ String.sub s (i + String.length a) (String.length s - i - String.length a)
  | exception Not_found -> failwith ("control: text not found: " ^ a)

let controls ~isa ~cfg ~hl =
  let quiet f =
    (* run [f] with stdout silenced; return how many failures it found *)
    let before = !failures and c = !checks in
    flush stdout;
    let saved = Unix.dup Unix.stdout in
    let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
    Unix.dup2 null Unix.stdout;
    (try f () with e -> incr failures; ignore e);
    flush stdout;
    Unix.dup2 saved Unix.stdout; Unix.close null; Unix.close saved;
    let found = !failures - before in
    failures := before; checks := c;
    found in
  let cases = [
    "SETP's val and oe swapped in the encoding table",
    (fun () -> encoding_table (replace_once isa "mask[11:4] val[3] oe[2] q[1:0]" "mask[11:4] val[2] oe[3] q[1:0]"));
    "SHI's quad bit listed as ignored",
    (fun () -> encoding_table (replace_once isa "| 8 | SHI | pin[11:9] msb[8] quad[7] | [6:0] |" "| 8 | SHI | pin[11:9] msb[8] | [7:0] |"));
    "BANK's reserved bits claimed as a field",
    (fun () -> encoding_table (replace_once isa "| F | BANK | sub[11:8]=6 imm[1:0] | [7:2] |" "| F | BANK | sub[11:8]=6 imm[2:0] | [7:3] |"));
    "WAITC 8 and 9 named the wrong way round",
    (fun () -> waitc_table (replace_once (replace_once isa "| 8 | byte |" "| 8 | hostx |") "| 9 | host |" "| 9 | byte |"));
    "an example's expected edge one slot late",
    (fun () -> List.iter run_block (blocks "isa.md" (replace_once isa "; expect: pin0 edges at slots 0, 8" "; expect: pin0 edges at slots 0, 9")));
    "an example's expected accumulator wrong",
    (fun () -> List.iter run_block (blocks "isa.md" (replace_once isa "; expect: at slot 10: acc=0x22" "; expect: at slot 10: acc=0x11")));
    "the control register's reset value wrong",
    (fun () -> register_table (replace_once cfg "| 0x00 | control | 2 | 2 |" "| 0x00 | control | 2 | 3 |"));
    "a PE field one bit off",
    (fun () -> pe_table (replace_once cfg "| x | [1:0] |" "| x | [2:1] |"));
    "a pad source code wrong",
    (fun () -> code_table (replace_once cfg "| 24 | esbit |" "| 25 | esbit |") "pad source" Config.pad_sources pad_spec);
    "a host-link target number wrong",
    (fun () -> target_table (replace_once hl "| 5 | PECFG |" "| 6 | PECFG |"));
  ] in
  List.iter (fun (name, f) ->
      let n = quiet f in
      incr checks;
      if n = 0 then (incr failures; Printf.printf "FAIL control not caught: %s\n" name)
      else Printf.printf "control caught (%d failure%s): %s\n" n (if n = 1 then "" else "s") name) cases

let () =
  let docs = try Sys.argv.(1) with _ -> "../../docs" in
  let path f = Filename.concat docs f in
  let isa = read (path "isa.md") in
  encoding_table isa;
  waitc_table isa;
  channel_table isa;
  if Sys.file_exists (path "configuration.md") then begin
    let cfg = read (path "configuration.md") in
    register_table cfg;
    code_table cfg "pad source" Config.pad_sources pad_spec;
    code_table cfg "flag source" Config.flag_sources flag_spec;
    pe_table cfg;
    seg_table cfg
  end else fail "docs/configuration.md missing";
  if Sys.file_exists (path "host-link.md") then target_table (read (path "host-link.md"))
  else fail "docs/host-link.md missing";
  code_blocks docs;
  if Sys.file_exists (path "configuration.md") && Sys.file_exists (path "host-link.md") then
    controls ~isa ~cfg:(read (path "configuration.md")) ~hl:(read (path "host-link.md"));
  Printf.printf "%d checks\n" !checks;
  if !failures = 0 then print_endline "DOCS DRIFT: NONE"
  else (Printf.printf "DOCS DRIFT: %d FAILURES\n" !failures; exit 1)
