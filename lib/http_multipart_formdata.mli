(*-------------------------------------------------------------------------
 * Copyright (c) 2020, 2021 Bikal Gurung. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License,  v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 *-------------------------------------------------------------------------*)

(** {2 Types} *)

(** Represents the multipart boundary value. *)
type boundary

(** {2 Mulipart Boundary parser} *)

val parse_boundary : content_type:string -> (boundary, string) result
(** [parse_boundary ~content_type] parses [content_type] to extract [boundary]
    value.[content_type] is the HTTP request [Content-Type] header value. *)

val pp_boundary : Format.formatter -> boundary -> unit

(** {2 Multipart Parser} *)

module type MULTIPART_PARSER = sig
  (** {2 Types} *)

  type input

  and 'a promise

  and reader

  and read_result =
    [ `End
    | `Header of part_header
    | `Body of Cstruct.t
    | `Body_end
    | `Error of string ]

  (** Represents a parsed multipart part header data. *)
  and part_header

  (** {2 Multipart Reader} *)

  val reader : ?read_body_len:int -> boundary -> input -> reader
  (** [reader ?read_body_len boundary input] creates reader. The default value
      for [read_body_len] is 1KB. *)

  val read_part : reader -> read_result promise
  (** [read_part ?read_body_len ~boundary reader] reads a http multipart body
      and returns a [read_result]. *)

  (** {2 Part header} *)

  val name : part_header -> string
  (** [name t] returns the form field name *)

  val content_type : part_header -> string
  (** [content_type t] returns the part content-type. *)

  val filename : part_header -> string option
  (** [filename t] returns the uploaded filename is the multipart is a file *)

  val header_value : string -> part_header -> string option
  (** [param_value name t] returns the multipart parameter value with name
      [name]. *)

  (** {2 Pretty Printers} *)

  val pp_part_header : Format.formatter -> part_header -> unit
  val pp_read_result : Format.formatter -> read_result -> unit
end

(** {2 Make Multipart Parser} *)

module Make (P : Reparse.PARSER) :
  MULTIPART_PARSER with type input = P.input with type 'a promise = 'a P.promise
