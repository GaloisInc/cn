module CF = Cerb_frontend
module CB = Cerb_backend
open Cn

let preprocess
      filename
      cc
      macros
      permissive
      incl_dirs
      incl_files
      debug_level
      output_file
      disable_linemarkers
      magic_comment_char_dollar
      allow_split_magic_comments
  =
  (* Set debug level *)
  Cerb_debug.debug_level := debug_level;
  let filename = Common.there_can_only_be_one filename in
  (* Determine output destination *)
  let output_dest =
    match output_file with
    | Some path -> path
    | None -> "/dev/stdout" (* Output to stdout by default *)
  in
  (* Set up Cerberus configuration - required for preprocessing *)
  Cerb_global.set_cerb_conf
    ~backend_name:"Cn"
    ~exec:false
    Random
    ~concurrency:false
    Basic
    ~defacto:false
    ~permissive
    ~agnostic:false
    ~ignore_bitfields:false;
  CF.Ocaml_implementation.set CF.Ocaml_implementation.HafniumImpl.impl;
  CF.Switches.set
    ([ "inner_arg_temps"; "at_magic_comments" ]
     @ if magic_comment_char_dollar then [ "magic_comment_char_dollar" ] else []);
  if allow_split_magic_comments then Parse.allow_split_magic_comments := true;
  (* Build config with output path - cpp_save will write to this file *)
  let conf =
    Setup.conf cc macros incl_dirs incl_files disable_linemarkers [] (Some output_dest)
  in
  (* Run the preprocessor - it will save output via cpp_save *)
  let result = CB.Pipeline.cpp (conf, Setup.io) ~filename in
  match result with
  | CF.Exception.Exception err ->
    prerr_endline (CF.Pp_errors.to_string err);
    exit 2
  | CF.Exception.Result _txt ->
    (* Success - output was already written by cpp_save *)
    (match output_file with
     | None -> prerr_endline "Preprocessing complete."
     | Some _ -> prerr_endline ("Preprocessed output written to: " ^ output_dest));
    exit 0


open Cmdliner

module Flags = struct
  let output_file =
    let doc = "Write preprocessed output to FILE (default: stdout)" in
    Arg.(value & opt (some string) None & info [ "o"; "output" ] ~docv:"FILE" ~doc)


  let disable_linemarkers =
    let doc = "Disable linemarkers in preprocessed output (same as cpp -P)" in
    Arg.(value & flag & info [ "P"; "no-linemarkers" ] ~doc)
end

let preprocess_t : unit Term.t =
  let open Term in
  const preprocess
  $ Common.Flags.file
  $ Common.Flags.cc
  $ Common.Flags.macros
  $ Common.Flags.permissive
  $ Common.Flags.incl_dirs
  $ Common.Flags.incl_files
  $ Common.Flags.debug_level
  $ Flags.output_file
  $ Flags.disable_linemarkers
  $ Common.Flags.magic_comment_char_dollar
  $ Common.Flags.allow_split_magic_comments


let cmd =
  let doc =
    "Preprocess C source file with CN's default settings.\n\
    \    Outputs preprocessed C code suitable for creduce.\n\
    \    The preprocessing is idempotent with other CN commands."
  in
  let info = Cmd.info "preprocess" ~doc in
  Cmd.v info preprocess_t
