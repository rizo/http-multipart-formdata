type t

val create : string -> t

val current : t -> Char_token.t

val lex_start : t -> unit

val next : t -> unit

val peek : t -> Char_token.t

val peek2 : t -> Char_token.t

val lexeme : t -> string

val expect : Char_token.t -> t -> (unit, string) Result.t

val accept : Char_token.t -> t -> (string, string) Result.t
