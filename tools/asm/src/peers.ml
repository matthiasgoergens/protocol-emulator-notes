(* The outside world of a run: things on the nets (logical pins 0-7) besides the chip.

   Every clock, each peer first says what it drives (before it sees this clock's levels), the nets
   resolve, and then each peer observes the resolved levels. A level is a nibble: bit p is the
   level in quarter p of the clock. A net is a wired AND with a pull-up: anything driving 0 pulls
   it low; a net nobody drives reads 1.

   Clocks are counted from the run's start (the first clock the sequencer executes), so a peer
   behaves the same whether the image runs on the ISA interpreter or on the chip after its
   host-link load (negative clocks are before the start). *)

type t = {
  name : string;
  drive : clock:int -> (int * int) list;          (* (net, nibble) *)
  observe : clock:int -> int array -> unit;       (* resolved nibbles of the 8 nets *)
  report : unit -> string list;
}

let rep4 b = if b <> 0 then 15 else 0
let level nib = (nib lsr 3) land 1                 (* the clock's last quarter *)

(* ---- a stimulus file: "CLOCK NET LEVEL" lines, LEVEL 0, 1 or z; '#' comments ----
   The net is driven at that level from that clock on (z: released). *)
let stimulus_of_lines ~name lines =
  let evs = List.filter_map (fun (lineno, l) ->
      let l = String.trim (match String.index_opt l '#' with Some i -> String.sub l 0 i | None -> l) in
      if l = "" then None
      else match String.split_on_char ' ' l |> List.filter (( <> ) "") with
        | [ c; n; v ] ->
          let lv = match v with "0" -> Some 0 | "1" -> Some 1 | "z" | "Z" -> None
                              | _ -> failwith (Printf.sprintf "%s:%d: level %s (0, 1 or z)" name lineno v) in
          Some (int_of_string c, int_of_string n, lv)
        | _ -> failwith (Printf.sprintf "%s:%d: expected CLOCK NET LEVEL" name lineno)) lines in
  let evs = Array.of_list (List.stable_sort (fun (a, _, _) (b, _, _) -> compare a b) evs) in
  let cur = Array.make 8 None and i = ref 0 in
  { name = "stimulus " ^ name;
    drive = (fun ~clock ->
        while !i < Array.length evs && (let c, _, _ = evs.(!i) in c <= clock) do
          let _, n, v = evs.(!i) in cur.(n) <- v; incr i
        done;
        List.filter_map (fun n -> Option.map (fun v -> (n, rep4 v)) cur.(n)) (List.init 8 Fun.id));
    observe = (fun ~clock:_ _ -> ());
    report = (fun () -> [ Printf.sprintf "%d events" (Array.length evs) ]) }

let stimulus_file path =
  let ic = open_in path in
  let rec go n acc = match input_line ic with
    | l -> go (n + 1) ((n, l) :: acc)
    | exception End_of_file -> close_in ic; List.rev acc in
  stimulus_of_lines ~name:path (go 1 [])

(* ---- a UART transmitter: 8N1, lsb first, [bit] clocks a bit, from clock [start], [gap] idle
   clocks between frames ---- *)
let uart_tx ~net ~bit ~start ?(gap = 0) bytes =
  let frame b = 0 :: List.init 8 (fun i -> (b lsr i) land 1) @ [ 1 ] in
  let bits = Array.of_list (List.concat_map (fun b -> List.init (10 * bit + gap) (fun c ->
      if c < 10 * bit then List.nth (frame b) (c / bit) else 1)) bytes) in
  { name = Printf.sprintf "uart_tx net %d" net;
    drive = (fun ~clock ->
        let k = clock - start in
        [ (net, rep4 (if k >= 0 && k < Array.length bits then bits.(k) else 1)) ]);
    observe = (fun ~clock:_ _ -> ());
    report = (fun () -> [ Printf.sprintf "sent %s at %d clocks a bit from clock %d"
                            (String.concat " " (List.map (Printf.sprintf "%02x") bytes)) bit start ]) }

(* ---- a wire: net [dst] follows net [src] ---- *)
let wire ~src ~dst =
  let last = ref 15 in
  { name = Printf.sprintf "wire %d->%d" src dst;
    drive = (fun ~clock:_ -> [ (dst, !last) ]);
    observe = (fun ~clock:_ v -> last := v.(src));
    report = (fun () -> []) }

(* ---- an I2C target: a 256-byte register file at a 7-bit address, as a serial EEPROM is used:
   a write sets the register pointer (first data byte) and writes the bytes after it; a read
   returns bytes from the pointer on, which advances. It acknowledges its address and every byte
   written, releases SDA when the controller does not acknowledge a read byte, and may stretch
   SCL for [stretch] clocks after every falling edge. Written from the I2C specification (NXP
   UM10204): data changes while SCL is low, is valid while SCL is high; START and STOP are SDA
   edges while SCL is high. ---- *)
type i2c_state = Idle | Addr | Ack_addr | Wr | Ack_wr | Rd | Ack_rd

let i2c_target ~sda ~scl ~addr ?(stretch = 0) (mem : int array) =
  let st = ref Idle and sh = ref 0 and nb = ref 0 and ptr = ref 0 and first = ref false and reading = ref false in
  let acked = ref false and pull_sda = ref false and hold_scl = ref 0 in
  let p_sda = ref 1 and p_scl = ref 1 in
  let log = ref [] in
  let say fmt = Printf.ksprintf (fun s -> log := s :: !log) fmt in
  let out_byte = ref 0 in
  let drive_bit () = pull_sda := (!out_byte lsr (7 - !nb)) land 1 = 0; incr nb in
  { name = Printf.sprintf "i2c target 0x%02x" addr;
    drive = (fun ~clock:_ ->
        (if !pull_sda then [ (sda, 0) ] else []) @ (if !hold_scl > 0 then [ (scl, 0) ] else []));
    observe = (fun ~clock v ->
        let d = level v.(sda) and c = level v.(scl) in
        if !hold_scl > 0 then decr hold_scl;
        if !p_scl = 1 && c = 1 && !p_sda = 1 && d = 0 && not !pull_sda then begin
          (* START or repeated START (SDA falls while SCL is high, and not by our own hand) *)
          if !st <> Idle && !st <> Addr then say "%d: repeated START" clock else say "%d: START" clock;
          st := Addr; sh := 0; nb := 0
        end
        else if !p_scl = 1 && c = 1 && !p_sda = 0 && d = 1 && not !pull_sda then begin
          if !st <> Idle then say "%d: STOP" clock;
          st := Idle
        end
        else if !p_scl = 0 && c = 1 then begin
          (* rising SCL: the receiver samples *)
          match !st with
          | Addr | Wr -> sh := ((!sh lsl 1) lor d) land 0xFF; incr nb
          | Ack_rd -> acked := d = 0
          | _ -> ()
        end
        else if !p_scl = 1 && c = 0 then begin
          (* falling SCL: the transmitter changes SDA now *)
          if stretch > 0 then hold_scl := stretch;
          match !st with
          | Addr when !nb = 8 ->
            if !sh lsr 1 = addr then begin
              reading := !sh land 1 = 1;
              say "%d: address 0x%02x %s, ack" clock addr (if !reading then "read" else "write");
              pull_sda := true; st := Ack_addr; first := true
            end else (say "%d: address 0x%02x is not mine" clock (!sh lsr 1); st := Idle)
          | Ack_addr ->
            pull_sda := false;
            if !reading then (st := Rd; nb := 0; out_byte := mem.(!ptr); drive_bit ())
            else (st := Wr; sh := 0; nb := 0)
          | Wr when !nb = 8 ->
            if !first then (ptr := !sh; first := false; say "%d: pointer 0x%02x" clock !sh)
            else (mem.(!ptr) <- !sh; say "%d: wrote 0x%02x at 0x%02x" clock !sh !ptr; ptr := (!ptr + 1) land 0xFF);
            pull_sda := true; st := Ack_wr
          | Ack_wr -> pull_sda := false; st := Wr; sh := 0; nb := 0
          | Rd when !nb < 8 -> drive_bit ()
          | Rd ->
            say "%d: read 0x%02x from 0x%02x" clock !out_byte !ptr;
            ptr := (!ptr + 1) land 0xFF; pull_sda := false; st := Ack_rd; acked := false
          | Ack_rd ->
            if !acked then (st := Rd; nb := 0; out_byte := mem.(!ptr); drive_bit ())
            else (say "%d: controller did not acknowledge: end of read" clock; st := Idle)
          | _ -> ()
        end;
        p_sda := d; p_scl := c);
    report = (fun () -> List.rev !log) }
