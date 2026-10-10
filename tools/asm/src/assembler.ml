(* The assembler: source text -> loaded state (Image.t) -> host-link image.

   Pass 1 reads the source line by line: it expands .include, .macro, .rep and .if, assigns every
   instruction its (page, pc) (every instruction is one word), defines labels and constants, and
   records the expanded statements. Constants, .org, .rep counts and .if conditions must be known
   when they are reached. Pass 2 evaluates every operand (labels may be used before they are
   defined), encodes instructions through Isa2's encoders (Insn), and collects the configuration
   directives and the .timing blocks. *)

open Syntax

type sym = Const of int | Label of int * int   (* page, pc *)

type macro = { params : (string * string option) list; body : (Loc.t * string) list; mloc : Loc.t }

type item =
  | Word of { loc : Loc.t; page : int; pc : int; mnem : string; args : arg list; src : string }
  | Dir of { loc : Loc.t; page : int; pc : int; name : string; args : arg list }

type timing = {
  tloc : Loc.t;
  thread : int;
  mutable lines : (Loc.t * string * arg list) list;   (* reversed *)
}

type ctx = {
  syms : (string, sym * Loc.t) Hashtbl.t;
  macros : (string, macro) Hashtbl.t;
  mutable page : int;
  page_pc : int array;                       (* the fill pointer of each page *)
  mutable items : item list;                 (* reversed *)
  mutable uniq : int;
  include_dirs : string list;
  mutable timings : timing list;             (* reversed *)
  mutable in_timing : timing option;
  mutable depth : int;                       (* include and macro nesting, against runaway recursion *)
}

let config_directives =
  [ ".thread"; ".layout"; ".pad"; ".pinin"; ".flag"; ".streamer"; ".sampler"; ".sampler_pins";
    ".edge_sampler"; ".crc"; ".nco"; ".matcher"; ".reg"; ".bankdata"; ".pe"; ".pebytes"; ".peinit";
    ".pecfg"; ".seg"; ".segreg"; ".hostin"; ".stream"; ".run"; ".stop"; ".ctrl" ]
let timing_directives = [ ".channel"; ".bytes"; ".expect"; ".state"; ".from" ]

let create ?(include_dirs = []) () =
  { syms = Hashtbl.create 64; macros = Hashtbl.create 16; page = 0; page_pc = Array.make 4 0; items = [];
    uniq = 0; include_dirs; timings = []; in_timing = None; depth = 0 }

let env ctx ~here : Expr.env =
  { lookup = (fun s -> match Hashtbl.find_opt ctx.syms s with
        | Some (Const v, _) -> Some v | Some (Label (_, pc), _) -> Some pc | None -> None);
    label = (fun s -> match Hashtbl.find_opt ctx.syms s with Some (Label (p, c), _) -> Some (p, c) | _ -> None);
    here = (fun () -> here) }

let eval_toks ctx loc ~here toks = Expr.eval loc (env ctx ~here) (Expr.parse loc toks)

let define ctx loc name v =
  (match Hashtbl.find_opt ctx.syms name with
   | Some (_, l) -> Loc.error loc "%s is already defined at %s" name (Loc.to_string l)
   | None -> ());
  if List.mem name Insn.mnemonics then Loc.error loc "%s is a mnemonic and cannot be a symbol" name;
  Hashtbl.replace ctx.syms name (v, loc)

let here ctx = ctx.page_pc.(ctx.page)

(* ---- text substitution for macros and .rep ---- *)

let substitute _loc (subst : (string * string) list) ~uniq text =
  let b = Buffer.create (String.length text) in
  let n = String.length text in
  let i = ref 0 in
  while !i < n do
    if text.[!i] = '\\' && !i + 1 < n then begin
      if text.[!i + 1] = '@' then (Buffer.add_string b (string_of_int uniq); i := !i + 2)
      else if text.[!i + 1] = '(' && !i + 2 < n && text.[!i + 2] = ')' then i := !i + 3
      else begin
        let j = ref (!i + 1) in
        while !j < n && Lexer.is_ident_char text.[!j] do incr j done;
        let name = String.sub text (!i + 1) (!j - !i - 1) in
        match List.assoc_opt name subst with
        | Some v -> Buffer.add_string b v; i := !j
        | None -> Buffer.add_char b '\\'; i := !i + 1   (* an inner block's parameter, or an error the lexer reports *)
      end
    end
    else (Buffer.add_char b text.[!i]; incr i)
  done;
  Buffer.contents b

let with_chain (outer : Loc.t) what (l : Loc.t) = { l with chain = l.chain @ [ (what, outer.file, outer.line) ] @ outer.chain }

(* ---- block structure ---- *)

(* the index of the line that closes the block opened at [start], counting nested openers *)
let find_close lines start ~opens ~close =
  let n = Array.length lines in
  let rec go i depth =
    if i >= n then Loc.error (fst lines.(start)) "%s without %s" (List.hd opens) close
    else
      let h, _ = Syntax.head (snd lines.(i)) in
      if List.mem h opens then go (i + 1) (depth + 1)
      else if h = close then (if depth = 0 then i else go (i + 1) (depth - 1))
      else go (i + 1) depth in
  go (start + 1) 0

let has_label text =
  let h, _ = Syntax.head text in
  let t = String.trim (Lexer.strip_comment text) in
  not (String.length t >= String.length h && String.sub t 0 (String.length h) = h)

let read_file loc path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic; s
  with Sys_error e -> Loc.error loc "cannot read %s: %s" path e

let lines_of_string file s =
  Array.of_list (List.mapi (fun i l -> ({ Loc.file; line = i + 1; chain = [] }, l)) (String.split_on_char '\n' s))

let rec process ctx (lines : (Loc.t * string) array) =
  let n = Array.length lines in
  let i = ref 0 in
  while !i < n do
    let loc, text = lines.(!i) in
    let h, rest = Syntax.head text in
    let block_check () = if has_label text then Loc.error loc "put labels on their own line before %s" h in
    match h with
    | ".macro" ->
      block_check ();
      let close = find_close lines !i ~opens:[ ".macro" ] ~close:".endm" in
      let toks = Lexer.tokens loc rest in
      (match Syntax.split_commas toks with
       | (Lexer.Ident name :: first) :: others ->
         let params = List.map (fun p -> match p with
             | [ Lexer.Ident p ] -> (p, None)
             | Lexer.Ident p :: Lexer.Op "=" :: d -> (p, Some (Syntax.toks_to_string d))
             | _ -> Loc.error loc "macro parameters are names, optionally name=default")
             ((if first = [] then [] else [ first ]) @ others) in
         if Hashtbl.mem ctx.macros name then Loc.error loc "macro %s defined twice" name;
         if List.mem name Insn.mnemonics then Loc.error loc "macro %s would hide the instruction" name;
         Hashtbl.replace ctx.macros name
           { params; body = Array.to_list (Array.sub lines (!i + 1) (close - !i - 1)); mloc = loc }
       | _ -> Loc.error loc ".macro NAME [param, ...]");
      i := close + 1
    | ".rep" ->
      block_check ();
      let close = find_close lines !i ~opens:[ ".rep" ] ~close:".endr" in
      let toks = Lexer.tokens loc rest in
      let count, var = match Syntax.split_commas toks with
        | [ c ] -> (c, None)
        | [ c; [ Lexer.Ident v ] ] -> (c, Some v)
        | _ -> Loc.error loc ".rep COUNT [, VAR]" in
      let count = eval_toks ctx loc ~here:(here ctx) count in
      if count < 0 || count > 100_000 then Loc.error loc ".rep count %d out of range" count;
      let body = Array.sub lines (!i + 1) (close - !i - 1) in
      for k = 0 to count - 1 do
        ctx.uniq <- ctx.uniq + 1;
        let u = ctx.uniq in
        let subst = match var with Some v -> [ (v, string_of_int k) ] | None -> [] in
        process ctx (Array.map (fun (l, t) ->
            let l' = with_chain loc (Printf.sprintf ".rep iteration %d" k) l in
            (l', substitute l' subst ~uniq:u t)) body)
      done;
      i := close + 1
    | ".if" ->
      block_check ();
      let close = find_close lines !i ~opens:[ ".if" ] ~close:".endif" in
      (* the branches: .if, then each .elif/.else at depth 0 *)
      let rec split j depth start cond acc =
        if j = close then List.rev ((cond, start, j) :: acc)
        else
          let h', rest' = Syntax.head (snd lines.(j)) in
          if h' = ".if" then split (j + 1) (depth + 1) start cond acc
          else if h' = ".endif" then split (j + 1) (depth - 1) start cond acc
          else if depth = 0 && (h' = ".elif" || h' = ".else") then
            split (j + 1) depth (j + 1) (if h' = ".else" then None else Some (fst lines.(j), rest')) ((cond, start, j) :: acc)
          else split (j + 1) depth start cond acc in
      let branches = split (!i + 1) 0 (!i + 1) (Some (loc, rest)) [] in
      let truth = function
        | None -> true
        | Some (l, r) -> eval_toks ctx l ~here:(here ctx) (Lexer.tokens l r) <> 0 in
      (match List.find_opt (fun (c, _, _) -> truth c) branches with
       | Some (_, a, b) -> process ctx (Array.sub lines a (b - a))
       | None -> ());
      i := close + 1
    | ".endm" | ".endr" | ".endif" | ".else" | ".elif" -> Loc.error loc "%s without its opening directive" h
    | ".include" ->
      block_check ();
      (match Lexer.tokens loc rest with
       | [ Lexer.Str f ] ->
         let cands = (if Filename.is_relative f then Filename.concat (Filename.dirname loc.file) f else f)
                     :: List.map (fun d -> Filename.concat d f) ctx.include_dirs in
         let path = match List.find_opt Sys.file_exists cands with
           | Some p -> p | None -> Loc.error loc "include file %S not found (searched %s)" f (String.concat ", " cands) in
         ctx.depth <- ctx.depth + 1;
         if ctx.depth > 50 then Loc.error loc "includes nested more than 50 deep";
         let sub = lines_of_string path (read_file loc path) in
         process ctx (Array.map (fun ((l : Loc.t), t) -> ({ l with chain = l.chain @ [ ("include", loc.Loc.file, loc.Loc.line) ] @ loc.Loc.chain }, t)) sub);
         ctx.depth <- ctx.depth - 1
       | _ -> Loc.error loc ".include \"FILE\"");
      incr i
    | _ -> statement ctx loc text; incr i
  done

and statement ctx loc text =
  let { labels; stmt } = Syntax.parse loc text in
  List.iter (fun l ->
      if ctx.in_timing <> None then Loc.error loc "labels are not allowed inside .timing";
      define ctx loc l (Label (ctx.page, here ctx))) labels;
  match stmt with
  | Empty -> ()
  | Assign (name, toks) -> define ctx loc name (Const (eval_toks ctx loc ~here:(here ctx) toks))
  | Call (name, args) ->
    (match ctx.in_timing with
     | Some t when name <> ".endtiming" ->
       if List.mem name timing_directives then t.lines <- (loc, name, args) :: t.lines
       else if Hashtbl.mem ctx.macros name then call_macro ctx loc name args
       else Loc.error loc "%s inside .timing (expected one of %s, or .endtiming)" name (String.concat " " timing_directives)
     | _ ->
       if Hashtbl.mem ctx.macros name then call_macro ctx loc name args
       else if List.mem name Insn.mnemonics then emit_word ctx loc name args text
       else
         match name, args with
         | (".equ" | ".set"), [ Pos [ Lexer.Ident n ]; Pos e ] -> define ctx loc n (Const (eval_toks ctx loc ~here:(here ctx) e))
         | (".equ" | ".set"), _ -> Loc.error loc "%s NAME, VALUE" name
         | ".page", [ Pos e ] ->
           let p = eval_toks ctx loc ~here:(here ctx) e in
           if p < 0 || p > 3 then Loc.error loc "page %d out of range 0..3" p;
           ctx.page <- p
         | ".org", [ Pos e ] ->
           let a = eval_toks ctx loc ~here:(here ctx) e in
           if a < 0 || a > 255 then Loc.error loc ".org %d out of range 0..255 (an address within the page)" a;
           ctx.page_pc.(ctx.page) <- a
         | ".word", (_ :: _) -> List.iter (fun a -> emit_word ctx loc ".word" [ a ] text) args
         | ".timing", [ Pos e ] ->
           if ctx.in_timing <> None then Loc.error loc ".timing inside .timing";
           let th = eval_toks ctx loc ~here:(here ctx) e in
           if th < 0 || th > 3 then Loc.error loc "thread %d out of range 0..3" th;
           let t = { tloc = loc; thread = th; lines = [] } in
           ctx.in_timing <- Some t; ctx.timings <- t :: ctx.timings
         | ".endtiming", [] ->
           if ctx.in_timing = None then Loc.error loc ".endtiming without .timing";
           ctx.in_timing <- None
         | n, _ when List.mem n config_directives ->
           ctx.items <- Dir { loc; page = ctx.page; pc = here ctx; name = n; args } :: ctx.items
         | n, _ when n.[0] = '.' -> Loc.error loc "unknown directive %s" n
         | n, _ -> Loc.error loc "unknown instruction or macro %s" n)

and emit_word ctx loc mnem args text =
  let pc = here ctx in
  if pc > 255 then Loc.error loc "page %d is full (256 words); use .page or .org" ctx.page;
  ctx.items <- Word { loc; page = ctx.page; pc; mnem; args; src = String.trim (Lexer.strip_comment text) } :: ctx.items;
  ctx.page_pc.(ctx.page) <- pc + 1

and call_macro ctx loc name args =
  let m = Hashtbl.find ctx.macros name in
  let pos = List.filter_map (function Pos t -> Some (Syntax.toks_to_string t) | Kw _ -> None) args in
  let kws = List.filter_map (function Kw (k, t) -> Some (k, Syntax.toks_to_string t) | Pos _ -> None) args in
  if List.length pos > List.length m.params then
    Loc.error loc "macro %s takes %d arguments, given %d" name (List.length m.params) (List.length pos);
  List.iter (fun (k, _) -> if not (List.mem_assoc k m.params) then Loc.error loc "macro %s has no parameter %s" name k) kws;
  let subst = List.mapi (fun i (p, def) ->
      let v = match List.nth_opt pos i, List.assoc_opt p kws, def with
        | Some v, _, _ | None, Some v, _ | None, None, Some v -> v
        | None, None, None -> Loc.error loc "macro %s: missing argument %s" name p in
      (p, v)) m.params in
  ctx.depth <- ctx.depth + 1;
  if ctx.depth > 100 then Loc.error loc "macros nested more than 100 deep (recursive macro?)";
  ctx.uniq <- ctx.uniq + 1;
  let u = ctx.uniq in
  process ctx (Array.of_list (List.map (fun (l, t) ->
      let l' = with_chain loc ("macro " ^ name) l in
      (l', substitute l' subst ~uniq:u t)) m.body));
  ctx.depth <- ctx.depth - 1

(* ---- pass 2: operands ---- *)

let pos_args = List.filter_map (function Pos t -> Some t | Kw _ -> None)
let kw_args = List.filter_map (function Kw (k, t) -> Some (k, t) | Pos _ -> None)

let check_kws loc allowed args =
  List.iter (fun (k, _) -> if not (List.mem k allowed) then
                Loc.error loc "unknown keyword %s= (allowed: %s)" k (if allowed = [] then "none" else String.concat ", " allowed))
    (kw_args args)

let range loc what lo hi v = if v < lo || v > hi then Loc.error loc "%s %d out of range %d..%d" what v lo hi; v

let num ctx loc ~here what lo hi toks = range loc what lo hi (eval_toks ctx loc ~here toks)

(* a branch or fail target: a label on the same page, '.', or a number 0..255 *)
let target ctx loc ~page ~here toks =
  (match toks with
   | [ Lexer.Ident l ] when l <> "." ->
     (match Hashtbl.find_opt ctx.syms l with
      | Some (Label (p, _), _) when p <> page ->
        Loc.error loc "label %s is on page %d; jumps and fail targets stay within the page (%d)" l p page
      | _ -> ())
   | _ -> ());
  num ctx loc ~here "target" 0 255 toks

let named loc what names toks ~num:n =
  match toks with
  | [ Lexer.Ident s ] when List.mem_assoc s names -> List.assoc s names
  | [ Lexer.Ident s ] when not (List.mem s [ "." ]) && n = None ->
    Loc.error loc "unknown %s %s (one of %s)" what s (String.concat " " (List.map fst names))
  | _ -> (match n with Some f -> f toks | None -> Loc.error loc "expected a %s name" what)

let flags loc allowed (l : Lexer.tok list list) =
  List.map (function
      | [ Lexer.Ident f ] when List.mem f allowed -> f
      | t -> Loc.error loc "expected one of %s, found %s" (String.concat ", " allowed) (Syntax.toks_to_string t)) l

let encode_word ctx loc ~page ~pc mnem args : int =
  let here = pc in
  let n what lo hi t = num ctx loc ~here what lo hi t in
  let tgt t = target ctx loc ~page ~here t in
  let p = pos_args args in
  let nargs k = if List.length p <> k then Loc.error loc "%s takes %d operand%s, given %d" mnem k (if k = 1 then "" else "s") (List.length p) in
  let q () = match List.assoc_opt "q" (kw_args args) with Some t -> n "q" 0 3 t | None -> 0 in
  let ins (i : Insn.t) = Insn.encode i in
  let fail_of = function [] -> here | [ f ] -> tgt f | _ -> Loc.error loc "too many operands" in
  match mnem with
  | ".word" -> check_kws loc [] args; (match p with [ e ] -> n "word" (-32768) 0xFFFF e land 0xFFFF | _ -> assert false)
  | "nop" -> check_kws loc [] args; nargs 0; ins Nop
  | "setp" ->
    check_kws loc [ "q" ] args; nargs 3;
    (match p with [ m; v; o ] -> ins (Setp { mask = n "mask" 0 255 m; v = n "level" 0 1 v; oe = n "oe" 0 1 o; q = q () })
                | _ -> assert false)
  | "ldc" | "ldd" -> check_kws loc [] args; nargs 1;
    let v = n (mnem ^ " count") 0 4095 (List.hd p) in ins (if mnem = "ldc" then Ldc v else Ldd v)
  | "lda" -> check_kws loc [] args; nargs 1; ins (Lda (n "byte" (-128) 255 (List.hd p) land 0xFF))
  | "waitp" ->
    check_kws loc [] args;
    (match p with
     | pin :: v :: f when List.length f <= 1 -> ins (Waitp { pin = n "pin" 0 7 pin; v = n "level" 0 1 v; fail = fail_of f })
     | _ -> Loc.error loc "waitp PIN, LEVEL [, FAIL]")
  | "waitd" -> check_kws loc [] args; nargs 0; ins Waitd
  | "sho" ->
    check_kws loc [ "q" ] args;
    (match p with
     | pin :: dir :: fl ->
       let msb = match dir with [ Lexer.Ident "msb" ] -> true | [ Lexer.Ident "lsb" ] -> false
                              | _ -> Loc.error loc "sho PIN, msb|lsb [, od] [, pair] [, psel] [, cap] [, q=Q]" in
       let fl = flags loc [ "od"; "pair"; "psel"; "cap" ] fl in
       let has f = List.mem f fl in
       if has "psel" && not (has "pair") then Loc.warn loc "psel without pair has no effect";
       ins (Sho { pin = n "pin" 0 7 pin; msb; od = has "od"; pair = has "pair"; psel = has "psel"; cap = has "cap"; q = q () })
     | _ -> Loc.error loc "sho PIN, msb|lsb [, od] [, pair] [, psel] [, cap] [, q=Q]")
  | "shi" ->
    check_kws loc [] args;
    (match p with
     | pin :: dir :: fl ->
       let msb = match dir with [ Lexer.Ident "msb" ] -> true | [ Lexer.Ident "lsb" ] -> false
                              | _ -> Loc.error loc "shi PIN, msb|lsb [, quad]" in
       let fl = flags loc [ "quad" ] fl in
       ins (Shi { pin = n "pin" 0 7 pin; msb; quad = List.mem "quad" fl })
     | _ -> Loc.error loc "shi PIN, msb|lsb [, quad]")
  | "jmp" | "jnz" -> check_kws loc [] args; nargs 1;
    let a = tgt (List.hd p) in ins (if mnem = "jmp" then Jmp a else Jnz a)
  | "halt" -> check_kws loc [] args; nargs 0; ins (Jmp here)
  | "out" -> check_kws loc [ "tag" ] args; nargs 0;
    ins (Out { tag = (match List.assoc_opt "tag" (kw_args args) with Some t -> n "tag" 0 7 t | None -> 0) })
  | "outi" -> check_kws loc [ "tag" ] args; nargs 1;
    ins (Outi { v = n "byte" (-128) 255 (List.hd p) land 0xFF;
                tag = (match List.assoc_opt "tag" (kw_args args) with Some t -> n "tag" 0 7 t | None -> 0) })
  | "in" -> check_kws loc [] args; nargs 0; ins In
  | "send" | "recv" ->
    check_kws loc [] args;
    (match p with
     | ch :: f when List.length f <= 1 ->
       let ch = named loc "channel" Insn.chan_names ch ~num:(Some (n "channel" 0 7)) in
       ins (if mnem = "send" then Send { ch; fail = fail_of f } else Recv { ch; fail = fail_of f })
     | _ -> Loc.error loc "%s CHANNEL [, FAIL]" mnem)
  | "waitc" ->
    check_kws loc [] args;
    (match p with
     | c :: f when List.length f <= 1 ->
       ins (Waitc { cond = named loc "condition" Insn.cond_names c ~num:(Some (n "condition" 0 15)); fail = fail_of f })
     | _ -> Loc.error loc "waitc CONDITION [, FAIL]")
  | "skne" | "skeq" | "fine" | "bank" | "cfg" ->
    check_kws loc [] args; nargs 1;
    ins (Ext { sub = List.assoc mnem Insn.ext_names; imm = n "immediate" (-128) 255 (List.hd p) land 0xFF })
  | "cnta" | "ldb" | "stb" -> check_kws loc [] args; nargs 0; ins (Ext { sub = List.assoc mnem Insn.ext_names; imm = 0 })
  | "ext" -> check_kws loc [] args; nargs 2;
    (match p with [ s; i ] -> ins (Ext { sub = n "sub-operation" 0 15 s; imm = n "immediate" 0 255 i }) | _ -> assert false)
  | m -> Loc.error loc "unknown instruction %s" m

(* ---- pass 2: configuration ---- *)

type cfg = {
  regs : (int, int * Loc.t) Hashtbl.t;
  bank : (int, int * Loc.t) Hashtbl.t;
  threads : (int * int * Loc.t) option array;
  mutable layout : int array;
  pe : (int * int, int array * Loc.t) Hashtbl.t;       (* (segment, index) -> 8 bytes *)
  pe_raw : int list array;                             (* .pecfg: raw chain bytes per segment *)
  peinit : (int * int, int * Loc.t) Hashtbl.t;
  segregs : (int * int, int * Loc.t) Hashtbl.t;        (* (segment, register) -> byte *)
  mutable matcher : int list;
  mutable hostin : int list;
  mutable stream : int list;
  mutable ctrl : (int * Loc.t) option;
}

let set_reg c loc a v =
  if a = Regs.r_ctrl then Loc.error loc "the control register is set by .run/.stop/.ctrl";
  if a < 0 || a >= 0x10000 then Loc.error loc "register address %d out of range" a;
  (match Hashtbl.find_opt c.regs a with
   | Some (_, l) -> Loc.error loc "register 0x%02x is already set at %s" a (Loc.to_string l)
   | None -> ());
  Hashtbl.replace c.regs a (v land 0xFF, loc)

let set_regs c loc a0 vs = List.iteri (fun k v -> set_reg c loc (a0 + k) v) vs

let byte_list ctx loc ~here (toks : Lexer.tok list list) =
  List.concat_map (function
      | [ Lexer.Str s ] -> List.init (String.length s) (fun i -> Char.code s.[i])
      | t -> [ num ctx loc ~here "byte" (-128) 255 t land 0xFF ]) toks

let directive ctx c loc ~page ~here name args =
  let n what lo hi t = num ctx loc ~here what lo hi t in
  let p = pos_args args and kws = kw_args args in
  let kw k = List.assoc_opt k kws in
  let kwn k what lo hi ~default = match kw k with Some t -> n what lo hi t | None -> default in
  let req k what lo hi = match kw k with Some t -> n what lo hi t | None -> Loc.error loc "%s needs %s=" name k in
  let fl allowed = flags loc allowed in
  match name with
  | ".thread" ->
    check_kws loc [ "page"; "pc" ] args;
    let th, pg, pc = match p, kw "page", kw "pc" with
      | [ t; [ Lexer.Ident l ] ], None, None when (match Hashtbl.find_opt ctx.syms l with Some (Label _, _) -> true | _ -> false) ->
        (match Hashtbl.find ctx.syms l with (Label (pg, pc), _) -> (n "thread" 0 3 t, pg, pc) | _ -> assert false)
      | [ t ], Some pg, Some pc -> (n "thread" 0 3 t, n "page" 0 3 pg, n "pc" 0 255 pc)
      | _ -> Loc.error loc ".thread T, LABEL  or  .thread T, page=P, pc=ADDRESS" in
    (match c.threads.(th) with Some (_, _, l) -> Loc.error loc "thread %d already declared at %s" th (Loc.to_string l) | None -> ());
    c.threads.(th) <- Some (pg, pc, loc)
  | ".layout" ->
    check_kws loc [] args;
    if List.length p <> 4 then Loc.error loc ".layout A, B, C, D: the PEs in each of the four segments";
    c.layout <- Array.of_list (List.map (n "segment size" 1 16) p)
  | ".pad" ->
    check_kws loc [ "undriven"; "src" ] args;
    (match p with
     | pad :: rest ->
       let pad = n "pad" 0 15 pad in
       if not (List.mem pad Regs.general_out_pads) then
         Loc.error loc "pad %d is not a general output pad (0-7, 14, 15)" pad;
       let src, rest = match rest, kw "src" with
         | s :: r, None -> (named loc "pad source" Config.pad_sources s ~num:None, r)
         | r, Some s -> (n "source" 0 31 s, r)
         | [], None -> Loc.error loc ".pad PAD, SOURCE [, invert] [, undriven=LEVEL]" in
       let inv = List.mem "invert" (fl [ "invert" ] rest) in
       set_reg c loc (Regs.r_padsel pad) (src lor (Config.b2i inv lsl 5) lor (kwn "undriven" "level" 0 1 ~default:0 lsl 6))
     | [] -> Loc.error loc ".pad PAD, SOURCE [, invert] [, undriven=LEVEL]")
  | ".pinin" ->
    check_kws loc [] args;
    (match p with [ k; pad ] -> set_reg c loc (Regs.r_pinin (n "logical pin" 0 7 k)) (n "input pad" 0 15 pad)
                | _ -> Loc.error loc ".pinin LOGICAL_PIN, INPUT_PAD")
  | ".flag" ->
    check_kws loc [] args;
    (match p with
     | [ t; k; s ] ->
       let src = named loc "flag source" Config.flag_sources s ~num:(Some (n "flag source" 0 31)) in
       set_reg c loc (Regs.r_flagsel ((4 * n "thread" 0 3 t) + n "flag" 0 3 k)) src
     | _ -> Loc.error loc ".flag THREAD, K, SOURCE")
  | ".streamer" ->
    check_kws loc [ "period"; "width"; "od"; "idle"; "idle_oe" ] args;
    let width = req "width" "width" 1 4 in
    if not (List.mem width [ 1; 2; 4 ]) then Loc.error loc "streamer width %d: must be 1, 2 or 4" width;
    set_regs c loc Regs.r_str_per
      (Config.streamer ~period:(req "period" "period" 1 4095) ~width ~od:(kwn "od" "mask" 0 15 ~default:0)
         ~idle:(kwn "idle" "mask" 0 15 ~default:0) ~idle_oe:(kwn "idle_oe" "mask" 0 15 ~default:0))
  | ".sampler" ->
    check_kws loc [ "period"; "width"; "offset"; "trigger"; "trigger_level"; "frame" ] args;
    let fls = fl [ "clocked" ] p in
    let width = req "width" "width" 1 4 in
    if not (List.mem width [ 1; 2; 4 ]) then Loc.error loc "sampler width %d: must be 1, 2 or 4" width;
    let s = Config.sampler ~period:(req "period" "period" 1 4095) ~width ~clocked:(List.mem "clocked" fls)
        ~offset:(kwn "offset" "offset" 0 4095 ~default:0) ~trig_pin:(kwn "trigger" "trigger pin" 0 3 ~default:0)
        ~trig_val:(kwn "trigger_level" "level" 0 1 ~default:0) ~frame:(kwn "frame" "frame length" 0 255 ~default:0) in
    List.iteri (fun k a -> set_reg c loc a (List.nth s k)) Config.sampler_regs
  | ".sampler_pins" ->
    check_kws loc [] args;
    (match p with
     | [ a; b; d; e ] -> set_regs c loc (Regs.r_smp_pin 0) (List.map (n "input pad" 0 15) [ a; b; d; e ] @ [ 0 ])
     | [ a; b; d; e; [ Lexer.Ident "recovered" ] ] -> set_regs c loc (Regs.r_smp_pin 0) (List.map (n "input pad" 0 15) [ a; b; d; e ] @ [ 1 ])
     | _ -> Loc.error loc ".sampler_pins PAD0, PAD1, PAD2, PAD3 [, recovered]")
  | ".edge_sampler" ->
    check_kws loc [ "mode"; "pad"; "active"; "holdoff"; "timeout"; "offset"; "period" ] args;
    let fls = fl [ "invert" ] p in
    let mode = match kw "mode" with Some t -> named loc "mode" Config.es_modes t ~num:None | None -> Loc.error loc ".edge_sampler needs mode=" in
    let es = Config.edge_sampler ~mode ~invert:(List.mem "invert" fls) ~use_active:(kw "active" <> None)
        ~pad:(req "pad" "pad" 0 15) ~active:(kwn "active" "pad" 0 15 ~default:0) ~holdoff:(kwn "holdoff" "holdoff" 0 1023 ~default:0)
        ~timeout:(kwn "timeout" "timeout" 0 1023 ~default:0) ~offset:(kwn "offset" "offset" 0 255 ~default:0)
        ~period:(kwn "period" "period" 0 255 ~default:0) in
    List.iteri (fun k a -> set_reg c loc a (List.nth es k)) Config.es_regs
  | ".crc" ->
    check_kws loc [ "width"; "poly"; "init"; "xorout"; "residue" ] args;
    let fls = fl [ "reflected"; "start_on_match" ] p in
    let w32 k = kwn k k 0 0xFFFF_FFFF ~default:0 in
    let v = Config.crc ~reflected:(List.mem "reflected" fls) ~start_on_match:(List.mem "start_on_match" fls)
        ~poly:(w32 "poly") ~init:(w32 "init") ~width:(req "width" "width" 1 32) ~xorout:(w32 "xorout") ~residue:(w32 "residue") in
    List.iteri (fun k a -> set_reg c loc a (List.nth v k)) Config.crc_regs
  | ".nco" -> check_kws loc [ "inc" ] args; set_regs c loc Regs.r_nco_inc (Config.le 4 (req "inc" "increment" 0 0xFFFF_FFFF))
  | ".matcher" ->
    check_kws loc [ "pattern"; "mask"; "threshold" ] args;
    if c.matcher <> [] then Loc.error loc ".matcher given twice";
    let pat = req "pattern" "pattern" 0 0xFFFF and mask = req "mask" "mask" 0 0xFFFF in
    let cfg = { Eth10.Model.t = Array.init Eth10.Model.n (fun i -> (pat lsr i) land 1);
                m = Array.init Eth10.Model.n (fun i -> (mask lsr i) land 1); thr = req "threshold" "threshold" 0 31 } in
    c.matcher <- Eth10.Model.cfg_bits cfg
  | ".reg" ->
    check_kws loc [] args;
    (match p with a :: (_ :: _ as bs) -> set_regs c loc (n "register" 0 (Regs.reg_space - 1) a) (byte_list ctx loc ~here bs)
                | _ -> Loc.error loc ".reg ADDRESS, BYTE...")
  | ".bankdata" ->
    check_kws loc [] args;
    (match p with
     | a :: (_ :: _ as bs) ->
       let a0 = n "bank address" 0 (Isa2.bank_len - 1) a in
       List.iteri (fun k v ->
           let a = a0 + k in
           if a >= Isa2.bank_len then Loc.error loc "bank data runs past address %d" (Isa2.bank_len - 1);
           (match Hashtbl.find_opt c.bank a with Some (_, l) -> Loc.error loc "bank byte %d already set at %s" a (Loc.to_string l) | None -> ());
           Hashtbl.replace c.bank a (v, loc)) (byte_list ctx loc ~here bs)
     | _ -> Loc.error loc ".bankdata ADDRESS, BYTE or \"STRING\"...")
  | ".pe" ->
    (match p with
     | sg :: idx :: fls ->
       let key = (n "segment" 0 3 sg, n "PE index" 0 15 idx) in
       if Hashtbl.mem c.pe key then Loc.error loc "PE %d of segment %d configured twice" (snd key) (fst key);
       let op = ref Upe.Spec.nop in
       List.iter (fun t -> match t with
           | [ Lexer.Ident f ] ->
             (match List.find_opt (fun (fd : Config.pe_field) -> fd.key = f && fd.is_flag) Config.pe_fields with
              | Some fd -> op := fd.set !op 1
              | None -> Loc.error loc "unknown PE flag %s" f)
           | _ -> Loc.error loc ".pe SEGMENT, INDEX, field=value | flag ...") fls;
       List.iter (fun (k, t) ->
           match List.find_opt (fun (fd : Config.pe_field) -> fd.key = k) Config.pe_fields with
           | Some fd when fd.is_flag -> op := fd.set !op (n k 0 1 t)
           | Some fd ->
             let v = if fd.names = [] then
                 (if fd.key = "k" then n "k" (-32768) 0xFFFF t land 0xFFFF else n k 0 ((1 lsl fd.width) - 1) t)
               else named loc k fd.names t ~num:(Some (n k 0 ((1 lsl fd.width) - 1))) in
             op := fd.set !op v
           | None -> Loc.error loc "unknown PE field %s= (fields: %s)" k
                       (String.concat " " (List.map (fun (f : Config.pe_field) -> f.key) Config.pe_fields))) kws;
       Hashtbl.replace c.pe key (Upe.Spec.bytes_of_op !op, loc)
     | _ -> Loc.error loc ".pe SEGMENT, INDEX, field=value | flag ...")
  | ".pebytes" ->
    check_kws loc [] args;
    (match p with
     | sg :: idx :: bs when List.length bs = 8 ->
       let key = (n "segment" 0 3 sg, n "PE index" 0 15 idx) in
       if Hashtbl.mem c.pe key then Loc.error loc "PE %d of segment %d configured twice" (snd key) (fst key);
       Hashtbl.replace c.pe key (Array.of_list (List.map (n "byte" 0 255) bs), loc)
     | _ -> Loc.error loc ".pebytes SEGMENT, INDEX, B0, ..., B7")
  | ".pecfg" ->
    check_kws loc [] args;
    (match p with
     | sg :: (_ :: _ as bs) -> let sg = n "segment" 0 3 sg in c.pe_raw.(sg) <- c.pe_raw.(sg) @ List.map (n "byte" 0 255) bs
     | _ -> Loc.error loc ".pecfg SEGMENT, BYTE...")
  | ".peinit" ->
    check_kws loc [] args;
    (match p with
     | [ sg; idx; v ] ->
       let key = (n "segment" 0 3 sg, n "PE index" 0 15 idx) in
       if Hashtbl.mem c.peinit key then Loc.error loc "PE %d of segment %d initialised twice" (snd key) (fst key);
       Hashtbl.replace c.peinit key (n "initial S" (-32768) 0xFFFF v land 0xFFFF, loc)
     | _ -> Loc.error loc ".peinit SEGMENT, INDEX, VALUE")
  | ".seg" ->
    check_kws loc [ "src"; "repeat"; "feed" ] args;
    (match p with
     | sg :: fls ->
       let sg = n "segment" 0 3 sg in
       let fls = fl (List.map fst Config.seg_flags) fls in
       let src = match kw "src" with Some t -> named loc "segment source" Config.seg_sources t ~num:(Some (n "source" 0 7)) | None -> 0 in
       let ctrl = List.fold_left (fun acc f -> acc lor (1 lsl List.assoc f Config.seg_flags)) src fls in
       let set r v = match Hashtbl.find_opt c.segregs (sg, r) with
         | Some (_, l) -> Loc.error loc "segment %d register %d already set at %s" sg r (Loc.to_string l)
         | None -> Hashtbl.replace c.segregs (sg, r) (v, loc) in
       (match kw "feed" with Some t -> let w = n "feed word" (-32768) 0xFFFF t land 0xFFFF in set 0 (w land 0xFF); set 1 (w lsr 8) | None -> ());
       set 2 ctrl;
       (match kw "repeat" with Some t -> set 3 (n "repeat period" 0 255 t) | None -> ())
     | [] -> Loc.error loc ".seg SEGMENT [, src=...] [, flags] [, repeat=R] [, feed=W]")
  | ".segreg" ->
    check_kws loc [] args;
    (match p with
     | [ sg; r; v ] ->
       let key = (n "segment" 0 3 sg, n "segment register" 0 3 r) in
       if Hashtbl.mem c.segregs key then Loc.error loc "segment %d register %d set twice" (fst key) (snd key);
       Hashtbl.replace c.segregs key (n "byte" 0 255 v, loc)
     | _ -> Loc.error loc ".segreg SEGMENT, REGISTER, BYTE")
  | ".hostin" ->
    check_kws loc [] args;
    c.hostin <- c.hostin @ byte_list ctx loc ~here p;
    if List.length c.hostin > Chip_spec.hostin_depth then
      Loc.error loc "%d bytes for HOSTIN: the FIFO holds %d" (List.length c.hostin) Chip_spec.hostin_depth
  | ".stream" ->
    check_kws loc [] args;
    (match p with
     | [ w; cnt ] -> let w = n "streamer word" 0 0xFFFF w in
       c.stream <- c.stream @ [ w land 0xFF; w lsr 8; n "vector count" 0 15 cnt ]
     | _ -> Loc.error loc ".stream WORD, VECTORS")
  | ".run" | ".stop" | ".ctrl" ->
    check_kws loc [] args;
    (match c.ctrl with Some (_, l) -> Loc.error loc "the run state is already set at %s" (Loc.to_string l) | None -> ());
    let v = match name, fl [ "assists" ] (if name = ".ctrl" then [] else p) with
      | ".run", [ "assists" ] -> 1 | ".run", [] -> 3 | ".stop", [] -> 2
      | ".ctrl", _ -> (match p with [ v ] -> n "control" 0 255 v | _ -> Loc.error loc ".ctrl VALUE")
      | _ -> Loc.error loc ".run [assists]  or  .stop" in
    c.ctrl <- Some (v, loc)
  | _ -> ignore page; Loc.error loc "unknown directive %s" name

(* ---- the result ---- *)

type listing_line = { l_page : int; l_pc : int; l_word : int; l_loc : Loc.t; l_src : string }

type result = {
  image : Image.t;
  listing : listing_line list;
  timings : (timing * Verif.Spec.t) list;
  threads : (int * int) array;
  symbols : (string * sym) list;
}

let chain_bytes c =
  let pecfg = Array.make 4 [] and peinit = Array.make 4 [] in
  for sg = 0 to 3 do
    let size = c.layout.(sg) in
    let mine = Hashtbl.fold (fun (s, i) (_, l) acc -> if s = sg then (i, l) :: acc else acc) c.pe [] in
    List.iter (fun (i, l) -> if i >= size then Loc.error l "segment %d has %d PE%s (see .layout); index %d is past its end" sg size (if size = 1 then "" else "s") i) mine;
    if mine <> [] && c.pe_raw.(sg) <> [] then Loc.error (snd (List.hd mine)) "segment %d has both .pe and .pecfg" sg;
    if mine <> [] then
      pecfg.(sg) <- List.concat (List.init size (fun k ->
          let i = size - 1 - k in
          let b = match Hashtbl.find_opt c.pe (sg, i) with Some (b, _) -> b | None -> Upe.Spec.bytes_of_op Upe.Spec.nop in
          List.init 8 (fun j -> b.(7 - j))))
    else pecfg.(sg) <- c.pe_raw.(sg);
    let inits = Hashtbl.fold (fun (s, i) (_, l) acc -> if s = sg then (i, l) :: acc else acc) c.peinit [] in
    List.iter (fun (i, l) -> if i >= size then Loc.error l "segment %d has %d PEs; index %d is past its end" sg size i) inits;
    if inits <> [] then
      peinit.(sg) <- List.concat (List.init size (fun k ->
          let i = size - 1 - k in
          let v = match Hashtbl.find_opt c.peinit (sg, i) with Some (v, _) -> v | None -> 0 in
          [ v lsr 8; v land 0xFF ]))
  done;
  pecfg, peinit

let assemble_lines ?include_dirs (lines : (Loc.t * string) array) =
  Loc.warnings := [];
  let ctx = create ?include_dirs () in
  process ctx lines;
  (match ctx.in_timing with Some t -> Loc.error t.tloc ".timing without .endtiming" | None -> ());
  let items = List.rev ctx.items in
  let words = Hashtbl.create 512 in
  let listing = ref [] in
  let c = { regs = Hashtbl.create 64; bank = Hashtbl.create 64; threads = Array.make 4 None; layout = [| 1; 1; 1; 1 |];
            pe = Hashtbl.create 16; pe_raw = Array.make 4 []; peinit = Hashtbl.create 16; segregs = Hashtbl.create 16;
            matcher = []; hostin = []; stream = []; ctrl = None } in
  List.iter (function
      | Word { loc; page; pc; mnem; args; src } ->
        let w = encode_word ctx loc ~page ~pc mnem args in
        let a = (page lsl 8) lor pc in
        (match Hashtbl.find_opt words a with
         | Some (_, l) -> Loc.error loc "page %d address %d already holds a word from %s" page pc (Loc.to_string l)
         | None -> ());
        Hashtbl.replace words a (w, loc);
        listing := { l_page = page; l_pc = pc; l_word = w; l_loc = loc; l_src = src } :: !listing
      | Dir { loc; page; pc; name; args } -> directive ctx c loc ~page ~here:pc name args) items;
  (* every thread must say where it starts *)
  let threads = Array.mapi (fun th -> function
      | Some (pg, pc, _) -> (pg, pc)
      | None ->
        Loc.error { Loc.none with file = (match lines with [||] -> "<input>" | _ -> (fst lines.(0)).file) }
          "thread %d has no .thread directive: every thread starts somewhere (use a halt word for an idle thread)" th) c.threads in
  Array.iteri (fun th (pg, pc) ->
      if not (Hashtbl.mem words ((pg lsl 8) lor pc)) then
        (match c.threads.(th) with Some (_, _, l) -> Loc.warn l "thread %d starts at page %d pc %d, where no word is assembled (it reads 0, NOP)" th pg pc | None -> ())) threads;
  set_regs c Loc.none (Regs.r_boot_pc 0) (Array.to_list (Array.map snd threads));
  set_reg c Loc.none Regs.r_boot_page (Array.fold_left (fun acc (i, (pg, _)) -> acc lor (pg lsl (2 * i))) 0 (Array.mapi (fun i x -> (i, x)) threads));
  let pecfg, peinit = chain_bytes c in
  let sorted h = List.sort compare (Hashtbl.fold (fun k (v, _) acc -> (k, v) :: acc) h []) in
  let image = { Image.layout = c.layout; regs = sorted c.regs; prog = sorted words; bank = sorted c.bank; pecfg; peinit;
                peseg = Array.init 4 (fun sg -> List.filter_map (fun ((s, r), v) -> if s = sg then Some (r, v) else None) (sorted c.segregs));
                matcher = c.matcher; hostin = c.hostin; ctrl = (match c.ctrl with Some (v, _) -> v | None -> 3); stream = c.stream } in
  let timings = List.map (fun t -> (t, Timing.build ~eval:(fun loc toks -> eval_toks ctx loc ~here:0 toks) t.tloc t.thread (List.rev t.lines)))
      (List.rev ctx.timings) in
  { image; listing = List.rev !listing; timings; threads;
    symbols = List.sort compare (Hashtbl.fold (fun k (v, _) acc -> (k, v) :: acc) ctx.syms []) }

let assemble_file ?include_dirs path =
  assemble_lines ?include_dirs (lines_of_string path (read_file Loc.none path))

let assemble_string ?include_dirs ?(name = "<string>") s = assemble_lines ?include_dirs (lines_of_string name s)

let listing_text r =
  String.concat ""
    (List.map (fun l -> Printf.sprintf "%d:%02x  %04x  %-36s  %s\n" l.l_page l.l_pc l.l_word
                  (Insn.to_asm ~pc:l.l_pc (Insn.decode l.l_word)) (Loc.to_string l.l_loc)) r.listing)
