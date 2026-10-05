(* Touch versus overlap: synthetic GDS cases for the extractor's join rule.

   Shapes on the same metal that merely abut are one conductor (a wire drawn
   as two rectangles sharing an edge).  A via joins two metals only where its
   cut overlaps each metal with positive area: a via whose edge or corner
   only touches a metal is not in contact with it.  The rule and the warning
   that a closed intersection test gets it wrong come from Shapovalov's paper
   on his extractor (FigureZig/asicrev, section II-C) and from JGalil's
   README (JGalil/gds2netlist-asic-puzzle, "Implementation notes"), reached
   independently; this test and its GDS writer are ours.

   Each case is its own top cell with two port labels, "a" and "b", and an
   expected verdict on whether they share a net.  The GDS is written by the
   small writer below, then read back through the same parser and extractor
   the round trip uses.

   test_via_overlap.exe OUT.gds *)

let u16 v = String.init 2 (fun i -> Char.chr ((v lsr (8 * (1 - i))) land 0xff))
let i32 v = String.init 4 (fun i -> Char.chr ((v asr (8 * (3 - i))) land 0xff))

let record tag payload = u16 (4 + String.length payload) ^ u16 tag ^ payload

let ascii s = if String.length s mod 2 = 1 then s ^ "\000" else s

(* GDS 8-byte real, excess-64 base-16; enough for 1e-3 and 1e-9 *)
let real8 x =
  let exp = ref 64 and m = ref x in
  while !m >= 1.0 do m := !m /. 16.0; incr exp done;
  while !m < 1.0 /. 16.0 do m := !m *. 16.0; decr exp done;
  let mant = Int64.of_float (Float.round (!m *. 72057594037927936.0)) in
  String.init 8 (fun i ->
    if i = 0 then Char.chr !exp
    else Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical mant (8 * (7 - i))) 0xffL)))

let dates = String.concat "" (List.init 12 (fun _ -> u16 0))

let boundary ~layer pts =
  let pts = pts @ [ List.hd pts ] in
  record 0x0800 ""
  ^ record 0x0d02 (u16 layer) ^ record 0x0e02 (u16 0)
  ^ record 0x1003 (String.concat "" (List.map (fun (x, y) -> i32 x ^ i32 y) pts))
  ^ record 0x1100 ""

let rect ~layer (x0, y0, x1, y1) = boundary ~layer [ (x0, y0); (x1, y0); (x1, y1); (x0, y1) ]

let text ~layer (x, y) s =
  record 0x0c00 "" ^ record 0x0d02 (u16 layer) ^ record 0x1602 (u16 25)
  ^ record 0x1003 (i32 x ^ i32 y) ^ record 0x1906 (ascii s) ^ record 0x1100 ""

let structure name elems =
  record 0x0502 dates ^ record 0x0606 (ascii name) ^ String.concat "" elems ^ record 0x0700 ""

let m1 = 8 and m2 = 10 and v1 = 19

(* Metal1 square on the left labelled "a", Metal2 square on the right labelled
   "b", and a Via1 cut between them; coordinates in dbu (1 nm). *)
let two_squares ?(m1r = (0, 0, 1000, 1000)) ?(m2r = (1000, 0, 2000, 1000)) via =
  let x0, y0, x1, y1 = m2r in
  [ rect ~layer:m1 m1r; rect ~layer:m2 m2r; via;
    text ~layer:m1 (100, 100) "a"; text ~layer:m2 ((x0 + x1) / 2, (y0 + y1) / 2 + 300) "b" ]

let cases =
  [ ("via_overlaps_both", true,
     two_squares (rect ~layer:v1 (900, 400, 1090, 590)));
    ("via_abuts_m1_edge", false,
     (* the cut lies inside Metal2 and shares only the line x = 1000 with Metal1 *)
     two_squares (rect ~layer:v1 (1000, 400, 1190, 590)));
    ("via_abuts_m2_edge", false,
     two_squares (rect ~layer:v1 (810, 400, 1000, 590)));
    ("via_touches_m1_corner", false,
     two_squares ~m2r:(1000, 1000, 2000, 2000) (rect ~layer:v1 (1000, 1000, 1190, 1190)));
    ("via_inside_both", true,
     two_squares ~m2r:(0, 0, 2000, 1000) (rect ~layer:v1 (400, 400, 590, 590)));
    ("via_equal_to_m1", true,
     (* the cut coincides with a Metal1 rectangle: every edge shared, no crossing *)
     [ rect ~layer:m1 (0, 0, 190, 190); rect ~layer:m2 (0, 0, 2000, 1000);
       rect ~layer:v1 (0, 0, 190, 190);
       text ~layer:m1 (100, 100) "a"; text ~layer:m2 (1900, 900) "b" ]);
    ("via_on_diagonal_vertex", false,
     (* Metal2 triangle whose hypotenuse passes through the cut's corner only *)
     [ rect ~layer:m1 (0, 0, 1000, 1000);
       boundary ~layer:m2 [ (1190, 590); (3000, 590); (3000, 2400) ];
       rect ~layer:v1 (1000, 400, 1190, 590);
       text ~layer:m1 (100, 100) "a"; text ~layer:m2 (2900, 700) "b" ]);
    ("via_cuts_diagonal", true,
     [ rect ~layer:m1 (0, 0, 1100, 1000);
       boundary ~layer:m2 [ (1000, 400); (3000, 400); (3000, 2400) ];
       rect ~layer:v1 (1000, 400, 1090, 590);
       text ~layer:m1 (100, 100) "a"; text ~layer:m2 (2900, 500) "b" ]);
    ("metal1_abuts_metal1", true,
     (* same-layer abutment is one conductor *)
     [ rect ~layer:m1 (0, 0, 1000, 1000); rect ~layer:m1 (1000, 0, 2000, 1000);
       text ~layer:m1 (100, 100) "a"; text ~layer:m1 (1900, 900) "b" ]);
    ("metal1_corner_metal1", true,
     [ rect ~layer:m1 (0, 0, 1000, 1000); rect ~layer:m1 (1000, 1000, 2000, 2000);
       text ~layer:m1 (100, 100) "a"; text ~layer:m1 (1900, 1900) "b" ]);
    ("metal1_gap_metal1", false,
     [ rect ~layer:m1 (0, 0, 1000, 1000); rect ~layer:m1 (1001, 0, 2000, 1000);
       text ~layer:m1 (100, 100) "a"; text ~layer:m1 (1900, 900) "b" ]) ]

let () =
  let out = Sys.argv.(1) in
  let oc = open_out_bin out in
  output_string oc
    (record 0x0002 (u16 600) ^ record 0x0102 dates ^ record 0x0206 (ascii "VIATEST")
     ^ record 0x0305 (real8 1e-3 ^ real8 1e-9)
     ^ String.concat "" (List.map (fun (n, _, es) -> structure n es) cases)
     ^ record 0x0400 "");
  close_out oc;
  let failures = ref 0 in
  List.iter (fun (name, expect, _) ->
    let nl, _ = Extract.extract ~gds_path:out ~top_name:name () in
    let net p = List.assoc p nl.Extract.ports in
    let a = net "a" and b = net "b" in
    let joined = a <> None && a = b in
    let ok = joined = expect && a <> None && b <> None in
    if not ok then incr failures;
    Printf.printf "%-24s expected %-9s got %-9s %s\n" name
      (if expect then "joined" else "separate") (if joined then "joined" else "separate")
      (if ok then "ok" else "WRONG"))
    cases;
  Printf.printf "%d of %d cases wrong\n" !failures (List.length cases);
  exit (if !failures = 0 then 0 else 1)
