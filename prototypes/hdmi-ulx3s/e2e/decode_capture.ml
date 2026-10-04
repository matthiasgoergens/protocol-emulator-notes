(* Decode a captured serial stream (tb.v: one hex digit per bit time, bit i = gpdi_dp[i]) with the
   independent decoder (../indep), compare the first complete frame with the test pattern's
   software reference, and write both as PNG.
   Usage: decode_capture.exe CAPTURE OUT_DIR *)
module I = Tmds_indep

let () =
  let capture = Sys.argv.(1) and out_dir = Sys.argv.(2) in
  let s = In_channel.with_open_bin capture In_channel.input_all in
  let s = String.trim s in
  let n = String.length s in
  let lane i = Array.init n (fun k ->
      let c = s.[k] in
      let v = if c >= 'a' then Char.code c - Char.code 'a' + 10 else Char.code c - Char.code '0' in
      (v lsr i) land 1 = 1) in
  let lanes = Array.init 4 lane in
  let fail fmt = Printf.ksprintf (fun m -> print_endline ("FAIL: " ^ m); exit 1) fmt in
  Printf.printf "bit times captured: %d\n" n;
  let offsets = Array.init 3 (fun i -> I.find_alignment lanes.(i)) in
  Array.iteri (fun i o -> Printf.printf "lane %d word alignment: %s\n" i
                  (match o with Some o -> string_of_int o | None -> "none")) offsets;
  let off = match offsets.(0) with Some o -> o | None -> fail "no alignment on blue" in
  Array.iteri (fun i o -> if o <> Some off then fail "lane %d aligned differently from blue" i) offsets;
  let words i = I.words_of_bits lanes.(i) ~offset:off in
  (* the clock lane must carry 0b00000_11111 in every word at the data lanes' alignment; the first
     few words precede the serialiser's first load *)
  let clk = words 3 in
  let bad = ref 0 and first_good = ref (-1) in
  Array.iteri (fun k w -> if w = 0b00000_11111 then (if !first_good < 0 then first_good := k)
                else if !first_good >= 0 then incr bad) clk;
  Printf.printf "clock lane: first full word at %d, %d wrong words after it\n" !first_good !bad;
  if !bad > 0 || !first_good < 0 then fail "clock lane";
  let sym i = Array.map I.decode_strict (Array.sub (words i) !first_good (Array.length clk - !first_good)) in
  let blue = sym 0 and green = sym 1 and red = sym 2 in
  (* running disparity of each data lane, from the words on the wire, reset by control periods;
     the DVI encoder keeps it within -8 .. +8 *)
  for i = 0 to 2 do
    let w = Array.sub (words i) !first_good (Array.length clk - !first_good) in
    let rd = ref 0 and worst = ref 0 in
    Array.iter (fun x -> match I.decode x with
        | I.Control _ -> rd := 0
        | _ -> rd := !rd + I.ones_minus_zeros x; worst := max !worst (abs !rd)) w;
    Printf.printf "lane %d: max |running disparity| %d\n" i !worst;
    if !worst > 8 then fail "lane %d running disparity exceeds 8" i
  done;
  let t = I.measure_timing ~blue ~green ~red in
  Printf.printf "timing: H %d/%d/%d/%d (total %d), V %d/%d/%d/%d (total %d), hsync %s, vsync %s\n"
    t.h_active t.h_front t.h_sync t.h_back t.h_total t.v_active t.v_front t.v_sync t.v_back t.v_total
    (if t.hsync_active_high then "+" else "-") (if t.vsync_active_high then "+" else "-");
  let frames = I.frames_of_lanes ~blue ~green ~red in
  Printf.printf "complete frames: %d\n" (List.length frames);
  match frames with
  | [] -> fail "no complete frame"
  | f :: _ ->
    let mism = ref 0 in
    let refpix x y = Hdmi_hw.Test_pattern.reference ~width:f.width ~height:f.height x y in
    for y = 0 to f.height - 1 do
      for x = 0 to f.width - 1 do
        if f.rgb.((y * f.width) + x) <> refpix x y then begin
          if !mism < 5 then begin
            let r, g, b = f.rgb.((y * f.width) + x) and r', g', b' = refpix x y in
            Printf.printf "  pixel (%d,%d): got %d,%d,%d want %d,%d,%d\n" x y r g b r' g' b'
          end;
          incr mism
        end
      done
    done;
    Png.write (Filename.concat out_dir "decoded.png") ~width:f.width ~height:f.height (fun x y -> f.rgb.((y * f.width) + x));
    Png.write (Filename.concat out_dir "expected.png") ~width:f.width ~height:f.height refpix;
    Printf.printf "frame %dx%d: %d pixels differ from the reference\n" f.width f.height !mism;
    List.iteri (fun i (g : I.frame) -> if g.rgb <> f.rgb then Printf.printf "frame %d differs from frame 0\n" i) frames;
    if !mism > 0 then fail "frame mismatch" else print_endline "E2E PASS"
