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
  let q x = Int64.of_float (Float.round (Float.of_int x *. k)) in
  (* shape bbox -> net, to name the net an element of the top cell belongs to *)
  let net_of_bbox = Hashtbl.create 65536 in
  Array.iteri (fun i (s : Extract.shape) ->
    Option.iter (fun net -> Hashtbl.replace net_of_bbox (s.kind, s.bbox) net) geo.shape_net.(i))
    geo.shapes;
  let elem_net (e : Gds.elem) =
    let kind =
      match Extract.metal_index e.elayer, Extract.via_metals e.elayer with
      | Some m, _ -> Some (Extract.Metal m)
      | _, Some (lo, hi) -> Some (Extract.Via (lo, hi))
      | _ -> None in
    match kind, Array.length e.exy with
    | Some kind, np when np >= 4 && e.ekind = `boundary ->
      let pts = Array.map (fun (x, y) -> (q x, q y)) (Array.sub e.exy 0 (np - 1)) in
      Hashtbl.find_opt net_of_bbox (kind, Extract.bbox_of pts)
    | _ -> None
  in
  let cut_candidates =
    List.filter (fun (e : Gds.elem) ->
      List.mem e.elayer [ 19; 29; 49; 10; 30 ] && e.edt = 0
      && (match elem_net e with Some x -> signal x | None -> false)) topc.elems
    |> Array.of_list in
  Printf.printf "cut candidates (top-level Via1-3 and Metal2-3 shapes on signal nets): %d\n"
    (Array.length cut_candidates);
  let results = ref [] in
  let run_one label path =
    let nl', _, r, t, _ = extract_and_check ~quiet:true ~gds:path ~top ~lib ~ports () in
    let caught = r.errors <> [] in
    Printf.printf "  %-6s %s: %d errors (%.2f s)%s\n%!" label (Filename.basename path)
      (List.length r.errors) t (if caught then "" else "  NOT CAUGHT");
    List.iteri (fun i e -> if i < 3 then Printf.printf "           %s\n" e) r.errors;
    ignore nl';
    results := (label, caught) :: !results
  in
  for i = 1 to n do
    let e = cut_candidates.(Random.int (Array.length cut_candidates)) in
    let path = Filename.concat outdir (Printf.sprintf "cut%02d.gds" i) in
    let net = Option.get (elem_net e) in
    Printf.printf "cut %d: layer %d element at bytes %d (net n%d)\n" i e.elayer e.estart net;
    Mutate.cut ~src:gds ~dst:path ~elem:e;
    run_one "cut" path
  done;
  (* shorts: a Metal2 rectangle from a shape on one signal net to the
     nearest Metal2 shape on another *)
  let m2 = List.filter_map (fun i ->
      match geo.shapes.(i).kind, geo.shape_net.(i) with
      | Extract.Metal 1, Some x when signal x -> Some i
      | _ -> None) (List.init (Array.length geo.shapes) Fun.id) |> Array.of_list in
  let centre (s : Extract.shape) =
    let x0, y0, x1, y1 = s.bbox in
    (Int64.div (Int64.add x0 x1) 2L, Int64.div (Int64.add y0 y1) 2L) in
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
  Printf.printf "controls: %d of %d planted faults caught structurally\n" caught (List.length !results)

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "check"; gds; top; rtl; models ] -> check gds top rtl models None
  | [ "check"; gds; top; rtl; models; out ] -> check gds top rtl models (Some out)
  | [ "controls"; gds; top; rtl; models; outdir; n; seed ] ->
    controls gds top rtl models outdir (int_of_string n) (int_of_string seed)
  | _ -> prerr_endline "usage: see the head of roundtrip_check.ml"; exit 2
