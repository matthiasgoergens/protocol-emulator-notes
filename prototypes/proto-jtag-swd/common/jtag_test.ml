(* JTAG host firmware against a chain of independent TAP models (Jtag_tap), with the pins wired
   cycle by cycle. Expected values come from the chain's configuration and IEEE 1149.1 semantics,
   never from the models' internals, so a bug shared by host and model would still have to agree
   with the configuration to pass. *)

open Jtag_host

type run = {
  tdo : int array;                                  (* one TDO sample per TCK *)
  trace : (int * int * int option * bool) array;    (* per clock: pin_out, pin_oe, host_out, host_in_ready *)
  tck : int array;                                  (* TCK level per clock *)
  contention : int; cycles : int; stalls : int;
  taps : Jtag_tap.t array; complete : bool;
}

let run ?(sync = 2) ?(tco = 0) ?(stall = fun () -> false) ~mk ~mem ~cfgs ~pins_in vecs =
  let taps = Array.map Jtag_tap.create cfgs in
  Array.iteri (fun i p -> match p with Some a -> Jtag_tap.set_pins_in taps.(i) a | None -> ()) pins_in;
  let n = Array.length taps in
  let vecs = pad8 vecs in
  let bytes = Queue.of_seq (List.to_seq (pack vecs)) in
  let want_out = List.length vecs / 8 in
  let core : Asm.core = mk mem in
  let din = Wire.delay sync 0 and dtco = Wire.delay tco None in
  let pin_in = ref 0b1110 in
  let contention = ref 0 and stalls = ref 0 in
  let outs = ref [] and nout = ref 0 in
  let trace = ref [] and tckt = ref [] in
  let cyc = ref 0 and limit = 200 * List.length vecs + 10_000 in
  while !nout < want_out && !cyc < limit do
    let stalled = (not (Queue.is_empty bytes)) && stall () in
    if stalled then incr stalls;
    let valid = (not (Queue.is_empty bytes)) && not stalled in
    let host_in = if valid then Queue.peek bytes else 0 in
    let o = core.step ~pin_in:!pin_in ~host_in ~host_in_valid:valid in
    if o.host_in_ready then ignore (Queue.pop bytes);
    (match o.host_out with Some b -> outs := b :: !outs; incr nout | None -> ());
    trace := (o.pin_out, o.pin_oe, o.host_out, o.host_in_ready) :: !trace;
    let lvl p pull = if Wire.bit o.pin_oe p = 1 then Wire.bit o.pin_out p else pull in
    let tck = lvl Wire.p_clk 0 and tms = lvl Wire.p_tms 1 and tdi = lvl Wire.p_tdi 1 in
    let pre = Array.map Jtag_tap.tdo taps in
    Array.iteri (fun i t ->
      let d = if i = 0 then tdi else (match pre.(i - 1) with Some b -> b | None -> 1) in
      Jtag_tap.step t ~tck ~tms ~tdi:d) taps;
    let dev = Wire.through dtco (Jtag_tap.tdo taps.(n - 1)) in
    let tdo = Wire.resolve ~oe:(Wire.bit o.pin_oe Wire.p_tdo = 1) ~out:(Wire.bit o.pin_out Wire.p_tdo)
        ~dev ~pull:1 ~contention in
    let bus = tck lor (tms lsl 1) lor (tdi lsl 2) lor (tdo lsl 3) in
    tckt := tck :: !tckt;
    pin_in := Wire.through din bus;
    incr cyc
  done;
  { tdo = Array.of_list (unpack (List.rev !outs)); trace = Array.of_list (List.rev !trace);
    tck = Array.of_list (List.rev !tckt); contention = !contention; cycles = !cyc; stalls = !stalls;
    taps; complete = !nout = want_out }

(* ---- Scenarios: operations with their vectors and a check on the TDO samples. ---- *)

type op = { name : string; vecs : vec list; offs : int list; check : int list -> Jtag_tap.t array -> string option }

let ok_if c msg = if c then None else Some msg
let rand_bits st n = List.init n (fun _ -> Random.State.int st 2)
let bits_to_string bs = String.concat "" (List.map string_of_int bs)
let take n l = List.filteri (fun i _ -> i < n) l
let drop n l = List.filteri (fun i _ -> i >= n) l

(* The captured DR contents of a chain whose devices hold [regs] (index 0 nearest TDI), in the
   order TDO presents them: nearest-TDO device first, each register LSB first. *)
let tdo_order regs = List.concat (List.rev regs)

let reset_op = { name = "reset"; vecs = reset; offs = []; check = (fun _ _ -> None) }

let idcode_regs (cfgs : Jtag_tap.config array) =
  Array.to_list (Array.map (fun (c : Jtag_tap.config) ->
    match c.idcode with Some id -> bits_of_int ~n:32 id | None -> [ 0 ]) cfgs)

(* After Test-Logic-Reset every device holds IDCODE or, lacking one, BYPASS: a DR scan reads the
   chain's IDCODEs, then the TDI data comes out behind them. *)
let read_idcodes st cfgs =
  let captured = tdo_order (idcode_regs cfgs) in
  let data = rand_bits st 16 in
  (* TDI: the random data, then zeros to push it through; TDO: the IDCODEs, then the data *)
  let vecs, offs = scan ~ir:false (data @ List.map (fun _ -> 0) captured) in
  let expect = captured @ data in
  { name = "idcodes"; vecs; offs;
    check = (fun got _ -> ok_if (got = expect)
      (Printf.sprintf "idcode scan: got %s want %s" (bits_to_string got) (bits_to_string expect))) }

let ir_scan ?early_exit ?drop_select cfgs codes =
  let bits = tdo_order (Array.to_list (Array.mapi (fun i (c : Jtag_tap.config) -> bits_of_int ~n:c.ir_len codes.(i)) cfgs)) in
  let vecs, offs = scan ?early_exit ?drop_select ~ir:true bits in
  let lens = List.rev (Array.to_list (Array.map (fun (c : Jtag_tap.config) -> c.ir_len) cfgs)) in
  { name = "ir"; vecs; offs;
    check = (fun got _ ->
      (* every device's captured IR ends in the mandated 01 (LSB first: 1 then 0) *)
      let rec go got = function
        | [] -> None
        | l :: rest ->
          (match got with
           | 1 :: 0 :: _ -> go (drop l got) rest
           | _ -> Some (Printf.sprintf "IR capture lacks 01: %s" (bits_to_string got))) in
      go got lens) }

let all_bypass cfgs = Array.map (fun c -> Jtag_tap.code_bypass c) cfgs

(* BYPASS chain test: each device contributes one captured 0 and one bit of delay. *)
let bypass_count st cfgs =
  let n = Array.length cfgs in
  let data = rand_bits st (24 + Random.State.int st 40) in
  let vecs, offs = scan ~ir:false data in
  let expect = List.init n (fun _ -> 0) @ take (List.length data - n) data in
  { name = "bypass"; vecs; offs;
    check = (fun got _ -> ok_if (got = expect)
      (Printf.sprintf "bypass: got %s want %s" (bits_to_string got) (bits_to_string expect))) }

(* Boundary scan of device j with the others in BYPASS: capture the pin levels, shift in new
   data, and the update latch of device j must then hold exactly its share of the data. *)
let boundary ?(check_latch = true) st (cfgs : Jtag_tap.config array) j ~pins =
  let n = Array.length cfgs in
  let len = cfgs.(j).bsr_len + (n - 1) in
  let data = rand_bits st len in
  let vecs, offs = scan ~ir:false data in
  let before = n - 1 - j in   (* bypass bits between device j and TDO *)
  let expect = List.init before (fun _ -> 0) @ Array.to_list pins @ List.init j (fun _ -> 0) in
  let latch = Array.of_list (take cfgs.(j).bsr_len (drop before data)) in
  { name = Printf.sprintf "bsr(dev %d, %d bits)" j cfgs.(j).bsr_len; vecs; offs;
    check = (fun got taps ->
      if got <> expect then Some (Printf.sprintf "boundary capture: got %s want %s" (bits_to_string got) (bits_to_string expect))
      else ok_if ((not check_latch) || Jtag_tap.pins_out taps.(j) = latch)
          (Printf.sprintf "boundary update: latch %s want %s"
             (bits_to_string (Array.to_list (Jtag_tap.pins_out taps.(j)))) (bits_to_string (Array.to_list latch)))) }

(* The latch check reads the models' state after the whole run, so only the last boundary op of
   a session makes it. Checks that are evaluated at the end of the whole run: *)
let final_state_ok taps =
  Array.for_all (fun t -> Jtag_tap.state t = "Run-Test/Idle" && Jtag_tap.errors t = []) taps

(* A random chain and a full session on it. [plant] modifies one op to carry a planted bug. *)
type chain = { cfgs : Jtag_tap.config array; pins : int array array }

let random_chain st ~max_devs ~max_bsr =
  let n = 1 + Random.State.int st max_devs in
  let cfgs = Array.init n (fun _ ->
    let ir_len = 2 + Random.State.int st 7 in
    let idcode = if Random.State.int st 4 = 0 then None
      else Some (((Random.State.bits st lor (Random.State.bits st lsl 30)) land 0xFFFFFFFF) lor 1) in
    { Jtag_tap.ir_len; idcode; bsr_len = 1 + Random.State.int st max_bsr }) in
  { cfgs; pins = Array.map (fun (c : Jtag_tap.config) -> Array.init c.bsr_len (fun _ -> Random.State.int st 2)) cfgs }

type plant = No_plant | Early_exit | Drop_select

let session ?(plant = No_plant) st ch =
  let cfgs = ch.cfgs in
  let n = Array.length cfgs in
  let j = Random.State.int st n in
  let sel = Array.mapi (fun i c -> if i = j then Jtag_tap.code_sample_preload c else Jtag_tap.code_bypass c) cfgs in
  let ext = Array.mapi (fun i c -> if i = j then Jtag_tap.code_extest c else Jtag_tap.code_bypass c) cfgs in
  let early_exit = plant = Early_exit and drop_select = plant = Drop_select in
  [ reset_op; read_idcodes st cfgs;
    ir_scan cfgs (all_bypass cfgs); bypass_count st cfgs;
    ir_scan ~early_exit ~drop_select cfgs sel; boundary ~check_latch:false st cfgs j ~pins:ch.pins.(j);
    ir_scan cfgs ext; boundary st cfgs j ~pins:ch.pins.(j) ]

(* Lay the ops end to end; returns the vectors and each op's absolute offsets. *)
let layout ops =
  let base = ref 0 in
  let placed = List.map (fun op -> let b = !base in base := b + List.length op.vecs; (op, List.map (( + ) b) op.offs)) ops in
  List.concat_map (fun op -> op.vecs) ops, placed

(* Run a session and judge it; returns the failures (empty = pass) and the run. *)
let judge ops (r : run) =
  let fails = ref [] in
  if not r.complete then fails := "run did not complete" :: !fails;
  if r.contention > 0 then fails := Printf.sprintf "%d clocks of contention" r.contention :: !fails;
  List.iter (fun ((op : op), offs) ->
      let got = List.map (fun o -> if o < Array.length r.tdo then r.tdo.(o) else -1) offs in
      match op.check got r.taps with Some m -> fails := (op.name ^ ": " ^ m) :: !fails | None -> ()) ops;
  if not (final_state_ok r.taps) then
    fails := Printf.sprintf "final TAP states %s, errors [%s]"
        (String.concat "," (Array.to_list (Array.map Jtag_tap.state r.taps)))
        (String.concat "; " (List.concat_map Jtag_tap.errors (Array.to_list r.taps))) :: !fails;
  List.rev !fails
