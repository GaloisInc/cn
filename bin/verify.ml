module CF = Cerb_frontend
module CB = Cerb_backend
open Cn

let verify
      filename
      cc
      macros
      permissive
      incl_dirs
      incl_files
      loc_pp
      debug_level
      print_level
      print_sym_nums
      no_timestamps
      json
      json_trace
      output_dir
      diag
      lemmata
      coq_export_file
      coq_mucore
      coq_proof_log
      coq_check_proof_log
      only
      skip
      csv_times
      solver_logging
      solver_flags
      solver_path
      solver_type
      solver_inc_enabled
      solver_inc_timeout
      astprints
      dont_use_vip
      fail_fast
      quiet
      no_inherit_loc
      magic_comment_char_dollar
      allow_split_magic_comments
      disable_resource_derived_constraints
      try_hard
      disable_unfold_multiclause_preds
      check_consistency
      no_produce_models
      no_state_html
      no_explore_root_cause
      profile
      enable_query_cache
      clear_query_cache
      use_db
      db_path
      clear_db
      db_stats
      portfolio
      portfolio_always
      portfolio_timeout
  =
  if json then (
    if debug_level > 0 then
      CF.Pp_errors.fatal "debug level must be 0 for json output";
    if print_level > 0 then
      CF.Pp_errors.fatal "print level must be 0 for json output");
  (*flags *)
  Cerb_debug.debug_level := debug_level;
  Pp.loc_pp := loc_pp;
  Pp.print_level := print_level;
  Sym.print_nums := print_sym_nums;
  Pp.print_timestamps := not no_timestamps;
  TypeErrors.explore_root_cause := not no_explore_root_cause;
  Timing.enabled := profile;
  Query_cache.enabled := enable_query_cache;
  if clear_query_cache then Query_cache.clear ();
  (* Open verification database if requested *)
  let db_handle =
    if use_db then (
      (* Create .cn directory if it doesn't exist *)
      let db_dir = Filename.dirname db_path in
      (try Unix.mkdir db_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let db = VerificationDb.open_db db_path in
      VerificationDb.init_schema db;
      if clear_db then VerificationDb.clear_all db;
      Some db)
    else
      None
  in
  (match solver_logging with
   | Some d ->
     Solver.Logger.to_file := true;
     Solver.Logger.dir := if String.equal d "" then None else Some d
   | _ -> ());
  Solver.solver_path := solver_path;
  Solver.solver_type := solver_type;
  Solver.solver_flags := solver_flags;
  Solver.try_hard := try_hard;
  Solver.inc_enabled := solver_inc_enabled;
  Solver.inc_timeout := solver_inc_timeout;
  (* Portfolio configuration *)
  Solver.use_portfolio := portfolio;
  Solver.portfolio_always := portfolio_always;
  Solver.portfolio_timeout := portfolio_timeout;
  (* Disable models when query cache is enabled (can't cache model state) *)
  Solver.produce_models := (not no_produce_models) && not enable_query_cache;
  IndexTerms.use_vip := not dont_use_vip;
  Check.fail_fast := fail_fast;
  Diagnostics.diag_string := diag;
  Resource.disable_resource_derived_constraints := disable_resource_derived_constraints;
  (* Set the prooflog flag based on --coq-proof-log *)
  Prooflog.set_enabled coq_proof_log;
  Typing.unfold_multiclause_preds := not disable_unfold_multiclause_preds;
  let filename = Common.there_can_only_be_one filename in
  Common.with_well_formedness_check (* CLI arguments *)
    ~filename
    ~cc
    ~macros:(("__CN_VERIFY", None) :: macros)
    ~permissive
    ~incl_dirs
    ~incl_files
    ~coq_export_file
    ~coq_mucore
    ~coq_proof_log
    ~coq_check_proof_log
    ~csv_times
    ~astprints
    ~no_inherit_loc
    ~magic_comment_char_dollar
    ~allow_split_magic_comments
    ~save_cpp:None
    ~disable_linemarkers:false
    ~skip_label_inlining:false
    ~handle_error:
      (Common.handle_type_error
         ~json
         ?output_dir
         ~serialize_json:json_trace
         ~generate_state_html:(not no_state_html))
    ~f:(fun ~cabs_tunit:_ ~prog5:_ ~ail_prog:_ ~statement_locs:_ ~paused ->
      let check (functions, global_var_constraints, lemmas) =
        let open Typing in
        let@ errors =
          Check.time_check_c_functions
            (skip, only)
            check_consistency
            ?db:db_handle
            (global_var_constraints, functions)
        in
        if not quiet then
          List.iter
            (fun (fn, err) ->
               Common.report_type_error
                 ~json
                 ?output_dir
                 ~fn_name:fn
                 ~serialize_json:json_trace
                 ~generate_state_html:(not no_state_html)
                 err)
            errors;
        Timing.print_stats ();
        Query_cache.print_stats ();
        (* Show portfolio statistics *)
        Solver.print_portfolio_stats ();
        (* Show database statistics if requested *)
        (match db_handle with
         | Some _db when db_stats ->
           (* TODO: implement print_statistics *)
           Printf.printf "\nVerification Database Statistics:\n";
           Printf.printf "  Database: %s\n" db_path
         | _ -> ());
        (* Close database *)
        Option.iter (fun db -> ignore (VerificationDb.close_db db)) db_handle;
        Option.fold ~none:() ~some:exit (Common.exit_code_of_errors (List.map snd errors));
        Check.generate_lemmas lemmas lemmata
      in
      Typing.run_from_pause check paused)


open Cmdliner

module Flags = struct
  let loc_pp =
    let doc = "Print pointer values as hexadecimal or as decimal values (hex | dec)" in
    Arg.(
      value
      & opt (enum [ ("hex", Pp.Hex); ("dec", Pp.Dec) ]) !Pp.loc_pp
      & info [ "locs" ] ~docv:"HEX" ~doc)


  let fail_fast =
    let doc = "Abort immediately after encountering a verification error" in
    Arg.(value & flag & info [ "fail-fast" ] ~doc)


  let quiet =
    let doc = "Only report success and failure, rather than rich errors" in
    Arg.(value & flag & info [ "quiet" ] ~doc)


  let diag =
    let doc = "explore branching diagnostics with key string" in
    Arg.(value & opt (some string) None & info [ "diag" ] ~doc)


  let solver_logging =
    let doc = "Log solver queries in SMT2 format to a directory." in
    Arg.(value & opt (some string) None & info [ "solver-logging" ] ~docv:"DIR" ~doc)


  let solver_flags =
    let doc =
      "Ovewrite default solver flags. Note that flags should enable at least incremental \
       checking."
    in
    Arg.(
      value & opt (some (list string)) None & info [ "solver-flags" ] ~docv:"X,Y,Z" ~doc)


  let solver_path =
    let doc = "Path to SMT solver executable" in
    Arg.(value & opt (some file) None & info [ "solver-path" ] ~docv:"FILE" ~doc)


  let solver_type =
    let doc = "Specify the SMT solver interface" in
    Arg.(
      value
      & opt (some (enum [ ("z3", Simple_smt.Z3); ("cvc5", Simple_smt.CVC5) ])) None
      & info [ "solver-type" ] ~docv:"z3|cvc5" ~doc)


  let solver_inc_enabled =
    let doc = "Enable or disable incremental SMT solving." in
    Arg.(value & opt bool !Solver.inc_enabled & info [ "incremental-solving" ] ~doc)


  let solver_inc_timeout =
    let doc =
      "Timeout after which a non-incremental SMT solver replaces the incremental solver"
    in
    Arg.(
      value
      & opt (some int) !Solver.inc_timeout
      & info [ "incremental-solver-timeout" ] ~doc)


  let portfolio_flag =
    let doc =
      "Enable adaptive portfolio mode: try incremental solver first, spawn Z3+CVC5 in \
       parallel if timeout expires. Best for projects with mixed query difficulty."
    in
    Arg.(value & flag & info [ "portfolio" ] ~doc)


  let portfolio_always_flag =
    let doc =
      "Always use portfolio mode (Z3+CVC5 in parallel), bypassing incremental solving. \
       Requires ~2x memory during query execution."
    in
    Arg.(value & flag & info [ "portfolio-always" ] ~doc)


  let portfolio_timeout_flag =
    let doc =
      "Timeout in seconds before spawning portfolio (default: 0.5). Only applies when \
       --portfolio is enabled."
    in
    Arg.(value & opt float 0.5 & info [ "portfolio-timeout" ] ~docv:"SECONDS" ~doc)


  let try_hard =
    let doc = "Try undecidable SMT solving using full set of assumptions" in
    Arg.(value & flag & info [ "try-hard" ] ~doc)


  let only =
    let doc = "Only type-check this function (or comma-separated names)" in
    Arg.(value & opt (list string) [] & info [ "only" ] ~doc)


  let skip =
    let doc = "Skip type-checking of this function (or comma-separated names)" in
    Arg.(value & opt (list string) [] & info [ "skip" ] ~doc)


  (* TODO remove this when VIP impl complete *)
  let dont_use_vip =
    let doc = "(temporary) disable VIP rules" in
    Arg.(value & flag & info [ "no-vip" ] ~doc)


  let json =
    let doc = "output summary in JSON format" in
    Arg.(value & flag & info [ "json" ] ~doc)


  let json_trace =
    let doc = "output state trace files as JSON, in addition to HTML" in
    Arg.(value & flag & info [ "json-trace" ] ~doc)


  let output_dir =
    let doc = "directory in which to output state files" in
    Arg.(value & opt (some dir) None & info [ "output-dir" ] ~docv:"DIR" ~doc)


  let disable_resource_derived_constraints =
    let doc = "disable resource-derived constraints" in
    Arg.(value & flag & info [ "disable-resource-derived-constraints" ] ~doc)


  let disable_unfold_multiclause_preds =
    let doc =
      "do not automatically unfold predicates with multiple (if-then-else) clauses"
    in
    Arg.(value & flag & info [ "disable-multiclause-predicate-unfolding" ] ~doc)


  let check_consistency =
    let doc =
      "check consistency of predicate definitions, function specifications, and lemmas"
    in
    Arg.(value & flag & info [ "check-consistency" ] ~doc)


  let no_produce_models =
    let doc = "disable SMT model generation (counterexamples) for improved performance" in
    Arg.(value & flag & info [ "no-produce-models" ] ~doc)


  let no_state_html =
    let doc = "disable HTML state file generation" in
    Arg.(value & flag & info [ "no-state-html" ] ~doc)


  let no_explore_root_cause =
    let doc = "disable expression exploration for root-cause analysis" in
    Arg.(value & flag & info [ "no-explore-root-cause" ] ~doc)


  let profile =
    let doc = "enable performance profiling and print timing statistics" in
    Arg.(value & flag & info [ "profile" ] ~doc)


  let enable_query_cache =
    let doc = "enable query caching with alpha-renaming normalization" in
    Arg.(value & flag & info [ "query-cache" ] ~doc)


  let clear_query_cache =
    let doc = "clear query cache before starting" in
    Arg.(value & flag & info [ "clear-query-cache" ] ~doc)


  let use_db =
    let doc =
      "enable verification status database for incremental checking (EXPERIMENTAL)"
    in
    Arg.(value & flag & info [ "use-db"; "verification-db" ] ~doc)


  let db_path =
    let doc = "path to verification database file (default: .cn/verification.db)" in
    Arg.(value & opt string ".cn/verification.db" & info [ "db-path" ] ~docv:"PATH" ~doc)


  let clear_db =
    let doc = "clear verification database before run" in
    Arg.(value & flag & info [ "clear-db" ] ~doc)


  let db_stats =
    let doc = "show verification database statistics after run" in
    Arg.(value & flag & info [ "db-stats" ] ~doc)
end

module Lemma_flags = struct
  let lemmata =
    let doc = "lemmata generation mode (target filename)" in
    Arg.(value & opt (some string) None & info [ "lemmata" ] ~docv:"FILE" ~doc)
end

module CoqExport_flags = struct
  let coq_export =
    let doc = "File to export to coq defintions" in
    Arg.(value & opt (some string) None & info [ "coq-export-file" ] ~docv:"FILE" ~doc)
end

module CoqMucore_flags = struct
  let coq_mucore =
    let doc = "include mu-core AST in coq export" in
    Arg.(value & flag & info [ "coq-mucore" ] ~doc)
end

module CoqProofLog_flags = struct
  let coq_proof_log =
    let doc = "include proof log in coq export" in
    Arg.(value & flag & info [ "coq-proof-log" ] ~doc)
end

module CoqCheckProofLog_flags = struct
  let coq_check_proof_log =
    let doc = "Include statements to check proof log in coq exported file" in
    Arg.(value & flag & info [ "coq-check-proof-log" ] ~doc)
end

let verify_t : unit Term.t =
  let open Term in
  const verify
  $ Common.Flags.file
  $ Common.Flags.cc
  $ Common.Flags.macros
  $ Common.Flags.permissive
  $ Common.Flags.incl_dirs
  $ Common.Flags.incl_files
  $ Flags.loc_pp
  $ Common.Flags.debug_level
  $ Common.Flags.print_level
  $ Common.Flags.print_sym_nums
  $ Common.Flags.no_timestamps
  $ Flags.json
  $ Flags.json_trace
  $ Flags.output_dir
  $ Flags.diag
  $ Lemma_flags.lemmata
  $ CoqExport_flags.coq_export
  $ CoqMucore_flags.coq_mucore
  $ CoqProofLog_flags.coq_proof_log
  $ CoqCheckProofLog_flags.coq_check_proof_log
  $ Flags.only
  $ Flags.skip
  $ Common.Flags.csv_times
  $ Flags.solver_logging
  $ Flags.solver_flags
  $ Flags.solver_path
  $ Flags.solver_type
  $ Flags.solver_inc_enabled
  $ Flags.solver_inc_timeout
  $ Common.Flags.astprints
  $ Flags.dont_use_vip
  $ Flags.fail_fast
  $ Flags.quiet
  $ Common.Flags.no_inherit_loc
  $ Common.Flags.magic_comment_char_dollar
  $ Common.Flags.allow_split_magic_comments
  $ Flags.disable_resource_derived_constraints
  $ Flags.try_hard
  $ Flags.disable_unfold_multiclause_preds
  $ Flags.check_consistency
  $ Flags.no_produce_models
  $ Flags.no_state_html
  $ Flags.no_explore_root_cause
  $ Flags.profile
  $ Flags.enable_query_cache
  $ Flags.clear_query_cache
  $ Flags.use_db
  $ Flags.db_path
  $ Flags.clear_db
  $ Flags.db_stats
  $ Flags.portfolio_flag
  $ Flags.portfolio_always_flag
  $ Flags.portfolio_timeout_flag


let cmd =
  let doc =
    "Verifies that functions meet\n\
    \    their CN specifications and the\n\
    \    absence of undefined behavior."
  in
  let info = Cmd.info "verify" ~doc in
  Cmd.v info verify_t
