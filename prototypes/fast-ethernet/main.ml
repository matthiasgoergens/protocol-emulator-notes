(* Checks and sweeps for the 100BASE-X prototype. See README.md. *)
open Hardcaml
module R = Ref_model

let bit_list_of_int w x = List.init w (fun i -> (x lsr i) land 1)

(* Run the RTL transmitter over a list of frames; returns per-clock (code bits, line outputs) *)
let run_tx media frames ~extra =
  let sim = Cyclesim.create (Pcs.tx_circuit media) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let clear = i "clear" and valid = i "tx_valid" and data = i "tx_data" and last = i "tx_last" in
  let ready = o "tx_ready" and code = o "code" in
  let outs = match media with Pcs.Fx -> [ "line" ] | Pcs.Tx -> [ "pin_a"; "pin_b"; "scrambled" ] in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let codes = ref [] and lines = ref [] in
  (* present the head byte; advance when tx_ready was high in that cycle *)
  let bytes = ref (List.concat_map (fun f -> List.mapi (fun j b -> (b, j = List.length f - 1)) f) frames) in
  let gap = ref 0 in
  while !bytes <> [] || !gap < extra do
    (match !bytes with
     | (b, l) :: _ -> valid := Bits.vdd; data := Bits.of_int ~width:8 b; last := Bits.of_bool l
     | [] -> valid := Bits.gnd; incr gap);
    (* record the combinational outputs of the current cycle, then clock *)
    Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim;
    let took = Bits.to_int !ready = 1 in
    codes := bit_list_of_int 2 (Bits.to_int !code) :: !codes;
    lines := List.map (fun n -> bit_list_of_int 2 (Bits.to_int !(o n))) outs :: !lines;
    Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim;
    if took then (match !bytes with _ :: r -> bytes := r | [] -> ())
  done;
  List.concat (List.rev !codes), List.rev !lines

let drop_to_first_j bits =
  let rec go = function
    | 1 :: 1 :: 0 :: 0 :: 0 :: 1 :: 0 :: 0 :: 0 :: 1 :: _ as l -> l
    | _ :: r -> go r | [] -> [] in go bits

let check name ok = Printf.printf "%-60s %s\n%!" name (if ok then "pass" else "FAIL")

let digital_checks () =
  let max0 = R.self_test () in
  check (Printf.sprintf "reference model self-test (longest run of zeros %d <= 3)" max0) (max0 <= 3);
  let rng = Random.State.make [| 1 |] in
  let frames = List.init 6 (fun i -> R.random_frame ~rng (64 + 290 * i)) in
  (* FX transmit: RTL code bits against the reference symbol stream *)
  let code, lines = run_tx Pcs.Fx frames ~extra:40 in
  let ref_bits = R.symbols_to_bits (R.stream ~gap:0 frames) in
  let got = drop_to_first_j code and want = drop_to_first_j ref_bits in
  (* compare frame by frame: decode both *)
  let dg = R.decode_stream got and dw = R.decode_stream want in
  check "FX tx: RTL code stream decodes to the same frames as the reference" (dg = dw && List.length dg = 6);
  if dg <> dw then List.iter2 (fun (a, _) (b, _) -> Printf.printf "  lengths %d %d equal %b\n   got  %s\n   want %s\n" (List.length a) (List.length b) (a = b)
    (String.concat " " (List.map (Printf.sprintf "%02x") (List.filteri (fun i _ -> i < 20) a)))
    (String.concat " " (List.map (Printf.sprintf "%02x") (List.filteri (fun i _ -> i < 20) b)))) dg dw;
  check "FX tx: every frame delimited and FCS correct" (List.for_all (fun (f, ok) -> ok && R.fcs_ok f) dg);
  let line = List.concat_map (function [ l ] -> l | _ -> assert false) lines in
  check "FX tx: NRZI line decodes to the code stream" (R.nrzi_decode line = code);
  (* TX transmit: scrambler + MLT-3 pins *)
  let code2, lines2 = run_tx Pcs.Tx frames ~extra:40 in
  let scr = List.concat_map (function [ _; _; s ] -> s | _ -> assert false) lines2 in
  let lvl = List.concat_map (function [ a; b; _ ] -> List.map2 ( - ) a b | _ -> assert false) lines2 in
  check "TX tx: scrambler output = reference keystream xor code" (scr = R.scramble ~seed:0x7FF code2);
  check "TX tx: pin pair A-B = reference MLT-3 of the scrambled stream" (lvl = R.mlt3_encode scr);
  let pa = List.concat_map (function [ a; _; _ ] -> a | _ -> assert false) lines2 in
  let pb = List.concat_map (function [ _; b; _ ] -> b | _ -> assert false) lines2 in
  let min_gap l = let last = ref (-100) and m = ref max_int and p = ref (List.hd l) in
    List.iteri (fun i x -> if x <> !p then (m := min !m (i - !last); last := i; p := x)) l; !m in
  Printf.printf "  TX pins: minimum spacing between edges on one pin: A %d UI, B %d UI\n" (min_gap pa) (min_gap pb);
  code, frames

let () =
  let _ = digital_checks () in ()
