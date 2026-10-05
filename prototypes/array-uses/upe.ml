(* An executable model of one upe_v0 processing element, cycle for cycle.

   The source of truth is ../unified-pe/rtl/upe.v compiled with -DNO_POP -DNO_LUT -DBITSEL (the
   configuration notes/architecture-v0.md calls upe_v0). Every register, mux and flag below is
   transcribed from that file; [Lockstep] checks this model against the Verilog under Icarus on
   random configurations and inputs. Configuration lives in the same 8-byte chain as the RTL, so
   loading a configuration (and what the PE does while one is being shifted in) is modelled too. *)

let m16 = 0xffff
let bit v i = (v lsr i) land 1

(* ---- the op word, as named in upe.v ---- *)
type op = {
  fn : int; xs : int; ys : int; ym : int; gs : int; sw : int; pw : int; sins : int;
  ix : int; stream : int; bsel : int; drop : int; bcast : int; pairlo : int; outs : int;
  ib : int; cinb : int; zf : int; k : int;
}

type state = {
  c : int array;          (* configuration chain c[0..7]; op = c7..c2, K = {c1, c0} *)
  mutable s : int;
  mutable p : int;
  mutable pv : int;
  mutable f : int;
  mutable b1 : int;       (* lane register *)
  mutable cr : int;       (* carry-out register *)
  mutable dec : op option; (* decoded configuration, dropped whenever the chain shifts *)
}

type inputs = {
  clear : int; cfg_in : int; cfg_strobe : int; init_in : int; init_strobe : int; en : int;
  a : int; a_valid : int; b_in : int; bc_in : int; cb_in : int; s15_in : int; g_in : int;
}

let idle = { clear = 0; cfg_in = 0; cfg_strobe = 0; init_in = 0; init_strobe = 0; en = 1;
             a = 0; a_valid = 1; b_in = 0; bc_in = 0; cb_in = 0; s15_in = 0; g_in = 0 }

type outputs = {
  cfg_out : int; init_out : int; p_out : int; p_valid : int; b_out : int; cb_out : int;
  s15_out : int; g_out : int; flag : int; s_out : int;
}

let create () = { c = Array.make 8 0; s = 0; p = 0; pv = 0; f = 0; b1 = 0; cr = 0; dec = None }

let op_word st =
  let c = st.c in
  (c.(7) lsl 40) lor (c.(6) lsl 32) lor (c.(5) lsl 24) lor (c.(4) lsl 16) lor (c.(3) lsl 8) lor c.(2)

let decode_raw st =
  let o = op_word st in
  let fld lo w = (o lsr lo) land ((1 lsl w) - 1) in
  { fn = fld 0 3; xs = fld 3 2; ys = fld 5 2; ym = fld 7 2; gs = fld 9 3; sw = fld 12 2;
    pw = fld 14 2; sins = fld 16 2; ix = fld 28 2; stream = fld 30 1;
    bsel = (fld 41 1 lsl 1) lor fld 31 1; drop = fld 32 1; bcast = fld 33 1; pairlo = fld 34 1;
    outs = fld 35 1; ib = fld 36 4; cinb = fld 40 1; zf = fld 42 1;
    k = (st.c.(1) lsl 8) lor st.c.(0) }

let decode st =
  match st.dec with
  | Some d -> d
  | None -> let d = decode_raw st in st.dec <- Some d; d

(* the 48-bit op word and K as the 8 bytes to shift in, first byte first (it ends in c[7]) *)
let cfg_bytes ?(fn = 0) ?(xs = 0) ?(ys = 0) ?(ym = 0) ?(gs = 0) ?(sw = 0) ?(pw = 0) ?(sins = 0)
    ?(ix = 0) ?(stream = 0) ?(bsel = 0) ?(drop = 0) ?(bcast = 0) ?(pairlo = 0) ?(outs = 0)
    ?(ib = 0) ?(cinb = 0) ?(zf = 0) ?(k = 0) () =
  let o =
    fn lor (xs lsl 3) lor (ys lsl 5) lor (ym lsl 7) lor (gs lsl 9) lor (sw lsl 12) lor (pw lsl 14)
    lor (sins lsl 16) lor (ix lsl 28) lor (stream lsl 30) lor ((bsel land 1) lsl 31)
    lor (drop lsl 32) lor (bcast lsl 33) lor (pairlo lsl 34) lor (outs lsl 35) lor (ib lsl 36)
    lor (cinb lsl 40) lor ((bsel lsr 1) lsl 41) lor (zf lsl 42)
  in
  (* c7 .. c2 = op bytes 5 .. 0, c1 c0 = K; the first byte shifted in ends in c7 *)
  [ (o lsr 40) land 0xff; (o lsr 32) land 0xff; (o lsr 24) land 0xff; (o lsr 16) land 0xff;
    (o lsr 8) land 0xff; o land 0xff; (k lsr 8) land 0xff; k land 0xff ]

(* A bug to plant for the checks: every consumer of the model can be run with it switched on,
   and a check that still passes has not tested anything. *)
let fault = ref (Sys.getenv_opt "UPE_FAULT")
let fault_is s = match !fault with Some f -> f = s | None -> false

type comb = { g : int; r : int; loser : int; cout : int; x : int; step : bool; bi : int }

let comb st (i : inputs) =
  let o = decode st in
  let a = i.a land m16 in
  let step = i.en = 1 && (o.stream = 0 || i.a_valid = 1) in
  let bi = if o.bcast = 1 then i.bc_in else i.b_in in
  let s = st.s in
  let fb = (if o.pairlo = 1 then i.cb_in else bit s 15) lxor bit a 0 in
  let d = ((a lsr 8) - (o.k lsr 8)) land 0xff in
  let g_win = if d lsr 4 = 0 then bit s (15 - (d land 15)) else 0 in
  let g_lk = if o.ix = 3 then g_win else 0 (* NO_LUT: g_lut = 0 *) in
  let g =
    match o.gs with
    | 0 -> 1 | 1 -> bit a o.ib | 2 -> bi | 3 -> bit s 15 lxor bi | 4 -> fb | 5 -> st.f
    | 6 -> g_lk | _ -> i.g_in
  in
  let sin = match o.sins with 0 -> bi | 1 -> i.s15_in | 2 -> 0 (* pop[0], NO_POP *) | _ -> g in
  let x =
    match o.xs with
    | 0 -> s | 1 -> a | 2 -> ((s lsl 1) lor sin) land m16 | _ -> (sin lsl 15) lor (s lsr 1)
  in
  let y = match o.ys with 0 -> o.k | 1 -> a | 2 -> s | _ -> 1 in
  let is_mm = o.fn = 2 || o.fn = 3 in
  let yg = if o.ym = 1 && g = 0 then 0 else y in
  let neg = is_mm || o.ym = 3 || (o.ym = 2 && g = 1) in
  let neg = if fault_is "negate" && o.ym = 2 then false else neg in
  let yn = if neg then lnot yg land m16 else yg in
  let cin = if neg || (o.cinb = 1 && bi = 1) then 1 else 0 in
  let sx v = if v land 0x8000 <> 0 then v - 0x10000 else v in
  let t = (sx x + sx yn + cin) land 0x1ffff in              (* 17-bit sum of sign extensions *)
  let t15 = bit t 15 and t16 = bit t 16 in
  let cout = (bit x 15 land bit yn 15) lor ((bit x 15 lxor bit yn 15) land (1 - t15)) in
  let ovf = t16 lxor t15 in
  let sat = if ovf = 1 then (if t16 = 1 then 0x8000 else 0x7fff) else t land m16 in
  let lt = t16 in
  let mx = if lt = 1 then y else x and mn = if lt = 1 then x else y in
  let r =
    match o.fn with
    | 0 -> sat | 1 -> t land m16 | 2 -> mx | 3 -> mn
    | 4 -> x lxor yn | 5 -> x land yn | 6 -> x lor yn | _ -> a (* A + pop, pop = 0 *)
  in
  let loser = if o.fn = 2 then mn else mx in
  { g; r; loser; cout; x; step; bi }

let outputs st (i : inputs) =
  let o = decode st in
  let cb = comb st i in
  let b_out = match o.bsel with 0 -> st.b1 | 1 -> bit st.s 15 | 2 -> st.cr | _ -> cb.g in
  { cfg_out = st.c.(7); init_out = st.s lsr 8; p_out = st.p; p_valid = st.pv; b_out;
    cb_out = bit st.s 15; s15_out = bit st.s 15; g_out = cb.g; flag = st.f;
    s_out = (if o.outs = 1 then st.s else st.p) }

(* one rising clock edge *)
let clock st (i : inputs) =
  let o = decode st in
  let cb = comb st i in
  let a = i.a land m16 in
  if i.clear = 1 then begin
    st.s <- 0; st.p <- 0; st.pv <- 0; st.f <- 0; st.b1 <- 0; st.cr <- 0
  end else if i.init_strobe = 1 then st.s <- ((st.s lsl 8) lor (i.init_in land 0xff)) land m16
  else if cb.step then begin
    (match o.sw with
     | 0 -> () | 1 -> st.s <- cb.r | 2 -> st.s <- cb.x | _ -> if cb.g = 1 then st.s <- cb.r);
    st.p <-
      (match o.pw with
       | 0 -> a | 1 -> cb.r | 2 -> cb.loser
       | _ -> if cb.g = 1 then (a land 0xff00) lor (o.k land 0xff) else a);
    st.f <- (if o.zf = 1 then (if cb.r = 0 then 1 else 0) else cb.g);
    st.pv <- (if o.stream = 1 then i.a_valid land (1 - (o.drop land cb.g)) else 1);
    st.b1 <- cb.bi;
    st.cr <- cb.cout
  end;
  (* the configuration chain shifts independently of clear and step *)
  if i.cfg_strobe = 1 then begin
    for j = 7 downto 1 do st.c.(j) <- st.c.(j - 1) done;
    st.c.(0) <- i.cfg_in land 0xff;
    st.dec <- None
  end

(* load a configuration directly (what 8 strobed clocks leave behind) *)
let load st bytes =
  List.iteri (fun j b -> st.c.(7 - j) <- b) bytes;
  st.dec <- None
