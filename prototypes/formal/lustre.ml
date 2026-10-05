(* Export of one round of the machine (four clocks, one slot of every thread) as a Lustre node
   for Kind 2, an established model checker (github.com/kind2-mc/kind2, Apache-2.0), so the same
   deadline property can be checked by k-induction and IC3 without a depth bound.

   The model is not written by hand: the state is a set of variables, one round of
   Isa2.Make (Smt.Value) and of the property monitor runs on them, and every SMT term in the cone
   of influence of the property becomes a Lustre equation over Kind 2's machine integers
   (uint<w>). A state variable is "initial value -> pre (its next value)". The data bank (an
   array) must stay outside the cone, and does for the programmes exported here.

   A thread whose pc is a state variable has no constant leaves to split on, so the caller gives
   the addresses the thread can be at ([reach], from [cfg_closure]); the property then includes
   "pc in reach", so a wrong set would show up as a violation rather than be assumed. *)

open Machine

(* the addresses reachable from [start] in thread [thread]'s page, by the successors each word
   can have (next, skip, jump or fail target, stay) *)
let cfg_closure (store : int array) ~start =
  let seen = Hashtbl.create 64 in
  let rec go a =
    if not (Hashtbl.mem seen a) then begin
      Hashtbl.replace seen a ();
      let w = store.(a) and page = a land lnot 0xFF and pc = a land 0xFF in
      let at p = page lor (p land 0xFF) in
      let target = at (w land 0xFF) in
      let op = (w lsr 12) land 15 in
      let succ =
        if op = Isa2.op_jmp then [ target ]
        else if op = Isa2.op_jnz then [ at (pc + 1); target ]
        else if op = Isa2.op_waitp || op = Isa2.op_mbx || op = Isa2.op_waitc then [ at (pc + 1); a; target ]
        else if op = Isa2.op_waitd || op = Isa2.op_in then [ at (pc + 1); a ]
        else if op = Isa2.op_ext then [ at (pc + 1); at (pc + 2) ]
        else [ at (pc + 1) ] in
      List.iter go succ
    end in
  go start;
  List.sort compare (Hashtbl.fold (fun a () l -> a :: l) seen [])

(* ---- state variables ---- *)
type slot = { sname : string; var : Smt.term; init : int; next : Sym.state -> Smt.term }

let state_slots () =
  let slots = ref [] in
  let add name w init next = let var = Smt.var name (Smt.Bv w) in slots := { sname = name; var; init; next } :: !slots; var in
  let per name w get init = Array.init Isa2.n_threads (fun t -> add (Printf.sprintf "%s%d" name t) w (init t) (fun st -> (get st).(t))) in
  let boot = Compat.boot_by_thread in
  let pcs = per "pc" 8 (fun st -> st.Sym.pcs) (fun t -> snd boot.(t)) in
  let pages = per "page" 2 (fun st -> st.Sym.pages) (fun t -> fst boot.(t)) in
  let z name w get = per name w get (fun _ -> 0) in
  let accs = z "acc" 8 (fun st -> st.Sym.accs) and cnts = z "cnt" 12 (fun st -> st.Sym.cnts) in
  let dls = z "dl" 12 (fun st -> st.Sym.dls) and bps = z "bp" 10 (fun st -> st.Sym.bps) in
  let fines = z "fine" 8 (fun st -> st.Sym.fines) and armed = z "armed" 1 (fun st -> st.Sym.armed) in
  let cfgs = z "cfg" 8 (fun st -> st.Sym.cfgs) and lsend = z "lsend" 3 (fun st -> st.Sym.lsend) in
  let inbox = z "inbox" 8 (fun st -> st.Sym.inbox) and full = z "full" 1 (fun st -> st.Sym.full) in
  let pin_out = add "pin_out" 8 0 (fun st -> st.Sym.pin_out) and pin_oe = add "pin_oe" 8 0 (fun st -> st.Sym.pin_oe) in
  let pin_sub = add "pin_sub" 32 0 (fun st -> st.Sym.pin_sub) and latch = add "latch" 8 0 (fun st -> st.Sym.latch) in
  let st : Sym.state = { pcs; pages; accs; cnts; dls; bps; fines; armed; cfgs; lsend; inbox; full; pin_out; pin_oe;
                         thread = 0; pin_sub; latch; bankmem = Smt.mem_var "bank" } in
  st, !slots

(* ---- Lustre text ---- *)
let ident s = String.map (fun ch -> if ch = '@' || ch = '.' then '_' else ch) s

let ty (t : Smt.term) = match t.sort with Bool -> "bool" | Bv w -> Printf.sprintf "uint<%d>" w | Mem -> failwith "the data bank is in the cone"

let rec expr (t : Smt.term) =
  let w () = Smt.width t in
  let lit w n = Printf.sprintf "(uint@<%d> %d)" w n in
  match t.node with
  | Var n -> ident n
  | B v -> string_of_bool v
  | K n -> lit (w ()) n
  | App (op, idx, args) ->
    let a = List.map ref_ args in
    (match op, idx, a with
     | "not", _, [ x ] -> Printf.sprintf "(not %s)" x
     | "and", _, [ x; y ] -> Printf.sprintf "(%s and %s)" x y
     | "or", _, [ x; y ] -> Printf.sprintf "(%s or %s)" x y
     | "=", _, [ x; y ] -> Printf.sprintf "(%s = %s)" x y
     | "bvult", _, [ x; y ] -> Printf.sprintf "(%s < %s)" x y
     | "ite", _, [ c; x; y ] -> Printf.sprintf "(if %s then %s else %s)" c x y
     | "bvadd", _, [ x; y ] -> Printf.sprintf "(%s + %s)" x y
     | "bvsub", _, [ x; y ] -> Printf.sprintf "(%s - %s)" x y
     | "bvand", _, [ x; y ] -> Printf.sprintf "(%s && %s)" x y
     | "bvor", _, [ x; y ] -> Printf.sprintf "(%s || %s)" x y
     | "bvxor", _, [ x; y ] -> Printf.sprintf "((%s || %s) && (!(%s && %s)))" x y x y
     | "bvnot", _, [ x ] -> Printf.sprintf "(!%s)" x
     | "bvshl", _, [ x; y ] -> Printf.sprintf "(%s lsh %s)" x y
     | "bvlshr", _, [ x; y ] -> Printf.sprintf "(%s rsh %s)" x y
     | "extract", [ hi; lo ], [ x ] ->
       let wx = Smt.width (List.hd args) in
       Printf.sprintf "(uint@<%d> (%s rsh %s))" (hi - lo + 1) x (lit wx lo)
     | "zero_extend", [ n ], [ x ] -> Printf.sprintf "(uint@<%d> %s)" (Smt.width (List.hd args) + n) x
     | _ -> failwith ("no Lustre for " ^ op))
and ref_ (t : Smt.term) = match t.node with App _ -> Printf.sprintf "n%d" t.id | _ -> expr t

(* the App nodes and variables under [roots] *)
let collect roots =
  let seen = Hashtbl.create 1024 and apps = ref [] and vars = ref [] in
  let rec go (t : Smt.term) =
    if not (Hashtbl.mem seen t.id) then begin
      Hashtbl.replace seen t.id ();
      match t.node with
      | Var _ -> vars := t :: !vars
      | App (_, _, args) -> List.iter go args; apps := t :: !apps
      | _ -> ()
    end in
  List.iter go roots;
  List.rev !apps, !vars

(* [write ~ok ~slots ~extra oc]: [ok] is the property (a Bool term over state variables and the
   round's inputs); [extra] are further state variables (monitors) as slots *)
let write oc ~node ~(ok : Smt.term) ~(slots : slot list) ~final =
  let by_var = Hashtbl.create 64 in
  List.iter (fun s -> Hashtbl.replace by_var s.var.Smt.id s) slots;
  (* the cone of influence: start from ok, add the next-state term of every state variable met *)
  let roots = ref [ ok ] and in_cone = Hashtbl.create 64 in
  let rec fix () =
    let _, vars = collect !roots in
    let fresh = List.filter (fun (v : Smt.term) -> Hashtbl.mem by_var v.id && not (Hashtbl.mem in_cone v.id)) vars in
    if fresh <> [] then begin
      List.iter (fun (v : Smt.term) -> Hashtbl.replace in_cone v.id (); roots := (Hashtbl.find by_var v.id).next final :: !roots) fresh;
      fix ()
    end in
  fix ();
  let apps, vars = collect !roots in
  let state = List.filter (fun s -> Hashtbl.mem in_cone s.var.Smt.id) slots in
  let inputs = List.filter (fun (v : Smt.term) -> not (Hashtbl.mem by_var v.id)) vars in
  let inputs = List.sort (fun (a : Smt.term) (b : Smt.term) -> compare a.id b.id) inputs in
  Printf.fprintf oc "-- generated by prototypes/formal (lustre.ml); %d state variables, %d inputs, %d equations\n"
    (List.length state) (List.length inputs) (List.length apps);
  Printf.fprintf oc "node %s (%s) returns (ok : bool);\nvar\n" node
    (String.concat "; " (List.map (fun (v : Smt.term) -> Printf.sprintf "%s : %s" (expr v) (ty v)) inputs));
  List.iter (fun s -> Printf.fprintf oc "  %s : %s;\n" (ident s.sname) (ty s.var)) state;
  List.iter (fun (t : Smt.term) -> Printf.fprintf oc "  n%d : %s;\n" t.id (ty t)) apps;
  Printf.fprintf oc "let\n";
  List.iter (fun s ->
      Printf.fprintf oc "  %s = %s -> pre %s;\n" (ident s.sname) (expr (Smt.k ~w:(Smt.width s.var) s.init)) (ref_ (s.next final))) state;
  List.iter (fun (t : Smt.term) -> match t.node with App _ -> Printf.fprintf oc "  n%d = %s;\n" t.id (expr t) | _ -> ()) apps;
  Printf.fprintf oc "  ok = %s;\n  --%%PROPERTY ok;\ntel\n" (ref_ ok);
  List.length state, List.length inputs, List.length apps
