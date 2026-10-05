open Base
open Hardcaml
module Uid = Signal.Type.Uid

type finding =
  { at : string
  ; anchor : string
  ; expected : string * int
  ; got : string * int
  }

type result =
  { findings : finding list
  ; nodes : int
  ; checked : int
  ; loop_registers : int
  ; cut_boundaries : int
  }

let describe (s : Signal.t) =
  let kind =
    match s with
    | Empty -> "empty"
    | Const _ -> "const"
    | Op2 { op; _ } ->
      (match op with
       | Signal_add -> "+"
       | Signal_sub -> "-"
       | Signal_mulu | Signal_muls -> "*"
       | Signal_and -> "&"
       | Signal_or -> "|"
       | Signal_xor -> "^"
       | Signal_eq -> "=="
       | Signal_lt -> "<")
    | Mux _ -> "mux"
    | Cat _ -> "concat"
    | Not _ -> "not"
    | Wire { driver; _ } -> if Signal.is_empty !driver then "input" else "wire"
    | Select { high; low; _ } -> Printf.sprintf "select[%d:%d]" high low
    | Reg _ -> "reg"
    | Multiport_mem _ -> "memory"
    | Mem_read_port _ -> "memory read"
    | Inst _ -> "instance"
  in
  let names =
    match Signal.names s with
    | [] -> ""
    | ns -> " " ^ String.concat ~sep:"/" ns
  in
  let site =
    match Signal.Type.caller_id s with
    | None -> ""
    | Some c ->
      (* [Caller_id.t] is only observable as a sexp of "file:line:col" atoms. Take the first
         frame outside Hardcaml and this library (both keep their sources under [src/])
         and outside the standard library (no directory in the path):
         in v0.17 [Top_of_stack] stops inside [signal__type.ml], so [Full_trace] mode is
         needed for this to find the design's own line. *)
      let rec atoms (s : Sexp.t) =
        match s with
        | Atom a -> [ a ]
        | List l -> List.concat_map l ~f:atoms
      in
      (match
         List.find (atoms (Caller_id.sexp_of_t c)) ~f:(fun a ->
           String.contains a ':'
           && String.contains a '/'
           && (not (String.is_prefix a ~prefix:"src/"))
           && not (String.is_prefix a ~prefix:"stdlib"))
       with
       | Some a -> " @ " ^ a
       | None -> "")
  in
  Printf.sprintf "%s%s (uid %s)%s" kind names (Uid.to_string (Signal.uid s)) site
;;

let is_input (s : Signal.t) =
  match s with
  | Wire { driver; _ } -> Signal.is_empty !driver
  | _ -> false
;;

(* Data inputs of a node, each with the number of registers on the edge. *)
let data_deps ~check_enables (s : Signal.t) : (Signal.t * int) list =
  match s with
  | Empty | Const _ | Multiport_mem _ | Inst _ -> []
  | Reg { d; register; _ } ->
    (d, 1)
    ::
    (if check_enables && not (Signal.Type.is_const register.reg_enable || Signal.is_empty register.reg_enable)
     then [ register.reg_enable, 1 ]
     else [])
  | Mem_read_port { read_address; _ } -> [ read_address, 0 ]
  | Wire { driver; _ } -> if Signal.is_empty !driver then [] else [ !driver, 0 ]
  | Op2 _ | Mux _ | Cat _ | Not _ | Select _ ->
    List.map (Signal.Type.Deps.to_list s) ~f:(fun d -> d, 0)
;;

(* Tarjan's strongly connected components over the data edges. Returns, for every node,
   the id of its component and whether that component is a real loop. *)
let components ~check_enables (nodes : Signal.t list) =
  let index = Hashtbl.create (module Uid) in
  let low = Hashtbl.create (module Uid) in
  let on_stack = Hashtbl.create (module Uid) in
  let comp = Hashtbl.create (module Uid) in
  let looped = Hashtbl.create (module Int) in
  let stack = Stack.create () in
  let counter = ref 0 in
  let ncomp = ref 0 in
  let rec visit (v : Signal.t) =
    let vu = Signal.uid v in
    Hashtbl.set index ~key:vu ~data:!counter;
    Hashtbl.set low ~key:vu ~data:!counter;
    Int.incr counter;
    Stack.push stack v;
    Hashtbl.set on_stack ~key:vu ~data:true;
    let self_loop = ref false in
    List.iter (data_deps ~check_enables v) ~f:(fun (w, _) ->
      let wu = Signal.uid w in
      if Uid.equal wu vu then self_loop := true;
      match Hashtbl.find index wu with
      | None ->
        visit w;
        Hashtbl.set low ~key:vu ~data:(Int.min (Hashtbl.find_exn low vu) (Hashtbl.find_exn low wu))
      | Some wi ->
        if Hashtbl.find on_stack wu |> Option.value ~default:false
        then Hashtbl.set low ~key:vu ~data:(Int.min (Hashtbl.find_exn low vu) wi));
    if Hashtbl.find_exn low vu = Hashtbl.find_exn index vu
    then (
      let id = !ncomp in
      Int.incr ncomp;
      let size = ref 0 in
      let rec pop () =
        let w = Stack.pop_exn stack in
        Hashtbl.set on_stack ~key:(Signal.uid w) ~data:false;
        Hashtbl.set comp ~key:(Signal.uid w) ~data:id;
        Int.incr size;
        if not (Uid.equal (Signal.uid w) vu) then pop ()
      in
      pop ();
      Hashtbl.set looped ~key:id ~data:(!size > 1 || !self_loop))
  in
  List.iter nodes ~f:(fun v -> if not (Hashtbl.mem index (Signal.uid v)) then visit v);
  comp, looped
;;

let check ?(check_enables = false) ?(hold_registers = false) ?(static = fun _ -> false) outputs
  =
  let graph = Signal_graph.create outputs in
  let nodes = Signal_graph.fold graph ~init:[] ~f:(fun acc s -> s :: acc) in
  let comp, looped = components ~check_enables nodes in
  let comp_of s = Hashtbl.find_exn comp (Signal.uid s) in
  let in_loop s = Hashtbl.find_exn looped (comp_of s) in
  let declared_static (s : Signal.t) =
    match s with
    | Empty | Const _ -> true
    | Reg { register; _ } when hold_registers ->
      not (Signal.Type.is_const register.reg_enable || Signal.is_empty register.reg_enable)
    | _ -> static s
  in
  (* Static-ness propagates: a node all of whose data inputs are static is static, e.g. a
     concatenation of configuration registers. Least fixed point, so a loop (a free-running
     counter) never becomes static by depending only on itself. *)
  let static_set = Hashtbl.create (module Uid) in
  List.iter nodes ~f:(fun s ->
    if declared_static s then Hashtbl.set static_set ~key:(Signal.uid s) ~data:());
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter nodes ~f:(fun s ->
      let deps = data_deps ~check_enables s in
      if (not (Hashtbl.mem static_set (Signal.uid s)))
         (* a read at a constant address still sees contents that writes change *)
         && (not (Signal.Type.is_mem_read_port s))
         && (not (List.is_empty deps))
         && List.for_all deps ~f:(fun (d, _) -> Hashtbl.mem static_set (Signal.uid d))
      then (
        Hashtbl.set static_set ~key:(Signal.uid s) ~data:();
        changed := true))
  done;
  let is_static (s : Signal.t) = Hashtbl.mem static_set (Signal.uid s) in
  (* The edges that count, with feedback edges cut and loop-entry registers weighted 0. *)
  let edges (v : Signal.t) =
    if is_static v
    then []
    else
      List.filter_map (data_deps ~check_enables v) ~f:(fun (u, w) ->
        if is_static u
        then None
        else if Signal.Type.is_reg v && in_loop v
        then if comp_of u = comp_of v then None else Some (u, 0)
        else Some (u, w))
  in
  (* union-find with offsets: latency x = latency (root x) + offset x *)
  let parent = Hashtbl.create (module Uid) in
  let offset = Hashtbl.create (module Uid) in
  let anchor = Hashtbl.create (module Uid) in
  let rec find u =
    match Hashtbl.find parent u with
    | None -> u, 0
    | Some p ->
      let root, po = find p in
      let o = Hashtbl.find_exn offset u + po in
      Hashtbl.set parent ~key:u ~data:root;
      Hashtbl.set offset ~key:u ~data:o;
      root, o
  in
  (* The signal latencies are reported against: an input port if the component has one. *)
  let set_anchor root (s : Signal.t) =
    match Hashtbl.find anchor root with
    | Some a when is_input a || not (is_input s) -> ()
    | _ -> Hashtbl.set anchor ~key:root ~data:s
  in
  let nodes_by_uid = Hashtbl.create (module Uid) in
  List.iter nodes ~f:(fun s -> Hashtbl.set nodes_by_uid ~key:(Signal.uid s) ~data:s);
  List.iter nodes ~f:(fun s -> set_anchor (Signal.uid s) s);
  let latency_after_anchor u =
    let root, o = find u in
    match Hashtbl.find anchor root with
    | Some a ->
      let _, ao = find (Signal.uid a) in
      a, o - ao
    | None -> Hashtbl.find_exn nodes_by_uid root, o
  in
  (* [union v u w]: latency v = latency u + w *)
  let union v u w =
    let rv, ov = find v in
    let ru, ou = find u in
    if Uid.equal rv ru
    then ov = ou + w
    else (
      (* attach rv under ru: latency rv = latency v - ov = latency u + w - ov *)
      Hashtbl.set parent ~key:rv ~data:ru;
      Hashtbl.set offset ~key:rv ~data:(ou + w - ov);
      (match Hashtbl.find anchor rv with
       | Some a -> set_anchor ru a
       | None -> ());
      true)
  in
  (* Visit in dependency order (the cut graph is acyclic), so that a conflict is reported
     at the first node where the paths meet. *)
  let visited = Hashtbl.create (module Uid) in
  let order = ref [] in
  let rec dfs v =
    let vu = Signal.uid v in
    if not (Hashtbl.mem visited vu)
    then (
      Hashtbl.set visited ~key:vu ~data:();
      List.iter (edges v) ~f:(fun (u, _) -> dfs u);
      order := v :: !order)
  in
  List.iter nodes ~f:dfs;
  let findings = ref [] in
  List.iter (List.rev !order) ~f:(fun v ->
    let vu = Signal.uid v in
    let first = ref None in
    List.iter (edges v) ~f:(fun (u, w) ->
      let uu = Signal.uid u in
      match union vu uu w, !first with
      | true, None -> first := Some (u, w)
      | true, Some _ -> ()
      | false, None ->
        (* cannot happen: [v] is unconstrained until its own edges are added *)
        assert false
      | false, Some (fu, fw) ->
        (match !findings with
         | f :: _ when String.equal f.at (describe v) -> ()
         | _ ->
           let a, lu = latency_after_anchor uu in
           let _, lf = latency_after_anchor (Signal.uid fu) in
           findings
           := { at = describe v
              ; anchor = describe a
              ; expected = describe fu, lf + fw
              ; got = describe u, lu + w
              }
              :: !findings)));
  let count f = List.count nodes ~f in
  { findings = List.rev !findings
  ; nodes = List.length nodes
  ; checked = count (fun s -> not (is_static s))
  ; loop_registers = count (fun s -> Signal.Type.is_reg s && in_loop s && not (is_static s))
  ; cut_boundaries = count (fun s -> Signal.Type.is_mem s || Signal.Type.is_inst s)
  }
;;

let check_circuit ?check_enables ?hold_registers ?static circuit =
  check ?check_enables ?hold_registers ?static (Circuit.outputs circuit)
;;

let to_string f =
  Printf.sprintf
    "reconvergence at %s\n  measured from %s:\n    %3d cycles: %s\n    %3d cycles: %s"
    f.at
    f.anchor
    (snd f.expected)
    (fst f.expected)
    (snd f.got)
    (fst f.got)
;;

let report ~title r =
  Stdio.printf "== %s: %d finding(s)\n" title (List.length r.findings);
  (* Say how much was actually checked: a lint that has quietly declared everything static
     (or cut everything at instantiations) would otherwise report a clean zero. *)
  Stdio.printf
    "   %d of %d nodes checked (the rest static); %d loop registers; %d memories/instances \
     cut\n"
    r.checked
    r.nodes
    r.loop_registers
    r.cut_boundaries;
  if r.checked = 0 && r.nodes > 0
  then Stdio.print_endline "   WARNING: nothing was checked; every node is static";
  List.iter r.findings ~f:(fun f -> Stdio.print_endline (to_string f))
;;
