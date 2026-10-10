(* run: an image on the ISA v2 interpreter and on the chip (specification and RTL in lockstep).

     run IMAGE [--isa | --chip | --both] [--no-rtl] [--clocks N] [--stimulus FILE] [--peer SPEC]...
         [--hostin FILE] [--vcd FILE] [--sigrok FILE.bin] [--sr FILE.sr] [--prog-words N]

   --both (the default) runs the interpreter and the chip and requires their nets to be equal on
   every clock of the run; on the chip, the specification and the RTL are compared on every pad,
   every clock (--no-rtl skips the RTL). The waveform files are written from the chip's run (from
   the interpreter's with --isa). Peers (SPEC, keys separated by commas):
     uart_tx:net=N,bit=CLOCKS,start=CLOCK[,gap=CLOCKS],bytes=HEX
     i2c_target:sda=N,scl=N,addr=A[,stretch=CLOCKS][,mem=HEX]
     wire:src=N,dst=N
   A stimulus file has lines "CLOCK NET LEVEL" (LEVEL 0, 1 or z), clocks from the run's start.
   --hostin FILE: bytes (binary) the host sends to the threads' IN during the run.
   Exit status 1 if the interpreter and the chip disagree, or the specification and the RTL. *)

let die fmt = Printf.ksprintf (fun s -> prerr_endline ("run: " ^ s); exit 2) fmt

let hex s =
  if String.length s mod 2 <> 0 then die "hex string %S has an odd length" s;
  List.init (String.length s / 2) (fun i -> int_of_string ("0x" ^ String.sub s (2 * i) 2))

let peer_of_spec spec =
  match String.index_opt spec ':' with
  | None -> die "peer %S: expected KIND:key=value,..." spec
  | Some i ->
    let kind = String.sub spec 0 i in
    let kv = List.map (fun p -> match String.index_opt p '=' with
        | Some j -> (String.sub p 0 j, String.sub p (j + 1) (String.length p - j - 1))
        | None -> die "peer %S: %S is not key=value" spec p)
        (String.split_on_char ',' (String.sub spec (i + 1) (String.length spec - i - 1))) in
    let get k = match List.assoc_opt k kv with Some v -> v | None -> die "peer %s needs %s=" kind k in
    let geti k = int_of_string (get k) in
    let opti k d = match List.assoc_opt k kv with Some v -> int_of_string v | None -> d in
    (match kind with
     | "uart_tx" -> Peers.uart_tx ~net:(geti "net") ~bit:(geti "bit") ~start:(geti "start") ~gap:(opti "gap" 0) (hex (get "bytes"))
     | "i2c_target" ->
       let mem = Array.make 256 0 in
       (match List.assoc_opt "mem" kv with Some h -> List.iteri (fun k v -> mem.(k) <- v) (hex h) | None -> ());
       Peers.i2c_target ~sda:(geti "sda") ~scl:(geti "scl") ~addr:(geti "addr") ~stretch:(opti "stretch" 0) mem
     | "wire" -> Peers.wire ~src:(geti "src") ~dst:(geti "dst")
     | k -> die "unknown peer kind %s (uart_tx, i2c_target, wire)" k)

let read_bytes path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.init (String.length s) (fun i -> Char.code s.[i])

let () =
  let image = ref None and mode = ref `Both and rtl = ref true and clocks = ref 10_000 in
  let stim = ref [] and peers = ref [] and hostin = ref [] and vcd = ref None and srb = ref None and sr = ref None in
  let prog_words = ref 1024 in
  let rec go = function
    | "--isa" :: r -> mode := `Isa; go r
    | "--chip" :: r -> mode := `Chip; go r
    | "--both" :: r -> mode := `Both; go r
    | "--no-rtl" :: r -> rtl := false; go r
    | "--clocks" :: n :: r -> clocks := int_of_string n; go r
    | "--stimulus" :: f :: r -> stim := !stim @ [ f ]; go r
    | "--peer" :: p :: r -> peers := !peers @ [ p ]; go r
    | "--hostin" :: f :: r -> hostin := read_bytes f; go r
    | "--vcd" :: f :: r -> vcd := Some f; go r
    | "--sigrok" :: f :: r -> srb := Some f; go r
    | "--sr" :: f :: r -> sr := Some f; go r
    | "--prog-words" :: n :: r -> prog_words := int_of_string n; go r
    | f :: r when f.[0] <> '-' && !image = None -> image := Some f; go r
    | [] -> ()
    | x :: _ -> die "unknown argument %s" x in
  go (List.tl (Array.to_list Sys.argv));
  let path = match !image with Some p -> p | None -> die "usage: run IMAGE [options] (see the source header)" in
  let img = try Image.parse (Image.of_file path) with Image.Bad_image m -> die "%s: not an image: %s" path m in
  (* fresh peers for each run: they hold state *)
  let make_peers () = List.map Peers.stimulus_file !stim @ List.map peer_of_spec !peers in
  let opts peers = { Runner.clocks = !clocks; peers; hostin = !hostin; prog_words = !prog_words } in
  let show (r : Runner.result) =
    let name = match r.mode with Isa -> "interpreter" | Chip { rtl = true } -> "chip (specification and RTL)" | Chip _ -> "chip (specification)" in
    Printf.printf "%s: %d clocks%s\n" name !clocks (if r.run_start > 0 then Printf.sprintf ", started at chip clock %d after the host-link load" r.run_start else "");
    Printf.printf "  OUT executed in the run: %d; host received: %s\n" (List.length r.trace.outs) (match r.received with [] -> "nothing"
        | l -> String.concat " " (List.map (fun (t, b) -> if t = 0 then Printf.sprintf "%02x" b else Printf.sprintf "%02x/%d" b t) l));
    (match r.agree with
     | Some true -> print_endline "  specification and RTL: equal on every pad, every clock"
     | Some false -> Printf.printf "  specification and RTL: DIFFER, first at chip clock %d\n" (Option.get r.first_diff)
     | None -> ());
    List.iter (Printf.printf "  %s\n") r.log in
  let isa_peers = make_peers () and chip_peers = make_peers () in
  let isa = if !mode <> `Chip then Some (Runner.run Runner.Isa img (opts isa_peers)) else None in
  let chip = if !mode <> `Isa then Some (Runner.run (Runner.Chip { rtl = !rtl }) img (opts chip_peers)) else None in
  Option.iter show isa;
  Option.iter show chip;
  let bad = ref false in
  (match isa, chip with
   | Some a, Some c ->
     (match Runner.compare a c with
      | None -> Printf.printf "interpreter and chip: equal nets on every clock of the run\n"
      | Some k -> Printf.printf "interpreter and chip: nets DIFFER at run clock %d\n" k; bad := true);
     if a.trace.outs <> c.trace.outs then (print_endline "interpreter and chip: the threads' OUTs differ (byte, tag or clock)"; bad := true)
     else Printf.printf "interpreter and chip: the same %d OUTs at the same clocks\n" (List.length a.trace.outs)
   | _ -> ());
  (match chip with Some { agree = Some false; _ } -> bad := true | _ -> ());
  (* the host link must deliver every OUT of the run, in order (and may deliver later ones) *)
  (match chip with
   | Some c ->
     let sent = List.map (fun (_, t, b) -> (t, b)) c.trace.outs in
     let rec prefix a b = match a, b with [], _ -> true | x :: a', y :: b' -> x = y && prefix a' b' | _ -> false in
     if not (prefix sent c.received) then (print_endline "chip: the host did not receive the threads' OUTs in order"; bad := true)
   | None -> ());
  let main = match chip, isa with Some c, _ -> c | None, Some a -> a | None, None -> assert false in
  List.iter (fun (p : Peers.t) -> List.iter (fun l -> Printf.printf "  %s: %s\n" p.name l) (p.report ()))
    (if chip <> None then chip_peers else isa_peers);
  Option.iter (fun f -> Wave.vcd f main.trace; Printf.printf "waveform: %s (VCD)\n" f) !vcd;
  Option.iter (fun f -> Wave.sigrok_bin f main.trace; Printf.printf "trace: %s (one byte a clock, bit k = net k, 60 MHz)\n" f) !srb;
  Option.iter (fun f -> Wave.sigrok_session f main.trace; Printf.printf "session: %s (sigrok/PulseView)\n" f) !sr;
  if !bad then exit 1
