(** Independent DVI 1.0 TMDS reference model and decoder (stdlib only).
    Written from the DVI 1.0 specification (sections 3.2, 3.3, Figures 3-5 and 3-6),
    a copy of which was downloaded to spec/dvi.pdf (see NOTES.txt). *)

(** 10-bit TMDS words are ints 0..1023; bit 0 is the first bit transmitted (q_out[0]). *)
type symbol =
  | Data of int                          (** decoded 8-bit value, 0..255 *)
  | Control of { c0 : bool; c1 : bool }  (** one of the four control codes *)
  | Invalid of int                       (** neither (raw word) *)

val decode : int -> symbol
(** Decoder per Figure 3-6.  Every word that is not one of the four control
    codes is decoded as data (the spec's decoder does this); so [decode] never
    returns [Invalid].  Use [decode_strict] to get [Invalid] for words the
    encoder can never produce. *)

val decode_strict : int -> symbol
(** Like [decode], but returns [Invalid w] when [is_valid_data w] is false and
    [w] is not a control code. *)

val is_valid_data : int -> bool
(** True iff some (8-bit value, reachable running disparity) pair makes the spec
    encoder emit this word. *)

val control_word : c0:bool -> c1:bool -> int
(** The control code from the spec's table (Figure 3-5). *)

val ones_minus_zeros : int -> int
(** Disparity of a 10-bit word: number of ones minus number of zeros. *)

(** The spec's encoder, written straight from the flowchart (Figure 3-5). *)
module Ref_encoder : sig
  type t
  val create : unit -> t           (* cnt = 0 *)
  val cnt : t -> int               (* running disparity counter as in the spec *)
  val set_cnt : t -> int -> unit
  val data : t -> int -> int       (* encode an 8-bit value, updating cnt *)
  val control : t -> c0:bool -> c1:bool -> int  (* emit control code; spec resets cnt to 0 *)
end

val find_alignment : bool array -> int option
(** Offset 0..9 at which 10-bit word boundaries lie, found by requiring a run of
    at least 8 consecutive control-code words at that offset, and exactly one
    such offset. *)

val words_of_bits : bool array -> offset:int -> int array
(** Cut a serial stream (index 0 first in time) into words starting at [offset];
    a trailing partial word is dropped. *)

type frame = { width : int; height : int; rgb : (int * int * int) array (* row-major *) }

val frames_of_lanes : blue:symbol array -> green:symbol array -> red:symbol array -> frame list
(** Rebuild the complete frames (between two VSYNC active edges) from three
    word-aligned lanes.  Raises [Failure] (with the cycle index) if the lanes
    disagree on data enable, an [Invalid] symbol is seen, or line widths differ.
    The pixel triple is (r, g, b). *)

type timing = {
  h_active : int; h_front : int; h_sync : int; h_back : int; h_total : int;
  v_active : int; v_front : int; v_sync : int; v_back : int; v_total : int;
  hsync_active_high : bool; vsync_active_high : bool;
}

val measure_timing :
  blue:symbol array -> green:symbol array -> red:symbol array -> timing
(** Timing measured from the stream alone (horizontal in pixel clocks,
    vertical in lines).  Raises [Failure] when the stream is inconsistent. *)
