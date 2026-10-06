(* Every cell master embedded in a hardened GDS against the PDK's own GDS of that cell, layer by
   layer: the round trip trusts everything below Metal1 as the PDK's (README, "What it does not
   check"), and this checks that what the GDS carries under those names is the PDK's.

   The idea is retrace's cellcheck (elementalcollision/retrace, tools/retrace/cellcheck.py,
   Apache-2.0; notes/learned-from-puzzle-solvers.md lesson P4): its campaign killed the
   cell-internal tampering mutants with it. This is our own implementation of the idea; no code
   was read or copied.

   cellcheck.exe GDS TOP REFERENCE.gds [REFERENCE.gds ...]

   For every master the top cell places that a reference library defines (standard cells, SRAM
   macros), compare it and every sub-cell it references, recursively, with the reference's cell
   of the same name, per (layer, datatype): the polygons as a multiset, each normalised (no
   closing vertex, starting at its smallest vertex, counter-clockwise); the paths as a multiset
   of (width, type, extensions, points); the references as a multiset of (cell, origin,
   reflection, magnification, angle, array); the labels as a multiset of (layer, type, text,
   position). Masters that no reference defines are listed (the router's via cells) and not
   compared. *)

let read_lib = Gds.parse

(* a polygon as a canonical vertex list: closing vertex dropped (Gds.parse does), collinear
   vertices kept, counter-clockwise, starting at the smallest vertex *)
let canon_poly (pts : (int * int) array) =
  let n = Array.length pts in
  if n = 0 then [||]
  else begin
    let area2 = ref 0 in
    for i = 0 to n - 1 do
      let x0, y0 = pts.(i) and x1, y1 = pts.((i + 1) mod n) in
      area2 := !area2 + (x0 * y1) - (x1 * y0)
    done;
    let pts = if !area2 < 0 then Array.init n (fun i -> pts.(n - 1 - i)) else pts in
    let m = ref 0 in
    Array.iteri (fun i p -> if compare p pts.(!m) < 0 then m := i) pts;
    Array.init n (fun i -> pts.((!m + i) mod n))
  end

type key =
  | P of int * int * (int * int) array
  | H of int * int * int * int * int * int * (int * int) array
  | R of string * (float * float) * bool * float * float * (int * int * (int * int) * (int * int)) option
  | L of int * int * string * float * float

let layer_of = function
  | P (l, d, _) | H (l, d, _, _, _, _, _) -> Printf.sprintf "%d/%d" l d
  | R _ -> "references"
  | L (l, d, _, _, _) -> Printf.sprintf "labels %d/%d" l d

(* [rename]: the name a referenced cell has in the reference library *)
let keys ?(rename = Fun.id) (c : Gds.cell) =
  List.map (fun (p : Gds.poly) -> P (p.player, p.pdt, canon_poly p.ppts)) c.polys
  @ List.map (fun (h : Gds.path) -> H (h.hlayer, h.hdt, h.hwidth, h.htype, h.hbgn, h.hend, h.hpts)) c.paths
  @ List.map (fun (r : Gds.ref_) -> R (rename r.rcell, r.rorigin, r.rxrefl, r.rmag, r.rangle, r.rarray)) c.refs
  @ List.map (fun (l : Gds.label) -> L (l.llayer, l.ltexttype, l.ltext, l.lx, l.ly)) c.labels

(* When two macros' GDS files are merged into one, a sub-cell name they share is kept for the
   first and renamed "NAME$1" for the second (the two macros' RM_IHPSG13_1P_BITKIT_CELL, for
   instance); compare such a cell with NAME in the second macro's library. *)
let base_name n =
  match String.rindex_opt n '$' with
  | Some i when i + 1 < String.length n
                && String.for_all (fun c -> c >= '0' && c <= '9') (String.sub n (i + 1) (String.length n - i - 1)) ->
    String.sub n 0 i
  | _ -> n

(* multiset difference, counted per layer: (layer, only in a, only in b) *)
let diff a b =
  let count l =
    let h = Hashtbl.create 64 in
    List.iter (fun k -> Hashtbl.replace h k (1 + Option.value ~default:0 (Hashtbl.find_opt h k))) l; h in
  let ha = count a and hb = count b in
  let per = Hashtbl.create 8 in
  let bump k side n =
    let lay = layer_of k in
    let x, y = Option.value ~default:(0, 0) (Hashtbl.find_opt per lay) in
    Hashtbl.replace per lay (if side then (x + n, y) else (x, y + n)) in
  Hashtbl.iter (fun k na -> let nb = Option.value ~default:0 (Hashtbl.find_opt hb k) in if na > nb then bump k true (na - nb)) ha;
  Hashtbl.iter (fun k nb -> let na = Option.value ~default:0 (Hashtbl.find_opt ha k) in if nb > na then bump k false (nb - na)) hb;
  Hashtbl.fold (fun lay (x, y) acc -> (lay, x, y) :: acc) per [] |> List.sort compare

(* Compare a cell of the GDS with the cell of the same base name in [rlib], and every cell it
   references, recursively, with the cell its reference names in [rlib].  Returns the differing
   cells with their per-layer counts; memoised per (cell, library). *)
let compare_tree (lib : Gds.lib) =
  let memo = Hashtbl.create 256 in
  let rec go name (rname, (rlib : Gds.lib)) =
    match Hashtbl.find_opt memo (name, rname) with
    | Some r -> r
    | None ->
      let c = Hashtbl.find lib.cells name in
      let result =
        match Hashtbl.find_opt rlib.cells (base_name name) with
        | None -> [ (name, [ ("cell", 1, 0) ]) ]
        | Some r ->
          let own = match diff (keys ~rename:base_name c) (keys r) with [] -> [] | d -> [ (name, d) ] in
          let subs = List.sort_uniq compare (List.map (fun (x : Gds.ref_) -> x.rcell) c.refs) in
          own @ List.concat_map (fun sub -> go sub (rname, rlib)) subs in
      Hashtbl.replace memo (name, rname) result;
      result in
  (go, memo)

let check gds top refs =
  let lib = read_lib gds in
  let reflibs = List.map (fun r -> (r, read_lib r)) refs in
  if List.exists (fun (_, (l : Gds.lib)) -> Float.abs (l.dbu_um -. lib.dbu_um) > 1e-12) reflibs then
    failwith "database units differ between the GDS and a reference";
  let topc = Hashtbl.find lib.cells top in
  let masters = List.sort_uniq compare (List.map (fun (r : Gds.ref_) -> r.rcell) topc.refs) in
  let cmp, memo = compare_tree lib in
  let same = ref 0 and differ = ref [] and unknown = ref [] in
  List.iter (fun m ->
    match List.find_opt (fun (_, (l : Gds.lib)) -> Hashtbl.mem l.cells (base_name m)) reflibs with
    | None -> unknown := m :: !unknown
    | Some rl ->
      (match cmp m rl with
       | [] -> incr same
       | d -> differ := (m, d) :: !differ)) masters;
  let unknown = List.rev !unknown in
  let via_cells = List.filter (fun n -> Extract.starts_with n "VIA_") unknown in
  Printf.printf "%s: top cell %s places %d masters; %d defined by a reference: %d identical, %d differ (%d cells compared, sub-cells included); %d not in any reference (%d router via cells%s)\n"
    gds top (List.length masters) (!same + List.length !differ) !same (List.length !differ) (Hashtbl.length memo)
    (List.length unknown) (List.length via_cells)
    (String.concat "" (List.map (fun n -> ", " ^ n) (List.filter (fun n -> not (Extract.starts_with n "VIA_")) unknown)));
  List.iter (fun (m, d) ->
    Printf.printf "  DIFFERS %s:\n" m;
    List.iter (fun (name, ls) ->
      Printf.printf "    %s:%s\n" name
        (String.concat "" (List.map (fun (lay, x, y) -> Printf.sprintf " %s (%d only in the GDS, %d only in the reference)" lay x y) ls))) d)
    (List.rev !differ);
  print_endline (if !differ = [] then "CELLS IDENTICAL" else "CELLS DIFFER");
  !differ = []

(* Controls: copies of GDS with one polygon removed from inside a master, which the check
   must report as that master differing: in a standard cell, the first polygon on GatPoly
   (5/0) of [cell]; in a macro, the first polygon of [sub], a sub-cell of a macro. *)
let plants gds top refs outdir ~cell ~sub =
  let lib = read_lib gds in
  let plant label cname layer =
    let c = Hashtbl.find lib.cells cname in
    match List.find_opt (fun (e : Gds.elem) -> e.ekind = `boundary && (layer < 0 || e.elayer = layer)) c.elems with
    | None -> Printf.printf "plant %s: no boundary in %s\n" label cname; true
    | Some e ->
      let path = Filename.concat outdir (label ^ ".gds") in
      Mutate.cut ~src:gds ~dst:path ~elem:e;
      Printf.printf "plant %s: one polygon on layer %d/%d removed from %s\n%!" label e.elayer e.edt cname;
      not (check path top refs) in
  let a = plant "cell_tamper" cell 5 in
  let b = plant "macro_tamper" sub (-1) in
  Printf.printf "cellcheck controls: %d of 2 caught\n" ((if a then 1 else 0) + if b then 1 else 0)

let () =
  match Array.to_list Sys.argv |> List.tl with
  | "--plants" :: outdir :: cell :: sub :: gds :: top :: (_ :: _ as refs) -> plants gds top refs outdir ~cell ~sub
  | gds :: top :: (_ :: _ as refs) -> exit (if check gds top refs then 0 else 1)
  | _ -> prerr_endline "usage: cellcheck.exe [--plants OUTDIR CELL SUBCELL] GDS TOP REFERENCE.gds [REFERENCE.gds ...]"; exit 2
