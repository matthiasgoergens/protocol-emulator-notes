(* upe_v1: the unified processing element as specified in notes/architecture-v0.md section 2.4,
   turned into a concrete encoding. Written from the note's prose, not from rtl/upe.v.

   Configuration: 8 bytes per PE on a byte-wide chain, b0 (least significant) .. b7.
   K = b1:b0. The 48-bit op word = b7..b2; op bit j is configuration bit 16 + j.

   op bits   field      values
   1:0       xsel       0 S, 1 A, 2 (S << 1) | sin, 3 (S >> 1) | sin << 15
   3:2       sinsel     0 g, 1 lane_in, 2 s15_in (left PE's S[15]), 3 A[0]
   5:4       ysel       0 K, 1 A, 2 S, 3 the constant 1
   7:6       ymod       0 none, 1 gate (g ? Y : 0), 2 negate when g, 3 negate
   10:8      gsel       0 one, 1 A[bit], 2 lane_in, 3 S[15] ^ lane_in, 4 CRC feedback
                        ((pairlo ? cb_in : S[15]) ^ A[0]), 5 F, 6 window, 7 g_in (left PE's g)
   14:11     bit        bit index for gsel = 1
   15        pairlo     CRC feedback from the right PE's S[15] (cb_in) instead of own S[15]
   18:16     alu        0 saturating add, 1 wrapping add, 2 max, 3 min, 4 XOR, 5 AND, 6 OR, 7 Y
   19        cin_lane   the adder's carry-in is lane_in (else it is the negation's +1)
   21:20     swb        S <- 0 hold, 1 result, 2 X, 3 (g ? result : hold)
   23:22     pwb        P <- 0 A, 1 result, 2 loser, 3 merge (g ? {A[15:8], K[7:0]} : A)
   25:24     fwb        F <- 0 hold, 1 g, 2 (result = 0), 3 hold
   27:26     lout       lane register <- 0 lane_in, 1 S'[15] (S after this step), 2 carry out, 3 g
   28        lane_bc    lane_in is the segment's broadcast bit (else the left neighbour's lane)
   29        del        valid out = A.valid and not g (deletion); else A.valid
   30        stream     step only when A is valid (else every clock the segment runs)
   31        tap_p      this PE's tap is P (else S); used where the PE ends a segment
   32        follow     step exactly when the left PE steps (PROPOSED addition, see README)
   47:33     unused

   The Y operand after its modifier is yn = n ? ~yv : yv (ones' complement), n the negation.
   The adder computes X + yn + c with c = cin_lane ? lane_in : n, so "negate" is exact
   subtraction and a chain of PEs with cin_lane does multi-word subtraction as well as
   addition. Saturating add clamps the exact signed sum to [-32768, 32767]. Max and min compare
   X and yn as signed numbers; the winner is the result and the other is the loser (ties: X
   wins). For non-comparison ops the loser output is X. The carry out is the unsigned carry of
   X + yn + c, whatever the op. The zero flag is result = 0.

   Window: d = (A[15:8] - K[15:8]) mod 256; window = d < 16 and S[15 - d].

   State per PE: S, P, Pv (P's valid), F, L (the lane register, which is the lane output), and
   the 64 configuration flops: 99 flops. *)

type op = {
  xsel : int;
  sinsel : int;
  ysel : int;
  ymod : int;
  gsel : int;
  bitsel : int;
  pairlo : bool;
  alu : int;
  cin_lane : bool;
  swb : int;
  pwb : int;
  fwb : int;
  lout : int;
  lane_bc : bool;
  del : bool;
  stream : bool;
  tap_p : bool;
  follow : bool;
  k : int;
}

let nop =
  { xsel = 0; sinsel = 0; ysel = 0; ymod = 0; gsel = 0; bitsel = 0; pairlo = false; alu = 0;
    cin_lane = false; swb = 0; pwb = 0; fwb = 0; lout = 0; lane_bc = false; del = false;
    stream = false; tap_p = false; follow = false; k = 0 }

let b2i b = if b then 1 else 0

let op_word o =
  o.xsel lor (o.sinsel lsl 2) lor (o.ysel lsl 4) lor (o.ymod lsl 6) lor (o.gsel lsl 8)
  lor (o.bitsel lsl 11) lor (b2i o.pairlo lsl 15) lor (o.alu lsl 16) lor (b2i o.cin_lane lsl 19)
  lor (o.swb lsl 20) lor (o.pwb lsl 22) lor (o.fwb lsl 24) lor (o.lout lsl 26)
  lor (b2i o.lane_bc lsl 28) lor (b2i o.del lsl 29) lor (b2i o.stream lsl 30)
  lor (b2i o.tap_p lsl 31) lor (b2i o.follow lsl 32)

let field w lo n = (w lsr lo) land ((1 lsl n) - 1)
let flag w b = (w lsr b) land 1 = 1

let decode_word w k =
  { xsel = field w 0 2; sinsel = field w 2 2; ysel = field w 4 2; ymod = field w 6 2;
    gsel = field w 8 3; bitsel = field w 11 4; pairlo = flag w 15; alu = field w 16 3;
    cin_lane = flag w 19; swb = field w 20 2; pwb = field w 22 2; fwb = field w 24 2;
    lout = field w 26 2; lane_bc = flag w 28; del = flag w 29; stream = flag w 30;
    tap_p = flag w 31; follow = flag w 32; k }

(* the 8 configuration bytes, b0 first *)
let bytes_of_op o =
  let w = op_word o in
  Array.init 8 (fun j -> if j < 2 then (o.k lsr (8 * j)) land 0xff else (w lsr (8 * (j - 2))) land 0xff)

let op_of_bytes b =
  let k = b.(0) lor (b.(1) lsl 8) in
  let w = ref 0 in
  for j = 7 downto 2 do w := (!w lsl 8) lor b.(j) done;
  decode_word !w k

(* ---- the array ----
   16 PEs in one chain, cut into segments of 2, 2, 4 and 8. Per segment: a feed register (two
   bytes; writing the high byte presents the word as valid for exactly one clock), a control
   register (bits 2:0 the first PE's source: 0 join (the previous segment's end; zero for
   segment 0), 1 loop (own segment's end), 2 feed, 3 fixed neighbour (an external port: a bank
   read port or the recovered-bit stream), 4-7 zero; bit 3 the broadcast lane bit; bit 4 run; bit 5 (PROPOSED) take the broadcast from the
   previous segment instead, so joined segments share one broadcast),
   a configuration chain and an init chain (both byte-wide, through the segment's PEs in
   order), and a tap (the end PE's S or P, its valid and its flag).
   The feed and control registers are written through the mailbox byte path: sel 0 feed low
   byte, 1 feed high byte (marks valid), 2 control.
   Pair wires run along the physical chain regardless of segments: s15_in, g_in and the left
   PE's step from PE i-1, cb_in from PE i+1 (zero off the ends). At a segment start the lane
   from the left is the source's lane: join and loop give that end PE's lane register, feed
   gives the broadcast bit, fixed and zero give 0. *)

let n_pe = 16
let seg_start = [| 0; 2; 4; 8 |]
let seg_end = [| 1; 3; 7; 15 |]
let seg_of i = if i < 2 then 0 else if i < 4 then 1 else if i < 8 then 2 else 3

type inputs = {
  mbx_wr : bool;
  mbx_seg : int;
  mbx_sel : int;
  mbx_byte : int;
  cfg_wr : bool;
  cfg_seg : int;
  cfg_byte : int;
  init_wr : bool;
  init_seg : int;
  init_byte : int;
  fixed_d : int array; (* 4 *)
  fixed_v : bool array; (* 4 *)
}

let idle =
  { mbx_wr = false; mbx_seg = 0; mbx_sel = 0; mbx_byte = 0; cfg_wr = false; cfg_seg = 0;
    cfg_byte = 0; init_wr = false; init_seg = 0; init_byte = 0; fixed_d = Array.make 4 0;
    fixed_v = Array.make 4 false }

(* Everything that is state, for lockstep comparison. *)
type pe_state = { s : int; p : int; pv : bool; f : bool; l : bool; cfg : int array }
type seg_state = { flo : int; fhi : int; fv : bool; ctrl : int }
type tap = { td : int; tv : bool; tf : bool }
type state = { pes : pe_state array; segs : seg_state array; taps : tap array }

let pe_state_to_string (x : pe_state) =
  Printf.sprintf "S=%04x P=%04x Pv=%b F=%b L=%b cfg=%s" x.s x.p x.pv x.f x.l
    (String.concat "" (List.rev_map (Printf.sprintf "%02x") (Array.to_list x.cfg)))

(* differences between two states, as readable strings *)
let diff (a : state) (b : state) =
  let out = ref [] in
  Array.iteri
    (fun i (x : pe_state) ->
      let y = b.pes.(i) in
      if x <> y then
        out := Printf.sprintf "PE%d: %s | %s" i (pe_state_to_string x) (pe_state_to_string y) :: !out)
    a.pes;
  Array.iteri
    (fun j (x : seg_state) ->
      let y = b.segs.(j) in
      if x <> y then
        out := Printf.sprintf "seg%d: flo %02x/%02x fhi %02x/%02x fv %b/%b ctrl %02x/%02x" j x.flo y.flo
                 x.fhi y.fhi x.fv y.fv x.ctrl y.ctrl :: !out)
    a.segs;
  Array.iteri
    (fun j (x : tap) ->
      let y = b.taps.(j) in
      if x <> y then
        out := Printf.sprintf "tap%d: %04x/%04x v %b/%b f %b/%b" j x.td y.td x.tv y.tv x.tf y.tf :: !out)
    a.taps;
  List.rev !out

(* The simulators share this interface: apply one clock's inputs, then read the state. *)
module type SIM = sig
  type t
  val create : unit -> t
  val cycle : t -> inputs -> unit
  val state : t -> state
end
