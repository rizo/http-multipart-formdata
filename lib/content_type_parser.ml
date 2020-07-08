(* Implements the following RFCs
   1. 2045 https://tools.ietf.org/html/rfc2045 
   2. 2046 https://tools.ietf.org/html/rfc2046#section-5.1.1
   3. 5234 https://tools.ietf.org/html/rfc5234#appendix-B.1
   4. 6838 https://tools.ietf.org/html/rfc6838#section-4.2
   5. 5322 https://tools.ietf.org/html/rfc5322#section-3.2.1
*)
open Std
open Sexplib.Std

type parser = unit Parser.t

type t = { ty : string; subtype : string; parameters : (string * string) list }
[@@deriving sexp_of]

type result = (t, string) R.t [@@deriving sexp_of]

let rec parse_whitespace (l : parser) =
  if Parser.current l |> Char_token.is_whitespace then (
    Parser.next l;
    parse_whitespace l )

(* https://tools.ietf.org/html/rfc6838#section-4.2
 restricted-name = restricted-name-first *126restricted-name-chars
 restricted-name-first  = ALPHA / DIGIT
 restricted-name-chars  = ALPHA / DIGIT / "!" / "#" /
                          "$" / "&" / "-" / "^" / "_"
 restricted-name-chars =/ "." ; Characters before first dot always
                              ; specify a facet name
 restricted-name-chars =/ "+" ; Characters after last plus always
                              ; specify a structured syntax suffix
*)
let parse_restricted_name (l : parser) =
  let rec parse_restricted_char count =
    let ch = Parser.current l in
    if
      (count < 126 && Char_token.is_alpha ch)
      || Char_token.is_digit ch
      || ch == Char_token.bang
      || ch == Char_token.hash
      || ch == Char_token.dollar
      || ch == Char_token.ampersand
      || ch == Char_token.minus
      || ch == Char_token.caret
      || ch == Char_token.underscore
      || ch == Char_token.dot
      || ch == Char_token.plus
    then (
      Parser.next l;
      parse_restricted_char (count + 1) )
  in
  Parser.lex_start l;
  let ch = Parser.current l in
  if Char_token.is_alpha ch || Char_token.is_digit ch then (
    Parser.next l;
    parse_restricted_char 0;
    Parser.lexeme l |> R.ok )
  else
    asprintf "Expected ALPHA|DIGIT but received '%a'" Char_token.pp ch
    |> R.error

(* https://tools.ietf.org/html/rfc5322#section-3.2.2  
 FWS = ([*WSP CRLF] 1*WSP) /  obs-FWS   ; Folding white space
*)
let rec parse_fws (l : parser) =
  parse_whitespace l;
  if
    Parser.current l == Char_token.cr
    && Parser.peek l == Char_token.lf
    && (Char_token.is_whitespace @@ Parser.peek2 l)
  then (
    Parser.(
      next l;
      next l;
      next l);
    parse_fws l )

let parse_quoted_pair (l : parser) =
  if Parser.current l == Char_token.back_slash then
    let lookahead = Parser.peek l in
    if Char_token.is_vchar lookahead || Char_token.is_whitespace lookahead then (
      Parser.lex_start l;
      Parser.next l;
      Parser.next l;
      Parser.lexeme l |> R.ok )
    else
      sprintf "Invalid QUOTED_PAIR, VCHAR or WSP expected after '\'" |> R.error
  else R.ok ""

(* https://tools.ietf.org/html/rfc5322#section-3.2.1
 quoted-pair     =   ('\' (VCHAR / WSP)) / obs-qp

 RFC - https://tools.ietf.org/html/rfc5322#section-3.2.2
 ctext           =   %d33-39 /          ; Printable US-ASCII
                     %d42-91 /          ;  characters not including
                     %d93-126 /         ;  '(', ')', or '\'
                     obs-ctext

 ccontent        =   ctext / quoted-pair / comment

 comment         =   '(' *([FWS] ccontent) [FWS] ')'

 CFWS            =   (1*([FWS] comment) [FWS]) / FWS   
*)
let parse_cfws (l : parser) =
  let open R.O in
  let rec parse_comment () =
    let rec parse_ccontents () =
      parse_fws l;
      let ch = Parser.current l in
      if Char_token.is_ctext ch then (
        Parser.lex_start l;
        Parser.next l;
        parse_ccontents () )
      else if ch == Char_token.back_slash then
        parse_quoted_pair l >>= fun _ -> parse_ccontents ()
      else if ch == Char_token.lparen then (
        Parser.next l;
        parse_comment () >>= parse_ccontents )
      else R.ok ()
    in
    parse_ccontents () >>= fun () ->
    parse_fws l;
    Parser.expect Char_token.rparen l
  in
  let rec parse_comments () =
    parse_fws l;
    if Parser.current l == Char_token.lparen then (
      Parser.next l;
      parse_comment () >>= parse_comments )
    else R.ok ()
  in
  parse_comments ()

(* https://tools.ietf.org/html/rfc5322#section-3.2.4
 qtext           = %d33 /             ; Printable US-ASCII
                   %d35-91 /          ;  characters not including
                   %d93-126 /         ;  '\' or the quote character
                   obs-qtext

 qcontent        = qtext / quoted-pair

 quoted-string   = [CFWS]
                   DQUOTE *([FWS] qcontent) [FWS] DQUOTE
                   [CFWS]
*)
let parse_quoted_string (l : parser) =
  let open R.O in
  let rec parse_qcontents qcontent =
    parse_fws l;
    let ch = Parser.current l in
    if Char_token.is_qtext ch then (
      Parser.lex_start l;
      Parser.next l;
      qcontent ^ Parser.lexeme l |> parse_qcontents )
    else if ch == Char_token.back_slash then
      parse_quoted_pair l >>= fun quoted_pair ->
      parse_qcontents (qcontent ^ quoted_pair)
    else R.ok qcontent
  in

  parse_qcontents "" >>= fun qcontent ->
  parse_fws l;
  Parser.expect Char_token.double_quote l >>= fun () -> R.ok qcontent

(* https://tools.ietf.org/html/rfc2045#section-5.1
 token := 1*<any (US-ASCII) CHAR except SPACE, CTLs, or tspecials> 
 tspecials :=  "(" / ")" / "<" / ">" / "@" /
               "," / ";" / ":" / "\" / <">
               "/" / "[" / "]" / "?" / "="
               ; Must be in quoted-string,
               ; to use within parameter values
*)
let parse_token l =
  let open Char_token in
  let is_tspecials ch =
    ch == lparen
    || ch == rparen
    || ch == less_than
    || ch == greater_than
    || ch == at
    || ch == comma
    || ch == semicolon
    || ch == colon
    || ch == back_slash
    || ch == double_quote
    || ch == forward_slash
    || ch == lbracket
    || ch == rbracket
    || ch == question
    || ch == equal
  in
  let is_token_char ch =
    is_ascii ch && ch <> space && (not (is_control ch)) && not (is_tspecials ch)
  in
  let rec parse_token_chars () =
    if is_token_char (Parser.current l) then (
      Parser.next l;
      parse_token_chars () )
    else Parser.lexeme l |> R.ok
  in

  Parser.lex_start l;
  if is_token_char (Parser.current l) then (
    Parser.next l;
    parse_token_chars () )
  else
    asprintf "parse_token: expected 'token' but got '%a'" Char_token.pp
      (Parser.current l)
    |> R.error

(* https://tools.ietf.org/html/rfc2045#section-5.1
 parameter := attribute "=" value
 attribute := token
              ; Matching of attributes
              ; is ALWAYS case-insensitive.
 value := token / quoted-string              
*)
let parse_parameter (l : parser) =
  let open R.O in
  parse_whitespace l;
  let* attribute = parse_token l in
  parse_whitespace l;
  Parser.expect Char_token.equal l >>= fun () ->
  parse_cfws l >>= fun () ->
  let* value =
    if Parser.current l == Char_token.double_quote then (
      Parser.next l;
      parse_quoted_string l )
    else parse_token l
  in

  parse_cfws l >>| fun () ->
  (* Printf.printf "a: %s, v: %s\n\n" attribute value; *)
  (attribute, value)

(* https://tools.ietf.org/html/rfc2045#section-5.1
 content := "Content-Type" ":" type "/" subtype
            *(";" parameter)
            ; Matching of media type and subtype
            ; is ALWAYS case-insensitive.

 https://tools.ietf.org/html/rfc6838#section-4.2
 type-name = restricted-name
 subtype-name = restricted-name
*)
let parse_content_type l =
  let open R.O in
  let rec parse_parameters parameters =
    if Parser.current l == Char_token.semicolon then (
      Parser.next l;
      parse_parameter l >>= fun parameter ->
      parse_parameters (parameter :: parameters) )
    else R.ok parameters
  in

  parse_whitespace l;
  let* ty = parse_restricted_name l in
  let* () = Parser.expect Char_token.forward_slash l in
  let* subtype = parse_restricted_name l in
  parse_whitespace l;
  let+ parameters = parse_parameters [] in
  parse_whitespace l;
  { ty; subtype; parameters }

(*----------------- Tests ---------------*)

let test_parse_content_type s =
  Parser.create () s
  |> parse_content_type
  |> sexp_of_result
  |> Sexplib.Sexp.pp_hum_indent 2 Format.std_formatter

let%expect_test _ =
  test_parse_content_type "multipart/form-data; charset=us-ascii (Plain text)";
  [%expect
    {| (Ok ((ty multipart) (subtype form-data) (parameters ((charset us-ascii))))) |}]

let%expect_test _ =
  test_parse_content_type
    "multipart/form-data; charset=(Plain text) us-ascii (Plain text)";
  [%expect
    {| (Ok ((ty multipart) (subtype form-data) (parameters ((charset us-ascii))))) |}]

let%expect_test _ =
  test_parse_content_type "   text/plain  ;charset=\"us-ascii\" ";
  [%expect
    {| (Ok ((ty text) (subtype plain) (parameters ((charset us-ascii))))) |}]

let%expect_test _ =
  test_parse_content_type "text/html ; ";

  [%expect {| (Error "parse_token: expected 'token' but got 'EOF'") |}]

let%expect_test _ =
  test_parse_content_type
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  [%expect
    {|
    (Ok
      ((ty application)
        (subtype vnd.openxmlformats-officedocument.wordprocessingml.document)
        (parameters ()))) |}]

let%expect_test _ =
  test_parse_content_type
    "application/vnd.adobe.air-application-installer-package+zip";
  [%expect
    {|
    (Ok
      ((ty application) (subtype vnd.adobe.air-application-installer-package+zip)
        (parameters ()))) |}]

let%expect_test _ =
  test_parse_content_type " !!";
  [%expect {| (Error "Expected ALPHA|DIGIT but received '!'") |}]

(* let%expect_test "lex_token" = *)
(*   [ "boundary ="; "bound\x7Fary"; "boundary"; "boundary    " ] *)
(*   |> List.map (Parser.create Content_type) *)
(*   |> List.iter (lex_token >> pp_result); *)
(*   [%expect *)
(*     {| *)
(*     (Ok (Token boundary))(Ok (Token bound))(Ok (Token boundary))(Ok *)
(*                                                                  (Token boundary)) |}] *)
