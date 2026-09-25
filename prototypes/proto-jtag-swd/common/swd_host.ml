(* SWD host as firmware on the deadline sequencer: one thread, one programme, on the WIDE ISA
   variant (8-bit pc, 256 words per thread). The stock 64-word store is too small: see README.

   The engine is a transaction machine. Per host byte it runs one SWD packet with every decision
   the protocol needs taken locally, at pin speed:

   - bit 0 of the host byte is the request's Start bit, which is always 1. A 0 makes the byte a
     command instead: bit 1 set = JTAG-to-SWD switch then line reset, clear = line reset only.
     The engine decides by driving the bit onto SWDIO with SWCLK low (the target does not
     sample) and reading the pad back with WAITP.
   - RnW is read back from the pad the same way while it is on the line, to choose the read or
     the write path. The branch costs no state: the programme counter is the state.
   - the three ACK bits are sampled and each one is checked with a WAITP in the same low phase,
     so a WAIT, a FAULT or no response at all (the pull-up gives 111) leaves the packet before
     the data phase: turnaround, one idle cycle, next packet. The ACK goes to the host either way.
   - read: 32 data bits and parity in, four data bytes and a parity byte (bit 7) to the host.
   - write: the host always follows a write request with 4 data bytes and a parity byte (bit 0),
     and the engine always consumes them, shifting them out only after an OK. So the host can
     stream a packet's bytes without waiting for its ACK.

   Edge convention (ADIv5, SW-DP): the target samples SWDIO on SWCLK rising and changes its own
   output after SWCLK rising. The host changes SWDIO in the low phase, early, and samples in the
   low phase, late, just before rising. The turnaround cycles are both-released cycles;
   the host drives again from the low phase after a turnaround.

   Parities are the host's: it builds request bytes with the parity bit in place and sends the
   write-data parity; it checks the read-data parity. This is the precompute-on-the-host rule of
   the other protocols here. *)

open Asm

let clk = Wire.p_swclk and dio = Wire.p_swdio
let m p = 1 lsl p
let clk0 = W (Isa.setp ~mask:(m clk) ~value:0 ~oe:1)
let clk1 = W (Isa.setp ~mask:(m clk) ~value:1 ~oe:1)
let drive v = W (Isa.setp ~mask:(m dio) ~value:v ~oe:1)
let release = W (Isa.setp ~mask:(m dio) ~value:0 ~oe:0)
let sho = W (Isa.sho ~pin:dio ~msb:0 ())
let shi = W (Isa.shi ~pin:dio ~msb:0)

(* [lo]: slots in the low phase after the SETP that lowers SWCLK (>= 1, the data instruction);
   [hi]: slots in the high phase after the SETP that raises it (>= 1, the loop branch). The
   fastest bit is 4 slots, 16 core clocks. Planted bugs for the controls: [no_trn] drops the
   turnaround before the ACK, [no_trn_write] the one after a write's ACK, [late_sample] samples
   after the rising edge instead of before, [bad_switch] sends one wrong bit of the select
   sequence. *)
type knobs = {
  lo : int; hi : int;
  no_trn : bool; no_trn_write : bool; late_sample : bool; bad_switch : bool;
}
let fastest = { lo = 1; hi = 1; no_trn = false; no_trn_write = false; late_sample = false; bad_switch = false }

let engine k =
  assert (k.lo >= 1 && k.hi >= 1);
  let lbl = let n = ref 0 in fun s -> incr n; Printf.sprintf "%s%d" s !n in
  (* host-driven cycle: change early, then setup *)
  let out_cycle ?(low = [ sho ]) ?(high = []) () =
    [ clk0 ] @ low @ pad (k.lo - List.length low) @ [ clk1 ] @ high @ pad (k.hi - List.length high) in
  (* target-driven cycle: wait, sample late; [check] is extra work after the sample, still low *)
  let in_cycle ?(check = []) ?(high = []) () =
    if k.late_sample then
      [ clk0 ] @ pad (k.lo - 1) @ [ clk1; shi ] @ check @ high @ pad (k.hi - 1 - List.length high)
    else [ clk0 ] @ pad (k.lo - 1) @ [ shi ] @ check @ [ clk1 ] @ high @ pad (k.hi - List.length high) in
  let loop n body =
    let l = lbl "loop" in
    let cyc = match body with
      | `Out -> [ clk0; sho ] @ pad (k.lo - 1) @ [ clk1 ]
      | `In -> if k.late_sample then [ clk0 ] @ pad (k.lo - 1) @ [ clk1; shi ]
               else [ clk0 ] @ pad (k.lo - 1) @ [ shi; clk1 ]
      | `Idle -> [ clk0; shi ] @ pad (k.lo - 1) @ [ clk1 ] (* SHI only counts; host is driving *) in
    [ W (Isa.ldc n); L l ] @ cyc @ pad (k.hi - 1 - (if k.late_sample && body = `In then 1 else 0)) @ [ Jnz l ] in
  let trn () = out_cycle ~low:[ release ] () in
  let idle_cycle () = out_cycle ~low:[ drive 0 ] () in
  (* ACK: three sampled cycles, each checked; a failed check jumps to the matching entry of the
     not-OK chain, which finishes the remaining ACK cycles with identical timing. *)
  let ack_checked nk =
    List.concat (List.mapi (fun i want ->
      in_cycle ~check:[ Waitp (dio, want, Printf.sprintf "%s%d" nk i) ] ()) [ 1; 0; 0 ]) in
  let not_ok_chain nk ~tail =
    (* entry i: the rising edge of ACK cycle i, then the rest of the ACK unchecked *)
    let entry i =
      [ L (Printf.sprintf "%s%d" nk i); clk1 ] @ pad k.hi
      @ (if i < 2 then [ clk0 ] @ pad (k.lo - 1) @ [ shi; W Isa.nop ] else []) in
    (* each entry falls through into the next: entry 0 clocks ACK 1, entry 1 clocks ACK 2 *)
    entry 0 @ entry 1 @ entry 2 @ [ W Isa.out ] @ trn () @ idle_cycle () @ tail @ [ Jmp "top" ] in
  let req_rest () = loop 5 `Out in   (* a function: each use needs its own label *)
  let prologue = [ clk0; drive 1 ] in
  let top =
    [ L "top"; W Isa.in_ ]
    (* request bit 0: Start, or a command *)
    @ [ clk0; sho ] @ pad (k.lo - 1) @ [ Waitp (dio, 1, "cmd"); clk1 ] @ pad k.hi
    @ loop 2 `Out                                  (* APnDP, RnW *)
    @ [ Waitp (dio, 1, "write") ] in               (* RnW still on the line: 0 = write *)
  let read_path =
    req_rest ()
    @ (if k.no_trn then [ release ] else trn ())
    @ ack_checked "rnk"
    @ [ W Isa.out ]
    @ List.concat (List.init 4 (fun _ -> loop 8 `In @ [ W Isa.out ]))
    @ in_cycle ~high:[ W Isa.out ] ()              (* parity *)
    @ trn () @ idle_cycle () @ [ Jmp "top" ] in
  let write_path =
    [ L "write" ] @ req_rest ()
    @ (if k.no_trn then [ release ] else trn ())
    @ ack_checked "wnk"
    @ [ W Isa.out ]
    @ (if k.no_trn_write then [ drive 0 ] else out_cycle ~low:[] ~high:[ drive 0 ] ())
    @ List.concat (List.init 4 (fun _ -> [ W Isa.in_ ] @ loop 8 `Out))
    @ [ W Isa.in_ ] @ out_cycle ()                 (* parity *)
    @ idle_cycle () @ [ Jmp "top" ] in
  let cmd =
    (* entered with SWCLK low and bit 0 = 0 on SWDIO; bit 1 chooses *)
    [ L "cmd"; sho ] @ pad (k.lo - 1) @ [ Waitp (dio, 1, "lreset") ]
    @ [ L "switch"; drive 1 ] @ loop 56 `Idle
    @ [ W (Isa.lda (if k.bad_switch then 0x9F else 0x9E)) ] @ loop 8 `Out
    @ [ W (Isa.lda 0xE7) ] @ loop 8 `Out
    @ [ L "lreset"; drive 1 ] @ loop 56 `Idle
    @ [ drive 0 ] @ loop 4 `Idle @ [ Jmp "top" ] in
  prologue @ top @ read_path @ write_path
  @ not_ok_chain "rnk" ~tail:[]
  @ not_ok_chain "wnk" ~tail:(List.init 5 (fun _ -> W Isa.in_))
  @ cmd

let programmes k =
  let p, len = assemble (engine k) in
  [| p; halted; halted; halted |], len

(* ---- Host side: packets as bytes, and the responses back. ---- *)

let parity x = let rec go x a = if x = 0 then a else go (x lsr 1) (a lxor (x land 1)) in go x 0

type txn = { ap : int; rnw : int; a : int (* register address 0x0, 0x4, 0x8, 0xC *); wdata : int }
let dp_read a = { ap = 0; rnw = 1; a; wdata = 0 }
let dp_write a d = { ap = 0; rnw = 0; a; wdata = d }
let ap_read a = { ap = 1; rnw = 1; a; wdata = 0 }
let ap_write a d = { ap = 1; rnw = 0; a; wdata = d }

(* Start 1, APnDP, RnW, A[2], A[3], parity of those four, Stop 0, Park 1; LSB first on the wire. *)
let request ?(bad_parity = false) t =
  let a2 = (t.a lsr 2) land 1 and a3 = (t.a lsr 3) land 1 in
  let p = t.ap lxor t.rnw lxor a2 lxor a3 lxor (if bad_parity then 1 else 0) in
  1 lor (t.ap lsl 1) lor (t.rnw lsl 2) lor (a2 lsl 3) lor (a3 lsl 4) lor (p lsl 5) lor (1 lsl 7)

let bytes_of ?bad_parity ?(bad_wparity = false) t =
  request ?bad_parity t
  :: (if t.rnw = 1 then []
      else List.init 4 (fun i -> (t.wdata lsr (8 * i)) land 0xFF)
           @ [ parity t.wdata lxor (if bad_wparity then 1 else 0) ])

let cmd_switch = 0x02 and cmd_line_reset = 0x00

type ack = Ok | Wait | Fault | Other of int
let ack_of_byte b = match (b lsr 5) land 7 with 1 -> Ok | 2 -> Wait | 4 -> Fault | x -> Other x
let string_of_ack = function
  | Ok -> "OK" | Wait -> "WAIT" | Fault -> "FAULT" | Other x -> Printf.sprintf "none(%d%d%d)" (x land 1) ((x lsr 1) land 1) (x lsr 2)
