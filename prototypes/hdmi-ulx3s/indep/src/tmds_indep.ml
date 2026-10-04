(* Independent TMDS reference model.
   Source: Digital Visual Interface (DVI) Revision 1.0, 2 April 1999, DDWG,
   section 3.2.2 (encode algorithm, Figure 3-5, Table 3-1), 3.2.3
   (serialisation: q_out[0] is transmitted first), 3.3.3 (decode algorithm,
   Figure 3-6).  The PDF was downloaded; see NOTES.txt for URL and sha256.
   Nothing here was copied from any other TMDS implementation.

   Bit convention: a 10-bit word is an int whose bit i is q_out[i]. *)

type symbol =
  | Data of int
  | Control of { c0 : bool; c1 : bool }
  | Invalid of int

let bit w i = (w lsr i) land 1

let popcount x =
  let rec go x acc = if x = 0 then acc else go (x lsr 1) (acc + (x land 1)) in
  go x 0

let ones_minus_zeros w = (2 * popcount (w land 0x3ff)) - 10

(* ---- Control codes (Figure 3-5, "case (C1, C0)") ------------------------
   The spec writes them as q_out[0:9] = <string>, i.e. the LEFT character of
   the string is q_out[0], the first bit on the wire. *)
let word_of_spec_string s =
  let w = ref 0 in
  String.iteri (fun i ch -> if ch = '1' then w := !w lor (1 lsl i)) s;
  !w

let control_word ~c0 ~c1 =
  word_of_spec_string
    (match (c1, c0) with
     | false, false -> "0010101011"   (* C1,C0 = 00 *)
     | false, true -> "1101010100"    (* 01 *)
     | true, false -> "0010101010"    (* 10 *)
     | true, true -> "1101010101")    (* 11 *)

let control_of_word w =
  let r = ref None in
  List.iter
    (fun (c0, c1) -> if control_word ~c0 ~c1 = w then r := Some (c0, c1))
    [ (false, false); (true, false); (false, true); (true, true) ];
  !r

(* ---- Decoder (Figure 3-6) ---------------------------------------------- *)
let decode_data w =
  (* D[9] = 1: the data bits were inverted; undo that. *)
  let d = if bit w 9 = 1 then (lnot w) land 0xff else w land 0xff in
  (* D[8] = 1: XOR was used; D[8] = 0: XNOR was used. *)
  let xor_used = bit w 8 = 1 in
  let q = ref (d land 1) in
  for i = 1 to 7 do
    let x = bit d i lxor bit d (i - 1) in
    let v = if xor_used then x else 1 - x in
    q := !q lor (v lsl i)
  done;
  !q

let decode w =
  let w = w land 0x3ff in
  match control_of_word w with
  | Some (c0, c1) -> Control { c0; c1 }
  | None -> Data (decode_data w)

(* ---- Encoder (Figure 3-5) ---------------------------------------------- *)
module Ref_encoder = struct
  type t = { mutable cnt : int }

  let create () = { cnt = 0 }
  let cnt t = t.cnt
  let set_cnt t v = t.cnt <- v

  let data t d =
    let d = d land 0xff in
    (* Stage 1: transition minimisation. *)
    let n1d = popcount d in
    let use_xnor = n1d > 4 || (n1d = 4 && bit d 0 = 0) in
    let qm = ref (d land 1) in
    for i = 1 to 7 do
      let x = bit !qm (i - 1) lxor bit d i in
      qm := !qm lor ((if use_xnor then 1 - x else x) lsl i)
    done;
    let qm = !qm in
    let q_m8 = if use_xnor then 0 else 1 in
    let n1 = popcount qm in
    let n0 = 8 - n1 in
    let inv = lnot qm land 0xff in
    (* Stage 2: DC balance. *)
    if t.cnt = 0 || n1 = n0 then begin
      let q9 = 1 - q_m8 in
      let lo = if q_m8 = 1 then qm else inv in
      if q_m8 = 0 then t.cnt <- t.cnt + (n0 - n1)
      else t.cnt <- t.cnt + (n1 - n0);
      lo lor (q_m8 lsl 8) lor (q9 lsl 9)
    end
    else if (t.cnt > 0 && n1 > n0) || (t.cnt < 0 && n0 > n1) then begin
      t.cnt <- t.cnt + (2 * q_m8) + (n0 - n1);
      inv lor (q_m8 lsl 8) lor (1 lsl 9)
    end
    else begin
      t.cnt <- t.cnt - (2 * (1 - q_m8)) + (n1 - n0);
      qm lor (q_m8 lsl 8)
    end

  let control t ~c0 ~c1 =
    t.cnt <- 0;
    control_word ~c0 ~c1
end

(* ---- Valid data words --------------------------------------------------
   cnt only ever changes by even amounts (2*q_m[8] and N1-N0 of an 8-bit
   value are even) and starts at 0, so the reachable states are found by
   closure over all 256 inputs. *)
let reachable_cnts =
  let seen = Hashtbl.create 16 in
  let rec go c =
    if not (Hashtbl.mem seen c) then begin
      Hashtbl.add seen c ();
      for d = 0 to 255 do
        let e = Ref_encoder.create () in
        Ref_encoder.set_cnt e c;
        ignore (Ref_encoder.data e d);
        go (Ref_encoder.cnt e)
      done
    end
  in
  go 0;
  List.sort compare (Hashtbl.fold (fun c () acc -> c :: acc) seen [])

let valid_table =
  let a = Array.make 1024 false in
  List.iter
    (fun c ->
      for d = 0 to 255 do
        let e = Ref_encoder.create () in
        Ref_encoder.set_cnt e c;
        a.(Ref_encoder.data e d) <- true
      done)
    reachable_cnts;
  a

let is_valid_data w = w >= 0 && w < 1024 && valid_table.(w)

let decode_strict w =
  match decode w with
  | Data _ when not (is_valid_data w) -> Invalid w
  | s -> s

(* ---- Serial alignment -------------------------------------------------- *)
let words_of_bits bits ~offset =
  let n = (Array.length bits - offset) / 10 in
  let n = max n 0 in
  Array.init n (fun i ->
      let w = ref 0 in
      for j = 0 to 9 do
        if bits.(offset + (10 * i) + j) then w := !w lor (1 lsl j)
      done;
      !w)

let min_control_run = 8

let find_alignment bits =
  let longest_run offset =
    let words = words_of_bits bits ~offset in
    let best = ref 0 and cur = ref 0 in
    Array.iter
      (fun w ->
        if control_of_word w <> None then begin
          incr cur;
          if !cur > !best then best := !cur
        end
        else cur := 0)
      words;
    !best
  in
  let cands = List.filter (fun o -> longest_run o >= min_control_run) (List.init 10 Fun.id) in
  match cands with [ o ] -> Some o | _ -> None

(* ---- Frames and timing -------------------------------------------------- *)
type frame = { width : int; height : int; rgb : (int * int * int) array }

let lane_name = [| "blue"; "green"; "red" |]

(* Data enable: DVI defines it as "data symbols on the lanes" (section 3.2.1
   channel map); all three lanes must agree on every cycle. *)
let data_enable ~blue ~green ~red =
  let n = Array.length blue in
  if Array.length green <> n || Array.length red <> n then
    failwith "lane length mismatch";
  let is_data lane i s =
    match s with
    | Data _ -> true
    | Control _ -> false
    | Invalid w ->
      failwith (Printf.sprintf "invalid word 0x%03x on %s lane at cycle %d" w lane_name.(lane) i)
  in
  Array.init n (fun i ->
      let b = is_data 0 i blue.(i) and g = is_data 1 i green.(i) and r = is_data 2 i red.(i) in
      if b <> g || g <> r then
        failwith (Printf.sprintf "data enable disagrees between lanes at cycle %d" i);
      b)

(* HSYNC = c0, VSYNC = c1 of the blue lane's control codes (blanking only).
   During data cycles the last blanking value is held (back-filled before the
   first blanking cycle) so the sync waveform is defined for every cycle.
   The active level is the minority level of that waveform. *)
let held_sync ~blue ~de pick =
  let n = Array.length blue in
  let first = ref None in
  Array.iteri
    (fun i s ->
      match (s, !first) with
      | Control { c0; c1 }, None -> first := Some (pick c0 c1); ignore i
      | _ -> ())
    blue;
  let init = match !first with Some v -> v | None -> failwith "no blanking cycles in stream" in
  let cur = ref init in
  Array.init n (fun i ->
      (match blue.(i) with
       | Control { c0; c1 } when not de.(i) -> cur := pick c0 c1
       | _ -> ());
      !cur)

let active_levels waveform what =
  let hi = Array.fold_left (fun a b -> if b then a + 1 else a) 0 waveform in
  let lo = Array.length waveform - hi in
  if hi = lo then failwith (what ^ ": cannot decide polarity (50% duty)");
  let active_high = hi < lo in
  (active_high, Array.map (fun b -> b = active_high) waveform)

let sync_activity ~blue ~de =
  let hs = held_sync ~blue ~de (fun c0 _ -> c0) in
  let vs = held_sync ~blue ~de (fun _ c1 -> c1) in
  let hpol, ha = active_levels hs "hsync" in
  let vpol, va = active_levels vs "vsync" in
  (hpol, ha, vpol, va)

(* Maximal runs [start, length] where [p i] holds. *)
let runs n p =
  let acc = ref [] and start = ref (-1) in
  for i = 0 to n - 1 do
    if p i then (if !start < 0 then start := i)
    else if !start >= 0 then (acc := (!start, i - !start) :: !acc; start := -1)
  done;
  if !start >= 0 then acc := (!start, n - !start) :: !acc;
  List.rev !acc

let rising_edges a =
  let acc = ref [] in
  for i = 1 to Array.length a - 1 do
    if a.(i) && not a.(i - 1) then acc := i :: !acc
  done;
  List.rev !acc

let value_of = function Data v -> v | _ -> failwith "internal: not data"

let frames_of_lanes ~blue ~green ~red =
  let n = Array.length blue in
  let de = data_enable ~blue ~green ~red in
  let _, _, _, va = sync_activity ~blue ~de in
  let edges = Array.of_list (rising_edges va) in
  let lines = runs n (fun i -> de.(i)) in
  let frames = ref [] in
  for k = 0 to Array.length edges - 2 do
    let lo = edges.(k) and hi = edges.(k + 1) in
    let ls = List.filter (fun (s, _) -> s >= lo && s < hi) lines in
    match ls with
    | [] -> failwith (Printf.sprintf "no data lines between vsync edges %d and %d" lo hi)
    | (s0, w) :: _ ->
      List.iter
        (fun (s, l) ->
          if l <> w then
            failwith (Printf.sprintf "line at cycle %d has width %d, expected %d" s l w))
        ls;
      let pix =
        List.concat_map
          (fun (s, l) ->
            List.init l (fun x ->
                let i = s + x in
                (value_of red.(i), value_of green.(i), value_of blue.(i))))
          ls
      in
      ignore s0;
      frames := { width = w; height = List.length ls; rgb = Array.of_list pix } :: !frames
  done;
  List.rev !frames

type timing = {
  h_active : int; h_front : int; h_sync : int; h_back : int; h_total : int;
  v_active : int; v_front : int; v_sync : int; v_back : int; v_total : int;
  hsync_active_high : bool; vsync_active_high : bool;
}

(* All elements of a non-empty list equal, else fail with [what]. *)
let the_same what = function
  | [] -> failwith (what ^ ": no measurements")
  | x :: rest ->
    List.iter (fun y -> if y <> x then failwith (Printf.sprintf "%s inconsistent (%d vs %d)" what x y)) rest;
    x

let measure_timing ~blue ~green ~red =
  let n = Array.length blue in
  let de = data_enable ~blue ~green ~red in
  let hpol, ha, vpol, va = sync_activity ~blue ~de in
  (* Horizontal. *)
  let hedges = rising_edges ha in
  let pitches =
    let rec d = function a :: (b :: _ as r) -> (b - a) :: d r | _ -> [] in
    d hedges
  in
  let h_total = the_same "hsync period" pitches in
  let hpulses = List.filter (fun (s, l) -> s > 0 && s + l < n) (runs n (fun i -> ha.(i))) in
  let h_sync = the_same "hsync width" (List.map snd hpulses) in
  let dl = runs n (fun i -> de.(i)) in
  (* Ignore a first/last run cut by the stream boundary. *)
  let dl_full = List.filter (fun (s, l) -> s > 0 && s + l < n) dl in
  let h_active = the_same "active width" (List.map snd dl_full) in
  let next_edge_after t = List.find_opt (fun e -> e >= t) hedges in
  let h_front =
    the_same "horizontal front porch"
      (List.filter_map (fun (s, l) -> Option.map (fun e -> e - (s + l)) (next_edge_after (s + l))) dl_full)
  in
  let h_back =
    let starts = List.map fst dl in
    the_same "horizontal back porch"
      (List.filter_map
         (fun (s, l) ->
           if List.mem (s + h_total) starts then
             Option.map (fun e -> s + h_total - (e + h_sync)) (next_edge_after (s + l))
           else None)
         dl_full)
  in
  (* Vertical.  Line grid: one line every [h_total] cycles, anchored at the
     first data run.  A line has data if the cycle at column 0 is data; its
     VSYNC is sampled at column [h_active] (start of the front porch). *)
  let s0 = fst (List.hd dl) in
  let first_k = - (s0 / h_total) in
  let lines = ref [] in
  let k = ref first_k in
  while s0 + (!k * h_total) + h_active < n do
    let t = s0 + (!k * h_total) in
    if t >= 0 then begin
      if de.(t + h_active) then failwith (Printf.sprintf "data inside porch at cycle %d" (t + h_active));
      lines := (de.(t), va.(t + h_active)) :: !lines
    end;
    incr k
  done;
  let lines = Array.of_list (List.rev !lines) in
  let nl = Array.length lines in
  let vedges = ref [] in
  for i = 1 to nl - 1 do
    if snd lines.(i) && not (snd lines.(i - 1)) then vedges := i :: !vedges
  done;
  let a, b =
    match List.rev !vedges with
    | a :: b :: _ -> (a, b)
    | _ -> failwith "fewer than two vsync edges: cannot measure vertical timing"
  in
  let v_total = b - a in
  let pos = ref a in
  let count p =
    let c = ref 0 in
    while !pos < b && p lines.(!pos) do incr c; incr pos done;
    !c
  in
  let v_sync = count (fun (d, v) -> v && not d) in
  let v_back = count (fun (d, v) -> (not v) && not d) in
  let v_active = count (fun (d, v) -> d && not v) in
  let v_front = count (fun (d, v) -> (not v) && not d) in
  if !pos <> b then failwith "vertical structure is not sync/back/active/front";
  { h_active; h_front; h_sync; h_back; h_total; v_active; v_front; v_sync; v_back; v_total;
    hsync_active_high = hpol; vsync_active_high = vpol }
