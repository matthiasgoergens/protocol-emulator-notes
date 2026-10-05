(* A fast model of one line through the feeder and the PE row, built from the PE-X specification
   (pex_model.ml) and the feeder's rules as video.ml implements them: entries at one per clock,
   steps every [period] clocks from [start] with priority over entries, WAIT n holding entries until
   step n has gone out. No sequencer, no output port. It checks the host encoder and the PE
   configurations against the reference renderer over many more lines than the RTL can run; the
   RTL itself is checked against the same reference by check.ml. *)

let start = 200

let line (l : Scene.line) =
  let entries = Array.of_list (Scene.encode l) in
  let pes = Array.init Video.npe (fun k ->
    Pex_model.create (Pex_model.cfg_of_bytes
                        (if k < Video.kcells then Pex_model.tile_cfg ~kcells:Video.kcells else Pex_model.sprite_cfg))) in
  let out = ref [] in
  let ptr = ref 0 and cnt = ref 0 and pix_val = ref 0 and pix_en = ref false and active = ref true in
  let clock = ref 0 in
  while !cnt < Video.nsteps || Array.exists (fun p -> p.Pex_model.out_tag <> 0) pes || !clock < start + 10 * Video.nsteps + 40 do
    (* the feeder's word this clock *)
    let slot = !pix_en && !cnt < Video.nsteps && !clock >= start && (!clock - start) mod Video.period = 0 in
    let tag, data =
      if slot then begin
        let d = !pix_val lor (if !cnt = Video.nsteps - 1 then 0x8000 else 0) in
        incr cnt; (Pex_model.tag_step, d)
      end else if !active && !ptr < Array.length entries then begin
        let t, d = entries.(!ptr) in
        if t = Scene.t_wait then ((if !cnt > d then incr ptr); (0, 0))
        else if t = Scene.t_pixels then (pix_val := d; pix_en := true; incr ptr; (0, 0))
        else if t = Scene.t_end || t = 5 then (active := false; (0, 0))
        else (incr ptr; (t, d))
      end else (0, 0) in
    let ins = Array.init Video.npe (fun k -> if k = 0 then (tag, data) else (pes.(k - 1).out_tag, pes.(k - 1).out_data)) in
    Array.iteri (fun k p -> let t, d = ins.(k) in Pex_model.step p ~tag:t ~data:d) pes;
    let last = pes.(Video.npe - 1) in
    if last.out_tag = Pex_model.tag_step then out := (last.out_data land 63) :: !out;
    incr clock
  done;
  Array.of_list (List.rev !out)

let compare l =
  let g = line l and r = Scene.reference l in
  if Array.length g <> Scene.npix then Scene.npix
  else Array.fold_left ( + ) 0 (Array.mapi (fun i c -> if g.(i) <> c then 1 else 0) r)

let main () =
  Random.init 23;
  let n = 20000 in
  let bad = ref 0 and bad_lines = ref 0 in
  for _ = 1 to n do
    let b = compare (Scene.random_line ()) in
    if b > 0 then incr bad_lines; bad := !bad + b
  done;
  Printf.printf "model chip (feeder rules + PE-X model), %d random lines: %d lines, %d pixels differ\n" n !bad_lines !bad;
  let dbad = ref 0 in
  for i = 0 to 239 do dbad := !dbad + compare (Scene.directed_line i) done;
  Printf.printf "directed edge lines (240): %d pixels differ\n" !dbad;
  (* the case an adversarial review raised: a flipped sprite at x = -1 whose only pixel is 15 *)
  let lone = Array.init 16 (fun p -> if p = 15 then 1 else if p = 14 then 2 else 0) in
  let l = { (Scene.directed_line 0) with Scene.sprites = [ { x = -1; spix = lone; spal = 0; flip = true; behind = false } ] } in
  let g = line l and r = Scene.reference l in
  Printf.printf "flipped sprite at x = -1 with pixels 14 = 2, 15 = 1: screen x 0 shows %d (reference %d), x 1 shows %d (reference %d)\n"
    g.(0) r.(0) g.(1) r.(1);
  !bad = 0 && !dbad = 0
