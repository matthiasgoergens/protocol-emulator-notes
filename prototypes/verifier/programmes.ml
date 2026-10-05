(* The programmes under verification and their specifications.

   Images. The protocol programmes are the output of the repository's compiler
   (../deadline-sequencer/compiler.ml, base ISA), translated word by word to ISA v2 by
   ../sequencer-v2/compat.ml, as every v2 port runs them; words past the programme read 0 (NOP).
   A thread's image is its 256-word page.

   Specifications. Each is written from the timing the compiler's comments document, as closed
   forms in the protocol's parameters, not from the words it emits: if the code generator and
   its comment disagree, verification fails. Where a comment leaves a gap unstated (the slots
   between an ack's SCL fall and the next byte's first SDA change, say), the gap is stated here
   and the interpreter cross-check (sim.ml) confirms it on every run. *)

open Spec

type image = {
  name : string;
  words : int array;          (* the thread's 256-word page, ISA v2 *)
  spec : Spec.t;
  thread : int;               (* the thread it runs on in the cross-checks *)
  env : env;                  (* the environment the interpreter cross-check runs it in *)
}

(* What drives the released pins in a cross-check run. *)
and env =
  | Pull_up                                    (* every released pin reads 1 *)
  | I2c_slave of { sda : int; scl : int }     (* an acking slave that stretches SCL at random *)
  | Random_inputs                              (* every input random on every clock *)

let v2_of_base (p : int array) =
  Array.init Isa2.page_len (fun pc ->
      if pc < Array.length p then Compat.of_base ~pc_bits:Isa.pc_bits ~addr:pc p.(pc) else 0)

(* ---- specifications ---- *)

let ex = Interval.exactly

(* UART 8N1, lsb first, on pin [u]: [b] slots a bit; data bit [k] of the first byte [d] slots
   longer when [stretch = Some (k, d)] (compiler.ml: "Start bit ... width 4+x = bit_slots",
   "Data bit: ... 4+x", "Stop: ... 4+x"). The idle level is set within one bit of the start, the
   first start bit follows within a bit time, and every later cell boundary is exact. *)
let uart_spec ~u ~b ~nbytes ~stretch =
  let bl = builder () in
  step bl [ (u, Set H) ] (Interval.range 0 b) "idle high";
  for i = 0 to nbytes - 1 do
    let width j = b + (match stretch with Some (k, d) when i = 0 && k = j -> d | _ -> 0) in
    step bl [ (u, Set L) ] (if i = 0 then Interval.range 1 b else ex b) (Printf.sprintf "byte %d start bit" i);
    for j = 1 to 8 do
      step bl [ (u, Data_pp) ] (ex (if j = 1 then b else width (j - 1))) (Printf.sprintf "byte %d data bit %d" i j)
    done;
    step bl [ (u, Set H) ] (ex (width 8)) (Printf.sprintf "byte %d stop bit" i)
  done;
  finish bl ~name:(Printf.sprintf "uart b=%d bytes=%d%s" b nbytes
                     (match stretch with Some (k, d) -> Printf.sprintf " stretch=%d+%d" k d | None -> ""))
    ~pins:[ u ]

(* SPI mode 0, msb first, period [p] slots (compiler.ml: "High width 3+b = P/2"; the bit loop
   "SHO(0) ... SETP sclk=1 (3+a) ... SETP sclk=0 (6+a+b) JNZ, next SHO at 8+a+b" with
   a + b = P - 8). So SCLK is high for P/2 and low for P/2, MOSI changes 2 slots after each fall
   and so P/2 - 2 before each rise, and CS changes 2 slots from its neighbours. *)
let spi_spec ~sclk ~mosi ~cs ~p ~nbytes =
  let bl = builder () in
  (* the compiler lists "cs high" before "sclk and mosi low" in its source, but its item list is
     reversed as a whole at the end, so the image sets sclk and mosi first *)
  step bl [ (sclk, Set L); (mosi, Set L) ] (ex 0) "sclk and mosi low";
  step bl [ (cs, Set H) ] (ex 1) "cs idle";
  for i = 0 to nbytes - 1 do
    step bl [ (cs, Set L) ] (ex 2) (Printf.sprintf "byte %d cs asserted" i);
    for j = 1 to 8 do
      step bl [ (mosi, Data_pp) ] (ex 2) (Printf.sprintf "byte %d bit %d mosi" i j);
      step bl [ (sclk, Set H) ] (ex (p / 2 - 2)) (Printf.sprintf "byte %d bit %d sclk rise" i j);
      step bl [ (sclk, Set L) ] (ex (p / 2)) (Printf.sprintf "byte %d bit %d sclk fall" i j)
    done;
    step bl [ (cs, Set H) ] (ex 2) (Printf.sprintf "byte %d cs released" i)
  done;
  finish bl ~name:(Printf.sprintf "spi p=%d bytes=%d" p nbytes) ~pins:[ sclk; mosi; cs ]

(* I2C master write with clock stretching, quarter period [q] slots, stretch limit [lm] slots
   (compiler.ml, i2c_write). Every release of SCL is followed by an observation of SCL high within
   [lm] slots (A1 lets the slave hold it for any time), or by a timeout at exactly [lm] slots
   after which both lines are released one slot later and the programme stops. The high phase is
   timed from the observation: 2q - 1 slots to the fall for a data bit (the comment's "high time
   measured from the rise is between (2q-1) slots plus one clock and 2q slots"); the ack is
   sampled q - 1 slots after the observation and SCL falls q slots after the sample ("SHI at
   y+3q", "scl low at y+4q"). *)
let i2c_spec ~sda ~scl ~q ~nbytes ~lm =
  let bl = builder () in
  let scl_up label =
    let r = bl.cur in
    let t = fresh bl (label ^ ": timed out") in
    add bl ~src:r [ (scl, Timeout 1) ] (ex lm) ~dst:t (label ^ ": timeout");
    let f = fresh bl (label ^ ": released after timeout") in
    add bl ~src:t [ (sda, Set Z); (scl, Set Z) ] (ex 1) ~dst:f (label ^ ": release after timeout");
    step bl [ (scl, Seen 1) ] (Interval.range 1 lm) (label ^ ": scl seen high") in
  step bl [ (sda, Set L) ] (ex 0) "START sda low";
  step bl [ (scl, Set L) ] (ex q) "START scl low";
  for i = 0 to nbytes - 1 do
    for j = 1 to 8 do
      let l = Printf.sprintf "byte %d bit %d" i j in
      step bl [ (sda, Data_od) ] (ex (if j > 1 then 2 else if i = 0 then 3 else 4)) (l ^ " sda");
      step bl [ (scl, Set Z) ] (ex (2 * q - 2)) (l ^ " scl released");
      scl_up l;
      step bl [ (scl, Set L) ] (ex (2 * q - 1)) (l ^ " scl low")
    done;
    let l = Printf.sprintf "byte %d ack" i in
    step bl [ (sda, Set Z) ] (ex 2) (l ^ " sda released");
    step bl [ (scl, Set Z) ] (ex (2 * q - 2)) (l ^ " scl released");
    scl_up l;
    step bl [ (sda, Smp) ] (ex (q - 1)) (l ^ " sampled");
    step bl [ (scl, Set L) ] (ex q) (l ^ " scl low")
  done;
  step bl [ (sda, Set L) ] (ex 2) "STOP sda low";
  step bl [ (scl, Set Z) ] (ex (2 * q - 1)) "STOP scl released";
  scl_up "STOP";
  step bl [ (sda, Set Z); (scl, Set Z) ] (ex (q - 1)) "STOP sda released";
  finish bl ~name:(Printf.sprintf "i2c q=%d bytes=%d limit=%d" q nbytes lm) ~pins:[ sda; scl ]

(* ../formal/programmes.ml's deadline programme: pin 7 low; wait up to the deadline register
   ([ldd], 20 there) for pin 1 to rise; then pin 6 high, or on a timeout pin 7 high. Declared:
   the response comes 1 slot after the observation, which is within [2, ldd + 2] slots of the
   start, or 1 slot after the timeout at ldd + 2. *)
let deadline_spec ~name ~watch ~ok ~bad ~ldd =
  let bl = builder () in
  step bl [ (bad, Set L) ] (ex 0) "timeout pin low";
  let w = bl.cur in
  let t = fresh bl "timed out" in
  add bl ~src:w [ (watch, Timeout 1) ] (ex (ldd + 2)) ~dst:t "timeout";
  let f = fresh bl "timeout reported" in
  add bl ~src:t [ (bad, Set H) ] (ex 1) ~dst:f "timeout reported";
  step bl [ (watch, Seen 1) ] (Interval.range 2 (ldd + 2)) "input seen";
  (match ok with Some ok -> step bl [ (ok, Set H) ] (ex 1) "event reported" | None -> ());
  finish bl ~name ~pins:(watch :: bad :: (match ok with Some p -> [ p ] | None -> []))

(* ---- the compiled images ---- *)

let uart ?(thread = 0) ?stretch ~b bytes =
  let p, _ = Compiler.uart_tx { upin = 0; bit_slots = b; ubytes = bytes; stretch } in
  { name = Printf.sprintf "uart_b%d_n%d%s" b (List.length bytes)
        (match stretch with Some (k, d) -> Printf.sprintf "_s%d+%d" k d | None -> "");
    words = v2_of_base p; spec = uart_spec ~u:0 ~b ~nbytes:(List.length bytes) ~stretch; thread; env = Pull_up }

let spi ?(thread = 1) ~p bytes =
  let w, _ = Compiler.spi_master { sclk = 1; mosi = 2; cs = 3; period = p; sbytes = bytes } in
  { name = Printf.sprintf "spi_p%d_n%d" p (List.length bytes); words = v2_of_base w;
    spec = spi_spec ~sclk:1 ~mosi:2 ~cs:3 ~p ~nbytes:(List.length bytes); thread; env = Pull_up }

let i2c ?(thread = 2) ?(lm = 4095) ~q bytes =
  let w, _ = Compiler.i2c_write ~stretch_limit:lm { sda = 4; scl = 5; q; ibytes = bytes } in
  { name = Printf.sprintf "i2c_q%d_n%d_l%d" q (List.length bytes) lm; words = v2_of_base w;
    spec = i2c_spec ~sda:4 ~scl:5 ~q ~nbytes:(List.length bytes) ~lm; thread; env = I2c_slave { sda = 4; scl = 5 } }

let deadline_words ~ldd =
  let p = Array.make Isa.prog_len Isa.nop in
  p.(0) <- Isa.setp ~mask:0x80 ~value:0 ~oe:1;
  p.(1) <- Isa.ldd ldd;
  p.(2) <- Isa.waitp ~pin:1 ~value:1 ~fail:5;
  p.(3) <- Isa.setp ~mask:0x40 ~value:1 ~oe:1;
  p.(4) <- Isa.halt;
  p.(5) <- Isa.setp ~mask:0x80 ~value:1 ~oe:1;
  p.(6) <- Isa.halt;
  v2_of_base p

let deadline ?(ldd = 20) () =
  { name = Printf.sprintf "deadline_ldd%d" ldd; words = deadline_words ~ldd;
    spec = deadline_spec ~name:(Printf.sprintf "deadline ldd=%d" ldd) ~watch:1 ~ok:(Some 6) ~bad:7 ~ldd;
    thread = 0; env = Random_inputs }

let watchdog_words ~timeout_mask =
  let p = Array.make Isa.prog_len Isa.halt in
  p.(0) <- Isa.setp ~mask:0x80 ~value:0 ~oe:1;
  p.(1) <- Isa.ldd 20;
  p.(2) <- Isa.waitp ~pin:6 ~value:1 ~fail:4;
  p.(3) <- Isa.halt;
  p.(4) <- Isa.setp ~mask:timeout_mask ~value:1 ~oe:1;
  p.(5) <- Isa.halt;
  v2_of_base p

let watchdog () =
  { name = "watchdog"; words = watchdog_words ~timeout_mask:0x80;
    spec = deadline_spec ~name:"watchdog" ~watch:6 ~ok:None ~bad:7 ~ldd:20; thread = 3; env = Random_inputs }

(* ---- the parameter sweep: every programme the compiler emits in these ranges ---- *)

let byte_lists = [ [ 0x55 ]; [ 0xA5; 0x3C ]; [ 0x4F; 0x4B; 0x21 ]; [ 0x00; 0xFF; 0x81; 0x7E ] ]

let fits f = try Some (f ()) with Failure _ -> None   (* the 64-word base store *)

let sweep () =
  let uarts = List.concat_map (fun b -> List.filter_map (fun bs -> fits (fun () -> uart ~b bs)) byte_lists)
      (List.init 60 (fun i -> i + 5)) in
  let uart_stretch = List.concat_map (fun k -> List.map (fun d -> uart ~b:16 ~stretch:(k, d) [ 0x4F ]) [ 0; 1; 3; 8 ])
      [ 1; 2; 3; 4; 5; 6; 7; 8 ] in
  let spis = List.concat_map (fun p -> List.filter_map (fun bs -> fits (fun () -> spi ~p bs)) byte_lists)
      (List.init 28 (fun i -> 10 + 2 * i)) in
  let i2cs = List.concat_map (fun q -> List.concat_map (fun lm ->
      List.filter_map (fun bs -> fits (fun () -> i2c ~q ~lm bs)) [ [ 0xA0 ]; [ 0xA0; 0x5A ] ])
      [ 1; 2; 7; 100; 4095 ]) (List.init 13 (fun i -> i + 4)) in
  uarts @ uart_stretch @ spis @ i2cs @ [ deadline (); deadline ~ldd:0 (); deadline ~ldd:4095 (); watchdog () ]

(* ---- planted bugs: each must be rejected ---- *)

let opcode w = (w lsr 12) land 0xF
let with_words img ~name f = { img with name; words = f (Array.copy img.words) }

(* the n-th word (from 0) with opcode [op] *)
let nth_op words op n =
  let rec go i k = if i >= Array.length words then raise Not_found
    else if opcode words.(i) = op then (if k = n then i else go (i + 1) (k + 1)) else go (i + 1) k in
  go 0 0

let planted () =
  let spi10 = spi ~p:10 [ 0xA5 ] in
  (* the compiler's arithmetic at P = 8: a = P - 8 - (P/2 - 3) = -1, so LDD a is LDD 4095, and
     b = 1. Made from the P = 10 image (a = 0, b = 2) by setting the loop's two LDDs as the
     compiler did before it gained its assertion (formal/README.md, Findings 1) *)
  let spi8 = { (with_words spi10 ~name:"PLANTED spi_p8 (LDD a wraps to 4095)" (fun w ->
      w.(nth_op w 3 0) <- Isa2.ldd 4095; w.(nth_op w 3 1) <- Isa2.ldd 1; w))
               with spec = spi_spec ~sclk:1 ~mosi:2 ~cs:3 ~p:8 ~nbytes:1 } in
  let i2c1 = i2c ~q:4 [ 0xA0 ] in
  let no_waitp = with_words i2c1 ~name:"PLANTED i2c without WAITP (stretch-blind)" (fun w ->
      Array.map (fun x -> if opcode x = Isa2.op_waitp then Isa2.nop else x) w) in
  let one_waitp = with_words i2c1 ~name:"PLANTED i2c, the ack's WAITP missing" (fun w ->
      w.(nth_op w Isa2.op_waitp 1) <- Isa2.nop; w) in
  let no_limit = with_words i2c1 ~name:"PLANTED i2c, stretch limit LDD missing before a release" (fun w ->
      (* the LDD stretch_limit before the first data bit's release becomes NOP: the WAITP then
         runs on whatever the earlier LDD 2q-6 WAITD left, dl = 0, and times out at once *)
      let r = nth_op w Isa2.op_waitp 0 in w.(r - 2) <- Isa2.nop; w) in
  let wrong_fail = with_words i2c1 ~name:"PLANTED i2c, a WAITP's timeout target is the next word" (fun w ->
      let r = nth_op w Isa2.op_waitp 0 in w.(r) <- (w.(r) land 0xFF00) lor ((r + 1) land 0xFF); w) in
  let uart16 = uart ~b:16 [ 0x4F; 0x4B ] in
  let uart_off = with_words uart16 ~name:"PLANTED uart, a data-bit LDD one short" (fun w ->
      let i = nth_op w 3 1 in w.(i) <- Isa2.ldd ((w.(i) land 0xFFF) - 1); w) in
  let uart_halt = with_words uart16 ~name:"PLANTED uart, HALT before the second stop bit" (fun w ->
      let i = nth_op w 1 4 in w.(i) <- Isa2.halt_at i; w) in
  let uart_ldc = with_words uart16 ~name:"PLANTED uart, LDC 7 (a bit short)" (fun w ->
      let i = nth_op w 2 0 in w.(i) <- Isa2.ldc 7; w) in
  let spi_cs = with_words (spi ~p:16 [ 0xA5 ]) ~name:"PLANTED spi, cs released one slot early" (fun w ->
      (* swap the JNZ and the following SETP cs=1: cs rises before the loop's last decision *)
      let j = nth_op w Isa2.op_jnz 0 in let x = w.(j) in w.(j) <- w.(j + 1); w.(j + 1) <- x; w) in
  let dl30 = { (deadline ~ldd:30 ()) with name = "PLANTED deadline programme, LDD 30 against a declared 20";
                                          spec = (deadline ()).spec } in
  let in_wait = with_words uart16 ~name:"PLANTED uart, LDA replaced by IN (waits for the host)" (fun w ->
      let i = nth_op w Isa2.op_lda 1 in w.(i) <- Isa2.in_; w) in
  [ spi8; no_waitp; one_waitp; no_limit; wrong_fail; uart_off; uart_halt; uart_ldc; spi_cs; dl30; in_wait ]
