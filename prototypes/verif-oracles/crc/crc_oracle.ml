(* The CRC combine identity (crc_combine.ml) as an oracle.

     crc_oracle.exe maths            the identity against the direct CRC (Refs.crc), monoid laws,
                                     square-and-multiply against bit-at-a-time, planted faults
     crc_oracle.exe zlib-vectors F   write CRC-32/ISO-HDLC vectors for zlib_check.py
     crc_oracle.exe pe N             the unified PE's CRC configurations (model and RTL in
                                     lockstep, cells.ml): split N random messages at random
                                     points, run the parts, combine, compare with the whole
     crc_oracle.exe shared-faults N  the same with faults planted in model AND RTL together
     crc_oracle.exe split            one CRC computed on two array segments at once *)

open Crc_combine

let pr = Printf.printf
let rng = Random.State.make [| 20261005 |]
let ri n = Random.State.int rng n
let rand_msg n = String.init n (fun _ -> Char.chr (ri 256))
let direct = Refs.crc
let find name = List.find (fun (c : Refs.crc) -> c.name = name) Refs.catalogue

(* ---------------------------------------------------------------- maths *)
let maths () =
  let all_ok = ref true in
  let check name ok = if not ok then all_ok := false; pr "  %-66s %s\n" name (if ok then "ok" else "FAIL") in
  (* the reference itself against the catalogue *)
  check "Refs.crc reproduces every catalogue check value"
    (List.for_all (fun (c : Refs.crc) -> direct c "123456789" = c.check) Refs.catalogue);
  (* square-and-multiply against one bit at a time *)
  check "xpow = xpow_slow for n = 0..3000, every catalogue polynomial"
    (List.for_all (fun (c : Refs.crc) ->
         let w = c.width and poly = c.poly in
         let slow = ref 1 and ok = ref true in
         for n = 0 to 3000 do
           if xpow ~w ~poly n <> !slow then ok := false;
           slow := mulmod ~w ~poly !slow 2
         done; !ok) Refs.catalogue);
  check "xpow_slow agrees with the incremental loop at n = 1234"
    (let c = find "CRC-32/ISO-HDLC" in xpow_slow ~w:32 ~poly:c.poly 1234 = xpow ~w:32 ~poly:c.poly 1234);
  (* x^(2^k (P's order)) = 1 for the primitive CRC-16/CCITT polynomial? Not assumed; instead
     the exponent law x^(a+b) = x^a x^b on large random exponents *)
  check "x^(a+b) = x^a * x^b for 1000 random a, b < 2^40"
    (List.for_all (fun (c : Refs.crc) ->
         let w = c.width and poly = c.poly in
         List.for_all (fun _ ->
             let a = Random.State.bits rng * 1024 + ri 1024 and b = Random.State.bits rng * 1024 in
             xpow ~w ~poly (a + b) = mulmod ~w ~poly (xpow ~w ~poly a) (xpow ~w ~poly b)) (List.init 1000 Fun.id))
       Refs.catalogue);
  (* the identity on random splits *)
  let trials = 3000 in
  List.iter (fun (c : Refs.crc) ->
      let bad = ref 0 in
      for _ = 1 to trials do
        let m = rand_msg (ri 300) in
        let k = ri (String.length m + 1) in
        let a = String.sub m 0 k and b = String.sub m k (String.length m - k) in
        if combine c ~crc_a:(direct c a) ~crc_b:(direct c b) ~len_b:(String.length b) <> direct c m then incr bad
      done;
      check (Printf.sprintf "%-16s combine(crc a, crc b, |b|) = crc(a ++ b), %d random splits" c.name trials) (!bad = 0))
    Refs.catalogue;
  (* monoid laws on (crc, length) pairs: identity (crc "", 0) and associativity *)
  List.iter (fun (c : Refs.crc) ->
      let op (ca, la) (cb, lb) = (combine c ~crc_a:ca ~crc_b:cb ~len_b:lb, la + lb) in
      let e = (direct c "", 0) in
      let ok = ref true in
      for _ = 1 to 500 do
        let x = (Random.State.bits rng land mask c.width, ri 1000) and y = (Random.State.bits rng land mask c.width, ri 1000)
        and z = (Random.State.bits rng land mask c.width, ri 100_000) in
        if op (op x y) z <> op x (op y z) || op e x <> x || op x e <> x then ok := false
      done;
      check (Printf.sprintf "%-16s monoid: identity (crc \"\", 0), associativity, 500 random triples" c.name) !ok)
    Refs.catalogue;
  (* planted faults: each must be caught on at least one catalogue CRC; report where *)
  List.iter (fun f ->
      let caught = List.filter_map (fun (c : Refs.crc) ->
          let bad = ref 0 in
          for _ = 1 to 200 do
            let a = rand_msg (1 + ri 50) and b = rand_msg (1 + ri 50) in
            if combine_faulty f c ~crc_a:(direct c a) ~crc_b:(direct c b) ~len_b:(String.length b) <> direct c (a ^ b) then incr bad
          done;
          if !bad > 0 then Some (Printf.sprintf "%s %d/200" c.name !bad) else None) Refs.catalogue in
      let ok = caught <> [] in
      if not ok then all_ok := false;
      pr "  control %-46s %s on %d of %d CRCs: %s\n" (fault_name f) (if ok then "caught" else "MISSED")
        (List.length caught) (List.length Refs.catalogue) (String.concat ", " caught))
    [ Bits_not_bytes; No_init_term; No_reflection; Zlib_formula ];
  pr "maths: %s\n" (if !all_ok then "PASS" else "FAIL");
  !all_ok

(* ---------------------------------------------------------------- zlib vectors *)
(* Lines: hex(a) hex(b) crc_a crc_b len_b combined_ours, plus lines with huge len_b where only
   the two combine implementations can be compared ("big crc_a crc_b len_b ours"). *)
let zlib_vectors file =
  let c = find "CRC-32/ISO-HDLC" in
  let oc = open_out file in
  let hex s = if s = "" then "-" else String.concat "" (List.map (fun ch -> Printf.sprintf "%02x" (Char.code ch)) (List.of_seq (String.to_seq s))) in
  for _ = 1 to 2000 do
    let m = rand_msg (ri 400) in
    let k = ri (String.length m + 1) in
    let a = String.sub m 0 k and b = String.sub m k (String.length m - k) in
    let ca = direct c a and cb = direct c b in
    Printf.fprintf oc "pair %s %s %d %d %d %d\n" (hex a) (hex b) ca cb (String.length b) (combine c ~crc_a:ca ~crc_b:cb ~len_b:(String.length b))
  done;
  for _ = 1 to 2000 do
    let ca = Random.State.bits rng lor ((Random.State.bits rng land 3) lsl 30) and cb = Random.State.bits rng lor ((Random.State.bits rng land 3) lsl 30) in
    (* zlib's len2 is z_off_t (64-bit here); below 2^57 so that 8 * len stays inside OCaml's int *)
    let len = if ri 2 = 0 then ri 100_000 else (Random.State.bits rng land 0x7FFFFFF) * (1 lsl 30) + Random.State.bits rng in
    Printf.fprintf oc "big %d %d %d %d\n" ca cb len (combine c ~crc_a:ca ~crc_b:cb ~len_b:len)
  done;
  close_out oc;
  pr "wrote 2000 split vectors and 2000 large-length vectors to %s\n" file

(* ---------------------------------------------------------------- the PE *)
(* The PE's CRC of [msg] for catalogue CRC [c] in configuration [mode], and its lockstep mismatches. *)
let pe_crc mode (c : Refs.crc) msg =
  match mode with
  | `One_pe -> let v, _, mm = Cells.crc16_run c msg in (v, mm)
  | (`Continuous | `Follow) as m -> Cells.crc32_run m c msg

let modes_of (c : Refs.crc) = if c.width = 16 then [ `One_pe ] else [ `Continuous; `Follow ]
let mode_name = function `One_pe -> "1 PE" | `Continuous -> "pair, every clock" | `Follow -> "pair, gaps, follow"

(* Returns (identity failures, reference failures, lockstep mismatches) over [n] splits. The
   identity check uses only PE outputs and the combine: no direct CRC is consulted for it. *)
let rev8 s = String.map (fun ch -> Char.chr (Refs.reflect (Char.code ch) 8)) s

let pe_campaign ?(wrong_bit_order = false) ~n mode (c : Refs.crc) =
  let pe_crc mode c m = pe_crc mode c (if wrong_bit_order then rev8 m else m) in
  let id_bad = ref 0 and ref_bad = ref 0 and mism = ref 0 in
  for _ = 1 to n do
    let len = 2 + ri 40 in
    let m = rand_msg len in
    (* both parts non-empty: the every-clock pair cannot run an empty message (its run bit is
       cleared on the last bit's clock, so with no bits it never stops) *)
    let k = 1 + ri (len - 1) in
    let a = String.sub m 0 k and b = String.sub m k (len - k) in
    let pa, m1 = pe_crc mode c a and pb, m2 = pe_crc mode c b and pw, m3 = pe_crc mode c m in
    mism := !mism + m1 + m2 + m3;
    if combine c ~crc_a:pa ~crc_b:pb ~len_b:(String.length b) <> pw then incr id_bad;
    if pw <> direct c m then incr ref_bad
  done;
  (!id_bad, !ref_bad, !mism)

let pe n =
  let ok = ref true in
  List.iter (fun (c : Refs.crc) ->
      List.iter (fun mode ->
          let idb, rb, mm = pe_campaign ~n mode c in
          if idb + rb + mm > 0 then ok := false;
          pr "  %-16s %-19s %3d splits: identity fails %d, whole vs direct CRC fails %d, lockstep mismatches %d\n%!"
            c.name (mode_name mode) n idb rb mm) (modes_of c)) Refs.catalogue;
  pr "pe: %s\n" (if !ok then "PASS" else "FAIL");
  !ok

(* Faults planted in model and RTL together pass lockstep by construction; the question is
   whether the identity alone, with no direct CRC, notices them. *)
let shared_faults n =
  let faults = [ "window_bit_order"; "carry_bit15"; "neg_no_plus1"; "sin_s15_uses_own"; "merge_colour_hi"; "max_unsigned" ] in
  List.iter (fun b ->
      Model.bug := b; Upe_rtl.bug := b;
      let rows = List.concat_map (fun (c : Refs.crc) ->
          List.map (fun mode -> let idb, rb, mm = pe_campaign ~n mode c in (c.name, mode, idb, rb, mm)) (modes_of c)) Refs.catalogue in
      let id_hits = List.filter (fun (_, _, i, _, _) -> i > 0) rows and ref_hits = List.filter (fun (_, _, _, r, _) -> r > 0) rows in
      pr "  fault %-18s configurations where the identity fails: %d of %d; where the direct CRC fails: %d of %d; lockstep mismatches %d\n%!"
        b (List.length id_hits) (List.length rows) (List.length ref_hits) (List.length rows)
        (List.fold_left (fun s (_, _, _, _, m) -> s + m) 0 rows);
      List.iter (fun (name, mode, i, r, _) -> pr "      %-16s %-19s identity %d/%d, direct %d/%d\n" name (mode_name mode) i n r n) ref_hits)
    faults;
  Model.bug := ""; Upe_rtl.bug := ""

(* The identity's blind spot, shown rather than assumed: a PE fed each byte in the wrong bit
   order computes a genuine CRC of another message of the same length, so the identity holds
   and only the direct CRC can notice. *)
let blind n =
  List.iter (fun name ->
      let c = find name in
      List.iter (fun mode ->
          let idb, rb, mm = pe_campaign ~wrong_bit_order:true ~n mode c in
          pr "  control bits of each byte fed in the wrong order, %-16s %-19s identity fails %d of %d (blind), direct CRC fails %d of %d, lockstep %d\n%!"
            name (mode_name mode) idb n rb n mm) (modes_of c)) [ "CRC-16/KERMIT"; "CRC-32/ISO-HDLC" ]

(* ---------------------------------------------------------------- two segments *)
(* CRC-16: part a on segment 0 (PE 0, from init), part b on segment 1 (PE 2, from 0), fed
   through the two segments' feed registers in alternate clocks, in one run of the array.
   CRC-32: part a on segment 1's pair (PEs 2, 3, from init), part b on segment 2's first pair
   (PEs 4, 5, from 0), bits through the fixed ports with random gaps (follow mode). Then
   crc = out((R_a * x^(8|b|) + R_b0) mod P), identity (1). *)
open Spec

let split16 (c : Refs.crc) a b =
  let op = { nop with xsel = 2; sinsel = 0; ysel = 0; ymod = 1; gsel = 4; alu = 4; swb = 1; fwb = 2; stream = true;
                      k = c.poly land 0xfffe; tap_p = false } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ Cells.ctrl 0 ~src:2 ~run:false (); Cells.ctrl 1 ~src:2 ~run:false () ];
  add (Cells.cfg_seq 0 [| op; nop |]); add (Cells.cfg_seq 1 [| op; nop |]);
  add (Cells.init_seq 0 [| c.init; 0 |]); add (Cells.init_seq 1 [| 0; 0 |]);
  add [ Cells.ctrl 0 ~src:2 ~run:true (); Cells.ctrl 1 ~src:2 ~run:true () ];
  let ba = Array.of_list (Cells.bits_of_msg c a) and bb = Array.of_list (Cells.bits_of_msg c b) in
  for i = 0 to max (Array.length ba) (Array.length bb) - 1 do
    if i < Array.length ba then add (Cells.feed_seq 0 ba.(i));
    if i < Array.length bb then add (Cells.feed_seq 1 bb.(i))
  done;
  add (Cells.idles 3);
  let states, mism = Cells.run !stim in
  let f = states.(Array.length states - 1) in
  (combine_raw c ~reg_a:f.pes.(0).s ~reg_b0:f.pes.(2).s ~len_b:(String.length b), mism)

let split32 (c : Refs.crc) a b =
  let kl = c.poly land 0xfffe and kh = c.poly lsr 16 in
  let lo = { nop with xsel = 2; sinsel = 0; ysel = 0; ymod = 1; gsel = 4; pairlo = true; alu = 4; swb = 1; k = kl; pwb = 0; stream = true } in
  let hi = { nop with xsel = 2; sinsel = 2; ysel = 0; ymod = 1; gsel = 7; alu = 4; swb = 1; k = kh; pwb = 0; follow = true } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ Cells.ctrl 1 ~src:3 ~run:false (); Cells.ctrl 2 ~src:3 ~run:false () ];
  add (Cells.cfg_seq 1 [| lo; hi |]); add (Cells.cfg_seq 2 [| lo; hi; nop; nop |]);
  add (Cells.init_seq 1 [| c.init land 0xffff; c.init lsr 16 |]); add (Cells.init_seq 2 [| 0; 0; 0; 0 |]);
  add [ Cells.ctrl 1 ~src:3 ~run:true (); Cells.ctrl 2 ~src:3 ~run:true () ];
  let ba = Array.of_list (Cells.bits_of_msg c a) and bb = Array.of_list (Cells.bits_of_msg c b) in
  let ia = ref 0 and ib = ref 0 in
  while !ia < Array.length ba || !ib < Array.length bb do
    (* each segment independently: a bit this clock or a gap *)
    let i = ref idle in
    if !ia < Array.length ba && ri 3 > 0 then (i := Cells.with_fixed 1 ba.(!ia) true !i; incr ia);
    if !ib < Array.length bb && ri 3 > 0 then (i := Cells.with_fixed 2 bb.(!ib) true !i; incr ib);
    add [ !i ]
  done;
  add (Cells.idles 3);
  let states, mism = Cells.run !stim in
  let f = states.(Array.length states - 1) in
  let ra = (f.pes.(3).s lsl 16) lor f.pes.(2).s and rb = (f.pes.(5).s lsl 16) lor f.pes.(4).s in
  (combine_raw c ~reg_a:ra ~reg_b0:rb ~len_b:(String.length b), mism)

let split () =
  let ok = ref true in
  List.iter (fun (c : Refs.crc) ->
      let bad = ref 0 and mism = ref 0 and n = 15 in
      for _ = 1 to n do
        let len = 2 + ri 40 in
        let m = rand_msg len in
        let k = 1 + ri (len - 1) in
        let a = String.sub m 0 k and b = String.sub m k (len - k) in
        let got, mm = (if c.width = 16 then split16 else split32) c a b in
        mism := !mism + mm;
        if got <> direct c m then incr bad
      done;
      if !bad + !mism > 0 then ok := false;
      pr "  %-16s %s: %d splits, %d wrong, %d lockstep mismatches\n%!" c.name
        (if c.width = 16 then "segments 0 and 1, one PE each, feed registers" else "segments 1 and 2, a pair each, fixed ports, gaps")
        n !bad !mism) Refs.catalogue;
  pr "split: %s\n" (if !ok then "PASS" else "FAIL");
  !ok

let () =
  let ok =
    match Array.to_list Sys.argv with
    | [ _; "maths" ] -> maths ()
    | [ _; "zlib-vectors"; f ] -> zlib_vectors f; true
    | [ _; "pe"; n ] -> pe (int_of_string n)
    | [ _; "shared-faults"; n ] -> shared_faults (int_of_string n); true
    | [ _; "split" ] -> split ()
    | [ _; "blind"; n ] -> blind (int_of_string n); true
    | _ -> prerr_endline "usage: crc_oracle.exe maths | zlib-vectors FILE | pe N | shared-faults N | split"; false in
  exit (if ok then 0 else 1)
