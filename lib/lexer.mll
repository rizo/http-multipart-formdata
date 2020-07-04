(* RFC - https://tools.ietf.org/html/rfc2046#section-5.1.1 *)
{
  open Parser

  type mode =
    | Multipart_formdata
    | Multipart_body_part
    | Multipart_body_header_param
}

(*  https://tools.ietf.org/html/rfc5234
    https://www.w3.org/Protocols/HTTP/1.1/draft-ietf-http-v11-spec-01#Augmented-BNF
*)
let digit = ['0'-'9']
let alpha = ['A'-'Z' 'a'-'z']
let specials = [',' '(' ')' '+' '_' ',' '-' '.' '|' ':' '=' '?']

let bcharsnospace =  digit | alpha | specials
let bchars = bcharsnospace | ' '
let boundary = bchars* bcharsnospace

(* https://www.rfc-editor.org/std/std68.txt *)
let wsp = ['\x20' '\x09'] (* space or htab *)
let crlf = '\x0D' '\x0A'
let lwsp = wsp | crlf wsp

(* Content-Type type/subtype - https://tools.ietf.org/html/rfc6838#section-4.2 *)
let restricted_name_first = alpha | digit
let restricted_name_chars = (alpha | digit | '!' | '#' | '$' | '&' | '-' | '^' | '_' | '.' | '+')*
let restricted_name = restricted_name_first restricted_name_chars
let content_type = restricted_name '/' restricted_name

let dash_boundary = "--" boundary
let body = (_)*

let disposition_type = restricted_name
let ascii_chars = ['\x00' - '\x7F']
let control_chars = ['\000' - '\031' '\127']
let tspecials = ['(' ')' '<' '>' '@' ',' ';' ':' '\\' '"' '/' '[' ']' '?' '=' '{' '}' '\x20' '\x09']
let token = (ascii_chars # control_chars # tspecials)+
let attribute = token
let field_name = token
let quoted_text = ascii_chars # control_chars # '"'
let value = token | '"' quoted_text* '"'

rule lex_multipart_header = parse
| [' ' '\t'] {lex_multipart_header lexbuf}
| ';' { SEMI }
| "multipart/form-data" { MULTIPART_FORMDATA }
| "boundary" (wsp)* '=' (wsp)* {lex_boundary_value lexbuf}
| eof { EOF }
| _ {lex_multipart_header lexbuf}

and lex_boundary_value = parse
| '\'' (boundary as b) '\''  { BOUNDARY_VALUE b }
| (boundary as b) { BOUNDARY_VALUE b }

(*--- Multipart formdata ---*)
and lex_multipart_formdata mode = parse
| crlf (dash_boundary as b) lwsp*
  { mode := Multipart_body_part;
    DASH_BOUNDARY b
  }
| eof { EOF }
| _  { lex_multipart_formdata mode lexbuf} (* discard preamble/epilogue text. *)

and lex_body_part mode = parse
| crlf (dash_boundary as b) lwsp* { DASH_BOUNDARY b }
| crlf (dash_boundary as b) "--" lwsp* { mode := Multipart_formdata; CLOSE_BOUNDARY b}
| crlf "Content-Type" (wsp)* ':' (wsp)* content_type as ct
  { mode := Multipart_body_header_param;
    HEADER (`Content_type ct)
  }
| crlf "Content-Disposition" (wsp)* ':' (wsp)* (disposition_type as dt)
  { mode := Multipart_body_header_param;
    HEADER (`Content_disposition dt)
  }
| crlf field_name (wsp)* ':' (wsp)* (ascii_chars # control_chars | '\x09')* { lex_body_part mode lexbuf }
| crlf body as b { BODY b }

and lex_body_header_param mode = parse
| ';' (attribute as a) (wsp)* '=' (wsp)* (token as v) { HEADER_PARAM (a, v)}
| ';' (attribute as a) (wsp)* '=' (wsp)* '"' (quoted_text* as v) '"' { HEADER_PARAM (a, v)}
| lwsp* crlf
  { mode := Multipart_body_part;
    CRLF
  }

{
  let lex_multipart_formdata mode lb =
    match !mode with
    | Multipart_formdata -> Printf.printf "Multipart_formdata\n"; lex_multipart_formdata mode lb
    | Multipart_body_part -> Printf.printf "Multipart_body_part\n"; lex_body_part mode lb
    | Multipart_body_header_param -> Printf.printf "Multipart_body_header_param\n"; lex_body_header_param mode lb
}