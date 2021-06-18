open! Http_multipart_formdata

type string_result = (string, string) result [@@deriving show, ord]

let%expect_test "parse_boundary" =
  let content_type =
    "multipart/form-data; \
     boundary=---------------------------735323031399963166993862150"
  in
  parse_boundary ~content_type
  |> Lwt_main.run
  |> pp_string_result Format.std_formatter;
  [%expect {| (Ok "---------------------------735323031399963166993862150") |}]

type parse_result = ((Part_header.t * string) list, string) result
[@@deriving show, ord]

let%expect_test "parse" =
  let body =
    String.concat "\r\n"
      [ {||}
      ; {|-----------------------------735323031399963166993862150|}
      ; {|Content-Disposition: form-data; name="text1"|}
      ; {||}
      ; {|text default|}
      ; {|-----------------------------735323031399963166993862150|}
      ; {|Content-Disposition: form-data; name="text2"|}
      ; {||}
      ; {|aωb|}
      ; {|-----------------------------735323031399963166993862150|}
      ; {|Content-Disposition: form-data; name="file1"; filename="a.txt"|}
      ; {|Content-Type: text/plain|}
      ; {||}
      ; {|Content of a.txt.|}
      ; {||}
      ; {|-----------------------------735323031399963166993862150|}
      ; {|Content-Disposition: form-data; name="file2"; filename="a.html"|}
      ; {|Content-Type: text/html|}
      ; {||}
      ; {|<!DOCTYPE html><title>Content of a.html.</title>|}
      ; {||}
      ; {|-----------------------------735323031399963166993862150|}
      ; {|Content-Disposition: form-data; name="file3"; filename="binary"|}
      ; {|Content-Type: application/octet-stream|}
      ; {||}
      ; {|aωb|}
      ; {|-----------------------------735323031399963166993862150--|}
      ]
  in
  (* Printf.printf "s: %s\n" body; *)
  let parts = Queue.create () in
  let on_part header =
    let stream, push = Lwt_stream.create () in
    Queue.push (header, push, stream) parts;
    push
  in
  let content_type =
    {|multipart/form-data; boundary=---------------------------735323031399963166993862150|}
  in
  Lwt_result.(
    parse_boundary ~content_type
    >>= fun boundary ->
    parse ~boundary ~on_part (Lwt_stream.of_string body)
    >>= fun () ->
    Queue.to_seq parts
    |> List.of_seq
    |> Lwt_list.map_p (fun (hd, push, stream) ->
           push None;
           Lwt.map
             (fun s -> (hd, s))
             (Lwt.bind (Lwt_stream.closed stream) (fun () ->
                  Lwt_stream.to_string stream)))
    |> ok)
  |> Lwt_main.run
  |> pp_parse_result Format.std_formatter;
  [%expect
    {|
    (Ok [(name: text1;
          content_type: text/plain;
          filename: ;
          parameters: , "\r\ntext default");
          (name: text2;
           content_type: text/plain;
           filename: ;
           parameters: , "\r\na\207\137b");
          (name: file1;
           content_type: text/plain;
           filename: a.txt;
           parameters: , "\r\nContent of a.txt.\r\n");
          (name: file2;
           content_type: text/html;
           filename: a.html;
           parameters: ,
           "\r\n<!DOCTYPE html><title>Content of a.html.</title>\r\n");
          (name: file3;
           content_type: application/octet-stream;
           filename: binary;
           parameters: , "\r\na\207\137b")
          ]) |}]

(* let multi_values_suite = *)
(*   let content_type_header = *)
(* " multipart/form-data; \ *) (*
   boundary=---------------------------735323031399963166993862150" *)
(*   in *)
(*   let body = *)
(*     [ {||} *)
(*     ; {|-----------------------------735323031399963166993862150|} *)
(*     ; {|Content-Disposition: form-data; name="text1"|} *)
(*     ; {||} *)
(*     ; {|text default|} *)
(*     ; {|-----------------------------735323031399963166993862150|} *)
(*     ; {|Content-Disposition: form-data; name="text1"|} *)
(*     ; {||} *)
(*     ; {|aωb|} *)
(*     ; {|-----------------------------735323031399963166993862150|} *)
(*     ; {|Content-Disposition: form-data; name="file1"; filename="a.txt"|} *)
(*     ; {|Content-Type: text/plain|} *)
(*     ; {||} *)
(*     ; {|Content of a.txt.|} *)
(*     ; {||} *)
(*     ; {|-----------------------------735323031399963166993862150|} *)
(*     ; {|Content-Disposition: form-data; name="file1"; filename="a.html"|} *)
(*     ; {|Content-Type: text/html|} *)
(*     ; {||} *)
(*     ; {|<!DOCTYPE html><title>Content of a.html.</title>|} *)
(*     ; {||} *)
(*     ; {|-----------------------------735323031399963166993862150|} *)
(*     ; {|Content-Disposition: form-data; name="file1"; filename="binary"|} *)
(*     ; {|Content-Type: application/octet-stream|} *)
(*     ; {||} *)
(*     ; {|aωb|} *)
(*     ; {|-----------------------------735323031399963166993862150--|} *)
(*     ] *)
(*     |> String.concat "\r\n" *)
(*   in *)
(*   let mp = M.parse ~content_type_header ~body in *)
(*   let files_actual = M.Map.find "file1" mp in *)
(*   let files_expected = *)
(*     [ { M.Part.body = Bytes.of_string "\r\nContent of a.txt.\r\n\r\n" *)
(*       ; name = "file1" *)
(*       ; content_type = "text/plain" *)
(*       ; filename = Some "a.txt" *)
(*       ; parameters = M.Map.empty *)
(*       } *)
(*     ; { M.Part.body = *)
(*           Bytes.of_string *)
(*             "\r\n<!DOCTYPE html><title>Content of a.html.</title>\r\n\r\n" *)
(*       ; name = "file1" *)
(*       ; content_type = "text/html" *)
(*       ; filename = Some "a.html" *)
(*       ; parameters = M.Map.empty *)
(*       } *)
(*     ; { M.Part.body = Bytes.of_string "\r\naωb\r\n" *)
(*       ; name = "file1" *)
(*       ; content_type = "application/octet-stream" *)
(*       ; filename = Some "binary" *)
(*       ; parameters = M.Map.empty *)
(*       } *)
(*     ] *)
(*   in *)
(*   let text1_a = M.Map.find "text1" mp in *)
(*   let text1_e = *)
(*     [ { M.Part.body = Bytes.of_string "\r\ntext default\r\n" *)
(*       ; name = "text1" *)
(*       ; content_type = "text/plain" *)
(*       ; filename = None *)
(*       ; parameters = M.Map.empty *)
(*       } *)
(*     ; { M.Part.body = Bytes.of_string "\r\naωb\r\n" *)
(*       ; name = "text1" *)
(*       ; content_type = "text/plain" *)
(*       ; filename = None *)
(*       ; parameters = M.Map.empty *)
(*       } *)
(*     ] *)
(*   in *)
(*   [ ( "file1" *)
(*     , `Quick *)
(*     , fun () -> Alcotest.check parts "equal" files_actual files_expected ) *)
(* ; ("text1", `Quick, fun () -> Alcotest.check parts "equal" text1_a text1_e) *)
(* ] *)

(* let () = *)
(* Printexc.record_backtrace true; *)
(* Alcotest.run "M" *)
(*   [ ("Single Values", single_value_suite) *)
(*   ; ("Multi Values", multi_values_suite) *)
(*   ] *)
