(* Demo: three protocols compiled onto three threads, run on the RTL with an I2C slave model in
   the loop, checked three ways: (1) the interpreter's exact simulation predicts every pin edge
   the RTL produces; (2) independent decoders recover the payload bytes from the bus trace;
   (3) measured edge timings equal the closed forms. Then fault injection and a baud sweep. *)

let uart_pin = 0 and sclk = 1 and mosi = 2 and cs = 3 and sda = 4 and scl = 5
let slot = Compiler.slot

(* I2C slave: acks every byte after START; sda/scl are open drain with a pull-up. *)
type slave = { mutable started : bool; mutable nbits : int; mutable pull : bool; mutable p_sda : int; mutable p_scl : int }
let new_slave () = { started = false; nbits = 0; pull = false; p_sda = 1; p_scl = 1 }

(* bus levels from the master's outputs and the slave; returns (bus, pin_in for the core) *)
let resolve sl ~pin_out ~pin_oe =
  let drives p = (pin_oe lsr p) land 1 = 1 in
  let out p = (pin_out lsr p) land 1 in
  let scl_l = if drives scl then out scl else 1 in
  let sda_l = if drives sda && out sda = 0 then 0 else if sl.pull then 0 else if drives sda then out sda else 1 in
  (* slave state machine on the resolved lines *)
  if sl.p_scl = 1 && scl_l = 1 && sl.p_sda = 1 && sda_l = 0 then (sl.started <- true; sl.nbits <- 0);
  if sl.p_scl = 1 && scl_l = 1 && sl.p_sda = 0 && sda_l = 1 && not sl.pull then sl.started <- false;
  if sl.started && sl.p_scl = 0 && scl_l = 1 then sl.nbits <- sl.nbits + 1;
  if sl.started && sl.p_scl = 1 && scl_l = 0 then begin
    if sl.nbits = 8 then sl.pull <- true
    else if sl.nbits = 9 then (sl.pull <- false; sl.nbits <- 0)
  end;
  sl.p_sda <- sda_l; sl.p_scl <- scl_l;
  let others = List.fold_left (fun acc p -> if drives p then acc lor (out p lsl p) else acc lor (1 lsl p)) 0 [0; 1; 2; 3; 6; 7] in
  others lor (sda_l lsl sda) lor (scl_l lsl scl)

(* Run programmes on RTL and interpreter in lockstep for [cycles]; returns the bus trace and the
   host bytes, and whether RTL and interpreter agreed on every cycle. *)
let run ~mem ~cycles =
  let s = Harness.make mem in
  let st = Isa.init () in
  let sl = new_slave () in
  let bus = ref (resolve sl ~pin_out:0 ~pin_oe:0) in
  let trace = ref [] and host = ref [] and agree = ref true in
  for c = 0 to cycles - 1 do
    let pin_in = !bus in
    let eff = Isa.step st ~mem ~pin_in ~host_in:0 ~host_in_valid:false in
    let o = Harness.cycle s ~pin_in ~host_in:0 ~host_in_valid:false in
    if o.pin_out <> st.pin_out || o.pin_oe <> st.pin_oe || o.host_out <> eff.host_out then agree := false;
    (match o.host_out with Some b -> host := b :: !host | None -> ());
    bus := resolve sl ~pin_out:o.pin_out ~pin_oe:o.pin_oe;
    trace := { Decoders.c; bus = !bus } :: !trace
  done;
  List.rev !trace, List.rev !host, !agree

let uart_bytes = [ 0x4F; 0x4B; 0x21 ]        (* "OK!" *)
let spi_bytes = [ 0xA5; 0x3C ]
let i2c_bytes = [ 0xA0; 0x5A ]               (* address+write, data *)
let bit_slots = 16 and spi_period = 16 and q = 4

let build ?stretch () =
  let u, ul = Compiler.uart_tx { upin = uart_pin; bit_slots; ubytes = (match stretch with Some _ -> [ List.hd uart_bytes ] | None -> uart_bytes); stretch } in
  let sp, sl = Compiler.spi_master { sclk; mosi; cs; period = spi_period; sbytes = spi_bytes } in
  let ic, il = Compiler.i2c_write { sda; scl; q; ibytes = i2c_bytes } in
  let idle = Array.make Isa.prog_len Isa.halt in
  [| u; sp; ic; idle |], [ ("uart_tx", u, ul); ("spi_master", sp, sl); ("i2c_write", ic, il) ]

let check_multiples name edges period =
  let ok = ref true and worst = ref 0 in
  let rec go = function
    | (c1, _) :: ((c2, _) :: _ as rest) ->
      let d = c2 - c1 in
      let r = d mod period in
      let dev = min r (period - r) in
      if dev > !worst then worst := dev;
      if r <> 0 then ok := false; go rest
    | _ -> () in
  go edges;
  Printf.printf "  %s: %d edges, all spacings multiples of %d cycles: %b (worst deviation %d cycles)\n" name (List.length edges) period !ok !worst;
  !ok

let main_demo () =
  let mem, listings = build () in
  List.iter (fun (n, p, l) -> Printf.printf "== %s (%d words)\n%s" n l (Compiler.disassemble p l)) listings;
  let trace, host, agree = run ~mem ~cycles:6000 in
  Printf.printf "RTL and interpreter agree on every cycle: %b\n" agree;
  let ub = Decoders.uart trace ~pin:uart_pin ~bit_cycles:(bit_slots * slot) in
  let sb = Decoders.spi trace ~sclk ~mosi ~cs in
  let ib, stopped = Decoders.i2c trace ~sda ~scl in
  Printf.printf "uart decoded: %s\n" (String.concat " " (List.map (fun (c, b, ok) -> Printf.sprintf "0x%02x@%d%s" b c (if ok then "" else "(framing)")) ub));
  Printf.printf "spi decoded:  %s\n" (String.concat " " (List.map (Printf.sprintf "0x%02x") sb));
  Printf.printf "i2c decoded:  %s stop=%b; host received ack bytes: %s\n"
    (String.concat " " (List.map (fun (b, a) -> Printf.sprintf "0x%02x%s" b (if a then "+ack" else "-nak")) ib)) stopped
    (String.concat " " (List.map (Printf.sprintf "0x%02x") host));
  let t1 = check_multiples "uart tx edge spacing" (Decoders.edges trace uart_pin) (bit_slots * slot) in
  let sclk_edges = Decoders.edges trace sclk in
  let rises = List.filter (fun (_, v) -> v = 1) sclk_edges in
  (* spacing within a byte only: rises 1..8 of each byte; the inter-byte gap is not a bit period *)
  let within = List.concat (List.mapi (fun i r -> if i mod 8 = 7 then [] else [ r ]) rises) in
  let rec pairs = function a :: (b :: _ as r) -> (a, b) :: pairs r | _ -> [] in
  let spac = pairs within |> List.filter (fun ((c1, _), (c2, _)) -> c2 - c1 < 2 * spi_period * slot) |> List.map (fun ((c1, _), (c2, _)) -> c2 - c1) in
  let t2 = List.for_all (fun d -> d = spi_period * slot) spac in
  Printf.printf "  spi sclk period within bytes: %s (expected %d): %b\n" (String.concat "," (List.map string_of_int spac)) (spi_period * slot) t2;
  let scl_edges = Decoders.edges trace scl in
  let highs = let rec go = function (c1, 1) :: ((c2, 0) :: _ as r) -> (c2 - c1) :: go r | _ :: r -> go r | [] -> [] in go scl_edges in
  let t3 = List.for_all (fun w -> w = 2 * q * slot) highs in
  Printf.printf "  i2c scl high widths: %s (expected %d): %b\n" (String.concat "," (List.map string_of_int highs)) (2 * q * slot) t3;
  let ok = agree && List.map (fun (_, b, ok) -> if ok then b else -1) ub = uart_bytes && sb = spi_bytes
           && List.map fst ib = i2c_bytes && List.for_all snd ib && stopped && host = [ 0x00; 0x00 ] && t1 && t2 && t3 in
  Printf.printf "main demo: %s\n\n" (if ok then "PASS" else "FAIL");
  ok

let fault_demo () =
  Printf.printf "== fault injection: UART data bit 5 stretched by d slots, receiver fixed at %d cycles/bit\n" (bit_slots * slot);
  List.for_all (fun d ->
    let mem, _ = build ~stretch:(5, d) () in
    let trace, _, agree = run ~mem ~cycles:1200 in
    let ub = Decoders.uart trace ~pin:uart_pin ~bit_cycles:(bit_slots * slot) in
    let got = match ub with (_, b, ok) :: _ -> Printf.sprintf "0x%02x%s" b (if ok then "" else " framing error") | [] -> "nothing" in
    (* a mid-bit-sampling receiver survives a cumulative shift of up to half a bit *)
    let expect_ok = d * slot <= bit_slots * slot / 2 in
    let decoded_ok = (match ub with (_, b, ok) :: _ -> ok && b = List.hd uart_bytes | [] -> false) in
    Printf.printf "  d=%2d slots (+%3d cycles, %+5.1f%% of a bit): decoded %s -> %s\n" d (d * slot)
      (100.0 *. float d /. float bit_slots) got (if decoded_ok then "still decodes" else "receiver breaks");
    agree && decoded_ok = expect_ok) [ 0; 2; 4; 7; 8; 9; 10 ]

let sweep_demo () =
  let base = 32 in
  Printf.printf "\n== timing microscope: transmitter bit period swept, receiver fixed at %d cycles/bit\n" (base * slot);
  List.iter (fun bs ->
    let u, _ = Compiler.uart_tx { upin = uart_pin; bit_slots = bs; ubytes = uart_bytes; stretch = None } in
    let mem = [| u; Array.make Isa.prog_len Isa.halt; Array.make Isa.prog_len Isa.halt; Array.make Isa.prog_len Isa.halt |] in
    let trace, _, _ = run ~mem ~cycles:6000 in
    let ub = Decoders.uart trace ~pin:uart_pin ~bit_cycles:(base * slot) in
    let bytes = List.map (fun (_, b, ok) -> if ok then b else -1) ub in
    Printf.printf "  tx %2d slots/bit (%+5.1f%%): decoded %s -> %s\n" bs (100.0 *. float (bs - base) /. float base)
      (String.concat " " (List.map (fun b -> if b < 0 then "ERR" else Printf.sprintf "0x%02x" b) bytes))
      (if bytes = uart_bytes then "ok" else "wrong")) [ 29; 30; 31; 32; 33; 34; 35 ]

let () =
  let a = main_demo () in
  let b = fault_demo () in
  sweep_demo ();
  print_endline (if a && b then "\nDEMO PASS" else "\nDEMO FAIL");
  exit (if a && b then 0 else 1)
