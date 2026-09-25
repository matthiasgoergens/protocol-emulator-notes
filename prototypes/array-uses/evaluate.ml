(* The evaluation table: every candidate workload on the upe_v0 array against the RP2350 host.

   Array side: items per second = PEs x 60 MHz / (PE-clocks per item), with the PE-clock count
   taken from a configuration of upe_v0 (notes/architecture-v0.md section 2.4) where one exists,
   and marked "est" where the mapping was only sketched. Host side: one item costs the llvm-mca
   cycle count of the kernel's innermost loop (results/host_cycles.txt, one Cortex-M33 core,
   single-cycle SRAM), divided over two cores at 150 MHz; the "+2" column adds two cycles per
   loop iteration for the taken branch the model does not charge. The host numbers are a static
   pipeline model, not a measurement on an RP2350.

   "need" is the rate the application actually requires, with its source or "est". The verdict
   asks two questions: is the array faster than the host by a useful factor, and does the need
   exceed what the host can do? Only a yes to both makes the array earn its area. *)

let fclk = 60e6
let host_hz = 2. *. 150e6

let host_cycles () =
  let ic = open_in "results/host_cycles.txt" in
  let tbl = Hashtbl.create 32 in
  (try
     while true do
       let l = input_line ic in
       match String.split_on_char ' ' l |> List.filter (( <> ) "") with
       | [ k; _; c; c2 ] when String.length k > 1 && k.[0] = 'k' ->
         (try Hashtbl.replace tbl k (float_of_string c, float_of_string c2) with _ -> ())
       | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  tbl

type cand = {
  name : string;
  item : string;
  kernel : string;          (* host kernel in host/kernels.c *)
  host_items_per_iter : float;
  pe_clocks : float;        (* PE-clocks per item on upe_v0; nan = does not map *)
  pe_note : string;         (* the configuration, and whether it is designed or est *)
  port_bound : float option;(* items per second a bank port allows, if lower *)
  need : float;             (* items per second the application needs; nan = none found *)
  need_note : string;
}

let nan = Float.nan

let cands = [
  { name = "1-bit correlation (GPS tracking, binary NN)"; item = "1x1-bit MAC";
    kernel = "k1b_corr_harley_seal"; host_items_per_iter = 64.; pe_clocks = 1.;
    pe_note = "S <- S + (g ? -A : A), g = broadcast lane (designed, gps)"; port_bound = None;
    need = 235.7e6; need_note = "12 ch x 6 corr x 3.27 MS/s (gps-hotcold README)" };
  { name = "multi-bit x +-1 code (DSSS, soft matcher)"; item = "16x1-bit MAC";
    kernel = "k2_pm1_smlad"; host_items_per_iter = 2.; pe_clocks = 1.;
    pe_note = "same configuration, multi-bit A"; port_bound = None;
    need = nan; need_note = "no application found beyond GPS" };
  { name = "HF direct-sampling DDC (8-bit ADC, I/Q, CIC3)"; item = "ADC sample";
    kernel = "k3_cic_ddc"; host_items_per_iter = 1.; pe_clocks = 16.;
    pe_note = "32-bit NCO (2), square-LO mixers (2), 3 x 32-bit integrators per arm (12); est; needs an 8x8 mixer for image rejection"; port_bound = None;
    need = 60e6; need_note = "0-30 MHz needs >= 60 MS/s (Nyquist)" };
  { name = "edit distance (Myers on host)"; item = "text char x 32 cells";
    kernel = "k5_myers"; host_items_per_iter = 1.; pe_clocks = 128.;
    pe_note = "about 4 PE-ops per DP cell, est; needs two links (see DTW)"; port_bound = None;
    need = nan; need_note = "none found at a rate the host misses" };
  { name = "Viterbi K=7 r=1/2"; item = "butterfly (2 ACS)";
    kernel = "k6_viterbi_step"; host_items_per_iter = 1.; pe_clocks = 8.;
    pe_note = "add, add, min per ACS (2 PEs + min), est; the trellis shuffle goes through a bank";
    port_bound = Some (fclk /. 2.);
    need = 8000.; need_note = "Galileo E1-B / SBAS: 250 bit/s x 32 butterflies" };
  { name = "dynamic time warping"; item = "DP cell";
    kernel = "k7_dtw_row"; host_items_per_iter = 1.; pe_clocks = 5.;
    pe_note = "does not map on upe_v0 (one link, static op); est 5 PE-clocks with a second link"; port_bound = None;
    need = nan; need_note = "offline trace matching: latency, not a rate" };
  { name = "min-plus relaxation (shortest paths)"; item = "2 relaxations";
    kernel = "k8_minplus"; host_items_per_iter = 1.; pe_clocks = 4.;
    pe_note = "P <- A + K, then S <- min(S, A): 2 PEs per relaxation (designed)"; port_bound = None;
    need = 6.6e6; need_note = "Floyd-Warshall n = 64 at 50 frames/s, est" };
  { name = "wavetable voice at 48 kHz"; item = "voice sample";
    kernel = "k9_voices"; host_items_per_iter = 1.; pe_clocks = nan;
    pe_note = "the array makes 60 MHz square/noise voices, not 48 kHz samples (synth.ml)"; port_bound = None;
    need = 48e3 *. 16.; need_note = "16 voices at 48 kHz" };
  { name = "1-D cellular automaton, 256 cells per line"; item = "32 cells";
    kernel = "k10_rule110"; host_items_per_iter = 1.; pe_clocks = 12.;
    pe_note = "16 cells per word, about 6 GF(2) ops per word, est"; port_bound = None;
    need = 125e3; need_note = "256 cells x 15,625 lines/s" };
  { name = "Mandelbrot"; item = "iteration";
    kernel = "k11_mandel"; host_items_per_iter = 1.; pe_clocks = 52.;
    pe_note = "no multiplier: 3 shift-add multiplies of 16 steps, est"; port_bound = None;
    need = 49e6; need_note = "256 x 192 x 50 frames x 20 iterations" };
  { name = "Reed-Solomon syndromes"; item = "symbol x syndrome";
    kernel = "k12_rs_syndrome"; host_items_per_iter = 1.; pe_clocks = 9.;
    pe_note = "GF(256) constant multiply as 8 gated XORs, one K per PE, est"; port_bound = None;
    need = nan; need_note = "no reachable link above 7 Mbit/s" };
  { name = "CRC polynomial search, brute force"; item = "candidate x bit";
    kernel = "k13_crc_bitwise"; host_items_per_iter = 1.; pe_clocks = 1.;
    pe_note = "CRC mode, one candidate per PE (designed)"; port_bound = None;
    need = nan; need_note = "a one-off; the GCD method (CRC RevEng) needs no search" };
  { name = "raycaster (column DDA)"; item = "DDA step";
    kernel = "k14_dda"; host_items_per_iter = 1.; pe_clocks = nan;
    pe_note = "data-dependent loop with a map lookup: no fit"; port_bound = None;
    need = 256. *. 20. *. 50.; need_note = "256 rays x 20 steps x 50 frames" };
  { name = "LZ77 longest match"; item = "position x byte";
    kernel = "k15_lz_match"; host_items_per_iter = 1.; pe_clocks = 2.;
    pe_note = "a window of 32 bytes in 16 PEs: too small to matter, est"; port_bound = None;
    need = nan; need_note = "host hash chains visit few positions" };
  { name = "PDM microphone decimation (CIC3)"; item = "8 PDM bits";
    kernel = "k16_pdm"; host_items_per_iter = 1.; pe_clocks = 24.;
    pe_note = "CIC integrators, one PE per stage (designed)"; port_bound = None;
    need = 3.072e6 /. 8.; need_note = "one microphone at 3.072 MHz" };
  { name = "streaming top-16 / insertion sort"; item = "compare-shift step";
    kernel = "k17_insert"; host_items_per_iter = 1.; pe_clocks = 1.;
    pe_note = "S <- max(S, A), P <- loser (designed)"; port_bound = None;
    need = 60e6; need_note = "one 60 MS/s stream, 1 step per sample typical (the host tests the threshold first)" };
]

let fmt x =
  if Float.is_nan x then "-"
  else if x >= 1e9 then Printf.sprintf "%.2fG" (x /. 1e9)
  else if x >= 1e6 then Printf.sprintf "%.1fM" (x /. 1e6)
  else if x >= 1e3 then Printf.sprintf "%.1fk" (x /. 1e3)
  else Printf.sprintf "%.0f" x

let main _ =
  let hc = host_cycles () in
  let b = Buffer.create 8192 in
  let p fmt_ = Printf.bprintf b fmt_ in
  p "Evaluation (evaluate.ml). Array: upe_v0 at 60 MHz; host: 2 x Cortex-M33 at 150 MHz, llvm-mca cycles.\n";
  p "items/s for 8, 16 array PEs; host items/s (mca, mca+2); ratio = 16 PEs / host (mca); need = application rate\n\n";
  p "%-46s %-22s %9s %9s %9s %9s %7s %9s %s\n" "workload" "item" "arr8" "arr16" "host" "host+2" "ratio" "need" "verdict";
  List.iter (fun c ->
      let cyc, cyc2 = try Hashtbl.find hc c.kernel with Not_found -> (nan, nan) in
      let host = host_hz /. (cyc /. c.host_items_per_iter) in
      let host2 = host_hz /. (cyc2 /. c.host_items_per_iter) in
      let arr n =
        let r = float n *. fclk /. c.pe_clocks in
        match c.port_bound with Some pb -> Float.min r pb | None -> r in
      let a8 = arr 8 and a16 = arr 16 in
      let ratio = a16 /. host in
      let host_ok = Float.is_nan c.need || c.need <= 0.5 *. host2 in
      let verdict =
        if Float.is_nan c.pe_clocks then "host (no fit on the array)"
        else if host_ok && Float.is_nan c.need then "host (no need beyond it)"
        else if host_ok then Printf.sprintf "host (need is %.1f%% of host)" (100. *. c.need /. host2)
        else if a16 >= c.need then "ARRAY (host short; array meets need)"
        else "neither meets the need at 16 PEs"
      in
      p "%-46s %-22s %9s %9s %9s %9s %7s %9s %s\n" c.name c.item (fmt a8) (fmt a16) (fmt host) (fmt host2)
        (if Float.is_nan ratio then "-" else Printf.sprintf "%.1f" ratio) (fmt c.need) verdict)
    cands;
  p "\nMappings and sources of the need:\n";
  List.iter (fun c -> p "- %s: %s. Need: %s.\n" c.name c.pe_note c.need_note) cands;
  let oc = open_out "results/evaluation.txt" in
  Buffer.output_buffer oc b; close_out oc;
  print_string (Buffer.contents b)
