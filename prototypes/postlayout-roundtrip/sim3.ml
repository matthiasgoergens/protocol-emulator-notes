(* Three-valued (0, 1, X) evaluation of the same flattened netlist as Sim.

   Sim starts every flip-flop at 0, which silicon does not do: a flip-flop
   without a reset powers up at an arbitrary value.  Here every signal starts
   at X (unknown) except the constants, and X propagates through the gates
   pessimistically: a gate's output is 0 or 1 only when every assignment of
   0 and 1 to its X inputs gives that value (a controlling 0 into an AND, a
   multiplexer whose candidates agree, and so on).  So a 0 or 1 here is the
   value for every power-up state, and an output that is never X after the
   reset sequence proves the sequence covers all of them.  The converse does
   not hold (X can be pessimistic through reconvergent logic), which is why
   the caller enumerates concrete power-up states for whatever stays X.

   Soto Franco ran both of his simulators over all sixteen power-up states
   of the puzzle chip's four unreset flip-flops, after a refuted hypothesis
   about power-up state had hidden a real bug; Ebert's and JGalil's
   simulators carry an X (JGalil/gds2netlist-asic-puzzle, MIT).  The idea is
   theirs, the code is ours. *)

let x = 2

type t = { s : Sim.t; v : int array }

let create (s : Sim.t) =
  let v = Array.make (Array.length s.v) x in
  (* the two constants: Sim allocates 0 and 1 right after the nets *)
  v.(s.const1 - 1) <- 0;
  v.(s.const1) <- 1;
  { s; v }

let eval (p : Cells.prim) (get : int -> int) n =
  let exists c = let r = ref false in for k = 0 to n - 1 do if get k = c then r := true done; !r in
  let inv a = if a = x then x else 1 - a in
  let and_ () = if exists 0 then 0 else if exists x then x else 1 in
  let or_ () = if exists 1 then 1 else if exists x then x else 0 in
  let xor_ () =
    if exists x then x else begin
      let r = ref 0 in for k = 0 to n - 1 do r := !r lxor get k done; !r end in
  (* a multiplexer: the value common to every candidate the select can reach *)
  let pick cands = match List.sort_uniq compare cands with [ c ] -> c | _ -> x in
  match p with
  | Cells.And -> and_ ()
  | Or -> or_ ()
  | Nand -> inv (and_ ())
  | Nor -> inv (or_ ())
  | Xor -> xor_ ()
  | Xnor -> inv (xor_ ())
  | Not -> inv (get 0)
  | Buf -> get 0
  | Mux2 ->
    (match get 2 with 0 -> get 0 | 1 -> get 1 | _ -> pick [ get 0; get 1 ])
  | Mux4 ->
    let sel b = match get b with 0 -> [ 0 ] | 1 -> [ 1 ] | _ -> [ 0; 1 ] in
    pick (List.concat_map (fun s1 -> List.map (fun s0 -> get (s1 * 2 + s0)) (sel 4)) (sel 5))

let settle t =
  Array.iter (fun (g : Sim.gate) ->
    t.v.(g.out) <- eval g.prim (fun k -> t.v.(g.ins.(k))) (Array.length g.ins)) t.s.gates

let apply_async t =
  let changed = ref true and rounds = ref 0 in
  while !changed do
    changed := false;
    incr rounds;
    if !rounds > 10 then failwith "asynchronous set/reset does not settle";
    Array.iter (fun (f : Sim.ff) ->
      let r = if f.r >= 0 then t.v.(f.r) else 0 and s = if f.s >= 0 then t.v.(f.s) else 0 in
      let q = t.v.(f.q) in
      let forced =
        if r = 1 then 0 else if s = 1 then 1
        else if r = x && q <> 0 then x else if s = x && q <> 1 then x else q in
      if forced <> q then begin t.v.(f.q) <- forced; changed := true end) t.s.ffs;
    if !changed then settle t
  done

let set_input t name value =
  match Hashtbl.find_opt t.s.port name with
  | Some s -> t.v.(s) <- value
  | None -> failwith ("no port " ^ name)

let get t name =
  match Hashtbl.find_opt t.s.port name with
  | Some s -> t.v.(s)
  | None -> failwith ("no port " ^ name)

let cycle t =
  settle t;
  apply_async t;
  let next = Array.map (fun (f : Sim.ff) -> t.v.(f.d)) t.s.ffs in
  Array.iteri (fun i (f : Sim.ff) -> t.v.(f.q) <- next.(i)) t.s.ffs;
  settle t;
  apply_async t

let unknown_ffs t =
  Array.to_list t.s.ffs |> List.filter (fun (f : Sim.ff) -> t.v.(f.q) = x)
