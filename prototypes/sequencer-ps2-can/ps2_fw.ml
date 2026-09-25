(* PS/2 firmware for the deadline sequencer, both roles, generated.

   Uses only base-ISA instructions (Asm.uses_only_base checks this); what it needs from the
   variant is programme space: each role is about 100 words, against 64 in the base core.

   Lines are open collector: a line is pulled low with SETP value 0 oe 1 (or SHO od) and released
   with oe 0; the pull-up (in the bench's wire model, with a finite rise time) makes it high. The
   firmware reads the lines through pin_in, which is the pad, so it sees what the wire does.

   Odd parity is computed in firmware without an ALU: the bit loop exists in two copies, "even so
   far" (E) and "odd so far" (O), and every data bit that reads back as 1 jumps across to the same
   point of the other copy. The pc is the parity register.

   Every event is reported to the host as two OUT bytes: a value, then a kind:
     1 byte received, parity good      2 byte received, parity bad      3 framing error
     4 device: transmission aborted (host inhibited)                    5 device: byte sent
     6 host: receive timeout           7 host: command sent and acknowledged
     8 host: no acknowledge            9 host: device did not clock *)

open Sim.Asm

type pins = { clk : int; data : int; req : int }   (* req: doorbell from the host side *)

type timing = {
  spu : int;          (* slots per microsecond *)
  half_us : float;    (* device clock half period *)
  setup_us : float;   (* device: data change to clock fall *)
  sample_us : float;  (* device: clock release to sampling the host's data *)
}

let default_timing ~spu = { spu; half_us = 40.; setup_us = 20.; sample_us = 10. }

let slots t us = int_of_float (Float.round (us *. float_of_int t.spu))
let kind k = [ W (Isa_v.out ()); W (Isa_v.lda k); W (Isa_v.out ()) ]
let kind0 k = [ W (Isa_v.lda 0); W (Isa_v.out ()); W (Isa_v.lda k); W (Isa_v.out ()) ]

(* control knobs, for the controls that must fail *)
type faults = { even_parity : bool; no_inhibit_check : bool }
let no_faults = { even_parity = false; no_inhibit_check = false }

(* Device role (keyboard): generates the clock, sends bytes the host side supplies, receives commands. *)
let device ?(faults = no_faults) (p : pins) (t : timing) =
  let m x = 1 lsl x in
  let low x = W (Isa_v.setp ~mask:(m x) ~value:0 ~oe:1) and rel x = W (Isa_v.setp ~mask:(m x) ~value:0 ~oe:0) in
  let h = slots t t.half_us and su = slots t t.setup_us and sa = slots t t.sample_us in
  let pulse = [ low p.clk ] @ delay (h - 1) @ [ rel p.clk ] in           (* clock low for h slots *)
  let check = if faults.no_inhibit_check then [ W Isa_v.nop ] else [ waitp ~pin:p.clk ~value:1 "txab" ] in
  (* one transmitted bit, data already set: setup, inhibit check, pulse, rest of the high phase *)
  let tx_tail = check @ pulse @ delay (h - su - 2) in
  let rx_bit e o =
    (* E copy: clock pulse, sample while high, parity branch *)
    [ L e ] @ pulse @ delay (sa - 1) @ [ W (Isa_v.shi ~pin:p.data ~msb:0 ()); waitp ~pin:p.data ~value:0 (o ^ "_c") ]
    @ [ L (e ^ "_c") ] @ delay (h - sa - 4) @ [ jnz e; jmp (e ^ "_p") ] in
  let tx_bit e o =
    [ L e; W (Isa_v.sho ~od:1 ~pin:p.data ~msb:0 ()) ] @ delay (su - 2)
    @ [ waitp ~pin:p.data ~value:0 (o ^ "_c"); L (e ^ "_c") ] @ tx_tail @ [ jnz e; jmp (e ^ "_p") ] in
  let par_ok_e, par_ok_o = if faults.even_parity then 0, 1 else 1, 0 in
  let items =
    [ W (Isa_v.setp ~mask:(m p.clk lor m p.data) ~value:0 ~oe:0);
      L "idle"; waitp ~pin:p.data ~value:1 "rts"; waitp ~pin:p.req ~value:0 "tx"; jmp "idle";
      (* host request to send: data low while the clock is released *)
      (* the condition must persist: a line just released is still low for its rise time *)
      L "rts"; waitp ~pin:p.clk ~value:1 "idle" ] @ delay (slots t 10.)
    @ [ waitp ~pin:p.data ~value:0 "idle"; waitp ~pin:p.clk ~value:1 "idle" ] @ delay (slots t 40.) @ [ W (Isa_v.ldc 8) ]
    @ rx_bit "rxE" "rxO" @ rx_bit "rxO" "rxE"
    @ [ L "rxE_p" ] @ pulse @ delay (sa - 1) @ [ waitp ~pin:p.data ~value:par_ok_e "rxperr"; jmp "rxok" ]
    @ [ L "rxO_p" ] @ pulse @ delay (sa - 1) @ [ waitp ~pin:p.data ~value:par_ok_o "rxperr"; jmp "rxok" ]
    @ [ L "rxok" ] @ kind 1 @ [ jmp "rxstop" ]
    @ [ L "rxperr" ] @ kind 2
    @ [ L "rxstop" ] @ delay (h - sa - 8) @ pulse @ delay (sa - 1) @ [ waitp ~pin:p.data ~value:1 "rxferr" ]
    (* acknowledge: data low, eleventh clock, release *)
    @ [ low p.data ] @ delay (h - sa - 1) @ pulse @ delay (sa - 1) @ [ rel p.data; jmp "idle" ]
    @ [ L "rxferr" ] @ kind 3 @ [ L "rxferr_w"; waitp ~pin:p.data ~value:1 "rxferr_w"; jmp "idle" ]
    (* transmit: the clock must stay released for 50 us, else the host is inhibiting *)
    @ [ L "tx"; W (Isa_v.ldd (slots t 50.)); waitp ~pin:p.clk ~value:0 "txgo"; W (Isa_v.ldd 0); jmp "idle";
        (* a pending request to send from the host wins over our byte *)
        L "txgo"; waitp ~pin:p.data ~value:1 "idle"; W Isa_v.in_; low p.data ] @ delay (su - 1) @ tx_tail @ [ W (Isa_v.ldc 8) ]
    @ tx_bit "txE" "txO" @ tx_bit "txO" "txE"
    @ [ L "txE_p"; (if par_ok_e = 1 then rel p.data else low p.data); jmp "txp" ]
    @ [ L "txO_p"; (if par_ok_o = 1 then rel p.data else low p.data); jmp "txp" ]
    @ [ L "txp" ] @ delay (su - 2) @ tx_tail
    @ [ rel p.data ] @ delay (su - 1) @ tx_tail
    @ kind0 5 @ [ jmp "idle" ]
    @ [ L "txab"; W (Isa_v.setp ~mask:(m p.clk lor m p.data) ~value:0 ~oe:0) ] @ kind0 4 @ [ jmp "idle" ] in
  assemble ~name:"ps2 device" items

(* Host role: receives device frames on falling clock edges, sends commands by inhibit and request
   to send. Timeouts use the deadline register (at most 4095 slots per wait). *)
let host ?(faults = no_faults) (p : pins) (t : timing) =
  let m x = 1 lsl x in
  let low x = W (Isa_v.setp ~mask:(m x) ~value:0 ~oe:1) and rel x = W (Isa_v.setp ~mask:(m x) ~value:0 ~oe:0) in
  let tmo = min 4095 (slots t 250.) in
  let wait_clk v fail = [ W (Isa_v.ldd tmo); waitp ~pin:p.clk ~value:v fail ] in
  let rx_bit e o =
    [ L e ] @ wait_clk 1 "hto" @ wait_clk 0 "hto"
    @ [ W (Isa_v.shi ~pin:p.data ~msb:0 ()) ] @ br ~pin:p.data ~value:0 (o ^ "_c") @ [ L (e ^ "_c"); jnz e; jmp (e ^ "_p") ] in
  let tx_bit e o =
    [ L e ] @ wait_clk 0 "htto"
    @ [ L (e ^ "_s"); W (Isa_v.sho ~od:1 ~pin:p.data ~msb:0 ()) ] @ wait_clk 1 "htto"
    @ br ~pin:p.data ~value:0 (o ^ "_c") @ [ L (e ^ "_c"); jnz e; jmp (e ^ "_p") ] in
  let par_ok_e, par_ok_o = if faults.even_parity then 0, 1 else 1, 0 in
  let items =
    [ W (Isa_v.setp ~mask:(m p.clk lor m p.data) ~value:0 ~oe:0);
      L "hidle"; waitp ~pin:p.clk ~value:1 "hrx"; waitp ~pin:p.req ~value:0 "htx"; jmp "hidle";
      (* first falling edge: the start bit is on the data line *)
      L "hrx" ] @ delay (slots t 5.) @ [ waitp ~pin:p.clk ~value:0 "hidle";   (* not a release still rising *)
      waitp ~pin:p.data ~value:0 "hferr"; W (Isa_v.ldc 8) ]
    @ rx_bit "hE" "hO" @ rx_bit "hO" "hE"
    @ [ L "hE_p" ] @ wait_clk 1 "hto" @ wait_clk 0 "hto" @ br ~pin:p.data ~value:par_ok_e "hperr" @ [ jmp "hok" ]
    @ [ L "hO_p" ] @ wait_clk 1 "hto" @ wait_clk 0 "hto" @ br ~pin:p.data ~value:par_ok_o "hperr" @ [ jmp "hok" ]
    @ [ L "hok" ] @ kind 1 @ [ jmp "hstop" ]
    @ [ L "hperr" ] @ kind 2
    @ [ L "hstop" ] @ wait_clk 1 "hto" @ wait_clk 0 "hto" @ br ~pin:p.data ~value:1 "hferr"
    @ wait_clk 1 "hto" @ [ W (Isa_v.ldd 0); jmp "hidle" ]
    @ [ L "hferr" ] @ kind 3 @ [ L "hferr_w"; waitp ~pin:p.clk ~value:1 "hferr_w"; jmp "hidle" ]
    @ [ L "hto" ] @ kind0 6 @ [ jmp "hidle" ]
    (* command: inhibit for 110 us, data low, release the clock, wait up to ~16 ms for the device *)
    @ [ L "htx"; low p.clk ] @ delay (slots t 110.) @ [ low p.data ] @ delay (slots t 5.) @ [ rel p.clk ] @ wait_clk 1 "htto" @ [ W (Isa_v.ldc 60);   (* see it high: a release is not an edge *)
        L "hw"; W (Isa_v.ldd 4095); waitp ~pin:p.clk ~value:0 "hw_dec"; jmp "hgot";   (* dl need not be 0: SHO is next *)
        L "hw_dec"; W (Isa_v.shi ~pin:p.clk ~msb:0 ()); jnz "hw"; jmp "htto";   (* SHI only counts down *)
        L "hgot"; W Isa_v.in_; W (Isa_v.ldc 8); jmp "htE_s" ]
    @ tx_bit "htE" "htO" @ tx_bit "htO" "htE"
    @ [ L "htE_p" ] @ wait_clk 0 "htto" @ [ (if par_ok_e = 1 then rel p.data else low p.data); jmp "htp" ]
    @ [ L "htO_p" ] @ wait_clk 0 "htto" @ [ (if par_ok_o = 1 then rel p.data else low p.data); jmp "htp" ]
    @ [ L "htp" ] @ wait_clk 1 "htto"
    @ wait_clk 0 "htto" @ [ rel p.data ] @ wait_clk 1 "htto"
    @ wait_clk 0 "htto" @ br ~pin:p.data ~value:0 "hnoack" @ wait_clk 1 "htto"
    @ [ W (Isa_v.ldd tmo); waitp ~pin:p.data ~value:1 "htto"; W (Isa_v.ldd 0) ] @ kind0 7 @ [ jmp "hidle" ]
    @ [ L "hnoack" ] @ kind0 8 @ [ L "hnoack_w" ] @ br ~pin:p.clk ~value:1 "hnoack_w" @ [ jmp "hidle" ]
    @ [ L "htto"; W (Isa_v.setp ~mask:(m p.clk lor m p.data) ~value:0 ~oe:0) ] @ kind0 9 @ [ jmp "hidle" ] in
  assemble ~name:"ps2 host" items
