open Std

type 'mode t = {
  src : string;
  src_len : int;
  mutable ch : Char_token.t;
  (* current character *)
  mutable offset : int;
  (* character offset *)
  mutable start_offset : int;
  (* start offset *)
  mutable rd_offset : int;
  (* reading offset (position after current character) *)
  mutable mode : 'mode; (* current lexer mode. *)
}

let current t = t.ch

let lex_start (t : 'mode t) = t.start_offset <- t.offset

let next (t : 'mode t) =
  if t.rd_offset < t.src_len then (
    t.offset <- t.rd_offset;
    t.ch <- Char_token.of_char t.src.[t.rd_offset];
    t.rd_offset <- t.rd_offset + 1 )
  else (
    t.offset <- t.src_len;
    t.ch <- Char_token.eof )

let peek (t : 'mode t) =
  if t.rd_offset < t.src_len then Char_token.of_char t.src.[t.rd_offset]
  else Char_token.eof

let peek2 (t : 'mode t) =
  if t.rd_offset + 1 < t.src_len then Char_token.of_char t.src.[t.rd_offset + 1]
  else Char_token.eof

let create mode src =
  let t =
    {
      src;
      src_len = String.length src;
      ch = Char_token.eof;
      offset = 0;
      start_offset = 0;
      rd_offset = 0;
      mode;
    }
  in
  next t;
  t

let lexeme t = String.sub t.src t.start_offset (t.offset - t.start_offset)

let expect ch (t : 'mode t) =
  if t.ch == ch then (
    next t;
    R.ok () )
  else
    asprintf "expected '%a' but got '%a'" Char_token.pp ch Char_token.pp t.ch
    |> R.error

let accept ch (t : 'mode t) =
  if t.ch == ch then (
    lex_start t;
    next t;
    lexeme t |> R.ok )
  else
    asprintf "expected '%a' but got '%a'" Char_token.pp ch Char_token.pp t.ch
    |> R.error
