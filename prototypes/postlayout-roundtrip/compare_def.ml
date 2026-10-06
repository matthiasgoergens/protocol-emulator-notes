(* Compare the extraction with the place-and-route run's own record, per
   placement and per net, not by cell-type counts.

   compare_def.exe GDS TOP DEF NL.V CELL.LEF [MACRO.LEF ...]

   SRAM macros (macros.ml) are compared like standard cells: their
   placements by (master, x, y, orientation) from their LEF's SIZE, their
   pins as endpoints; nl.v connects a macro's bus pins by concatenation,
   "{msb, ..., lsb}", which is read bit by bit.

   (a) Placements.  Every standard-cell reference in the GDS is turned into
       the DEF's form, (master, x, y, orientation), and the two multisets are
       compared; every extracted instance then takes its DEF name from that
       key, which must be unique.  The trap (Shapovalov's paper on
       FigureZig/asicrev, section II-B): a GDS reference gives the cell's
       origin, a DEF placement gives the lower-left corner of the cell's
       abutment box after orientation, and for a flipped or rotated cell the
       two differ by the cell's width or height.  So the abutment box is
       transformed by the reference and its lower-left taken, and the naive
       key (origin = DEF position) is also counted, to show what it would
       have scored.  All eight LEF/DEF orientations are mapped, as retrace
       found it needed once a macro was placed at E (elementalcollision/
       retrace, docs/TEMPO_LVS.md section 1.3); the map below is derived from
       the transforms, not copied.
   (b) Nets against the DEF's NETS and (c) against the final netlist nl.v:
       each net is the set of its endpoints, (instance, pin) or (PIN, port),
       and the extraction is compared with the record as a partition of
       endpoints, never by net name (Ebert's and JGalil's comparisons, and
       retrace's checks (b) and (c) in the same document).  For every net
       that differs the report says whether the extraction split it (its
       endpoints fall into several extracted nets) or merged it with another.
       Supply pins are not in either record's signal nets and are not
       extracted as pins, so they do not appear on either side. *)

let starts_with = Extract.starts_with

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

(* DEF and Verilog escape brackets in names; one spelling for comparison *)
let unescape s =
  let b = Buffer.create (String.length s) in
  String.iter (fun c -> if c <> '\\' then Buffer.add_char b c) s;
  Buffer.contents b

(* ---- LEF: SIZE and ORIGIN of each macro, in microns ---- *)

let parse_lef path =
  let tbl = Hashtbl.create 128 in
  let cur = ref None in
  String.split_on_char '\n' (read_file path) |> List.iter (fun line ->
    match String.split_on_char ' ' (String.trim line) |> List.filter (( <> ) "") with
    | [ "MACRO"; name ] -> cur := Some name; Hashtbl.replace tbl name ((0.0, 0.0), (0.0, 0.0))
    | "SIZE" :: w :: "BY" :: h :: _ ->
      Option.iter (fun n ->
        let o, _ = Hashtbl.find tbl n in
        Hashtbl.replace tbl n (o, (float_of_string w, float_of_string h))) !cur
    | "ORIGIN" :: x :: y :: _ ->
      Option.iter (fun n ->
        let _, sz = Hashtbl.find tbl n in
        Hashtbl.replace tbl n ((float_of_string x, float_of_string y), sz)) !cur
    | [ "END"; name ] when Some name = !cur -> cur := None
    | _ -> ());
  tbl

(* ---- DEF: components and signal nets ---- *)

type def = {
  units : int;
  comps : (string * string * int * int * string) list;  (* name, master, x, y, orient *)
  nets : (string * (string * string) list) list;        (* name, endpoints *)
}

(* DEF statements end with ';'; tokens are separated by blanks *)
let parse_def path =
  let toks = Array.of_list (String.split_on_char ' ' (String.map (function '\n' | '\t' | '\r' -> ' ' | c -> c) (read_file path))
                            |> List.filter (( <> ) "")) in
  let n = Array.length toks in
  let units = ref 1000 and comps = ref [] and nets = ref [] in
  let i = ref 0 in
  let section = ref "" in
  while !i < n do
    let t = toks.(!i) in
    (match t with
     | "UNITS" when !section = "" -> units := int_of_string toks.(!i + 3); i := !i + 4
     | "COMPONENTS" | "NETS" | "SPECIALNETS" | "PINS" when !section = "" -> section := t
     | "END" when !i + 1 < n && toks.(!i + 1) = !section -> section := ""; incr i
     | "-" when !section = "COMPONENTS" ->
       let name = unescape toks.(!i + 1) and master = toks.(!i + 2) in
       let j = ref (!i + 3) in
       while toks.(!j) <> ";" && toks.(!j) <> "PLACED" && toks.(!j) <> "FIXED" do incr j done;
       if toks.(!j) <> ";" then begin
         (* PLACED ( x y ) orient *)
         let x = int_of_string toks.(!j + 2) and y = int_of_string toks.(!j + 3) in
         comps := (name, master, x, y, toks.(!j + 5)) :: !comps
       end;
       while toks.(!j) <> ";" do incr j done;
       i := !j
     | "-" when !section = "NETS" ->
       let name = unescape toks.(!i + 1) in
       let j = ref (!i + 2) and eps = ref [] in
       (* endpoints come first, as "( inst pin )"; then "+" attributes *)
       while toks.(!j) = "(" do
         eps := (unescape toks.(!j + 1), unescape toks.(!j + 2)) :: !eps;
         j := !j + 4
       done;
       while toks.(!j) <> ";" do incr j done;
       nets := (name, List.rev !eps) :: !nets;
       i := !j
     | _ -> ());
    incr i
  done;
  { units = !units; comps = List.rev !comps; nets = List.rev !nets }

(* ---- nl.v: instances and their connections, as nets ---- *)

let verilog_tokens s =
  let n = String.length s in
  let toks = ref [] and i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    if c = '/' && !i + 1 < n && s.[!i + 1] = '/' then
      while !i < n && s.[!i] <> '\n' do incr i done
    else if c = '/' && !i + 1 < n && s.[!i + 1] = '*' then begin
      i := !i + 2;
      while !i + 1 < n && not (s.[!i] = '*' && s.[!i + 1] = '/') do incr i done;
      i := !i + 2
    end
    else if c = '\\' then begin
      (* escaped identifier: up to white space *)
      let j = ref (!i + 1) in
      while !j < n && not (List.mem s.[!j] [ ' '; '\n'; '\t'; '\r' ]) do incr j done;
      toks := String.sub s (!i + 1) (!j - !i - 1) :: !toks;
      i := !j
    end
    else if List.mem c [ '('; ')'; ','; ';'; '.'; '='; '{'; '}' ] then begin
      toks := String.make 1 c :: !toks; incr i
    end
    else if List.mem c [ ' '; '\n'; '\t'; '\r' ] then incr i
    else begin
      let j = ref !i in
      while !j < n && not (List.mem s.[!j] [ ' '; '\n'; '\t'; '\r'; '('; ')'; ','; ';'; '.'; '='; '{'; '}' ]) do incr j done;
      (* keep a bit select with its name: "pcs[3]" *)
      toks := String.sub s !i (!j - !i) :: !toks;
      i := !j
    end
  done;
  Array.of_list (List.rev !toks)

(* Returns the endpoint sets of nl.v's nets, and the number of assign
   statements and constant connections seen. *)
let parse_nl ~is_cell ~ports path =
  let t = verilog_tokens (read_file path) in
  let n = Array.length t in
  let members : (string, (string * string) list) Hashtbl.t = Hashtbl.create 4096 in
  let add net ep = Hashtbl.replace members net (ep :: Option.value ~default:[] (Hashtbl.find_opt members net)) in
  let assigns = ref [] and consts = ref 0 and insts = ref 0 in
  let i = ref 0 in
  while !i < n do
    if is_cell t.(!i) && !i + 2 < n && t.(!i + 2) = "(" then begin
      let inst = t.(!i + 1) in
      incr insts;
      let j = ref (!i + 3) in
      let connect pin net = if String.contains net '\'' then incr consts else add net (inst, pin) in
      while t.(!j) <> ";" do
        if t.(!j) = "." then begin
          let pin = t.(!j + 1) in
          (* .PIN ( net ), .PIN ( ), or a macro's bus .PIN ( { msb , ... , lsb } ) *)
          if t.(!j + 3) = "{" then begin
            let k = ref (!j + 4) and bits = ref [] in
            while t.(!k) <> "}" do
              if t.(!k) <> "," then bits := t.(!k) :: !bits;
              incr k
            done;
            (* !bits is LSB first *)
            List.iteri (fun b net -> connect (Printf.sprintf "%s[%d]" pin b) net) !bits;
            j := !k + 2
          end
          else begin
            if t.(!j + 3) <> ")" then connect pin t.(!j + 3);
            j := !j + 4
          end
        end else incr j
      done;
      i := !j
    end
    else if t.(!i) = "assign" then begin
      assigns := (t.(!i + 1), t.(!i + 3)) :: !assigns;
      i := !i + 5
    end
    else incr i
  done;
  List.iter (fun p -> add p ("PIN", p)) ports;
  (* assign a = b joins the two names into one net *)
  let parent = Hashtbl.create 64 in
  let rec find x = match Hashtbl.find_opt parent x with Some p when p <> x -> find p | _ -> x in
  List.iter (fun (a, b) -> let ra = find a and rb = find b in if ra <> rb then Hashtbl.replace parent ra rb) !assigns;
  let merged = Hashtbl.create 4096 in
  Hashtbl.iter (fun net eps ->
    let r = find net in
    Hashtbl.replace merged r (eps @ Option.value ~default:[] (Hashtbl.find_opt merged r))) members;
  (Hashtbl.fold (fun _ eps acc -> eps :: acc) merged [], List.length !assigns, !consts, !insts)

(* ---- orientation ---- *)

(* The 2x2 linear part of each DEF orientation, (a, b, d, e) for
   x' = a x + b y, y' = d x + e y, from the LEF/DEF definitions: N, S, W, E
   rotate by 0, 180, 90 and 270 degrees counter-clockwise; FN, FS, FW, FE
   are the same rotations applied after mirroring about the y axis. *)
let orientations =
  [ ("N", (1, 0, 0, 1)); ("S", (-1, 0, 0, -1)); ("W", (0, -1, 1, 0)); ("E", (0, 1, -1, 0));
    ("FN", (-1, 0, 0, 1)); ("FS", (1, 0, 0, -1)); ("FW", (0, 1, 1, 0)); ("FE", (0, -1, -1, 0)) ]

let orient_of_ref (r : Gds.ref_) =
  let xf = Gds.ref_xform r in
  let ri v = int_of_float (Float.round v) in
  let m = (ri xf.a, ri xf.b, ri xf.d, ri xf.e) in
  match List.find_opt (fun (_, m') -> m' = m) orientations with
  | Some (o, _) -> o
  | None -> failwith (Printf.sprintf "reference to %s: not one of the eight orientations" r.rcell)

(* DEF position of a reference: lower-left of the transformed abutment box
   (LEF ORIGIN and SIZE, in DEF units) *)
let def_position ~units ~lef (r : Gds.ref_) =
  let (ox, oy), (w, h) =
    match Hashtbl.find_opt lef r.rcell with
    | Some v -> v
    | None -> failwith ("no LEF macro " ^ r.rcell) in
  let u v = v *. Float.of_int units in
  (* the abutment box in the cell's own coordinates: LEF ORIGIN moves the
     cell's origin to (ox, oy) inside the box, so the box starts at -origin *)
  let x0 = -.u ox and y0 = -.u oy in
  let x1 = x0 +. u w and y1 = y0 +. u h in
  let xf = Gds.ref_xform r in
  let pts = List.map (Gds.xapply xf) [ (x0, y0); (x1, y0); (x0, y1); (x1, y1) ] in
  let ri v = int_of_float (Float.round v) in
  (ri (List.fold_left (fun m (x, _) -> Float.min m x) Float.infinity pts),
   ri (List.fold_left (fun m (_, y) -> Float.min m y) Float.infinity pts))

(* ---- partitions ---- *)

let canon eps = List.sort_uniq compare eps

(* Compare two lists of nets as partitions of their endpoints. *)
let compare_partitions ~label ~(ours : (string * string) list list) ~(theirs : (string * string) list list) =
  let ours = List.map canon ours |> List.filter (( <> ) []) in
  let theirs = List.map canon theirs |> List.filter (( <> ) []) in
  (* A pin on no wire is a net of one endpoint in the extraction and absent
     from the record (DEF lists no such net, nl.v leaves the pin out or
     empty): the same partition, so such singletons are set aside on either
     side, and counted.  The usual case is a dummy load that clock-tree synthesis adds (clkloadN). *)
  let endpoints l = let h = Hashtbl.create 8192 in List.iter (List.iter (fun e -> Hashtbl.replace h e ())) l; h in
  let eo = endpoints ours and et = endpoints theirs in
  let lone other = function [ e ] -> not (Hashtbl.mem other e) | _ -> false in
  let lone_ours = List.filter (lone et) ours and lone_theirs = List.filter (lone eo) theirs in
  let ours = List.filter (fun x -> not (lone et x)) ours and theirs = List.filter (fun x -> not (lone eo x)) theirs in
  Printf.printf "%s: pins on no wire, set aside: %d in the extraction (%s), %d in the record\n" label
    (List.length lone_ours) (String.concat " " (List.map (fun l -> let a, b = List.hd l in a ^ "/" ^ b) lone_ours))
    (List.length lone_theirs);
  let set l = let h = Hashtbl.create 4096 in List.iter (fun x -> Hashtbl.replace h x ()) l; h in
  let so = set ours and st = set theirs in
  let same = List.length (List.filter (Hashtbl.mem st) ours) in
  let only_ours = List.filter (fun x -> not (Hashtbl.mem st x)) ours in
  let only_theirs = List.filter (fun x -> not (Hashtbl.mem so x)) theirs in
  (* where each endpoint lives, on each side *)
  let index l = let h = Hashtbl.create 8192 in List.iteri (fun i eps -> List.iter (fun e -> Hashtbl.replace h e i) eps) l; h in
  let io = index ours and it = index theirs in
  let ep_ours = Hashtbl.length io and ep_theirs = Hashtbl.length it in
  let missing_ours = Hashtbl.fold (fun e _ acc -> if Hashtbl.mem io e then acc else e :: acc) it [] |> List.sort compare in
  let missing_theirs = Hashtbl.fold (fun e _ acc -> if Hashtbl.mem it e then acc else e :: acc) io [] |> List.sort compare in
  let splits = List.filter (fun eps ->
      List.length (List.sort_uniq compare (List.filter_map (Hashtbl.find_opt io) eps)) > 1) theirs in
  let merges = List.filter (fun eps ->
      List.length (List.sort_uniq compare (List.filter_map (Hashtbl.find_opt it) eps)) > 1) ours in
  let singles l = List.length (List.filter (fun eps -> List.length eps = 1) l) in
  Printf.printf "%s: extraction %d nets (%d single-endpoint) over %d endpoints; record %d nets (%d single-endpoint) over %d endpoints\n"
    label (List.length ours) (singles ours) ep_ours (List.length theirs) (singles theirs) ep_theirs;
  Printf.printf "%s: %d nets identical as endpoint sets; %d only in the extraction, %d only in the record; %d record nets split, %d extracted nets merge record nets\n"
    label same (List.length only_ours) (List.length only_theirs) (List.length splits) (List.length merges);
  Printf.printf "%s: %d endpoints only in the record, %d only in the extraction\n" label
    (List.length missing_ours) (List.length missing_theirs);
  let show what l = List.iteri (fun i eps -> if i < 10 then
      Printf.printf "    %s: %s\n" what (String.concat " " (List.map (fun (a, b) -> a ^ "/" ^ b) eps))) l in
  show "only in the extraction" only_ours;
  show "only in the record" only_theirs;
  List.iteri (fun i (a, b) -> if i < 10 then Printf.printf "    endpoint missing from the extraction: %s/%s\n" a b) missing_ours;
  List.iteri (fun i (a, b) -> if i < 10 then Printf.printf "    endpoint missing from the record: %s/%s\n" a b) missing_theirs;
  only_ours = [] && only_theirs = []

let () =
  let gds, top, def_path, nl_path, lef_paths =
    match Array.to_list Sys.argv |> List.tl with
    | g :: t :: d :: n :: (_ :: _ as l) -> (g, t, d, n, l)
    | _ -> prerr_endline "usage: compare_def.exe GDS TOP DEF NL.V CELL.LEF [MACRO.LEF ...]"; exit 2 in
  let nl, _ = Extract.extract ~gds_path:gds ~top_name:top () in
  let tech = nl.tech in
  (* the placements and nets compared: the library's standard cells and the
     SRAM macros (macros.ml) *)
  let is_cell m = starts_with m tech.cell_prefix || Macros.is_macro m in
  let lef = Hashtbl.create 128 in
  List.iter (fun p -> Hashtbl.iter (Hashtbl.replace lef) (parse_lef p)) lef_paths;
  let def = parse_def def_path in
  let lib = Gds.parse gds in
  if Float.abs (lib.Gds.dbu_um *. Float.of_int def.units -. 1.0) > 1e-9 then
    failwith "GDS database unit and DEF units differ; positions would need scaling";
  (* cross-check the LEF abutment box against the cell GDS's own prBoundary
     (189/4 in the IHP cells), where the cell has one *)
  let boundary_ok = ref 0 and boundary_bad = ref [] in
  Hashtbl.iter (fun name ((ox, oy), (w, h)) ->
    match Hashtbl.find_opt lib.cells name with
    | None -> ()
    | Some c ->
      List.iter (fun (p : Gds.poly) ->
        if p.player = 189 && p.pdt = 4 then begin
          let xs = Array.map fst p.ppts and ys = Array.map snd p.ppts in
          let mn a = Array.fold_left min max_int a and mx a = Array.fold_left max min_int a in
          let u v = int_of_float (Float.round (v *. Float.of_int def.units)) in
          if (mn xs, mn ys, mx xs, mx ys) = (-u ox, -u oy, u w - u ox, u h - u oy) then incr boundary_ok
          else boundary_bad := name :: !boundary_bad
        end) c.polys) lef;
  Printf.printf "abutment boxes: %d cells' prBoundary equals the LEF ORIGIN/SIZE box, %d differ%s\n" !boundary_ok
    (List.length !boundary_bad) (String.concat "" (List.map (fun n -> " " ^ n) !boundary_bad));
  (* (a) placements *)
  let top_cell = Hashtbl.find lib.cells top in
  let refs = List.concat_map Gds.expand_array top_cell.refs
             |> List.filter (fun (r : Gds.ref_) -> is_cell r.rcell) in
  let key_of r = let x, y = def_position ~units:def.units ~lef r in (r.Gds.rcell, x, y, orient_of_ref r) in
  let naive_key_of (r : Gds.ref_) =
    let x, y = r.rorigin in (r.rcell, int_of_float x, int_of_float y, orient_of_ref r) in
  let def_keys = Hashtbl.create 4096 in
  List.iter (fun (name, m, x, y, o) ->
    if is_cell m then
      Hashtbl.replace def_keys (m, x, y, o) (name :: Option.value ~default:[] (Hashtbl.find_opt def_keys (m, x, y, o))))
    def.comps;
  let ndef = List.length (List.filter (fun (_, m, _, _, _) -> is_cell m) def.comps) in
  let nmacro_refs = List.length (List.filter (fun (r : Gds.ref_) -> Macros.is_macro r.rcell) refs) in
  let nmacro_def = List.length (List.filter (fun (_, m, _, _, _) -> Macros.is_macro m) def.comps) in
  let count f = List.length (List.filter f refs) in
  let matched = count (fun r -> Hashtbl.mem def_keys (key_of r)) in
  let naive = count (fun r -> Hashtbl.mem def_keys (naive_key_of r)) in
  let orients = Hashtbl.create 8 in
  List.iter (fun r -> let o = orient_of_ref r in
              Hashtbl.replace orients o (1 + Option.value ~default:0 (Hashtbl.find_opt orients o))) refs;
  Printf.printf "placements: GDS %d standard-cell and macro references (%d macros; orientations%s), DEF %d components of the library and macros (%d macros)\n"
    (List.length refs) nmacro_refs
    (String.concat "" (List.map (fun (o, _) ->
       match Hashtbl.find_opt orients o with Some c -> Printf.sprintf " %s %d" o c | None -> "") orientations))
    ndef nmacro_def;
  Printf.printf "placements: %d of %d match a DEF component by (master, x, y, orientation); with the GDS origin taken as the DEF position, %d would\n"
    matched (List.length refs) naive;
  let ambiguous = Hashtbl.fold (fun _ ns acc -> if List.length ns > 1 then acc + 1 else acc) def_keys 0 in
  if ambiguous > 0 then Printf.printf "placements: %d DEF keys are shared by more than one component\n" ambiguous;
  (* the GDS multiset against the DEF multiset: each DEF key used once *)
  let used = Hashtbl.create 4096 in
  List.iter (fun r -> let k = key_of r in
              Hashtbl.replace used k (1 + Option.value ~default:0 (Hashtbl.find_opt used k))) refs;
  let def_unmatched = Hashtbl.fold (fun k ns acc ->
      let u = Option.value ~default:0 (Hashtbl.find_opt used k) in
      if u <> List.length ns then (k, ns) :: acc else acc) def_keys [] in
  List.iteri (fun i ((m, x, y, o), ns) -> if i < 10 then
      Printf.printf "    DEF component not placed once in the GDS: %s %s (%d %d) %s\n" (String.concat "," ns) m x y o)
    def_unmatched;
  let placements_ok = matched = List.length refs && List.length refs = ndef && def_unmatched = [] in
  (* names for the extracted instances *)
  let name_of = Hashtbl.create 4096 in
  let unnamed = ref 0 in
  Array.iter (fun (inst : Extract.inst) ->
    match Hashtbl.find_opt def_keys (key_of inst.iref) with
    | Some [ n ] -> Hashtbl.replace name_of inst.iname n
    | _ -> incr unnamed) nl.instances;
  Printf.printf "names: %d of %d extracted instances named from the DEF (%d not)\n"
    (Hashtbl.length name_of) (Array.length nl.instances) !unnamed;
  (* extracted nets as endpoint sets *)
  let power = List.filter_map (fun (p, n) -> if List.mem p Check.power_ports then n else None) nl.ports in
  let members = Array.make nl.nnets [] in
  Array.iter (fun (inst : Extract.inst) ->
    let iname = Option.value ~default:inst.iname (Hashtbl.find_opt name_of inst.iname) in
    List.iter (fun (p, n) -> Option.iter (fun x -> members.(x) <- (iname, p) :: members.(x)) n) inst.nets)
    nl.instances;
  List.iter (fun (p, n) ->
    if not (List.mem p Check.power_ports) then
      Option.iter (fun x -> members.(x) <- ("PIN", p) :: members.(x)) n) nl.ports;
  let ours = Array.to_list (Array.mapi (fun i eps -> if List.mem i power then [] else eps) members) in
  Printf.printf "supplies: %d extracted supply nets (by top-level label %s) left out\n" (List.length power)
    (String.concat "/" (List.filter (fun p -> List.mem_assoc p nl.ports) Check.power_ports));
  (* (b) against the DEF's NETS *)
  let def_nets = List.map (fun (_, eps) -> List.map (fun (a, b) -> if a = "PIN" then ("PIN", b) else (a, b)) eps) def.nets in
  let ok_def = compare_partitions ~label:"nets vs DEF" ~ours ~theirs:def_nets in
  (* (c) against nl.v *)
  let ports = List.filter_map (fun (p, _) -> if List.mem p Check.power_ports then None else Some p) nl.ports in
  let nl_nets, nassign, nconst, ninst = parse_nl ~is_cell ~ports nl_path in
  Printf.printf "nl.v: %d instances, %d assign statements, %d constant connections\n" ninst nassign nconst;
  let ok_nl = compare_partitions ~label:"nets vs nl.v" ~ours ~theirs:nl_nets in
  let ok = placements_ok && !unnamed = 0 && ok_def && ok_nl in
  print_endline (if ok then "COMPARISON CLEAN" else "COMPARISON DIFFERS");
  exit (if ok then 0 else 1)
