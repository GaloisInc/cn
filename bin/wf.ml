module CF = Cerb_frontend
module CB = Cerb_backend
open Cn

let well_formed
      filename
      cc
      macros
      permissive
      incl_dirs
      incl_files
      json
      json_trace
      output_dir
      csv_times
      astprints
      no_inherit_loc
      magic_comment_char_dollar
      allow_split_magic_comments
      cache_status
      db_path
  =
  let filename = Common.there_can_only_be_one filename in
  if cache_status then (
    (* Cache status mode: parse file and check against database *)
    let db_path = Common.expand_home db_path in
    Common.with_well_formedness_check
      ~filename
      ~cc
      ~macros
      ~permissive
      ~incl_dirs
      ~incl_files
      ~coq_export_file:None
      ~coq_mucore:false
      ~coq_proof_log:false
      ~coq_check_proof_log:false
      ~csv_times
      ~astprints
      ~no_inherit_loc
      ~magic_comment_char_dollar
      ~allow_split_magic_comments
      ~save_cpp:None
      ~disable_linemarkers:false
      ~skip_label_inlining:false
      ~handle_error:(fun _ -> ())
      ~f:(fun ~cabs_tunit:_ ~prog5:_ ~ail_prog:_ ~statement_locs:_ ~paused ->
        let check (c_functions, _global_var_constraints, _lemmas) =
          let open Typing in
          if not (Sys.file_exists db_path) then (
            Printf.printf "No cache found at %s\n" db_path;
            Printf.printf "All functions would need verification (no cache).\n";
            return ())
          else (
            let db = VerificationDb.open_db db_path in
            VerificationDb.init_schema db;
            let@ global = get_global () in
            Printf.printf "Cache Status Report\n";
            Printf.printf "===================\n\n";
            Printf.printf "Database: %s\n" db_path;
            Printf.printf "File: %s\n" filename;
            Printf.printf "Functions analyzed: %d\n\n" (List.length c_functions);
            (* Analyze each function *)
            List.iter
              (fun (sym, (loc, args_and_body)) ->
                 let sym_str = Sym.pp_string sym in
                 let file_path =
                   Option.value (Cerb_location.get_filename loc) ~default:"<unknown>"
                 in
                 (* Compute current hashes *)
                 let content_hash = ContentHash.hash_args_and_body args_and_body in
                 let ft_opt =
                   match Sym.Map.find_opt sym global.fun_decls with
                   | Some (_, ft_opt, _) -> ft_opt
                   | None -> None
                 in
                 let spec_hash = ContentHash.hash_function_spec ft_opt in
                 (* Check database *)
                 match VerificationDb.get_function_status db sym_str with
                 | None ->
                   Printf.printf
                     "[NEW] %s\n\
                     \  Location: %s\n\
                     \  Reason: Not in cache\n\
                     \  Action: Will verify\n\n"
                     sym_str
                     file_path
                 | Some record ->
                   let status_str =
                     match record.VerificationDb.status with
                     | VerificationDb.Pass -> "PASS"
                     | VerificationDb.Fail -> "FAIL"
                     | VerificationDb.Stale -> "STALE"
                     | VerificationDb.Unknown -> "UNKNOWN"
                   in
                   let content_changed =
                     String.compare record.VerificationDb.content_hash content_hash <> 0
                   in
                   let spec_changed =
                     String.compare record.VerificationDb.spec_hash spec_hash <> 0
                   in
                   if content_changed then
                     Printf.printf
                       "[STALE] %s (was: %s)\n\
                       \  Location: %s\n\
                       \  Reason: Content hash changed\n\
                       \  Old hash: %s\n\
                       \  New hash: %s\n\
                       \  Action: Will re-verify\n\n"
                       sym_str
                       status_str
                       file_path
                       record.VerificationDb.content_hash
                       content_hash
                   else if spec_changed then
                     Printf.printf
                       "[STALE] %s (was: %s)\n\
                       \  Location: %s\n\
                       \  Reason: Spec hash changed\n\
                       \  Old spec hash: %s\n\
                       \  New spec hash: %s\n\
                       \  Action: Will re-verify\n\n"
                       sym_str
                       status_str
                       file_path
                       record.VerificationDb.spec_hash
                       spec_hash
                   else
                     Printf.printf
                       "[CACHED] %s (%s)\n\
                       \  Location: %s\n\
                       \  Reason: Hashes match\n\
                       \  Action: Will skip verification\n\n"
                       sym_str
                       (String.lowercase_ascii status_str)
                       file_path)
              c_functions;
            VerificationDb.close_db db |> ignore;
            return ())
        in
        Typing.run_from_pause check paused))
  else (* Normal well-formedness check *)
    Common.with_well_formedness_check
      ~filename
      ~cc
      ~macros
      ~permissive
      ~incl_dirs
      ~incl_files
      ~coq_export_file:None
      ~coq_mucore:false
      ~coq_proof_log:false
      ~coq_check_proof_log:false
      ~csv_times
      ~astprints
      ~no_inherit_loc
      ~magic_comment_char_dollar
      ~allow_split_magic_comments
      ~save_cpp:None
      ~disable_linemarkers:false
      ~skip_label_inlining:false
      ~handle_error:
        (Common.handle_type_error ~json ?output_dir ~serialize_json:json_trace)
      ~f:(fun ~cabs_tunit:_ ~prog5:_ ~ail_prog:_ ~statement_locs:_ ~paused:_ ->
        Or_TypeError.return ())


open Cmdliner

let cmd =
  let open Term in
  let cache_status_flag =
    Arg.(
      value
      & flag
      & info
          [ "cache-status" ]
          ~doc:
            "Parse file and show cache status (which functions would be verified vs \
             cached)")
  in
  let db_path_flag =
    Arg.(
      value
      & opt string "~/.cache/cn/verification.db"
      & info [ "db-path" ] ~doc:"Path to verification database (for --cache-status)")
  in
  let wf_t =
    const well_formed
    $ Common.Flags.file
    $ Common.Flags.cc
    $ Common.Flags.macros
    $ Common.Flags.permissive
    $ Common.Flags.incl_dirs
    $ Common.Flags.incl_files
    $ Verify.Flags.json
    $ Verify.Flags.json_trace
    $ Verify.Flags.output_dir
    $ Common.Flags.csv_times
    $ Common.Flags.astprints
    $ Common.Flags.no_inherit_loc
    $ Common.Flags.magic_comment_char_dollar
    $ Common.Flags.allow_split_magic_comments
    $ cache_status_flag
    $ db_path_flag
  in
  let doc =
    "Runs CN's well-formedness check\n\
    \    which finds errors such as\n\
    \    ill-typing CN definitions\n\
    \    (predicates, specifications, lemmas)\n\
    \    and ill-formed recursion in datatypes.\n\
    \    It DOES NOT verify C functions,\n\
    \    which `cn verify` does.\n\n\
    \    With --cache-status, parses the file and shows\n\
    \    which functions would be verified vs cached,\n\
    \    comparing computed hashes with the database."
  in
  let info = Cmd.info "wf" ~doc in
  Cmd.v info wf_t
