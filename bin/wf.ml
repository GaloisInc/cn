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
            (* Build lookup maps for dependency checking *)
            let sym_name_map = Hashtbl.create 100 in
            List.iter
              (fun (sym, _) -> Hashtbl.add sym_name_map (Sym.pp_string sym) sym)
              c_functions;
            (* Build struct name -> definition map *)
            let struct_map = Hashtbl.create 100 in
            Sym.Map.iter
              (fun sym decl -> Hashtbl.add struct_map (Sym.pp_string sym) decl)
              global.struct_decls;
            (* Build datatype name -> definition map *)
            let datatype_map = Hashtbl.create 100 in
            Sym.Map.iter
              (fun sym dt_info -> Hashtbl.add datatype_map (Sym.pp_string sym) dt_info)
              global.datatypes;
            (* Build predicate name -> definition map *)
            let pred_name_map = Hashtbl.create 100 in
            Sym.Map.iter
              (fun sym pred_def ->
                 Hashtbl.add pred_name_map (Sym.pp_string sym) (sym, pred_def))
              global.resource_predicates;
            (* Build logical function name -> definition map *)
            let logfn_name_map = Hashtbl.create 100 in
            Sym.Map.iter
              (fun sym logfn_def ->
                 Hashtbl.add logfn_name_map (Sym.pp_string sym) (sym, logfn_def))
              global.logical_functions;
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
                   (* Get all dependencies *)
                   let call_deps = VerificationDb.get_call_dependencies db sym_str in
                   let pred_deps = VerificationDb.get_predicate_dependencies db sym_str in
                   let logfn_deps =
                     VerificationDb.get_function_logical_function_dependencies db sym_str
                   in
                   let struct_deps = VerificationDb.get_struct_dependencies db sym_str in
                   let datatype_deps =
                     VerificationDb.get_datatype_dependencies db sym_str
                   in
                   (* Check dependencies for staleness *)
                   let check_dep_staleness () =
                     let stale_calls =
                       List.filter_map
                         (fun callee ->
                            match VerificationDb.get_function_status db callee with
                            | Some callee_rec ->
                              (* For function calls, check if callee spec changed *)
                              (match Hashtbl.find_opt sym_name_map callee with
                               | Some callee_sym ->
                                 (match Sym.Map.find_opt callee_sym global.fun_decls with
                                  | Some (_, ft_opt, _) ->
                                    let current_spec_hash =
                                      ContentHash.hash_function_spec ft_opt
                                    in
                                    if
                                      String.compare
                                        callee_rec.VerificationDb.spec_hash
                                        current_spec_hash
                                      <> 0
                                    then
                                      Some (callee, "spec changed")
                                    else
                                      None
                                  | None -> Some (callee, "not found in global"))
                               | None ->
                                 (* Not in current file - external function *)
                                 None
                                 (* Assume external functions are stable *))
                            | None ->
                              (* Not in cache - could be external or first run *)
                              None
                            (* Don't flag as stale, let it be verified on demand *))
                         call_deps
                     in
                     let stale_preds =
                       List.filter_map
                         (fun pred ->
                            match VerificationDb.get_predicate_status db pred with
                            | Some pred_rec ->
                              (* For predicates, check if content hash changed *)
                              (match Hashtbl.find_opt pred_name_map pred with
                               | Some (_pred_sym, pred_def) ->
                                 let current_hash = ContentHash.hash_predicate pred_def in
                                 if
                                   String.compare
                                     pred_rec.VerificationDb.content_hash
                                     current_hash
                                   <> 0
                                 then
                                   Some (pred, "predicate definition changed")
                                 else
                                   None
                               | None -> None (* External or not in current file *))
                            | None -> None (* External or not tracked yet *))
                         pred_deps
                     in
                     let stale_logfns =
                       List.filter_map
                         (fun logfn ->
                            match VerificationDb.get_logical_function_status db logfn with
                            | Some logfn_rec ->
                              (* For logical functions, check if content hash changed *)
                              (match Hashtbl.find_opt logfn_name_map logfn with
                               | Some (_logfn_sym, logfn_def) ->
                                 let current_hash =
                                   ContentHash.hash_logical_function logfn_def
                                 in
                                 if
                                   String.compare
                                     logfn_rec.VerificationDb.content_hash
                                     current_hash
                                   <> 0
                                 then
                                   Some (logfn, "logical function definition changed")
                                 else
                                   None
                               | None -> None (* External or not in current file *))
                            | None -> None)
                         logfn_deps
                     in
                     let stale_structs =
                       List.filter_map
                         (fun struct_name ->
                            match VerificationDb.get_struct_definition db struct_name with
                            | Some struct_rec ->
                              (* Check if struct definition changed *)
                              (match Hashtbl.find_opt struct_map struct_name with
                               | Some struct_decl ->
                                 let current_hash =
                                   ContentHash.hash_struct_definition struct_decl
                                 in
                                 if
                                   String.compare
                                     struct_rec.VerificationDb.content_hash
                                     current_hash
                                   <> 0
                                 then
                                   Some (struct_name, "struct definition changed")
                                 else
                                   None
                               | None -> None)
                            | None -> None)
                         struct_deps
                     in
                     let stale_datatypes =
                       List.filter_map
                         (fun dt_name ->
                            match VerificationDb.get_datatype_definition db dt_name with
                            | Some dt_rec ->
                              (* Check if datatype definition changed *)
                              (match Hashtbl.find_opt datatype_map dt_name with
                               | Some dt_info ->
                                 let current_hash =
                                   ContentHash.hash_datatype_definition dt_info
                                 in
                                 if
                                   String.compare
                                     dt_rec.VerificationDb.content_hash
                                     current_hash
                                   <> 0
                                 then
                                   Some (dt_name, "datatype definition changed")
                                 else
                                   None
                               | None -> None)
                            | None -> None)
                         datatype_deps
                     in
                     stale_calls
                     @ stale_preds
                     @ stale_logfns
                     @ stale_structs
                     @ stale_datatypes
                   in
                   let stale_deps = check_dep_staleness () in
                   if content_changed then (
                     Printf.printf
                       "[STALE] %s (was: %s)\n\
                       \  Location: %s\n\
                       \  Reason: Content hash changed\n\
                       \  Old hash: %s\n\
                       \  New hash: %s\n\
                       \  Action: Will re-verify\n"
                       sym_str
                       status_str
                       file_path
                       record.VerificationDb.content_hash
                       content_hash;
                     if
                       List.length call_deps
                       + List.length pred_deps
                       + List.length logfn_deps
                       + List.length struct_deps
                       + List.length datatype_deps
                       > 0
                     then (
                       Printf.printf "  Dependencies:\n";
                       List.iter
                         (fun dep -> Printf.printf "    - calls: %s\n" dep)
                         call_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - predicate: %s\n" dep)
                         pred_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - logical function: %s\n" dep)
                         logfn_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - struct: %s\n" dep)
                         struct_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - datatype: %s\n" dep)
                         datatype_deps);
                     Printf.printf "\n")
                   else if spec_changed then (
                     Printf.printf
                       "[STALE] %s (was: %s)\n\
                       \  Location: %s\n\
                       \  Reason: Spec hash changed\n\
                       \  Old spec hash: %s\n\
                       \  New spec hash: %s\n\
                       \  Action: Will re-verify\n"
                       sym_str
                       status_str
                       file_path
                       record.VerificationDb.spec_hash
                       spec_hash;
                     if
                       List.length call_deps
                       + List.length pred_deps
                       + List.length logfn_deps
                       + List.length struct_deps
                       + List.length datatype_deps
                       > 0
                     then (
                       Printf.printf "  Dependencies:\n";
                       List.iter
                         (fun dep -> Printf.printf "    - calls: %s\n" dep)
                         call_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - predicate: %s\n" dep)
                         pred_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - logical function: %s\n" dep)
                         logfn_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - struct: %s\n" dep)
                         struct_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - datatype: %s\n" dep)
                         datatype_deps);
                     Printf.printf "\n")
                   else if List.length stale_deps > 0 then (
                     Printf.printf
                       "[STALE] %s (was: %s)\n\
                       \  Location: %s\n\
                       \  Reason: Dependencies changed\n\
                       \  Stale dependencies:\n"
                       sym_str
                       status_str
                       file_path;
                     List.iter
                       (fun (dep, reason) -> Printf.printf "    - %s (%s)\n" dep reason)
                       stale_deps;
                     Printf.printf "  Action: Will re-verify\n\n")
                   else (
                     Printf.printf
                       "[CACHED] %s (%s)\n\
                       \  Location: %s\n\
                       \  Reason: Hashes match, dependencies unchanged\n\
                       \  Content hash: %s\n\
                       \  Spec hash: %s\n"
                       sym_str
                       (String.lowercase_ascii status_str)
                       file_path
                       content_hash
                       spec_hash;
                     if
                       List.length call_deps
                       + List.length pred_deps
                       + List.length logfn_deps
                       + List.length struct_deps
                       + List.length datatype_deps
                       > 0
                     then (
                       Printf.printf "  Dependencies:\n";
                       List.iter
                         (fun dep -> Printf.printf "    - calls: %s\n" dep)
                         call_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - predicate: %s\n" dep)
                         pred_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - logical function: %s\n" dep)
                         logfn_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - struct: %s\n" dep)
                         struct_deps;
                       List.iter
                         (fun dep -> Printf.printf "    - datatype: %s\n" dep)
                         datatype_deps);
                     Printf.printf "  Action: Will skip verification\n\n"))
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
      & opt string ".cn/verification.db"
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
