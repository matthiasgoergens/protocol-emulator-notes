(* Oversampling clock and data recovery, as a precise model written the way the hardware would
   do it: integer (fixed-point) arithmetic, a bounded amount of work per clock, one clock of
   latency (it decides the previous clock's UIs with the current clock's samples as look-ahead).
   Generic over the number of samples per clock [n] and the nominal samples per UI [osr] (n / osr
   UIs per clock), and over the sample alphabet (an int: an NRZI level, or a sliced MLT-3 level).

   A second-order digital PLL on edge positions:
   - theta: where the next data sample falls, in 1/2^f of a sample (f = 16), relative to sample 0
     of the clock being decided; omega: samples per UI in the same units, which absorbs the
     frequency offset (resolution 2^-16 of a sample, about 8 ppm at osr = 2);
   - every transition between adjacent samples is an edge at the midpoint between them; its
     phase error is its distance from the nearest expected edge (half a UI before a data sample),
     wrapped into +-UI/2; after the clock, theta += sum(err) >> kp, omega += sum(err) >> ki
     (omega clamped to +-2000 ppm of nominal);
   - data samples: every theta, theta + omega, ... that falls in the clock, so 0..(n/osr + 1)
     UIs come out per clock.

   osr = 2 needs one more piece (found by measurement, see README): with two samples per UI the
   quantised phase detector has two stable points when edges straddle a sample, and even the
   good one sits about 0.1 sample from the rounding boundary between the good sample and the
   edge sample. The edge positions cannot tell the two candidates apart, but runs of exactly one
   sample can: a one-UI pulse always covers the sample half a UI from its edges, so lone samples
   sit on the good candidate. An eye-centre voter counts lone samples on and off the chosen
   candidate and, after 8 net votes against, moves the decision by one sample ([delta]),
   independently of the loop.

   With osr = 1 (n = 2: both clock edges at 62.5 MHz) there is nothing to choose between; that
   case is here to be measured, not because it can work. *)

type t = {
  n : int; osr : int; f : int; kp : int; ki : int;
  mutable theta : int; mutable omega : int; omega_nom : int;
  mutable prev : int array;       (* the clock being decided *)
  mutable prev_last : int;        (* the sample before it *)
  mutable before : int array;     (* the whole clock before it (edge look-back) *)
  mutable delta : int;            (* voter's decision offset, 0 or one sample *)
  mutable vote : int;
  mutable flips : int;
  voter : bool;
  hist : int array;               (* lone-sample positions relative to the decision, 8 bins (diagnostic) *)
  edge_mode : bool;               (* decide from edges (default) or by picking samples *)
  mutable carry : int;            (* level of the last UI output *)
}

let env k d = try int_of_string (Sys.getenv k) with Not_found -> d
let create ?(f = 16) ?(kp = env "CDR_KP" 3) ?(ki = env "CDR_KI" 9) ~n ~osr () =
  let one = 1 lsl f in
  { n; osr; f; kp; ki; theta = osr * one / 2; omega = osr * one; omega_nom = osr * one;
    prev = Array.make n 0; prev_last = 0; before = Array.make n 0; delta = 0; vote = 0; flips = 0;
    voter = env "CDR_VOTER" 0 = 1 && osr = 2; hist = Array.make 8 0;
    edge_mode = env "CDR_EDGE" 1 = 1; carry = 0 }

let trace_clk = ref 0
let trace_lo = env "CDR_TRACE" (-100)
(* one clock: new samples x.(0..n-1); returns the data samples of the previous clock *)
let step c (x : int array) =
  let one = 1 lsl c.f in
  incr trace_clk;
  let span = c.n * one in
  (* window: j = -1 is prev_last, 0..n-1 the clock being decided, n..2n-1 the new samples *)
  let get j = if j < 0 then c.before.(j + c.n) else if j < c.n then c.prev.(j) else x.(j - c.n) in
  let out = ref [] in
  let th = ref c.theta in
  let nui = ref 0 in
  while !th + one / 2 < span do
    let idx = max 0 ((!th + one / 2 + c.delta) asr c.f) in
    out := get idx :: !out;
    incr nui;
    th := !th + c.omega
  done;
  if c.edge_mode then begin
    (* Edge decoding: UI m (0-based in this clock) has its centre at theta + m omega and its
       leading boundary at theta - omega/2 + m omega. Each edge (between samples j-1 and j,
       j over this clock and the look-ahead clock) goes to its nearest boundary; the level of
       UI m is the level after the last edge assigned to a boundary in 0..m, else the carry. *)
    let lv = Array.make !nui (-99) in
    let x0 = c.theta - c.omega / 2 in
    (* look back a whole clock: an edge near the end of the previous clock may belong to this
       clock's first boundary (found by trace: without the look-back such edges were lost) *)
    for j = 1 - c.n to 2 * c.n - 1 do
      if get j <> get (j - 1) then begin
        let pe = j * one - one / 2 in
        let d = pe - x0 in
        (* nearest boundary index, rounding half up *)
        let m = (if d >= 0 then (d + c.omega / 2) / c.omega else - ((- d + c.omega / 2 - 1) / c.omega)) in
        (* an edge the previous clock left to this one can land on boundary -1 after the phase
           update; edges are visited in order and assignments are monotonic, so clamping to 0
           and letting the last edge win is safe *)
        if m < !nui then lv.(max 0 m) <- get j
      end
    done;
    if !trace_clk >= trace_lo && !trace_clk < trace_lo + 12 then begin
      Printf.printf "clk %d theta %.3f nui %d samples " !trace_clk (float c.theta /. float one) !nui;
      for j = -1 to 2 * c.n - 1 do print_int (get j); if j = -1 || j = c.n - 1 then print_char '|' done;
      Printf.printf " lv %s carry %d\n" (String.concat "," (Array.to_list (Array.map string_of_int lv))) c.carry
    end;
    let cur = ref c.carry in
    out := [];
    for m = 0 to !nui - 1 do
      if lv.(m) <> -99 then cur := lv.(m);
      out := !cur :: !out
    done;
    c.carry <- !cur
  end;
  let e = ref 0 in
  for j = 0 to c.n - 1 do
    if get j <> get (j - 1) then begin
      let pe = j * one - one / 2 in
      let d = pe - (c.theta - c.omega / 2) in
      let w = c.omega in
      e := !e + (((d mod w) + w + w / 2) mod w - w / 2)
    end
  done;
  if c.voter then begin
    for j = 0 to c.n - 1 do
      if get j <> get (j - 1) && get j <> get (j + 1) then begin
        let w = c.omega in
        let r = (((j * one - (c.theta + c.delta)) mod w) + w + one / 2) mod w in
        c.hist.(min 7 (r * 8 / w)) <- c.hist.(min 7 (r * 8 / w)) + 1;
        (* on a chosen candidate iff r (shifted by half a sample) is in the first sample *)
        c.vote <- max (-8) (if r < one then c.vote - 1 else c.vote + 1)
      end
    done;
    if c.vote >= 8 then begin c.vote <- 0; c.flips <- c.flips + 1; c.delta <- one - c.delta end
  end;
  c.prev_last <- c.prev.(c.n - 1);
  c.before <- c.prev;
  c.prev <- Array.copy x;
  let lim = c.omega_nom / 500 in
  c.omega <- max (c.omega_nom - lim) (min (c.omega_nom + lim) (c.omega + (!e asr c.ki)));
  c.theta <- !th - span + (!e asr c.kp);
  List.rev !out

(* Two samples per UI (the four-phase input stage at 62.5 MHz). The loop above has a false lock
   here, so this variant tracks the UI boundary grid G directly, in half-sample steps:
   - an edge between samples j-1 and j has class (j mod 2): the boundary is at 0.5 or 1.5 (mod 2);
   - over the last [win] edges, if nearly all are one class, G is that class's position;
   - if both classes occur, the edges straddle a sample, which is the boundary; which of the two
     samples (mod 2) it is cannot be told from edges, so it comes from lone samples (runs of one
     sample), which sit on data samples, half a UI from the boundary;
   - G is unwrapped against its previous value (moves of +-0.5 sample are drift; a move of 1
     sample is a voter correction and goes in the direction of the recent drift).
   UIs are then decided from edges as in [step]: each edge goes to its nearest boundary on the
   grid G + 2m, the UI's level is the level after its last edge. Absolute sample indices; n even. *)
(* Two samples per UI (the four-phase input stage at 62.5 MHz). The loop above has a false lock
   here (two stable points when edges straddle a sample), and the edge positions alone cannot
   say which sample is straddled. This variant is a slot tracker instead:
   - samples have absolute indices k; an edge between samples k-1 and k is "at k";
   - each edge gets the unique UI boundary index m with k - 2m in {R, R+1}: two slots hold the
     whole jitter cluster, including a straddle, so the assignment is unambiguous given R;
   - R follows the cluster: when the last [w] (64) edges all sat in the slot on the side the
     edges are drifting toward, R moves one step that way (w must be long: with a steady
     89/11 straddle, 6 majority edges in a row happen half the time and moved R wrongly);
   - a run of one sample is a one-UI pulse whose edges must go to consecutive boundaries; if
     both went to the same boundary the window is on the wrong pair of samples, and the last
     move is undone (or, if there was none, R moves against the drift);
   - the drift direction comes from idle, where every run is one UI: sum(run - 2) over idle
     telescopes to the net drift in samples, exactly (jitter excursions cancel);
   - R starts from the first [w] idle edges, whose residues k_i - 2i are known exactly;
   - UI m's level is the level after the last edge assigned to a boundary <= m, and UI m is
     final once samples up to 2(m+1) + R have been seen.
   Assumes the link starts in idle (it does: 100BASE-X sends /I/ whenever there is no frame). *)
module Osr2 = struct
  type t = {
    n : int; w : int;
    mutable k : int;                       (* absolute index of the next sample *)
    mutable last : int;                    (* last sample value *)
    mutable r : int; mutable started : bool; mutable init : int list;
    mutable m_next : int;                  (* next UI index to output *)
    mutable level : int;                   (* level after the last assigned edge *)
    mutable pending : (int * int) list;    (* (boundary index, level after) not yet output *)
    mutable side : int list;               (* slots (0/1) of the last w edges, newest first *)
    mutable drift : int; mutable drift_acc : int;
    mutable last_edge : int; mutable short_runs : int;
    mutable moves : int;
    mutable last_move : int;
    mutable prev_edge : int * int;         (* (k, boundary index) of the previous edge *)
    mutable undos : int;
    mutable pure : int;                    (* consecutive edges in the drift-side slot *)
  }
  let create ?(w = env "CDR2_W" 64) ~n () =
    { n; w; k = 0; last = 0; r = 0; started = false; init = []; m_next = 0; level = 0; pending = [];
      side = []; drift = 1; drift_acc = 0; last_edge = 0; short_runs = 0; moves = 0;
      last_move = 0; prev_edge = (-10, -10); undos = 0; pure = 0 }

  let step c (x : int array) =
    let out = ref [] in
    Array.iter (fun v ->
        let k = c.k in
        c.k <- c.k + 1;
        if v <> c.last then begin
          (* drift direction, learned in idle *)
          let run = k - c.last_edge in
          c.last_edge <- k;
          if run >= 1 && run <= 3 then begin
            if c.short_runs >= 12 then begin
              c.drift_acc <- max (-64) (min 64 (c.drift_acc + run - 2));
              if c.drift_acc <> 0 then c.drift <- (if c.drift_acc > 0 then 1 else -1)
            end;
            c.short_runs <- c.short_runs + 1
          end else c.short_runs <- 0;
          if not c.started then begin
            (* the first w edges are idle: edge i sits on boundary i *)
            c.init <- k :: c.init;
            if List.length c.init = c.w then begin
              let ks = List.rev c.init in
              let res = List.mapi (fun i kk -> kk - 2 * i) ks in
              c.r <- List.fold_left min max_int res;
              c.started <- true;
              c.m_next <- 0;
              List.iteri (fun i _ -> c.pending <- (i, 0) :: c.pending) ks;
              c.pending <- []; c.m_next <- c.w;   (* start output after the idle used for init *)
              c.level <- v
            end
          end else begin
            let m = (k - c.r) asr 1 in               (* floor((k - R) / 2) *)
            let slot = k - c.r - 2 * m in            (* 0 or 1 *)
            let pk, pm = c.prev_edge in
            if k - pk = 1 && m = pm then begin
              (* a one-sample pulse with both edges on one boundary: wrong window *)
              let mv = if c.last_move <> 0 then - c.last_move else - c.drift in
              c.r <- c.r + mv; c.last_move <- 0; c.undos <- c.undos + 1; c.pure <- 0;
              (* reassign this edge and the previous one under the corrected window *)
              let m' = (k - c.r) asr 1 and pm' = (pk - c.r) asr 1 in
              c.pending <- List.map (fun (mm, lv) -> if mm = pm && pk >= 0 then (pm', lv) else (mm, lv)) c.pending;
              c.pending <- (m', v) :: c.pending;
              c.prev_edge <- (k, m')
            end else begin
              c.pending <- (m, v) :: c.pending;
              c.prev_edge <- (k, m);
              let drift_side = if c.drift > 0 then 1 else 0 in
              if slot = drift_side then c.pure <- c.pure + 1 else c.pure <- 0;
              if c.pure >= c.w then begin
                c.r <- c.r + c.drift; c.last_move <- c.drift; c.moves <- c.moves + 1; c.pure <- 0
              end
            end
          end
        end;
        c.last <- v;
        (* output final UIs: UI m is final once samples up to 2(m+1) + R have been seen *)
        if c.started then
          while 2 * (c.m_next + 1) + c.r <= c.k - 1 do
            let pend = List.rev c.pending in
            let upto, rest = List.partition (fun (m, _) -> m <= c.m_next) pend in
            List.iter (fun (_, lv) -> c.level <- lv) upto;
            c.pending <- List.rev rest;
            out := c.level :: !out;
            c.m_next <- c.m_next + 1
          done) x;
    List.rev !out
end
