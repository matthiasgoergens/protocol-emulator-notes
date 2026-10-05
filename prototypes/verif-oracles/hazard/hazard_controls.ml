(* Planted violations for the hazard checker: each must be REJECTED (or raise), and a matching
   clean variant must be accepted, so that a checker that rejects everything also fails here. *)
open Hazard
module I = Isa2

let halt_at = I.halt_at

(* thread t's programme on page t; words beyond it read as NOP (pc wraps through them) *)
let fetch_of (progs : int list array) =
  let a = Array.map Array.of_list progs in
  fun addr -> let t = addr lsr 8 and pc = addr land 0xFF in
    if t < Array.length a && pc < Array.length a.(t) then a.(t).(pc) else I.nop

let idle = [ halt_at 0 ]
let progs l = Array.init 4 (fun t -> match List.assoc_opt t l with Some p -> p | None -> idle)
let drive p = I.setp ~mask:(1 lsl p) ~value:1 ~oe:1 ()
let grant r t ks = (r, Thread t, ks)

type expect = Accept | Reject of string | Raises

let cases = [
  (* pins *)
  "T0 drives pin 0, which it owns", Accept,
  progs [ 0, [ drive 0; halt_at 1 ] ], { no_decl with grants = [ grant (Pin 0) 0 [ Pin_drive ] ] };
  "T0 and T1 both drive pin 0 (T0 owns it)", Reject "pair",
  progs [ 0, [ drive 0; halt_at 1 ]; 1, [ drive 0; halt_at 1 ] ], { no_decl with grants = [ grant (Pin 0) 0 [ Pin_drive ] ] };
  "T1 drives pin 3, owned by T0 (T0 never touches it)", Reject "solo",
  progs [ 1, [ I.sho ~pin:3 ~msb:0 (); halt_at 1 ] ], { no_decl with grants = [ grant (Pin 3) 0 [ Pin_drive ] ] };
  "SHO pair on pin 7 drives pin 0 too (wraps), pin 0 not granted", Reject "solo",
  progs [ 2, [ I.sho ~pair:1 ~pin:7 ~msb:1 (); halt_at 1 ] ], { no_decl with grants = [ grant (Pin 7) 2 [ Pin_drive ] ] };
  "T0..T3 drive pin 0, declared a time-division group", Accept,
  progs (List.init 4 (fun t -> (t, [ drive 0; halt_at 1 ]))),
  { no_decl with grants = List.init 4 (fun t -> grant (Pin 0) t [ Pin_drive ]); shared = [ (Pin 0, List.init 4 (fun t -> Thread t)) ] };
  "T1 samples T0's pin (a monitor)", Accept,
  progs [ 0, [ drive 0; halt_at 1 ]; 1, [ I.waitp ~pin:0 ~value:1 ~fail:0; halt_at 1 ] ], { no_decl with grants = [ grant (Pin 0) 0 [ Pin_drive ] ] };
  "a foreign drive only in unreachable code", Accept,
  progs [ 0, [ halt_at 0; drive 5 ] ], no_decl;
  "a foreign drive behind a conditional branch (JNZ), reachable", Reject "solo",
  progs [ 0, [ I.jnz 3; halt_at 1; I.nop; drive 5; halt_at 4 ] ], no_decl;
  (* bank port: refresh versus access, array stream versus access *)
  "T1 LDB on bank 0, refresh every 8 clocks at offset 2 (T2's clocks)", Accept,
  progs [ 1, [ I.ldb; halt_at 1 ] ], { no_decl with grants = [ grant (Bankr 0) 1 [ Bank_read ] ]; refresh = [ (0, 8, 2) ] };
  "T1 LDB on bank 0, refresh every 8 clocks at offset 5 (T1's clocks)", Reject "pair",
  progs [ 1, [ I.ldb; halt_at 1 ] ], { no_decl with grants = [ grant (Bankr 0) 1 [ Bank_read ] ]; refresh = [ (0, 8, 5) ] };
  "T2 LDB on bank 0, refresh every 6 clocks at 0 (even clocks: T0's and T2's)", Reject "pair",
  progs [ 2, [ I.ldb; halt_at 1 ] ], { no_decl with grants = [ grant (Bankr 0) 2 [ Bank_read ] ]; refresh = [ (0, 6, 0) ] };
  "T1 LDB on bank 0, refresh every 6 clocks at 0 (never an odd clock)", Accept,
  progs [ 1, [ I.ldb; halt_at 1 ] ], { no_decl with grants = [ grant (Bankr 0) 1 [ Bank_read ] ]; refresh = [ (0, 6, 0) ] };
  "T3 STB on bank 1 (BANK imm 2) while segment 4 streams bank 1", Reject "pair",
  progs [ 3, [ I.lda 0; I.bank 2; I.stb; halt_at 3 ] ], { no_decl with grants = [ grant (Bankr 1) 3 [ Bank_write ] ]; streams = [ (1, 3) ] };
  "T3 STB on bank 1 while segment 3 streams bank 0", Accept,
  progs [ 3, [ I.lda 0; I.bank 2; I.stb; halt_at 3 ] ], { no_decl with grants = [ grant (Bankr 1) 3 [ Bank_write ] ]; streams = [ (0, 2) ] };
  "T3 STB on bank 1 granted bank 0 only", Reject "solo",
  progs [ 3, [ I.lda 0; I.bank 2; I.stb; halt_at 3 ] ], { no_decl with grants = [ grant (Bankr 0) 3 [ Bank_write ] ] };
  "T0 reads and T2 writes bank 0 (different clocks)", Accept,
  progs [ 0, [ I.ldb; halt_at 1 ]; 2, [ I.stb; halt_at 1 ] ],
  { no_decl with grants = [ grant (Bankr 0) 0 [ Bank_read ]; grant (Bankr 0) 2 [ Bank_write ] ] };
  (* mailboxes *)
  "T0 SEND to inbox 1 with fail = itself (no deadline), T1 RECV", Reject "solo",
  progs [ 0, [ I.send ~ch:1 ~fail:0; halt_at 1 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "T0 SEND whose fail path jumps straight back (no deadline)", Reject "solo",
  progs [ 0, [ I.send ~ch:1 ~fail:2; halt_at 1; I.jmp 0 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "T0 SEND whose fail path runs through nine NOPs and jumps back (review finding)", Reject "solo",
  progs [ 0, [ I.send ~ch:1 ~fail:2; halt_at 1 ] @ List.init 9 (fun _ -> I.nop) @ [ I.jmp 0 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "T0 SEND whose fail path ends in a HALT elsewhere (gives up: accepted)", Accept,
  progs [ 0, [ I.send ~ch:1 ~fail:2; halt_at 1; I.jmp 2 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "T0 LDD 50; SEND with a give-up path (deadline), T1 RECV", Accept,
  progs [ 0, [ I.ldd 50; I.send ~ch:1 ~fail:3; halt_at 2; I.outi ~tag:7 1; halt_at 4 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "WAITC 11 spinning on a full inbox (no deadline)", Reject "solo",
  progs [ 0, [ I.ldd 9; I.send ~ch:1 ~fail:2; I.waitc ~cond:I.c_space ~fail:2; halt_at 3 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k; Space_wait ]; grant (Inbox 0) 0 [ Space_wait ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "SEND to inbox 2, which nobody reads", Reject "counterpart",
  progs [ 0, [ I.ldd 9; I.send ~ch:2 ~fail:3; halt_at 2; halt_at 3 ] ], { no_decl with grants = [ grant (Inbox 2) 0 [ Send_k ] ] };
  "two consumers (T1 and T2 RECV) of inbox 1", Reject "pair",
  progs [ 0, [ I.ldd 9; I.send ~ch:1 ~fail:3; halt_at 2; halt_at 3 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ]; 2, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ]; grant (Inbox 1) 2 [ Recv_k ] ] };
  "two producers (T0, T3) of inbox 1, not declared shared", Reject "pair",
  progs [ 0, [ I.ldd 9; I.send ~ch:1 ~fail:3; halt_at 2; halt_at 3 ]; 3, [ I.ldd 9; I.send ~ch:1 ~fail:3; halt_at 2; halt_at 3 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ]; grant (Inbox 1) 3 [ Send_k ]; grant (Inbox 1) 1 [ Recv_k ] ] };
  "RECV on inbox 1 by a thread with no grant", Reject "solo",
  progs [ 0, [ I.ldd 9; I.send ~ch:1 ~fail:3; halt_at 2; halt_at 3 ]; 1, [ I.recv ~ch:1 ~fail:0; halt_at 1 ] ],
  { no_decl with grants = [ grant (Inbox 1) 0 [ Send_k ] ] };
  (* fail loudly *)
  "a reachable reserved EXT operation (EXT 9)", Raises,
  progs [ 0, [ I.ext 9 0; halt_at 1 ] ], no_decl;
]

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "table" then (print_table stdout default_tables; exit 0);
  let ok = ref true in
  List.iter (fun (name, expect, p, decl) ->
      (* a planted violation passes when a finding of the expected rule is among the findings *)
      let got, rules, detail =
        match check ~fetch:(fetch_of p) decl with
        | _, [] -> ("accepted", [], "")
        | _, fs ->
          let rules = List.sort_uniq compare (List.map (fun (f : finding) -> f.rule) fs) in
          ("rejected:" ^ String.concat "+" rules, rules,
           String.concat "; " (List.map (fun (f : finding) -> Printf.sprintf "[%s] %s at %s" f.rule f.key f.where) fs))
        | exception Unhandled m -> ("raised", [], "Unhandled: " ^ m) in
      let pass = match expect with
        | Accept -> got = "accepted" | Reject r -> List.mem r rules | Raises -> got = "raised" in
      if not pass then ok := false;
      Printf.printf "%-4s %-72s expected %-20s got %-26s %s\n" (if pass then "ok" else "FAIL") name
        (match expect with Accept -> "accepted" | Reject r -> "rejected:" ^ r | Raises -> "raised") got detail) cases;
  Printf.printf "\n%d cases; HAZARD CONTROLS %s\n" (List.length cases) (if !ok then "PASS" else "FAIL");
  exit (if !ok then 0 else 1)
