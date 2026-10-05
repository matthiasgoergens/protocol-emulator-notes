(* Functional models of the SG13G2 and SG13CMOS5L standard cells, read from
   the PDK's Verilog models (libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v,
   libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v; the latter keeps
   its user primitives in sg13cmos5l_udp.v, whose tables are the same as
   SG13G2's apart from comments and spacing).

   The Verilog models, not the liberty files, on purpose: synthesis mapped
   the design with the liberty functions, so reading the liberty here would
   share its source with the thing being checked.  The approach follows the
   puzzle solution's cells.ml (hardware-2026-08/oxcaml/cells.ml), which
   interpreted the sky130 models the same way: each module is a list of gate
   primitives over local wires.  SG13G2 adds user primitives: ihp_mux2,
   ihp_mux4, and the flip-flop primitives ihp_dff_r / ihp_dff_sr_1, which
   are turned into a state element here.  Latches and tristate drivers
   (bufif0, notif0) are recognised and rejected: the round trip assumes a
   single-clock flip-flop design and says so if it meets anything else. *)

type prim = And | Or | Nand | Nor | Xor | Xnor | Not | Buf | Mux2 | Mux4

(* An edge-triggered flip-flop: q takes d on the rising edge of clk; r (s)
   asynchronously forces 0 (1) while high.  Wires are cell-local names. *)
type ff = { q : string; clk : string; d : string; r : string option; s : string option }

type gate = { gprim : prim; gout : string; gins : string array }

type cell = {
  cname : string;
  inputs : string list;
  outputs : string list;
  gates : gate array;       (* topologically sorted, flip-flop outputs as sources *)
  ffs : ff list;
  unsupported : string option;  (* why the simulator cannot model this cell *)
}

let eval_prim p (xs : int array) : int =
  let all v = Array.for_all (fun x -> x = v) xs in
  let parity () = Array.fold_left ( lxor ) 0 xs in
  match p with
  | And -> if all 1 then 1 else 0
  | Or -> if all 0 then 0 else 1
  | Nand -> if all 1 then 0 else 1
  | Nor -> if all 0 then 1 else 0
  | Xor -> parity ()
  | Xnor -> 1 - parity ()
  | Not -> 1 - xs.(0)
  | Buf -> xs.(0)
  (* ihp_mux2 (z, a, b, s): z = s ? b : a, from the primitive's table *)
  | Mux2 -> if xs.(2) = 1 then xs.(1) else xs.(0)
  (* ihp_mux4 (z, a, b, c, d, s0, s1): z = [a; b; c; d].(s1 * 2 + s0) *)
  | Mux4 -> xs.(xs.(5) * 2 + xs.(4))

(* ---- tokens ---- *)

type tok = Id of string | Sym of char

let tokenize (s : string) : tok array =
  let n = String.length s in
  let toks = ref [] in
  let i = ref 0 in
  let defines = Hashtbl.create 16 and conds = ref [] in
  let is_id c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
    || c = '_' || c = '$' || c = '\'' in
  while !i < n do
    let c = s.[!i] in
    if c = '/' && !i + 1 < n && s.[!i + 1] = '/' then
      while !i < n && s.[!i] <> '\n' do incr i done
    else if c = '/' && !i + 1 < n && s.[!i + 1] = '*' then begin
      i := !i + 2;
      while !i + 1 < n && not (s.[!i] = '*' && s.[!i + 1] = '/') do incr i done;
      i := !i + 2
    end
    else if c = '`' then begin
      (* compiler directive: drop the line, but follow `define and the
         `ifdef/`ifndef/`else/`endif branches, so that only the branch a
         simulator without +define options would compile is read (the
         sg13cmos5l sighold model has a `ifdef DISPLAY_HOLD branch that this
         tokenizer cannot parse) *)
      let j = ref !i in
      while !j < n && s.[!j] <> '\n' do incr j done;
      let words = String.split_on_char ' ' (String.sub s (!i + 1) (!j - !i - 1))
                  |> List.map String.trim |> List.filter (( <> ) "") in
      let active () = List.for_all Fun.id !conds in
      (match words with
       | "define" :: name :: _ -> if active () then Hashtbl.replace defines name ()
       | [ "ifdef"; name ] -> conds := Hashtbl.mem defines name :: !conds
       | [ "ifndef"; name ] -> conds := (not (Hashtbl.mem defines name)) :: !conds
       | [ "else" ] ->
         (match !conds with c :: rest -> conds := (not c) :: rest | [] -> failwith "`else without `ifdef")
       | [ "endif" ] ->
         (match !conds with _ :: rest -> conds := rest | [] -> failwith "`endif without `ifdef")
       | ("ifdef" | "ifndef" | "elsif") :: _ -> failwith ("unsupported directive: " ^ String.concat " " words)
       | _ -> ());
      i := !j
    end
    else if not (List.for_all Fun.id !conds) then incr i
    else if is_id c then begin
      let j = ref !i in
      while !j < n && is_id s.[!j] do incr j done;
      toks := Id (String.sub s !i (!j - !i)) :: !toks;
      i := !j
    end
    else begin
      if c <> ' ' && c <> '\t' && c <> '\n' && c <> '\r' then toks := Sym c :: !toks;
      incr i
    end
  done;
  if !conds <> [] then failwith "`ifdef without `endif";
  Array.of_list (List.rev !toks)

let prim_of_string = function
  | "and" -> Some And | "or" -> Some Or | "nand" -> Some Nand | "nor" -> Some Nor
  | "xor" -> Some Xor | "xnor" -> Some Xnor | "not" -> Some Not | "buf" -> Some Buf
  | "ihp_mux2" -> Some Mux2 | "ihp_mux4" -> Some Mux4
  | _ -> None

(* The models route every input through a "delayed_X" wire for timing checks;
   functionally it is X. *)
let undelay w =
  let p = "delayed_" in
  let n = String.length p in
  if String.length w > n && String.sub w 0 n = p then String.sub w n (String.length w - n)
  else w

let parse_library (path : string) : (string, cell) Hashtbl.t =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let t = tokenize s in
  let n = Array.length t in
  let pos = ref 0 in
  let tbl = Hashtbl.create 128 in
  let skip_to kw = while !pos < n && t.(!pos) <> Id kw do incr pos done; incr pos in
  let skip_stmt () = while !pos < n && t.(!pos) <> Sym ';' do incr pos done; incr pos in
  (* comma-separated identifiers up to [stop] *)
  let idents stop =
    let acc = ref [] in
    while !pos < n && t.(!pos) <> Sym stop do
      (match t.(!pos) with Id x -> acc := x :: !acc | Sym _ -> ());
      incr pos
    done;
    incr pos;
    List.rev !acc
  in
  while !pos < n do
    match t.(!pos) with
    | Id "primitive" -> skip_to "endprimitive"
    | Id "module" ->
      incr pos;
      let name = match t.(!pos) with Id x -> x | _ -> failwith "module name" in
      incr pos;
      (* port list *)
      incr pos; (* '(' *)
      let ports = idents ')' in
      skip_stmt ();
      let dirs = Hashtbl.create 8 in
      let gates = ref [] and ffs = ref [] and unsupported = ref None in
      let fin = ref false in
      while not !fin do
        match t.(!pos) with
        | Id "endmodule" -> incr pos; fin := true
        | Id "specify" -> skip_to "endspecify"
        | Id "inout" -> unsupported := Some "inout pin"; skip_stmt ()
        | Id ("input" | "output" as dir) ->
          incr pos;
          List.iter (fun p -> Hashtbl.replace dirs p dir) (idents ';')
        | Id ("wire" | "reg" | "supply0" | "supply1") -> skip_stmt ()
        | Id p ->
          incr pos;
          (* optional instance name *)
          (match t.(!pos) with Id _ -> incr pos | _ -> ());
          if t.(!pos) <> Sym '(' then failwith (name ^ ": expected (");
          incr pos;
          (* a bare 0 or 1 is a constant: sg13cmos5l's flip-flops tie the
             primitive's unused error input with "buf (xcr_0, 0)" *)
          let const = function "0" -> "1'b0" | "1" -> "1'b1" | w -> w in
          let args = List.map (fun w -> const (undelay w)) (idents ')') in
          skip_stmt ();
          (match prim_of_string p, args with
           | Some g, out :: ins -> gates := { gprim = g; gout = out; gins = Array.of_list ins } :: !gates
           | None, [ q; _notifier; clk; d; r; _xcr ] when p = "ihp_dff_r" ->
             ffs := { q; clk; d; r = Some r; s = None } :: !ffs
           | None, [ q; _notifier; clk; d; s; r; _xcr ] when p = "ihp_dff_sr_1" || p = "ihp_dff_sr_0" ->
             (* _1 and _0 differ only when set and reset are both asserted *)
             ffs := { q; clk; d; r = Some r; s = Some s } :: !ffs
           | None, _ when String.length p > 8 && String.sub p (String.length p - 4) 4 = "_err" -> ()
           | None, _ -> unsupported := Some p
           | Some _, [] -> failwith (name ^ ": empty gate"))
        | Sym _ -> incr pos
      done;
      let inputs = List.filter (fun p -> Hashtbl.find_opt dirs p = Some "input") ports in
      let outputs = List.filter (fun p -> Hashtbl.find_opt dirs p = Some "output") ports in
      (* topological sort: inputs and flip-flop outputs are sources *)
      let ready = Hashtbl.create 16 in
      List.iter (fun i -> Hashtbl.replace ready i ()) ("1'b0" :: "1'b1" :: inputs);
      List.iter (fun f -> Hashtbl.replace ready f.q ()) !ffs;
      let remaining = ref (List.rev !gates) and ordered = ref [] and progress = ref true in
      while !remaining <> [] && !progress do
        progress := false;
        remaining := List.filter (fun g ->
          if Array.for_all (Hashtbl.mem ready) g.gins then begin
            Hashtbl.replace ready g.gout ();
            ordered := g :: !ordered;
            progress := true;
            false
          end else true) !remaining
      done;
      let unsupported =
        if !remaining <> [] && !unsupported = None then Some "combinational loop" else !unsupported in
      Hashtbl.replace tbl name
        { cname = name; inputs; outputs; gates = Array.of_list (List.rev !ordered);
          ffs = List.rev !ffs; unsupported }
    | _ -> incr pos
  done;
  tbl
