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
            (* Compute all current hashes like verify does *)
            let current_hashes = Hashtbl.create (List.length c_functions) in
            let@ () =
              let rec compute_hashes = function
                | [] -> return ()
                | (fsym, (loc, args_and_body)) :: rest ->
                  let@ _loc, ft_opt, _sig = Global.get_fun_decl loc fsym in
                  let spec_hash = ContentHash.hash_function_spec ft_opt in
                  let content_hash = ContentHash.hash_args_and_body args_and_body in
                  Hashtbl.add current_hashes (Sym.pp_string fsym) (content_hash, spec_hash);
                  compute_hashes rest
              in
              compute_hashes c_functions
            in
            (* Compute current hashes for all predicates *)
            let current_pred_hashes =
              Hashtbl.create (Sym.Map.cardinal global.resource_predicates)
            in
            let@ () =
              Sym.Map.fold
                (fun pred_sym pred_def acc ->
                   let@ () = acc in
                   let pred_hash = ContentHash.hash_predicate pred_def in
                   Hashtbl.add current_pred_hashes (Sym.pp_string pred_sym) pred_hash;
                   return ())
                global.resource_predicates
                (return ())
            in
            (* Compute current hashes for all logical functions *)
            let current_lf_hashes =
              Hashtbl.create (Sym.Map.cardinal global.logical_functions)
            in
            let@ () =
              Sym.Map.fold
                (fun lf_sym lf_def acc ->
                   let@ () = acc in
                   let lf_hash = ContentHash.hash_logical_function lf_def in
                   Hashtbl.add current_lf_hashes (Sym.pp_string lf_sym) lf_hash;
                   return ())
                global.logical_functions
                (return ())
            in
            (* Compute current hashes for all structs *)
            let current_struct_hashes =
              Hashtbl.create (Sym.Map.cardinal global.struct_decls)
            in
            Sym.Map.iter
              (fun struct_sym struct_decl ->
                 let struct_hash = ContentHash.hash_struct_definition struct_decl in
                 Hashtbl.add current_struct_hashes (Sym.pp_string struct_sym) struct_hash)
              global.struct_decls;
            (* Compute current hashes for all datatypes *)
            let current_datatype_hashes =
              Hashtbl.create (Sym.Map.cardinal global.datatypes)
            in
            Sym.Map.iter
              (fun dt_sym dt_info ->
                 let dt_hash = ContentHash.hash_datatype_definition dt_info in
                 Hashtbl.add current_datatype_hashes (Sym.pp_string dt_sym) dt_hash)
              global.datatypes;
            (* Analyze each function using the same logic as verify *)
            List.iter
              (fun (sym, (loc, _args_and_body)) ->
                 let sym_str = Sym.pp_string sym in
                 let file_path =
                   Option.value (Cerb_location.get_filename loc) ~default:"<unknown>"
                 in
                 let content_hash, spec_hash = Hashtbl.find current_hashes sym_str in
                 (* Use the same staleness check as verify *)
                 match
                   Check.check_function_staleness
                     db
                     sym_str
                     content_hash
                     spec_hash
                     current_pred_hashes
                     current_lf_hashes
                     current_struct_hashes
                     current_datatype_hashes
                     current_hashes
                 with
                 | None ->
                   (* Up to date *)
                   (match VerificationDb.get_function_status db sym_str with
                    | Some record ->
                      let status_str =
                        match record.VerificationDb.status with
                        | VerificationDb.Pass -> "pass"
                        | VerificationDb.Fail -> "fail"
                        | VerificationDb.Stale -> "stale"
                        | VerificationDb.Unknown -> "unknown"
                      in
                      Printf.printf
                        "[CACHED] %s (%s)\n\
                        \  Location: %s\n\
                        \  Action: Will skip verification\n\n"
                        sym_str
                        status_str
                        file_path
                    | None -> ())
                 | Some reasons ->
                   (* Stale - print detailed reasons *)
                   let status_str =
                     match VerificationDb.get_function_status db sym_str with
                     | Some record ->
                       (match record.VerificationDb.status with
                        | VerificationDb.Pass -> "PASS"
                        | VerificationDb.Fail -> "FAIL"
                        | VerificationDb.Stale -> "STALE"
                        | VerificationDb.Unknown -> "UNKNOWN")
                     | None -> "NEW"
                   in
                   Printf.printf "[STALE] %s (was: %s)\n" sym_str status_str;
                   Printf.printf "  Location: %s\n" file_path;
                   Printf.printf "  Reasons:\n";
                   List.iter
                     (fun reason ->
                        match reason with
                        | Check.NotInCache -> Printf.printf "    - Not in cache\n"
                        | Check.ContentChanged { old_hash; new_hash } ->
                          Printf.printf
                            "    - Content changed (old: %s, new: %s)\n"
                            (String.sub old_hash 0 (min 8 (String.length old_hash)))
                            (String.sub new_hash 0 (min 8 (String.length new_hash)))
                        | Check.SpecChanged { old_hash; new_hash } ->
                          Printf.printf
                            "    - Spec changed (old: %s, new: %s)\n"
                            (String.sub old_hash 0 (min 8 (String.length old_hash)))
                            (String.sub new_hash 0 (min 8 (String.length new_hash)))
                        | Check.PredicateChanged preds ->
                          Printf.printf
                            "    - Predicate dependencies changed: %s\n"
                            (String.concat ", " preds)
                        | Check.StructChanged structs ->
                          Printf.printf
                            "    - Struct dependencies changed: %s\n"
                            (String.concat ", " structs)
                        | Check.DatatypeChanged datatypes ->
                          Printf.printf
                            "    - Datatype dependencies changed: %s\n"
                            (String.concat ", " datatypes)
                        | Check.CalleeSpecChanged callees ->
                          Printf.printf
                            "    - Called function specs changed: %s\n"
                            (String.concat ", " callees)
                        | Check.LogicalFunctionChanged lfs ->
                          Printf.printf
                            "    - Logical function dependencies changed: %s\n"
                            (String.concat ", " lfs))
                     reasons;
                   Printf.printf "  Action: Will re-verify\n\n")
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
