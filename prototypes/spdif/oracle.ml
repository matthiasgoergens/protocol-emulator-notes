(* An independent S/PDIF decoder, written from the IEC 60958 / AES3 rules alone. It shares no code
   with iec60958.ml (the reference encoder) or rx.ml (the chip's receive path), and works
   differently from both: it reads the time between consecutive edges, classifies each interval as
   1, 2 or 3 UI against a tracked UI estimate, and parses that sequence.

   Rules used (AES3-1992 2.3, 2.4): in biphase mark each data symbol is either one 2-UI interval
   (a 0) or two 1-UI intervals (a 1); a 3-UI interval occurs only in a preamble. Edge positions
   in a preamble, from its first edge: X 0,3,6,7,8 / Y 0,3,5,6,8 / Z 0,3,4,5,8 (the 8 is the
   first symbol's leading edge), so the intervals are X 3,3,1,1 / Y 3,2,1,2 / Z 3,1,1,3, whatever
   the polarity. 28 symbols (slots 4..31) follow; slots 4..31 must hold an even number of ones.
   Frames are X or Z then Y; Z marks frame 0 of a 192-frame block; channel status is slot 30. *)

type pre = X | Y | Z

type sub = { pre : pre; bits : int array (* slots 4..31, index 0 = slot 4 *); parity_ok : bool; t : float }

type result = {
  subs : sub list;
  violations : int;          (* intervals of an impossible length, or symbols that are neither 0 nor 1 *)
  bad_preambles : int;       (* a 3-UI interval not followed by a valid preamble pattern *)
  ui_ns : float;             (* final UI estimate *)
  blocks : (int array * int array) list;  (* channel status of complete blocks (left, right) *)
  frame_errors : int;        (* subframe order not X/Z then Y *)
  viol_at : float list;      (* edge times where violations were found *)
}

let decode (edges : float array) =
  let n = Array.length edges in
  if n < 100 then { subs = []; violations = 0; bad_preambles = 0; ui_ns = 0.; blocks = []; frame_errors = 0; viol_at = [] } else begin
    let iv = Array.init (n - 1) (fun i -> edges.(i + 1) -. edges.(i)) in
    (* initial UI: the median of the intervals within 30 % of the shortest among the first 300 *)
    let first = Array.sub iv 0 (min 300 (Array.length iv)) in
    let mn = Array.fold_left Float.min infinity first in
    let short = List.filter (fun d -> d < 1.3 *. mn) (Array.to_list first) |> List.sort compare in
    let ui = ref (List.nth short (List.length short / 2)) in
    let cls = Array.make (Array.length iv) 0 in
    Array.iteri (fun i d ->
        let k = Float.round (d /. !ui) in
        let k = int_of_float k in
        cls.(i) <- (if k >= 1 && k <= 3 && Float.abs ((d /. float k) -. !ui) < 0.3 *. !ui then k else 0);
        if cls.(i) > 0 then ui := !ui +. (0.01 *. ((d /. float cls.(i)) -. !ui))) iv;
    let vat = ref [] in
    let viol = ref 0 and badp = ref 0 and subs = ref [] in
    let m = Array.length cls in
    let i = ref 0 in
    (* find the first 3 *)
    while !i < m && cls.(!i) <> 3 do incr i done;
    while !i + 3 < m do
      if cls.(!i) <> 3 then begin incr viol; vat := edges.(!i) :: !vat; incr i; while !i < m && cls.(!i) <> 3 do incr i done end
      else begin
        let p = match cls.(!i + 1), cls.(!i + 2), cls.(!i + 3) with
          | 3, 1, 1 -> Some X | 2, 1, 2 -> Some Y | 1, 1, 3 -> Some Z | _ -> None in
        match p with
        | None -> incr badp; incr i; while !i < m && cls.(!i) <> 3 do incr i done
        | Some pre ->
          let t = edges.(!i) in
          i := !i + 4;
          let bits = Array.make 28 0 and ok = ref true and k = ref 0 in
          while !ok && !k < 28 do
            if !i >= m then ok := false
            else if cls.(!i) = 2 then (bits.(!k) <- 0; incr k; incr i)
            else if cls.(!i) = 1 && !i + 1 < m && cls.(!i + 1) = 1 then (bits.(!k) <- 1; incr k; i := !i + 2)
            else ok := false
          done;
          if !ok then begin
            let ones = Array.fold_left ( + ) 0 bits in
            subs := { pre; bits; parity_ok = ones mod 2 = 0; t } :: !subs
          end else if !i < m - 1 then begin   (* a symbol cut off by the end of the capture is not a violation *)
            incr viol; vat := edges.(!i) :: !vat; while !i < m && cls.(!i) <> 3 do incr i done
          end
      end
    done;
    let subs = List.rev !subs in
    (* frames and channel-status blocks *)
    let fe = ref 0 and blocks = ref [] in
    let cl = Array.make 192 0 and cr = Array.make 192 0 in
    let frame = ref (-1) and in_block = ref false and last = ref Y in
    List.iter (fun s ->
        (match s.pre, !last with
         | (X | Z), Y | Y, (X | Z) -> ()
         | _ -> incr fe);
        last := s.pre;
        let c = s.bits.(26) in
        match s.pre with
        | Z ->
          if !in_block && !frame = 191 then blocks := (Array.copy cl, Array.copy cr) :: !blocks;
          in_block := true; frame := 0; cl.(0) <- c
        | X -> if !in_block then begin incr frame; if !frame < 192 then cl.(!frame) <- c else in_block := false end
        | Y -> if !in_block && !frame < 192 then cr.(!frame) <- c) subs;
    { subs; violations = !viol; bad_preambles = !badp; ui_ns = !ui; blocks = List.rev !blocks; frame_errors = !fe; viol_at = List.rev !vat }
  end

let pre_name = function X -> "M" | Y -> "W" | Z -> "B"

(* audio as a 24-bit two's-complement value: slots 4..27, LSB first *)
let audio24 s = let v = ref 0 in for k = 23 downto 0 do v := (!v lsl 1) lor s.bits.(k) done; !v
let slots s = let v = ref 0 in Array.iteri (fun k b -> v := !v lor (b lsl (k + 4))) s.bits; !v
