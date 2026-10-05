(* GDSII stream parser (from scratch, stdlib only).
   Record = uint16 BE total length, uint16 BE record type, payload.

   Copied from Matthias's solution to Jane Street's August 2026 ASIC puzzle
   (hardware-2026-08/oxcaml/gds.ml).  Changes for the post-layout round trip:
   AREF arrays are expanded (the puzzle GDS had none), and every element keeps
   the byte range it occupies in the file, so that a mutated copy of the GDS
   can be written by dropping or adding elements (Mutate). *)

type label = {
  lx : float; ly : float;
  llayer : int;
  ltexttype : int;
  ltext : string;
}

type ref_ = {
  rcell : string;
  rorigin : float * float; (* dbu *)
  rxrefl : bool;
  rmag : float;
  rangle : float; (* degrees CCW *)
  rarray : (int * int * (int * int) * (int * int)) option;
  (* AREF: columns, rows, end of the column vector, end of the row vector *)
}

type poly = { player : int; pdt : int; ppts : (int * int) array }

type path = {
  hlayer : int;
  hdt : int;
  hwidth : int;
  htype : int;   (* pathtype: 0 flush, 1 round, 2 +w/2, 4 explicit ext *)
  hbgn : int;
  hend : int;
  hpts : (int * int) array;
}

type elem = { ekind : [ `boundary | `path | `sref | `text | `none ];
              elayer : int; edt : int; estart : int; eend : int;
              exy : (int * int) array;
              esname : string (* the referenced cell, for SREF/AREF; "" otherwise *) }

type cell = {
  name : string;
  elems : elem list;   (* every element with its byte range, in file order *)
  endstr : int;        (* byte offset of the ENDSTR record *)
  polys : poly list;
  paths : path list;
  refs : ref_ list;
  labels : label list;
}

type lib = {
  cells : (string, cell) Hashtbl.t;
  cell_order : cell list;
  dbu_um : float; (* user units per dbu: coordinates * dbu_um = microns *)
}

let get_u16 d o = (Char.code (Bytes.get d o) lsl 8) lor Char.code (Bytes.get d (o + 1))

let get_i16 d o =
  let v = get_u16 d o in
  if v >= 0x8000 then v - 0x10000 else v

let get_i32 d o =
  let v = Int32.shift_left (Int32.of_int (get_u16 d o)) 16 in
  Int32.logor v (Int32.of_int (get_u16 d (o + 2))) |> Int32.to_int

(* 8-byte GDS real: bit63 sign, bits 62-56 exponent (excess 64),
   bits 55-0 mantissa; value = (mantissa / 2^56) * 16^(exp-64) *)
let get_real d o =
  let b0 = Char.code (Bytes.get d o) in
  let sign = if b0 land 0x80 <> 0 then -1.0 else 1.0 in
  let exp = (b0 land 0x7f) - 64 in
  let mant = ref 0L in
  for i = 1 to 7 do
    mant := Int64.logor (Int64.shift_left !mant 8) (Int64.of_int (Char.code (Bytes.get d (o + i))))
  done;
  sign *. (Int64.to_float !mant /. 72057594037927936.0)
    *. (16.0 ** Float.of_int exp)

let get_string d o len =
  let s = Bytes.sub_string d o len in
  (* strip trailing NULs *)
  let n = ref (String.length s) in
  while !n > 0 && s.[!n - 1] = '\000' do decr n done;
  String.sub s 0 !n

let parse path : lib =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let d = Bytes.create n in
  really_input ic d 0 n;
  close_in ic;
  let cells = Hashtbl.create 64 in
  let order = ref [] in
  let dbu_um = ref 1e-3 in
  (* current element state *)
  let cur_name = ref "" in
  let cur_polys = ref [] in
  let cur_paths = ref [] in
  let cur_refs = ref [] in
  let cur_labels = ref [] in
  let cur_elems = ref [] in
  let el_start = ref 0 in
  let e_colrow = ref None in
  (* per-element temporaries *)
  let el_kind = ref `none in
  let e_layer = ref 0 and e_dt = ref 0 and e_tt = ref 0 in
  let e_width = ref 0 and e_ptype = ref 0 and e_bgn = ref 0 and e_end = ref 0 in
  let e_sname = ref "" in
  let e_strans = ref false and e_mag = ref 1.0 and e_angle = ref 0.0 in
  let e_xy = ref [||] in
  let e_text = ref "" in
  let finish_cell endstr =
    let c = { name = !cur_name; elems = List.rev !cur_elems; endstr;
              polys = !cur_polys; paths = !cur_paths;
              refs = !cur_refs; labels = !cur_labels } in
    Hashtbl.replace cells c.name c;
    order := c :: !order
  in
  let off = ref 0 in
  while !off + 4 <= n do
    let len = get_u16 d !off in
    if len < 4 || !off + len > n then
      failwith (Printf.sprintf "%s: bad GDS record length %d at byte %d" path len !off);
    let rt = get_u16 d (!off + 2) in
    let tag = rt lsr 8 in
    let p = !off + 4 in
    let plen = len - 4 in
    (match tag with
     | 0x03 when plen = 16 -> (* UNITS *)
       dbu_um := get_real d p
     | 0x05 -> (* BGNSTR *)
       cur_name := ""; cur_polys := []; cur_paths := []; cur_refs := []; cur_labels := []; cur_elems := []
     | 0x06 -> cur_name := get_string d p plen (* STRNAME *)
     | 0x07 -> finish_cell !off (* ENDSTR *)
     | 0x08 -> (* BOUNDARY *)
       el_start := !off;
       el_kind := `boundary; e_layer := 0; e_dt := 0; e_xy := [||]
     | 0x09 -> (* PATH *)
       el_start := !off;
       el_kind := `path; e_layer := 0; e_dt := 0; e_width := 0;
       e_ptype := 0; e_bgn := 0; e_end := 0; e_xy := [||]
     | 0x0a | 0x0b -> (* SREF / AREF *)
       el_start := !off; e_colrow := None;
       el_kind := `sref; e_sname := ""; e_strans := false;
       e_mag := 1.0; e_angle := 0.0; e_xy := [||]
     | 0x0c -> (* TEXT *)
       el_start := !off;
       el_kind := `text; e_layer := 0; e_tt := 0; e_xy := [||]; e_text := "";
       e_strans := false; e_mag := 1.0; e_angle := 0.0
     | 0x0d -> e_layer := get_i16 d p (* LAYER *)
     | 0x0e -> e_dt := get_i16 d p (* DATATYPE *)
     | 0x0f -> e_width := get_i32 d p (* WIDTH *)
     | 0x10 -> (* XY *)
       let cnt = plen / 8 in
       let a = Array.make cnt (0, 0) in
       for i = 0 to cnt - 1 do
         a.(i) <- (get_i32 d (p + i * 8), get_i32 d (p + i * 8 + 4))
       done;
       e_xy := a
     | 0x13 -> (* COLROW *)
       e_colrow := Some (get_i16 d p, get_i16 d (p + 2))
     | 0x11 -> (* ENDEL *)
       cur_elems := { ekind = !el_kind; elayer = !e_layer; edt = !e_dt;
                      estart = !el_start; eend = !off + len; exy = !e_xy;
                      esname = (if !el_kind = `sref then !e_sname else "") }
                    :: !cur_elems;
       (match !el_kind with
        | `boundary ->
          let pts = !e_xy in
          let pts =
            (* first point repeated at end: drop it *)
            if Array.length pts >= 2 && pts.(0) = pts.(Array.length pts - 1)
            then Array.sub pts 0 (Array.length pts - 1) else pts
          in
          cur_polys := { player = !e_layer; pdt = !e_dt; ppts = pts } :: !cur_polys
        | `path ->
          cur_paths := { hlayer = !e_layer; hdt = !e_dt; hwidth = !e_width;
                         htype = !e_ptype; hbgn = !e_bgn; hend = !e_end;
                         hpts = !e_xy } :: !cur_paths
        | `sref ->
          let org = if Array.length !e_xy > 0 then !e_xy.(0) else (0, 0) in
          cur_refs := { rcell = !e_sname;
                        rorigin = (Float.of_int (fst org), Float.of_int (snd org));
                        rxrefl = !e_strans;
                        rmag = !e_mag; rangle = !e_angle;
                        rarray = (match !e_colrow with
                          | Some (c, r) when Array.length !e_xy = 3 ->
                            Some (c, r, !e_xy.(1), !e_xy.(2))
                          | _ -> None) } :: !cur_refs
        | `text ->
          let org = if Array.length !e_xy > 0 then !e_xy.(0) else (0, 0) in
          cur_labels := { lx = Float.of_int (fst org); ly = Float.of_int (snd org);
                          llayer = !e_layer; ltexttype = !e_tt; ltext = !e_text }
                        :: !cur_labels
        | `none -> ());
       el_kind := `none
     | 0x12 -> e_sname := get_string d p plen (* SNAME *)
     | 0x16 -> e_tt := get_i16 d p (* TEXTTYPE *)
     | 0x19 -> e_text := get_string d p plen (* STRING *)
     | 0x1a -> e_strans := (get_u16 d p land 0x8000) <> 0 (* STRANS *)
     | 0x1b -> e_mag := get_real d p (* MAG *)
     | 0x1c -> e_angle := get_real d p (* ANGLE *)
     | 0x21 -> e_ptype := get_i16 d p (* PATHTYPE *)
     | 0x30 -> e_bgn := get_i32 d p (* BGNEXTN *)
     | 0x31 -> e_end := get_i32 d p (* ENDEXTN *)
     | _ -> ());
    off := !off + len
  done;
  { cells; cell_order = List.rev !order; dbu_um = !dbu_um }

(* ---- affine transforms (2x3 matrix) ----
   x' = a*x + b*y + c ;  y' = d*x + e*y + f *)
type xform = { a : float; b : float; c : float; d : float; e : float; f : float }

let xid = { a = 1.0; b = 0.0; c = 0.0; d = 0.0; e = 1.0; f = 0.0 }

let xcompose p q =
  (* apply q first, then p *)
  { a = p.a *. q.a +. p.b *. q.d;
    b = p.a *. q.b +. p.b *. q.e;
    c = p.a *. q.c +. p.b *. q.f +. p.c;
    d = p.d *. q.a +. p.e *. q.d;
    e = p.d *. q.b +. p.e *. q.e;
    f = p.d *. q.c +. p.e *. q.f +. p.f }

let xapply t (x, y) = (t.a *. x +. t.b *. y +. t.c, t.d *. x +. t.e *. y +. t.f)

(* reference transform: reflect (y:=-y) if STRANS, scale by MAG,
   rotate by ANGLE (CCW degrees), translate by origin *)
let ref_xform (r : ref_) =
  let refl = if r.rxrefl then { a = 1.0; b = 0.0; c = 0.0; d = 0.0; e = -1.0; f = 0.0 }
             else xid in
  let m = r.rmag in
  let scale = { a = m; b = 0.0; c = 0.0; d = 0.0; e = m; f = 0.0 } in
  let th = r.rangle *. Float.pi /. 180.0 in
  let ct = Float.cos th and st = Float.sin th in
  let rot = { a = ct; b = -.st; c = 0.0; d = st; e = ct; f = 0.0 } in
  let ox, oy = r.rorigin in
  let tr = { a = 1.0; b = 0.0; c = ox; d = 0.0; e = 1.0; f = oy } in
  xcompose tr (xcompose rot (xcompose scale refl))

(* An AREF as the list of its placements (an SREF is a list of one).  The
   second and third XY points are the far ends of the column and row
   displacement vectors, measured from the origin. *)
let expand_array (r : ref_) : ref_ list =
  match r.rarray with
  | None -> [ r ]
  | Some (cols, rows, (cx, cy), (rx, ry)) ->
    let ox, oy = r.rorigin in
    let dcx = (Float.of_int cx -. ox) /. Float.of_int cols
    and dcy = (Float.of_int cy -. oy) /. Float.of_int cols in
    let drx = (Float.of_int rx -. ox) /. Float.of_int rows
    and dry = (Float.of_int ry -. oy) /. Float.of_int rows in
    List.concat_map (fun i ->
      List.map (fun j ->
        let fi = Float.of_int i and fj = Float.of_int j in
        { r with rarray = None;
                 rorigin = (ox +. fi *. dcx +. fj *. drx, oy +. fi *. dcy +. fj *. dry) })
        (List.init rows Fun.id))
      (List.init cols Fun.id)

(* ---- path -> rectangle polygons (in local dbu coords, floats) ----
   Each segment becomes one rectangle; consecutive rectangles overlap at the
   joint, so union-find merges them. *)
let path_rects (h : path) : (float * float) array list =
  let pts = h.hpts in
  let np = Array.length pts in
  let w = Float.of_int h.hwidth in
  let hw = w /. 2.0 in
  let ext_b, ext_e =
    match h.htype with
    | 0 -> (0.0, 0.0)
    | 2 -> (hw, hw)
    | 4 -> (Float.of_int h.hbgn, Float.of_int h.hend)
    | _ -> (hw, hw) (* round ends: approximate with square *)
  in
  let rects = ref [] in
  for i = 0 to np - 2 do
    let x1, y1 = pts.(i) and x2, y2 = pts.(i + 1) in
    let x1 = Float.of_int x1 and y1 = Float.of_int y1 in
    let x2 = Float.of_int x2 and y2 = Float.of_int y2 in
    let dx = x2 -. x1 and dy = y2 -. y1 in
    let len = Float.sqrt (dx *. dx +. dy *. dy) in
    if len > 0.0 then begin
      let ux = dx /. len and uy = dy /. len in
      (* perpendicular *)
      let px = -.uy *. hw and py = ux *. hw in
      let sx = if i = 0 then ux *. ext_b else 0.0 in
      let sy = if i = 0 then uy *. ext_b else 0.0 in
      let ex = if i = np - 2 then ux *. ext_e else 0.0 in
      let ey = if i = np - 2 then uy *. ext_e else 0.0 in
      let r = [| (x1 -. sx +. px, y1 -. sy +. py);
                 (x2 +. ex +. px, y2 +. ey +. py);
                 (x2 +. ex -. px, y2 +. ey -. py);
                 (x1 -. sx -. px, y1 -. sy -. py) |] in
      rects := r :: !rects
    end
  done;
  !rects

(* flatten a cell's geometry (deep) into local-coordinate polygons:
   returns (layer, datatype, points in local dbu floats) list.
   Memoized per cell. *)
let flatten_local (lib : lib) : (string, (int * int * (float * float) array) list) Hashtbl.t =
  let cache = Hashtbl.create 64 in
  let rec flat cname =
    match Hashtbl.find_opt cache cname with
    | Some v -> v
    | None ->
      Hashtbl.replace cache cname []; (* guard against cycles *)
      let c = Hashtbl.find lib.cells cname in
      let out = ref [] in
      List.iter (fun (p : poly) ->
        let pts = Array.map (fun (x, y) -> (Float.of_int x, Float.of_int y)) p.ppts in
        out := (p.player, p.pdt, pts) :: !out) c.polys;
      List.iter (fun (h : path) ->
        List.iter (fun r -> out := (h.hlayer, h.hdt, r) :: !out) (path_rects h))
        c.paths;
      List.iter (fun (r : ref_) ->
        if Hashtbl.mem lib.cells r.rcell then
          List.iter (fun r ->
            let xf = ref_xform r in
            List.iter (fun (lay, dt, pts) ->
              out := (lay, dt, Array.map (xapply xf) pts) :: !out)
              (flat r.rcell))
            (expand_array r)) c.refs;
      Hashtbl.replace cache cname !out;
      !out
  in
  List.iter (fun c -> ignore (flat c.name)) lib.cell_order;
  cache
