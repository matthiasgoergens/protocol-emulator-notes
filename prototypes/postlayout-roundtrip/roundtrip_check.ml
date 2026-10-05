(* Post-layout round trip, block-independent half: extract a gate-level
   netlist from a routed SG13G2 GDS and check it structurally against the
   RTL's port list.  With "controls", also plant cuts and shorts in copies of
   the GDS and show that each is caught.

   roundtrip_check.exe check    GDS TOP RTL.v MODELS.v [NETLIST_OUT]
   roundtrip_check.exe controls GDS TOP RTL.v MODELS.v OUTDIR N SEED *)

let time f =
  let t0 = Unix.gettimeofday () in
  let r = f () in
  (r, Unix.gettimeofday () -. t0)

let starts_with = Extract.starts_with

let log s = Printf.printf "  %s\n%!" s

let extract_and_check ?(quiet = false) ~gds ~top ~lib ~ports () =
  let (nl, geo), t_ext =
    time (fun () -> Extract.extract ~log:(if quiet then ignore else log) ~gds_path:gds ~top_name:top ()) in
  let report, t_chk = time (fun () -> Check.run ~lib ~ports ~clock:"clock" nl) in
  (nl, geo, report, t_ext, t_chk)

let print_report (r : Check.report) ~limit =
  List.iter (fun (k, v) -> Printf.printf "  %-28s %d\n" k v) r.stats;
  Printf.printf "  errors: %d, warnings: %d\n" (List.length r.errors) (List.length r.warnings);
  List.iteri (fun i e -> if i < limit then Printf.printf "    ERROR %s\n" e) r.errors;
  List.iteri (fun i e -> if i < limit then Printf.printf "    warn  %s\n" e) r.warnings

let check gds top rtl models out =
  let lib, t_lib = time (fun () -> Cells.parse_library models) in
  let ports = Check.rtl_ports rtl in
  Printf.printf "models: %d cells read in %.2f s; RTL ports: %d bits\n" (Hashtbl.length lib) t_lib
    (List.length ports);
  let nl, _, report, t_ext, t_chk = extract_and_check ~gds ~top ~lib ~ports () in
  Printf.printf "extract: %.2f s (%d shapes, %d components, %d instances, %d nets)\ncheck: %.3f s\n"
    t_ext nl.nshapes nl.ncomponents (Array.length nl.instances) nl.nnets t_chk;
  print_report report ~limit:50;
  Option.iter (Extract.write_netlist nl) out;
  (* the netlist must also simulate: build the flattened model *)
  let sim, t_sim = time (fun () -> Sim.create lib nl) in
  Printf.printf "simulator: %d primitive gates, %d flip-flops, built in %.2f s\n"
    (Array.length sim.gates) (Array.length sim.ffs) t_sim;
  let ok = report.errors = [] in
  print_endline (if ok then "STRUCTURE CLEAN" else "STRUCTURE ERRORS");
  exit (if ok then 0 else 1)

(* ---- planted faults ---- *)

let is_signal_net (nl : Extract.netlist) =
  let power = List.filter_map (fun (p, n) -> if List.mem p Check.power_ports then n else None) nl.ports in
  fun n -> not (List.mem n power)

let controls gds top rtl models outdir n seed =
  Random.init seed;
  let lib = Cells.parse_library models in
  let ports = Check.rtl_ports rtl in
  let nl, geo, report, t_ext, _ = extract_and_check ~quiet:true ~gds ~top ~lib ~ports () in
  Printf.printf "baseline: %d errors (extract %.2f s)\n" (List.length report.errors) t_ext;
  if report.errors <> [] then failwith "baseline is not clean; controls would mean nothing";
  let signal = is_signal_net nl in
  let gdslib = Gds.parse gds in
  let topc = Hashtbl.find gdslib.Gds.cells top in
  let k = gdslib.Gds.dbu_um *. 1e5 in (* centi-dbu per dbu *)
  (* shape bbox -> net, to name the net an element of the top cell belongs to *)
  let net_of_bbox = Hashtbl.create 65536 in
  Array.iteri (fun i (s : Extract.shape) ->
    Option.iter (fun net -> Hashtbl.replace net_of_bbox (s.kind, s.bbox) net) geo.shape_net.(i))
    geo.shapes;
  (* The element of the top cell a cut removes, and the net it is on.  A
     Magic-written GDS (the sg13g2 run) has every wire and via cut as a
     boundary in the top cell; a KLayout-written one (the sg13cmos5l run)
     has wires as paths and vias as references to VIA_* cells, so a control
     that only looked at boundaries removed nothing but redundant patches
     (ten of ten cuts had no effect on the first sg13cmos5l run). *)
  let lookup kind pts =
    let pts = Array.map (Extract.quant gdslib.Gds.dbu_um) pts in
    Hashtbl.find_opt net_of_bbox (kind, Extract.bbox_of pts) in
  let fl (x, y) = (Float.of_int x, Float.of_int y) in
  let via_cut_layer name =
    match Hashtbl.find_opt gdslib.cells name with
    | Some c ->
      List.find_map (fun (p : Gds.poly) ->
        if Extract.via_metals nl.tech p.player <> None && p.pdt = Extract.via_datatype then Some p else None) c.polys
    | None -> None in
  let elem_layer (e : Gds.elem) =
    match e.ekind with
    | `sref -> Option.map (fun (p : Gds.poly) -> p.player) (via_cut_layer e.esname)
    | _ -> Some e.elayer in
  let elem_net (e : Gds.elem) =
    match e.ekind with
    | `boundary when Array.length e.exy >= 4 ->
      let pts = Array.map fl (Array.sub e.exy 0 (Array.length e.exy - 1)) in
      (match Extract.metal_index nl.tech e.elayer, Extract.via_metals nl.tech e.elayer with
       | Some m, _ -> lookup (Extract.Metal m) pts
       | _, Some (lo, hi) -> lookup (Extract.Via (lo, hi)) pts
       | _ -> None)
    | `path ->
      (match Extract.metal_index nl.tech e.elayer,
             List.find_opt (fun (h : Gds.path) -> h.hlayer = e.elayer && h.hpts = e.exy) topc.paths with
       | Some m, Some h ->
         (match Gds.path_rects h with r :: _ -> lookup (Extract.Metal m) r | [] -> None)
       | _ -> None)
    | `sref when starts_with e.esname "VIA_" ->
      (match via_cut_layer e.esname,
             List.find_opt (fun (r : Gds.ref_) -> r.rcell = e.esname && r.rorigin = fl e.exy.(0)) topc.refs with
       | Some cut, Some r ->
         let xf = Gds.ref_xform r in
         (match Extract.via_metals nl.tech cut.player with
          | Some (lo, hi) -> lookup (Extract.Via (lo, hi)) (Array.map (fun p -> Gds.xapply xf (fl p)) cut.ppts)
          | None -> None)
       | _ -> None)
    | _ -> None
  in
  let cut_candidates =
    List.filter (fun (e : Gds.elem) ->
      (match elem_layer e with Some l -> List.mem l [ 19; 29; 49; 10; 30 ] | None -> false)
      && (e.ekind = `sref || e.edt = 0)
      && (match elem_net e with Some x -> signal x | None -> false)) topc.elems
    |> Array.of_list in
  let kinds = List.map (fun k ->
      Printf.sprintf "%d %s" (List.length (List.filter (fun (e : Gds.elem) -> e.ekind = k) (Array.to_list cut_candidates)))
        (match k with `boundary -> "boundaries" | `path -> "paths" | _ -> "via references"))
      [ `boundary; `path; `sref ] in
  Printf.printf "cut candidates (top-level Via1-3 and Metal2-3 elements on signal nets): %d (%s)\n"
    (Array.length cut_candidates) (String.concat ", " kinds);
  let results = ref [] in
  let run_one label path =
    let nl', _, r, t, _ = extract_and_check ~quiet:true ~gds:path ~top ~lib ~ports () in
    let caught = r.errors <> [] in
    (* a planted fault that leaves the connectivity as it was is no fault:
       say so, rather than count it either way *)
    (* nets are the components that reach a pin or a port; a rectangle that
       touches nothing adds a component but no net *)
    let effective = nl'.nnets <> nl.nnets in
    Printf.printf "  %-6s %s: nets %+d, %d errors (%.2f s)%s\n%!" label (Filename.basename path)
      (nl'.nnets - nl.nnets) (List.length r.errors) t
      (if not effective then "  NO EFFECT ON CONNECTIVITY" else if caught then "" else "  NOT CAUGHT");
    List.iteri (fun i e -> if i < 3 then Printf.printf "           %s\n" e) r.errors;
    if effective then results := (label, caught) :: !results
  in
  for i = 1 to n do
    let e = cut_candidates.(Random.int (Array.length cut_candidates)) in
    let path = Filename.concat outdir (Printf.sprintf "cut%02d.gds" i) in
    let net = Option.get (elem_net e) in
    Printf.printf "cut %d: layer %d %s at bytes %d (net n%d)\n" i (Option.get (elem_layer e))
      (match e.ekind with `sref -> "via " ^ e.esname | `path -> "path" | _ -> "boundary") e.estart net;
    Mutate.cut ~src:gds ~dst:path ~elem:e;
    run_one "cut" path
  done;
  (* shorts: a Metal2 rectangle from a shape on one signal net to the
     nearest Metal2 shape on another *)
  let m2 = List.filter_map (fun i ->
      match geo.shapes.(i).kind, geo.shape_net.(i) with
      | Extract.Metal 1, Some x when signal x -> Some i
      | _ -> None) (List.init (Array.length geo.shapes) Fun.id) |> Array.of_list in
  (* a vertex, not the bbox centre: the centre of an L-shaped wire can lie
     outside it, and then the planted rectangle touches nothing (this
     happened in the first run, and those "shorts" were no faults at all) *)
  let centre (s : Extract.shape) = s.pts.(0) in
  for i = 1 to n do
    let a = m2.(Random.int (Array.length m2)) in
    let na = Option.get geo.shape_net.(a) in
    let ax, ay = centre geo.shapes.(a) in
    let best = ref None in
    Array.iter (fun b ->
      if geo.shape_net.(b) <> Some na then begin
        let bx, by = centre geo.shapes.(b) in
        let d = Int64.add (Int64.abs (Int64.sub ax bx)) (Int64.abs (Int64.sub ay by)) in
        match !best with Some (_, d') when d' <= d -> () | _ -> best := Some (b, d)
      end) m2;
    let b, _ = Option.get !best in
    let bx, by = centre geo.shapes.(b) in
    let to_dbu v = Int64.to_int (Int64.div v (Int64.of_float k)) in
    let w = 100 (* dbu: half of a 0.2 um Metal2 wire *) in
    let rect = (to_dbu (Int64.min ax bx) - w, to_dbu (Int64.min ay by) - w,
                to_dbu (Int64.max ax bx) + w, to_dbu (Int64.max ay by) + w) in
    let path = Filename.concat outdir (Printf.sprintf "short%02d.gds" i) in
    Printf.printf "short %d: Metal2 n%d to n%d\n" i na (Option.get geo.shape_net.(b));
    Mutate.add_rect ~src:gds ~dst:path ~endstr:topc.endstr ~layer:10 ~datatype:0 rect;
    run_one "short" path
  done;
  let caught = List.length (List.filter snd !results) in
  Printf.printf "controls: %d of %d effective planted faults caught structurally (%d had no effect)\n"
    caught (List.length !results) (2 * n - List.length !results)

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "check"; gds; top; rtl; models ] -> check gds top rtl models None
  | [ "check"; gds; top; rtl; models; out ] -> check gds top rtl models (Some out)
  | [ "controls"; gds; top; rtl; models; outdir; n; seed ] ->
    controls gds top rtl models outdir (int_of_string n) (int_of_string seed)
  | _ -> prerr_endline "usage: see the head of roundtrip_check.ml"; exit 2
