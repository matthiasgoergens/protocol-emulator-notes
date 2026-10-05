(* Netlist extraction from a routed IHP SG13G2 GDS.

   The algorithm is the one from Matthias's solution to Jane Street's August
   2026 ASIC puzzle (hardware-2026-08/oxcaml/extract.ml, after work/extract.py):
   union-find over the conductor shapes of the flattened layout, where two
   shapes are joined when they are on the same metal and touch, or when one is
   a via and the other is one of the two metals the via joins.  Standard-cell
   pins are found from the cells' own pin labels, transformed by the instance
   placement, and the top-level labels become the ports.  What changed for
   SG13G2 is the layer map and the label conventions, below.

   Layer numbers are from the PDK's KLayout layer map
   (libs.tech/klayout/tech/sg13g2.map): drawing datatype 0, pin datatype 2,
   pin-name text datatype 25, fill datatype 22 (fill is never a conductor
   here: it is not connected to anything by design). *)

type metal = { mname : string; mlayer : int }

let metals =
  [| { mname = "Metal1"; mlayer = 8 }; { mname = "Metal2"; mlayer = 10 };
     { mname = "Metal3"; mlayer = 30 }; { mname = "Metal4"; mlayer = 50 };
     { mname = "Metal5"; mlayer = 67 }; { mname = "TopMetal1"; mlayer = 126 };
     { mname = "TopMetal2"; mlayer = 134 } |]

(* via layer, its name, and the indices into [metals] of the two metals it joins *)
let vias =
  [ (19, "Via1", 0, 1); (29, "Via2", 1, 2); (49, "Via3", 2, 3); (66, "Via4", 3, 4);
    (125, "TopVia1", 4, 5); (133, "TopVia2", 5, 6) ]

(* Cont (layer 6) joins Metal1 to Activ and GatPoly, i.e. into the
   transistors.  It is deliberately not followed: through diffusion it would
   join a cell's input to its output and every net to the supplies.  Below
   Metal1 the standard cells are trusted (they are the PDK's, not ours), so
   the extracted netlist is at gate level, as LVS against a gate-level netlist
   would be. *)
let cont_layer = 6

let metal_datatypes = [ 0; 2 ]
let via_datatype = 0
let text_datatype = 25

let metal_index layer =
  let r = ref None in
  Array.iteri (fun i m -> if m.mlayer = layer then r := Some i) metals;
  !r

let via_metals layer =
  List.find_map (fun (l, _, lo, hi) -> if l = layer then Some (lo, hi) else None) vias

let cell_prefix = "sg13g2_"

(* cells with no signal pins, or (antenna diode) with a pin that is only a load *)
let ignore_prefixes = [ "sg13g2_fill_"; "sg13g2_decap_" ]

let power_pins = [ "VDD"; "VSS" ]

let starts_with s p =
  let n = String.length p in
  String.length s >= n && String.sub s 0 n = p

(* ---------------- geometry: int64 coords in centi-dbu ---------------- *)

type pt = int64 * int64

type shape_kind = Metal of int | Via of int * int

type shape = {
  pts : pt array;
  bbox : int64 * int64 * int64 * int64; (* minx miny maxx maxy *)
  kind : shape_kind;
}

let quant (dbu_um : float) (x, y) : pt =
  let k = dbu_um *. 1e5 in
  (Int64.of_float (Float.round (x *. k)), Int64.of_float (Float.round (y *. k)))

let bbox_of (pts : pt array) =
  let minx = ref Int64.max_int and miny = ref Int64.max_int in
  let maxx = ref Int64.min_int and maxy = ref Int64.min_int in
  Array.iter (fun (x, y) ->
    if x < !minx then minx := x;
    if y < !miny then miny := y;
    if x > !maxx then maxx := x;
    if y > !maxy then maxy := y) pts;
  (!minx, !miny, !maxx, !maxy)

let bbox_overlap (ax0, ay0, ax1, ay1) (bx0, by0, bx1, by1) =
  ax0 <= bx1 && bx0 <= ax1 && ay0 <= by1 && by0 <= ay1

let cross (ax, ay) (bx, by) (cx, cy) =
  Int64.sub (Int64.mul (Int64.sub bx ax) (Int64.sub cy ay))
            (Int64.mul (Int64.sub by ay) (Int64.sub cx ax))

let sgn64 v = Int64.compare v 0L

let point_on_seg (p : pt) (a : pt) (b : pt) =
  cross a b p = 0L
  && Int64.min (fst a) (fst b) <= fst p && fst p <= Int64.max (fst a) (fst b)
  && Int64.min (snd a) (snd b) <= snd p && snd p <= Int64.max (snd a) (snd b)

let seg_intersect (a : pt) (b : pt) (c : pt) (d : pt) =
  let d1 = cross c d a and d2 = cross c d b in
  let d3 = cross a b c and d4 = cross a b d in
  let s1 = sgn64 d1 and s2 = sgn64 d2 and s3 = sgn64 d3 and s4 = sgn64 d4 in
  ((s1 > 0 && s2 < 0) || (s1 < 0 && s2 > 0)) && ((s3 > 0 && s4 < 0) || (s3 < 0 && s4 > 0))
  || (s1 = 0 && point_on_seg a c d)
  || (s2 = 0 && point_on_seg b c d)
  || (s3 = 0 && point_on_seg c a b)
  || (s4 = 0 && point_on_seg d a b)

let point_in_poly (p : pt) (pts : pt array) =
  let n = Array.length pts in
  let on_boundary = ref false and inside = ref false in
  let px, py = p in
  for i = 0 to n - 1 do
    let a = pts.(i) and b = pts.((i + 1) mod n) in
    if point_on_seg p a b then on_boundary := true
    else begin
      let ax, ay = a and bx, by = b in
      if (ay > py) <> (by > py) then begin
        let lhs = Int64.mul (Int64.sub bx ax) (Int64.sub py ay) in
        let rhs = Int64.mul (Int64.sub px ax) (Int64.sub by ay) in
        let cross_right = if by > ay then lhs > rhs else lhs < rhs in
        if cross_right then inside := not !inside
      end
    end
  done;
  !on_boundary || !inside

let poly_intersect (s1 : shape) (s2 : shape) =
  bbox_overlap s1.bbox s2.bbox
  && (Array.exists (fun p -> point_in_poly p s2.pts) s1.pts
      || Array.exists (fun p -> point_in_poly p s1.pts) s2.pts
      || (let n1 = Array.length s1.pts and n2 = Array.length s2.pts in
          let found = ref false in
          for i = 0 to n1 - 1 do
            if not !found then
              for j = 0 to n2 - 1 do
                if (not !found)
                   && seg_intersect s1.pts.(i) s1.pts.((i + 1) mod n1)
                        s2.pts.(j) s2.pts.((j + 1) mod n2)
                then found := true
              done
          done;
          !found))

(* Positive-area overlap, for via cuts.  A via joins a metal only where the
   cut overlaps it with positive area; a cut that shares only an edge or a
   corner with a metal is not in contact with it (Shapovalov's paper on
   FigureZig/asicrev, section II-C, and JGalil/gds2netlist-asic-puzzle's
   README reach this rule independently).  [poly_intersect] above is closed,
   which is right for two shapes on the same metal (a wire drawn as abutting
   rectangles is one conductor) and wrong for a via: test_via_overlap.ml has
   the cases, four of which the closed test joined.

   Sutherland-Hodgman clipping of one polygon by the other, which must be
   convex (cuts are rectangles); the clipped area is exact for Manhattan
   geometry, since every intersection then lies on the integer grid. *)
let signed_area2 (pts : (float * float) array) =
  let n = Array.length pts in
  let s = ref 0.0 in
  for i = 0 to n - 1 do
    let x0, y0 = pts.(i) and x1, y1 = pts.((i + 1) mod n) in
    s := !s +. (x0 *. y1 -. x1 *. y0)
  done;
  !s

let is_convex (pts : pt array) =
  let n = Array.length pts in
  let pos = ref false and neg = ref false in
  for i = 0 to n - 1 do
    let c = cross pts.(i) pts.((i + 1) mod n) pts.((i + 2) mod n) in
    if c > 0L then pos := true else if c < 0L then neg := true
  done;
  n >= 3 && not (!pos && !neg)

let fpt ((x, y) : pt) = (Int64.to_float x, Int64.to_float y)

let clip_area2 ~(clipper : pt array) (subject : pt array) =
  let c = Array.map fpt clipper in
  let ccw = signed_area2 c > 0.0 in
  let n = Array.length c in
  let side (ax, ay) (bx, by) (px, py) =
    let v = ((bx -. ax) *. (py -. ay)) -. ((by -. ay) *. (px -. ax)) in
    if ccw then v else -.v
  in
  let poly = ref (Array.to_list (Array.map fpt subject)) in
  for i = 0 to n - 1 do
    let a = c.(i) and b = c.((i + 1) mod n) in
    let input = Array.of_list !poly in
    let m = Array.length input in
    let out = ref [] in
    for j = 0 to m - 1 do
      let p = input.(j) and q = input.((j + 1) mod m) in
      let sp = side a b p and sq = side a b q in
      let cut () =
        let t = sp /. (sp -. sq) in
        let (px, py), (qx, qy) = (p, q) in
        (px +. t *. (qx -. px), py +. t *. (qy -. py))
      in
      if sp >= 0.0 then begin
        out := p :: !out;
        if sq < 0.0 then out := cut () :: !out
      end
      else if sq >= 0.0 then out := cut () :: !out
    done;
    poly := List.rev !out
  done;
  Float.abs (signed_area2 (Array.of_list !poly))

let poly_overlap_positive (s1 : shape) (s2 : shape) =
  let ax0, ay0, ax1, ay1 = s1.bbox and bx0, by0, bx1, by1 = s2.bbox in
  ax0 < bx1 && bx0 < ax1 && ay0 < by1 && by0 < ay1
  && begin
    let clipper, subject =
      if is_convex s1.pts then (s1.pts, s2.pts)
      else if is_convex s2.pts then (s2.pts, s1.pts)
      else failwith "via-metal overlap: neither shape is convex (a non-convex via cut?)"
    in
    (* twice the area, in centi-dbu squared; the smallest real overlap on a
       1 nm grid is 100 x 100 *)
    clip_area2 ~clipper subject >= 1.0
  end

let kinds_connect k1 k2 =
  match k1, k2 with
  | Metal a, Metal b -> a = b
  | Via (lo, hi), Metal m | Metal m, Via (lo, hi) -> m = lo || m = hi
  | Via _, Via _ -> false

(* ---------------- union find ---------------- *)

type uf = { parent : int array; mutable count : int }

let uf_create n = { parent = Array.init n (fun i -> i); count = n }

let rec uf_find uf a =
  let p = uf.parent.(a) in
  if p = a then a
  else begin
    let r = uf_find uf p in
    uf.parent.(a) <- r;
    r
  end

let uf_union uf a b =
  let ra = uf_find uf a and rb = uf_find uf b in
  if ra <> rb then begin
    uf.parent.(ra) <- rb;
    uf.count <- uf.count - 1
  end

(* ---------------- netlist ---------------- *)

type inst = {
  iname : string;            (* u<index>@x,y in um: GDS keeps no instance names *)
  icell : string;
  nets : (string * int option) list;  (* signal pin -> net; None = no metal under the label *)
}

type netlist = {
  instances : inst array;
  ports : (string * int option) list;
  nnets : int;
  unresolved : string list;  (* pins and ports whose label has no conductor under it *)
  nshapes : int;
  ncomponents : int;
  foreign_layers : (int * int * int) list;
  via_touches : int;
  (* via-metal pairs that touch along an edge or at a corner without
     overlapping, and so are not joined *)
  (* layer, datatype, count of shapes drawn in the top cell itself (the
     routing) on layers the extractor does not follow: a route on such a
     layer would silently split a net, so the check reports them *)
}

(* Shapes and their net, kept for choosing planted faults. *)
type geometry = {
  shapes : shape array;
  shape_net : int option array;   (* canonical net id, if the component reaches a pin *)
  dbu_um : float;
}

let grid_cell = 200000L (* 2 um in centi-dbu at 1 nm dbu *)

let extract ?(log = fun _ -> ()) ~(gds_path : string) ~(top_name : string) ()
  : netlist * geometry =
  let lib = Gds.parse gds_path in
  let top =
    match Hashtbl.find_opt lib.Gds.cells top_name with
    | Some c -> c
    | None -> failwith ("no top cell " ^ top_name)
  in
  let flat = Gds.flatten_local lib in
  let dbu = lib.Gds.dbu_um in
  (* instances: top-level references to standard cells *)
  let instances = ref [] in
  List.iter (fun (r0 : Gds.ref_) ->
    List.iter (fun (r : Gds.ref_) ->
      let cn = r.rcell in
      if starts_with cn cell_prefix
         && not (List.exists (starts_with cn) ignore_prefixes)
         && Hashtbl.mem lib.cells cn then begin
        let cell = Hashtbl.find lib.cells cn in
        let xf = Gds.ref_xform r in
        let pins = Hashtbl.create 8 in
        List.iter (fun (l : Gds.label) ->
          if l.ltexttype = text_datatype && metal_index l.llayer <> None
             && not (List.mem l.ltext power_pins) then begin
            let p = Gds.xapply xf (l.lx, l.ly) in
            let old = Option.value ~default:[] (Hashtbl.find_opt pins l.ltext) in
            Hashtbl.replace pins l.ltext ((quant dbu p, l.llayer) :: old)
          end) cell.labels;
        let ox, oy = r.rorigin in
        instances := (cn, (ox *. dbu, oy *. dbu), pins) :: !instances
      end) (Gds.expand_array r0)) top.refs;
  let instances = Array.of_list (List.rev !instances) in
  (* conductor shapes *)
  let shapes = ref [] in
  List.iter (fun (lay, dt, pts) ->
    let add kind =
      let pts = Array.map (quant dbu) pts in
      shapes := { pts; bbox = bbox_of pts; kind } :: !shapes
    in
    match metal_index lay, via_metals lay with
    | Some mi, _ when List.mem dt metal_datatypes -> add (Metal mi)
    | _, Some (lo, hi) when dt = via_datatype -> add (Via (lo, hi))
    | _ -> ())
    (Hashtbl.find flat top_name);
  let shapes = Array.of_list (List.rev !shapes) in
  let nshapes = Array.length shapes in
  let foreign = Hashtbl.create 8 in
  let known lay dt =
    (metal_index lay <> None && (List.mem dt metal_datatypes || dt = text_datatype))
    || (via_metals lay <> None && dt = via_datatype)
    || (lay = 189 && dt = 4) (* prBoundary, the die outline *) in
  List.iter (fun (p : Gds.poly) ->
    if not (known p.player p.pdt) then
      Hashtbl.replace foreign (p.player, p.pdt)
        (1 + Option.value ~default:0 (Hashtbl.find_opt foreign (p.player, p.pdt)))) top.polys;
  List.iter (fun (p : Gds.path) ->
    if not (known p.hlayer p.hdt) then
      Hashtbl.replace foreign (p.hlayer, p.hdt)
        (1 + Option.value ~default:0 (Hashtbl.find_opt foreign (p.hlayer, p.hdt)))) top.paths;
  let foreign_layers = Hashtbl.fold (fun (l, d) c acc -> (l, d, c) :: acc) foreign [] |> List.sort compare in
  log (Printf.sprintf "%d conductor shapes, %d cell instances" nshapes (Array.length instances));
  (* spatial hash *)
  let grid : (int64 * int64, int list) Hashtbl.t = Hashtbl.create 65536 in
  let cells_of_bbox (x0, y0, x1, y1) =
    let cx0 = Int64.div x0 grid_cell and cx1 = Int64.div x1 grid_cell in
    let cy0 = Int64.div y0 grid_cell and cy1 = Int64.div y1 grid_cell in
    let acc = ref [] in
    for cx = 0 to Int64.to_int (Int64.sub cx1 cx0) do
      for cy = 0 to Int64.to_int (Int64.sub cy1 cy0) do
        acc := (Int64.add cx0 (Int64.of_int cx), Int64.add cy0 (Int64.of_int cy)) :: !acc
      done
    done;
    !acc
  in
  Array.iteri (fun i s ->
    List.iter (fun key ->
      Hashtbl.replace grid key (i :: Option.value ~default:[] (Hashtbl.find_opt grid key)))
      (cells_of_bbox s.bbox)) shapes;
  let uf = uf_create nshapes in
  let stamp = Array.make nshapes (-1) in
  let via_touches = ref 0 in
  for i = 0 to nshapes - 1 do
    let si = shapes.(i) in
    List.iter (fun key ->
      match Hashtbl.find_opt grid key with
      | None -> ()
      | Some js ->
        List.iter (fun j ->
          if j > i && stamp.(j) <> i then begin
            stamp.(j) <- i;
            let sj = shapes.(j) in
            if kinds_connect si.kind sj.kind then
              match si.kind, sj.kind with
              | Metal _, Metal _ -> if poly_intersect si sj then uf_union uf i j
              | _ ->
                if poly_overlap_positive si sj then uf_union uf i j
                else if poly_intersect si sj then incr via_touches
          end) js)
      (cells_of_bbox si.bbox)
  done;
  log (Printf.sprintf "%d connected components; %d via-metal pairs touch without overlapping (not joined)"
         uf.count !via_touches);
  let point_net (p : pt) layer =
    match metal_index layer with
    | None -> None
    | Some mi ->
      let key = (Int64.div (fst p) grid_cell, Int64.div (snd p) grid_cell) in
      List.find_map (fun j ->
        let s = shapes.(j) in
        if s.kind = Metal mi && bbox_overlap s.bbox (fst p, snd p, fst p, snd p)
           && point_in_poly p s.pts
        then Some (uf_find uf j) else None)
        (Option.value ~default:[] (Hashtbl.find_opt grid key))
  in
  let unresolved = ref [] in
  let inst_arr =
    Array.mapi (fun idx (cn, (x, y), pins) ->
      let iname = Printf.sprintf "u%d@%.2f,%.2f" idx x y in
      let nets =
        Hashtbl.fold (fun pin pts acc ->
          let found = List.find_map (fun (p, lay) -> point_net p lay) pts in
          if found = None then unresolved := (iname ^ "/" ^ cn ^ "." ^ pin) :: !unresolved;
          (pin, found) :: acc) pins []
        |> List.sort compare
      in
      { iname; icell = cn; nets })
      instances
  in
  (* top-level ports: every name label on a metal; a port may carry several
     labels (all of which must agree, checked by the caller via [ports]) *)
  let port_tbl = Hashtbl.create 64 in
  let port_order = ref [] in
  List.iter (fun (l : Gds.label) ->
    if l.ltexttype = text_datatype && metal_index l.llayer <> None then begin
      let n = point_net (quant dbu (l.lx, l.ly)) l.llayer in
      if n = None then unresolved := ("port " ^ l.ltext) :: !unresolved;
      if not (Hashtbl.mem port_tbl l.ltext) then port_order := l.ltext :: !port_order;
      Hashtbl.replace port_tbl l.ltext
        (n :: Option.value ~default:[] (Hashtbl.find_opt port_tbl l.ltext))
    end) top.labels;
  let ports =
    List.rev_map (fun p ->
      match List.sort_uniq compare (Hashtbl.find port_tbl p) with
      | [ n ] -> (p, n)
      | ns ->
        unresolved := Printf.sprintf "port %s: %d labels on different nets" p (List.length ns)
                      :: !unresolved;
        (p, List.hd ns))
      !port_order
  in
  (* canonical net ids, in order of first appearance *)
  let remap = Hashtbl.create 4096 in
  let canon r =
    match Hashtbl.find_opt remap r with
    | Some i -> i
    | None -> let i = Hashtbl.length remap in Hashtbl.replace remap r i; i
  in
  let ports = List.map (fun (p, n) -> (p, Option.map canon n)) ports in
  let inst_arr = Array.map (fun inst ->
      { inst with nets = List.map (fun (p, n) -> (p, Option.map canon n)) inst.nets }) inst_arr in
  let shape_net = Array.init nshapes (fun i -> Hashtbl.find_opt remap (uf_find uf i)) in
  ({ instances = inst_arr; ports; nnets = Hashtbl.length remap;
     unresolved = List.rev !unresolved; nshapes; ncomponents = uf.count; foreign_layers;
     via_touches = !via_touches },
   { shapes; shape_net; dbu_um = dbu })

(* Plain-text netlist, one instance per line, for diffing between runs. *)
let write_netlist (nl : netlist) path =
  let oc = open_out path in
  let opt = function None -> "-" | Some i -> "n" ^ string_of_int i in
  List.iter (fun (p, n) -> Printf.fprintf oc "port %s %s\n" p (opt n)) nl.ports;
  Array.iter (fun i ->
    Printf.fprintf oc "inst %s %s %s\n" i.iname i.icell
      (String.concat " " (List.map (fun (p, n) -> p ^ "=" ^ opt n) i.nets)))
    nl.instances;
  close_out oc
