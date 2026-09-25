(* main.exe verilog NAME   print the Verilog of one circuit of Pe_rtl
   main.exe list           the circuit names
   main.exe check N        N random cycles of each circuit against an OCaml model *)
open Hardcaml

let sx w v = let v = v land ((1 lsl w) - 1) in if v >= 1 lsl (w - 1) then v - (1 lsl w) else v
let alu_model w op x y =
  let hi = (1 lsl (w - 1)) - 1 and lo = -(1 lsl (w - 1)) in
  let sat v = max lo (min hi v) in
  (* FAULT=1 plants a model error (min computed as max) so the check can be seen to fail *)
  match op with
  | 0 -> sat (x + y) | 1 -> sat (x - y) | 2 -> max x y
  | _ -> if Sys.getenv_opt "FAULT" = Some "1" then max x y else min x y

let rnd w = Random.int (1 lsl w)

let sim c = Cyclesim.create ~config:Cyclesim.Config.default c
let set sim name v w = (Cyclesim.in_port sim name) := Bits.of_int ~width:w v
let get sim name = Bits.to_int (!(Cyclesim.out_port sim name))
let gets sim name = Bits.to_sint (!(Cyclesim.out_port sim name))

let load_cfg s bytes =
  set s "cfg_strobe" 1 1;
  List.iter (fun b -> set s "cfg_in" b 8; Cyclesim.cycle s) bytes;
  set s "cfg_strobe" 0 1

(* returns (mismatches, comparisons) *)
let check_ring w n =
  let s = sim (Pe_rtl.ring_cell w) in
  let bad = ref 0 and tot = ref 0 in
  for _ = 1 to n / 16 do
    let op = Random.int 4 and xs = Random.int 5 and ys = Random.int 5 and k = sx w (rnd w) in
    let obyte = op lor (xs lsl 2) lor (ys lsl 5) in
    set s "do_step" 0 1;
    load_cfg s (obyte :: List.init (w / 8) (fun j -> (k asr (8 * (w / 8 - 1 - j))) land 255));
    let st = ref (gets s "s") in
    for _ = 1 to 16 do
      let nb = Array.init 4 (fun _ -> sx w (rnd w)) in
      Array.iteri (fun j v -> set s (Printf.sprintf "nb%d" (j + 1)) v w) nb;
      set s "do_step" 1 1;
      let x = if xs = 0 then !st else nb.(xs - 1) and y = if ys < 4 then nb.(ys) else k in
      Cyclesim.cycle s;
      st := alu_model w op x y;
      incr tot;
      if gets s "s" <> !st then incr bad
    done
  done;
  !bad, !tot

let check_pe16 n =
  let s = sim (Pe_rtl.pe16 ()) in
  let bad = ref 0 and tot = ref 0 in
  for _ = 1 to n / 16 do
    let op = Random.int 4 and yk = Random.int 2 and xs = Random.int 2 and k = sx 16 (rnd 16) in
    load_cfg s [ op lor (yk lsl 2) lor (xs lsl 3) lor (1 lsl 4); (k asr 8) land 255; k land 255 ];
    let st = ref (gets s "out") in
    for _ = 1 to 16 do
      let nbr = sx 16 (rnd 16) and en = Random.int 2 in
      set s "nbr_in" nbr 16; set s "en" en 1;
      let x = if xs = 1 then !st else nbr and y = if yk = 1 then k else !st in
      Cyclesim.cycle s;
      if en = 1 then st := alu_model 16 op x y;
      incr tot;
      if gets s "out" <> !st || gets s "pipe_out" <> nbr then incr bad
    done
  done;
  !bad, !tot

let check_acc name n ~model ~signed =
  let s = sim ((List.assoc name Pe_rtl.circuits) ()) in
  let bad = ref 0 and tot = ref 0 and acc = ref 0 in
  set s "clear" 1 1; Cyclesim.cycle s; set s "clear" 0 1;
  for _ = 1 to n do
    let a = rnd 16 and b = rnd 16 and first = Random.int 8 = 0 |> Bool.to_int and en = Random.int 4 > 0 |> Bool.to_int in
    set s "a_in" a 16; set s "b_in" b 16; set s "first" first 1; set s "en" en 1;
    Cyclesim.cycle s;
    let a, b = if signed then sx 16 a, sx 16 b else a, b in
    if en = 1 then acc := model ~first:(first = 1) !acc a b;
    incr tot;
    let got = if signed then gets s "acc" else get s "acc" in
    if got <> !acc then incr bad
  done;
  !bad, !tot

let () =
  match Array.to_list Sys.argv with
  | [ _; "list" ] -> List.iter (fun (n, _) -> print_endline n) Pe_rtl.circuits
  | [ _; "verilog"; name ] -> Rtl.print Verilog ((List.assoc name Pe_rtl.circuits) ())
  | [ _; "check"; n ] ->
    let n = int_of_string n in
    Random.init 42;
    let report name (b, t) = Printf.printf "%-12s %d of %d cycles differ from the model\n" name b t in
    report "ring_cell24" (check_ring 24 n);
    report "ring_cell16" (check_ring 16 n);
    report "pe16" (check_pe16 n);
    report "mac16" (check_acc "mac16" n ~signed:true ~model:(fun ~first acc a b ->
      let p = a * b in sx 32 (if first then p else acc + p)));
    report "minplus16" (check_acc "minplus16" n ~signed:false ~model:(fun ~first acc a b ->
      let t = min 0xffff (a + b) in if first then t else min acc t))
  | _ -> prerr_endline "usage: main.exe list | verilog NAME | check N"
