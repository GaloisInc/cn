module CF = Cerb_frontend
module Cn_to_ail = Cn_to_ail
module A = CF.AilSyntax
module C = CF.Ctype
module Extract = Extract
module Globals = Globals
module Internal = Internal
module Records = Records
module Ownership = Ownership
module Utils = Utils

(* ===== AST Rewriting: Memory Accesses ===== *)

(* Rewrite memory access expressions in-place in the AST.
   - AilErvalue(lv) -> AilEcall(CN_LOAD, [lv])
   - AilEassign(lv, e) -> AilEcall(CN_STORE, [lv, e])
   - AilEcompoundAssign(lv, op, e) -> AilEcall(CN_STORE_OP, [lv, op_expr, e])
   - AilEunary(PostfixIncr/Decr, lv) -> AilEcall(CN_POSTFIX, [lv, op_str]) *)
let rewrite_memory_accesses_in_sigma (sigm : CF.GenTypes.genTypeCategory A.sigma)
  : CF.GenTypes.genTypeCategory A.sigma
  =
  let mk_expr = Utils.mk_expr in
  let mk_ident s = mk_expr (A.AilEident (Sym.fresh s)) in
  let string_of_aop aop =
    match aop with
    | A.Mul -> "*"
    | Div -> "/"
    | Mod -> "%"
    | Add -> "+"
    | Sub -> "-"
    | Shl -> "<<"
    | Shr -> ">>"
    | Band -> "&"
    | Bxor -> "^"
    | Bor -> "|"
  in
  let rec rewrite_expr (A.AnnotatedExpression (gtc, strs, loc, e_)) =
    let rewrap e_' = A.AnnotatedExpression (gtc, strs, loc, e_') in
    match e_ with
    | A.AilErvalue lv ->
      let lv' = rewrite_expr lv in
      rewrap (A.AilEcall (mk_ident "CN_LOAD", [ lv' ]))
    | A.AilEassign (lv, e) ->
      let lv' = rewrite_expr lv in
      let e' = rewrite_expr e in
      rewrap (A.AilEcall (mk_ident "CN_STORE", [ lv'; e' ]))
    | A.AilEcompoundAssign (lv, aop, e) ->
      let lv' = rewrite_expr lv in
      let e' = rewrite_expr e in
      let aop_expr = mk_expr (A.AilEident (Sym.fresh (string_of_aop aop))) in
      rewrap (A.AilEcall (mk_ident "CN_STORE_OP", [ lv'; aop_expr; e' ]))
    | A.AilEunary (A.PostfixIncr, lv) ->
      let lv' = rewrite_expr lv in
      let op_expr = mk_expr (A.AilEident (Sym.fresh "++")) in
      rewrap (A.AilEcall (mk_ident "CN_POSTFIX", [ lv'; op_expr ]))
    | A.AilEunary (A.PostfixDecr, lv) ->
      let lv' = rewrite_expr lv in
      let op_expr = mk_expr (A.AilEident (Sym.fresh "--")) in
      rewrap (A.AilEcall (mk_ident "CN_POSTFIX", [ lv'; op_expr ]))
    (* Recursively rewrite sub-expressions *)
    | AilEunary (op, e) -> rewrap (AilEunary (op, rewrite_expr e))
    | AilEcast (q, ct, e) -> rewrap (AilEcast (q, ct, rewrite_expr e))
    | AilEbinary (e1, op, e2) ->
      rewrap (AilEbinary (rewrite_expr e1, op, rewrite_expr e2))
    | AilEcond (e1, e2_opt, e3) ->
      rewrap (AilEcond (rewrite_expr e1, Option.map rewrite_expr e2_opt, rewrite_expr e3))
    | AilEcall (e, es) -> rewrap (AilEcall (rewrite_expr e, List.map rewrite_expr es))
    | AilEassert e -> rewrap (AilEassert (rewrite_expr e))
    | AilEcompound (q, ct, e) -> rewrap (AilEcompound (q, ct, rewrite_expr e))
    | AilEmemberof (e, m) -> rewrap (AilEmemberof (rewrite_expr e, m))
    | AilEmemberofptr (e, m) -> rewrap (AilEmemberofptr (rewrite_expr e, m))
    | AilEannot (ct, e) -> rewrap (AilEannot (ct, rewrite_expr e))
    | AilEva_start (e, s) -> rewrap (AilEva_start (rewrite_expr e, s))
    | AilEva_arg (e, ct) -> rewrap (AilEva_arg (rewrite_expr e, ct))
    | AilEva_end e -> rewrap (AilEva_end (rewrite_expr e))
    | AilEva_copy (e1, e2) -> rewrap (AilEva_copy (rewrite_expr e1, rewrite_expr e2))
    | AilEprint_type e -> rewrap (AilEprint_type (rewrite_expr e))
    | AilEbmc_assume e -> rewrap (AilEbmc_assume (rewrite_expr e))
    | AilEarray_decay e -> rewrite_expr e
    | AilEfunction_decay e -> rewrite_expr e
    | AilEatomic e -> rewrap (AilEatomic (rewrite_expr e))
    | AilEunion (t, m, Some e) -> rewrap (AilEunion (t, m, Some (rewrite_expr e)))
    | AilEgeneric (e, ct, gas) ->
      let gas' =
        List.map
          (function
            | A.AilGAtype (q, ct, e) -> A.AilGAtype (q, ct, rewrite_expr e)
            | A.AilGAdefault e -> A.AilGAdefault (rewrite_expr e))
          gas
      in
      rewrap (AilEgeneric (rewrite_expr e, ct, gas'))
    | AilEarray (q, ct, xs) ->
      rewrap (AilEarray (q, ct, List.map (Option.map rewrite_expr) xs))
    | AilEstruct (tag, xs) ->
      rewrap
        (AilEstruct
           (tag, List.map (fun (m, e_opt) -> (m, Option.map rewrite_expr e_opt)) xs))
    | AilEgcc_statement (bs, ss) ->
      rewrap (AilEgcc_statement (bs, List.map rewrite_stmt ss))
    | AilEsizeof_expr e -> rewrap (AilEsizeof_expr (rewrite_expr e))
    (* Leaf nodes *)
    | AilEunion (_, _, None)
    | AilEoffsetof _ | AilEbuiltin _ | AilEstr _ | AilEconst _ | AilEident _
    | AilEsizeof _ | AilEalignof _ | AilEreg_load _ | AilEinvalid _ ->
      rewrap e_
  and rewrite_stmt (A.{ loc; desug_info; attrs; node = s_ } as _stmt) =
    let rewrap s_' = A.{ loc; desug_info; attrs; node = s_' } in
    match s_ with
    | A.AilSexpr e -> rewrap (A.AilSexpr (rewrite_expr e))
    | AilSreturn e -> rewrap (AilSreturn (rewrite_expr e))
    | AilSblock (bs, ss) -> rewrap (AilSblock (bs, List.map rewrite_stmt ss))
    | AilSif (e, s1, s2) ->
      rewrap (AilSif (rewrite_expr e, rewrite_stmt s1, rewrite_stmt s2))
    | AilSwhile (e, s, annot) ->
      rewrap (AilSwhile (rewrite_expr e, rewrite_stmt s, annot))
    | AilSdo (s, e, annot) -> rewrap (AilSdo (rewrite_stmt s, rewrite_expr e, annot))
    | AilSswitch (e, s) -> rewrap (AilSswitch (rewrite_expr e, rewrite_stmt s))
    | AilScase (c, s) -> rewrap (AilScase (c, rewrite_stmt s))
    | AilScase_rangeGNU (c1, c2, s) -> rewrap (AilScase_rangeGNU (c1, c2, rewrite_stmt s))
    | AilSdefault s -> rewrap (AilSdefault (rewrite_stmt s))
    | AilSlabel (l, s, annot) -> rewrap (AilSlabel (l, rewrite_stmt s, annot))
    | AilSmarker (m, s) -> rewrap (AilSmarker (m, rewrite_stmt s))
    | AilSpar ss -> rewrap (AilSpar (List.map rewrite_stmt ss))
    | AilSreg_store (r, e) -> rewrap (AilSreg_store (r, rewrite_expr e))
    | AilSdeclaration decls ->
      let decls' =
        List.map (fun (sym, e_opt) -> (sym, Option.map rewrite_expr e_opt)) decls
      in
      rewrap (AilSdeclaration decls')
    | AilSskip | AilSbreak | AilScontinue | AilSreturnVoid | AilSgoto _ -> rewrap s_
  in
  let function_definitions =
    List.map
      (fun (sym, (loc, n, attrs, params, body)) ->
         (sym, (loc, n, attrs, params, rewrite_stmt body)))
      sigm.function_definitions
  in
  { sigm with function_definitions }


(* ===== AST Rewriting: Ensure Block Bodies ===== *)

(* Lifetime of compound literals can change if enclosed in a block, so check *)
let contains_compound_literal s =
  let rec aux_expr (A.AnnotatedExpression (_, _, _, e_)) =
    match e_ with
    | AilEcompound _ -> true
    | AilEgcc_statement (_, ss) -> List.exists aux_stmt ss
    | AilEunion (_, _, None)
    | AilEoffsetof _ | AilEbuiltin _ | AilEstr _ | AilEconst _ | AilEident _
    | AilEsizeof _ | AilEalignof _ | AilEreg_load _ | AilEinvalid _ ->
      false
    | AilEsizeof_expr e
    | AilErvalue e
    | AilEunary (_, e)
    | AilEcast (_, _, e)
    | AilEassert e
    | AilEunion (_, _, Some e)
    | AilEmemberof (e, _)
    | AilEmemberofptr (e, _)
    | AilEannot (_, e)
    | AilEva_start (e, _)
    | AilEva_arg (e, _)
    | AilEva_end e
    | AilEprint_type e
    | AilEbmc_assume e
    | AilEarray_decay e
    | AilEfunction_decay e
    | AilEatomic e ->
      aux_expr e
    | AilEbinary (e1, _, e2)
    | AilEcond (e1, None, e2)
    | AilEva_copy (e1, e2)
    | AilEassign (e1, e2)
    | AilEcompoundAssign (e1, _, e2) ->
      aux_expr e1 || aux_expr e2
    | AilEcond (e1, Some e2, e3) -> aux_expr e1 || aux_expr e2 || aux_expr e3
    | AilEcall (e, es) -> aux_expr e || List.exists aux_expr es
    | AilEgeneric (e, _, gas) ->
      aux_expr e
      || List.exists (function A.AilGAtype (_, _, e) | AilGAdefault e -> aux_expr e) gas
    | AilEarray (_, _, xs) ->
      List.exists (function None -> false | Some e -> aux_expr e) xs
    | AilEstruct (_, xs) ->
      List.exists (function _, None -> false | _, Some e -> aux_expr e) xs
  and aux_stmt A.{ node = s_; _ } =
    match s_ with
    | A.(AilSdeclaration decls) ->
      List.exists
        (fun (_, e_opt) -> match e_opt with Some e -> aux_expr e | None -> false)
        decls
    | AilSblock (_, ss) -> List.exists aux_stmt ss
    | AilSif (e, s1, s2) -> aux_expr e || aux_stmt s1 || aux_stmt s2
    | AilSwhile (e, s, _) | AilSdo (s, e, _) | AilSswitch (e, s) ->
      aux_expr e || aux_stmt s
    | AilScase (_, s) | AilScase_rangeGNU (_, _, s) | AilSdefault s | AilSlabel (_, s, _)
      ->
      aux_stmt s
    | AilSreturn e | AilSexpr e | AilSreg_store (_, e) -> aux_expr e
    | AilSgoto _ | AilScontinue | AilSbreak | AilSskip | AilSreturnVoid | AilSpar _
    | AilSmarker _ ->
      false
  in
  aux_stmt s


let wrap_in_block s = Utils.mk_stmt (A.AilSblock ([], [ s ]))

let ensure_block_bodies_stmt stmt =
  let is_single_stat A.{ node = s_; _ } =
    match s_ with
    | A.(
        ( AilSexpr _ | AilSreturn _ | AilSgoto _ | AilScontinue | AilSbreak | AilSskip
        | AilSreturnVoid )) ->
      true
    | _ -> false
  in
  let should_wrap s = is_single_stat s && not (contains_compound_literal s) in
  let rec aux_stmt stmt =
    let rewrap s_' = A.{ stmt with node = s_' } in
    let is_forloop_body A.{ desug_info; _ } = desug_info.is_forloop_body in
    let stmt =
      if is_forloop_body stmt then
        rewrap (A.AilSblock ([], [ stmt ]))
      else
        stmt
    in
    match stmt.node with
    | A.AilSblock (bs, ss) -> rewrap (AilSblock (bs, List.map aux_stmt ss))
    | AilSif (e, s1, s2) ->
      let s1' = if should_wrap s1 then wrap_in_block (aux_stmt s1) else aux_stmt s1 in
      let s2' = if should_wrap s2 then wrap_in_block (aux_stmt s2) else aux_stmt s2 in
      rewrap (AilSif (e, s1', s2'))
    | AilSwhile (e, s, annot) ->
      let s' = if should_wrap s then wrap_in_block (aux_stmt s) else aux_stmt s in
      rewrap (AilSwhile (e, s', annot))
    | AilSdo (s, e, annot) ->
      let s' = if should_wrap s then wrap_in_block (aux_stmt s) else aux_stmt s in
      rewrap (AilSdo (s', e, annot))
    | AilSswitch (e, s) ->
      let s' = if should_wrap s then wrap_in_block (aux_stmt s) else aux_stmt s in
      rewrap (AilSswitch (e, s'))
    | AilScase (c, s) ->
      let s' = if should_wrap s then wrap_in_block (aux_stmt s) else aux_stmt s in
      rewrap (AilScase (c, s'))
    | AilScase_rangeGNU (c1, c2, s) ->
      let s' = if should_wrap s then wrap_in_block (aux_stmt s) else aux_stmt s in
      rewrap (AilScase_rangeGNU (c1, c2, s'))
    | AilSdefault s -> rewrap (AilSdefault (aux_stmt s))
    | AilSlabel (l, s, annot) -> rewrap (AilSlabel (l, aux_stmt s, annot))
    | AilSmarker (m, s) -> rewrap (AilSmarker (m, aux_stmt s))
    | _ -> stmt
  in
  aux_stmt stmt


let ensure_all_block_bodies (sigm : CF.GenTypes.genTypeCategory A.sigma) =
  let function_definitions =
    List.map
      (fun (sym, (loc, n, attrs, params, body)) ->
         (sym, (loc, n, attrs, params, ensure_block_bodies_stmt body)))
      sigm.function_definitions
  in
  { sigm with function_definitions }


(* ===== AST Modification: Instrument Function Bodies ===== *)

(* Convert ail_bs_and_ss to a list of statements, wrapping in a block if there are bindings *)
let bs_and_ss_to_stmts ((bs, ss) : Internal.ail_bs_and_ss) =
  if List.is_empty bs then
    List.map Utils.mk_stmt ss
  else
    [ Utils.mk_stmt (A.AilSblock (bs, List.map Utils.mk_stmt ss)) ]


(* Extract bindings and statements separately *)
let extract_bs_and_ss ((bs, ss) : Internal.ail_bs_and_ss) = (bs, List.map Utils.mk_stmt ss)

(* Context for the unified ownership + return-rewriting walk *)
type ownership_ctx =
  { in_scope_vars : (Sym.t * C.ctype) list;
    break_vars : (Sym.t * C.ctype) list;
    continue_vars : (Sym.t * C.ctype) list;
    cn_ret_sym : Sym.t;
    epilogue_sym : Sym.t;
    is_void : bool;
    loop_invariants : Cn_to_ail.loop_info list;
    in_stmt_injs : (Cerb_location.t * Internal.ail_bs_and_ss) list ref
  }

(* Generate ownership entry stmts for a list of declared variables *)
let make_entry_stmts vars =
  List.concat_map
    (fun (sym, ctype) ->
       let bs, ss = Ownership.generate_c_local_ownership_entry_bs_and_ss (sym, ctype) in
       if List.is_empty bs then
         List.map Utils.mk_stmt ss
       else
         [ Utils.mk_stmt (A.AilSblock (bs, List.map Utils.mk_stmt ss)) ])
    vars


(* Generate ownership exit stmts for a list of variables *)
let make_exit_stmts vars =
  List.map (fun v -> Utils.mk_stmt (Ownership.generate_c_local_ownership_exit v)) vars


(* Get declared variable types from a declaration statement *)
let get_declared_vars bindings decls =
  List.map (fun (sym, _) -> (sym, Utils.find_ctype_from_bindings bindings sym)) decls


(* Find a loop_info matching this statement's location *)
let find_loop_invariant loc loop_invariants =
  List.find_opt
    (fun (li : Cn_to_ail.loop_info) ->
       String.equal
         (Cerb_location.location_to_string loc)
         (Cerb_location.location_to_string li.loop_loc))
    loop_invariants


(* Check if an injection location falls between prev_loc and next_loc *)
let loc_line loc =
  match Cerb_location.to_cartesian_raw loc with
  | Some ((sl, _), _) -> Some sl
  | None -> None


(* Drain in_stmt_injs that should be inserted after a statement at the given line *)
let drain_in_stmt_injs_after stmt_loc next_loc_opt injs_ref =
  let stmt_line = loc_line stmt_loc in
  let next_line = Option.bind next_loc_opt loc_line in
  let matching, rest =
    List.partition
      (fun (inj_loc, _) ->
         let inj_line = loc_line inj_loc in
         match (stmt_line, inj_line, next_line) with
         | Some sl, Some il, Some nl -> il >= sl && il < nl
         | Some sl, Some il, None -> il >= sl
         | _ -> false)
      !injs_ref
  in
  injs_ref := rest;
  List.concat_map (fun (_, bs_and_ss) -> bs_and_ss_to_stmts bs_and_ss) matching


(* The unified walk: rewrites returns, inserts ownership entry/exit at block
   boundaries and control flow points, inserts loop invariants and in-stmt
   injections. *)
let rec instrument_stmt ctx bindings (stmt : CF.GenTypes.genTypeCategory A.statement) =
  let rewrap s_' = A.{ stmt with node = s_' } in
  match stmt.node with
  | A.AilSblock (bs, ss) ->
    let all_bindings = bs @ bindings in
    let new_ss, declared_vars = instrument_block_stmts ctx all_bindings [] ss in
    (* Add exit cleanup at end of block for all bindings declared in this block *)
    let block_binding_vars =
      List.map (fun (b_sym, ((_, _, _), _, _, b_ctype)) -> (b_sym, b_ctype)) bs
    in
    let exit_stmts = make_exit_stmts (declared_vars @ block_binding_vars) in
    rewrap (A.AilSblock (bs, new_ss @ exit_stmts))
  | A.AilSreturn e ->
    (* __cn_ret = e; cleanup_in_scope_vars; goto __cn_epilogue *)
    let cleanup_stmts = make_exit_stmts ctx.in_scope_vars in
    if ctx.is_void then
      rewrap
        (A.AilSblock ([], cleanup_stmts @ [ Utils.mk_stmt (A.AilSgoto ctx.epilogue_sym) ]))
    else
      rewrap
        (A.AilSblock
           ( [],
             [ Utils.mk_stmt
                 (A.AilSexpr
                    (Utils.mk_expr
                       (A.AilEassign (Utils.mk_expr (A.AilEident ctx.cn_ret_sym), e))))
             ]
             @ cleanup_stmts
             @ [ Utils.mk_stmt (A.AilSgoto ctx.epilogue_sym) ] ))
  | A.AilSreturnVoid ->
    let cleanup_stmts = make_exit_stmts ctx.in_scope_vars in
    rewrap
      (A.AilSblock ([], cleanup_stmts @ [ Utils.mk_stmt (A.AilSgoto ctx.epilogue_sym) ]))
  | A.AilSbreak ->
    let cleanup_stmts = make_exit_stmts ctx.break_vars in
    if List.is_empty cleanup_stmts then
      stmt
    else
      rewrap (A.AilSblock ([], cleanup_stmts @ [ Utils.mk_stmt A.AilSbreak ]))
  | A.AilSgoto _ ->
    (match stmt.desug_info.desug_case with
     | Some A.Desug_continue ->
       let cleanup_stmts = make_exit_stmts ctx.continue_vars in
       if List.is_empty cleanup_stmts then
         stmt
       else
         rewrap (A.AilSblock ([], cleanup_stmts @ [ stmt ]))
     | _ ->
       (* Real goto: clean up all in-scope vars *)
       let cleanup_stmts = make_exit_stmts ctx.in_scope_vars in
       if List.is_empty cleanup_stmts then
         stmt
       else
         rewrap (A.AilSblock ([], cleanup_stmts @ [ stmt ])))
  | A.AilSlabel (label_sym, s, label_annot_opt) ->
    let s' = instrument_stmt ctx bindings s in
    (* For real labels (not compiler-generated), re-enter scope for in-scope vars *)
    (match label_annot_opt with
     | None ->
       let entry_stmts =
         List.map
           (fun (sym, ctype) ->
              Utils.mk_stmt
                A.(
                  AilSexpr (Ownership.generate_c_local_ownership_entry_fcall (sym, ctype))))
           ctx.in_scope_vars
       in
       if List.is_empty entry_stmts then
         rewrap (A.AilSlabel (label_sym, s', label_annot_opt))
       else
         rewrap
           (A.AilSlabel
              ( label_sym,
                Utils.mk_stmt (A.AilSblock ([], entry_stmts @ [ s' ])),
                label_annot_opt ))
     | _ -> rewrap (A.AilSlabel (label_sym, s', label_annot_opt)))
  | A.AilSif (e, s1, s2) ->
    rewrap
      (A.AilSif (e, instrument_stmt ctx bindings s1, instrument_stmt ctx bindings s2))
  | A.AilSwhile (e, s, annot) ->
    let ctx' = { ctx with break_vars = []; continue_vars = [] } in
    let s' = instrument_stmt ctx' bindings s in
    (match find_loop_invariant stmt.loc ctx.loop_invariants with
     | Some loop_info ->
       let entry_stmts = bs_and_ss_to_stmts loop_info.loop_entry in
       let _cond_loc, cond_bs_and_ss = loop_info.cond in
       let cond_stmts = bs_and_ss_to_stmts cond_bs_and_ss in
       let exit_stmts_internal = bs_and_ss_to_stmts loop_info.loop_exit in
       let exit_stmts_external = bs_and_ss_to_stmts loop_info.loop_exit in
       (* Wrap loop body: cond check at top, exit at bottom *)
       let augmented_body =
         match s'.A.node with
         | A.AilSblock (bs, ss) ->
           A.{ s' with node = A.AilSblock (bs, cond_stmts @ ss @ exit_stmts_internal) }
         | _ ->
           Utils.mk_stmt (A.AilSblock ([], cond_stmts @ [ s' ] @ exit_stmts_internal))
       in
       (* Entry before loop, loop, exit after loop *)
       Utils.mk_stmt
         (A.AilSblock
            ( [],
              entry_stmts
              @ [ rewrap (A.AilSwhile (e, augmented_body, annot)) ]
              @ exit_stmts_external ))
     | None -> rewrap (A.AilSwhile (e, s', annot)))
  | A.AilSdo (s, e, annot) ->
    let ctx' = { ctx with break_vars = []; continue_vars = [] } in
    let s' = instrument_stmt ctx' bindings s in
    (match find_loop_invariant stmt.loc ctx.loop_invariants with
     | Some loop_info ->
       let entry_stmts = bs_and_ss_to_stmts loop_info.loop_entry in
       let _cond_loc, cond_bs_and_ss = loop_info.cond in
       let cond_stmts = bs_and_ss_to_stmts cond_bs_and_ss in
       let exit_stmts_internal = bs_and_ss_to_stmts loop_info.loop_exit in
       let exit_stmts_external = bs_and_ss_to_stmts loop_info.loop_exit in
       let augmented_body =
         match s'.A.node with
         | A.AilSblock (bs, ss) ->
           A.{ s' with node = A.AilSblock (bs, cond_stmts @ ss @ exit_stmts_internal) }
         | _ ->
           Utils.mk_stmt (A.AilSblock ([], cond_stmts @ [ s' ] @ exit_stmts_internal))
       in
       Utils.mk_stmt
         (A.AilSblock
            ( [],
              entry_stmts
              @ [ rewrap (A.AilSdo (augmented_body, e, annot)) ]
              @ exit_stmts_external ))
     | None -> rewrap (A.AilSdo (s', e, annot)))
  | A.AilSswitch (e, s) ->
    let ctx' = { ctx with break_vars = [] } in
    rewrap (A.AilSswitch (e, instrument_stmt ctx' bindings s))
  | A.AilScase (c, s) -> rewrap (A.AilScase (c, instrument_stmt ctx bindings s))
  | A.AilScase_rangeGNU (c1, c2, s) ->
    rewrap (A.AilScase_rangeGNU (c1, c2, instrument_stmt ctx bindings s))
  | A.AilSdefault s -> rewrap (A.AilSdefault (instrument_stmt ctx bindings s))
  | A.AilSmarker (m, s) -> rewrap (A.AilSmarker (m, instrument_stmt ctx bindings s))
  | A.AilSpar ss -> rewrap (A.AilSpar (List.map (instrument_stmt ctx bindings) ss))
  | A.AilSdeclaration _ | A.AilSexpr _ | A.AilSskip | A.AilScontinue | A.AilSreg_store _
    ->
    stmt


(* Process statements in a block sequentially, inserting ownership entry
   after each declaration, in-stmt injections between statements,
   and tracking declared variables for context updates *)
and instrument_block_stmts ctx bindings declared_so_far stmts =
  let next_loc stmts = match stmts with s :: _ -> Some s.A.loc | [] -> None in
  match stmts with
  | [] -> ([], declared_so_far)
  | stmt :: rest ->
    (match stmt.A.node with
     | A.AilSdeclaration decls ->
       let new_vars = get_declared_vars bindings decls in
       let entry_stmts = make_entry_stmts new_vars in
       let in_stmt_after =
         drain_in_stmt_injs_after stmt.loc (next_loc rest) ctx.in_stmt_injs
       in
       let ctx' =
         { ctx with
           in_scope_vars = new_vars @ ctx.in_scope_vars;
           break_vars = new_vars @ ctx.break_vars;
           continue_vars = new_vars @ ctx.continue_vars
         }
       in
       let rest_stmts, all_declared =
         instrument_block_stmts ctx' bindings (new_vars @ declared_so_far) rest
       in
       ((stmt :: entry_stmts) @ in_stmt_after @ rest_stmts, all_declared)
     | _ ->
       let stmt' = instrument_stmt ctx bindings stmt in
       let in_stmt_after =
         drain_in_stmt_injs_after stmt.loc (next_loc rest) ctx.in_stmt_injs
       in
       let rest_stmts, all_declared =
         instrument_block_stmts ctx bindings declared_so_far rest
       in
       ((stmt' :: in_stmt_after) @ rest_stmts, all_declared))


(* Instrument a function body with pre/post conditions, return rewriting,
   and ownership tracking. This is the unified entry point that replaces
   both the old return-rewriting pass and the injection-based ownership system. *)
let instrument_function_body
      ~with_testing
      fn_sym
      (pre : Internal.ail_bs_and_ss)
      (post : Internal.ail_bs_and_ss)
      (in_stmt_injs : (Cerb_location.t * Internal.ail_bs_and_ss) list)
      (loop_invariants : Cn_to_ail.loop_info list)
      (sigm : CF.GenTypes.genTypeCategory A.sigma)
  =
  let is_main = String.equal "main" (Sym.pp_string fn_sym) in
  match
    ( List.assoc_opt Sym.equal fn_sym sigm.function_definitions,
      List.assoc_opt Sym.equal fn_sym sigm.declarations )
  with
  | Some (floc, n, attrs, params, body), Some (_, _, decl) ->
    let ret_ty =
      match decl with
      | A.Decl_function (_, (_, ret_ty), _, _, _, _) -> ret_ty
      | _ -> C.void
    in
    let is_void = CF.AilTypesAux.is_void ret_ty in
    if with_testing && is_main then (
      let function_definitions =
        List.filter (fun (sym, _) -> not (Sym.equal sym fn_sym)) sigm.function_definitions
      in
      let declarations =
        List.filter (fun (sym, _) -> not (Sym.equal sym fn_sym)) sigm.declarations
      in
      { sigm with function_definitions; declarations })
    else (
      match body.node with
      | A.AilSblock (body_bs, body_ss) ->
        let pre_bs, pre_ss = extract_bs_and_ss pre in
        let post_bs, post_ss = extract_bs_and_ss post in
        let cn_ret_sym = Sym.fresh "__cn_ret" in
        let epilogue_sym = Sym.fresh "__cn_epilogue" in
        let extra_bs, extra_decl_ss =
          if is_void then
            ([], [])
          else (
            let init_expr =
              if is_main then
                Some
                  (Utils.mk_expr
                     (A.AilEconst
                        (A.ConstantInteger (A.IConstant (Z.zero, A.Decimal, None)))))
              else
                None
            in
            ( [ Utils.create_binding cn_ret_sym ret_ty ],
              [ Utils.mk_stmt (A.AilSdeclaration [ (cn_ret_sym, init_expr) ]) ] ))
        in
        let epilogue_stmts =
          let label_stmt =
            if List.is_empty post_ss then
              [ Utils.mk_stmt (A.AilSlabel (epilogue_sym, Utils.mk_stmt A.AilSskip, None))
              ]
            else (
              let post_block = Utils.mk_stmt (A.AilSblock (post_bs, post_ss)) in
              [ Utils.mk_stmt (A.AilSlabel (epilogue_sym, post_block, None)) ])
          in
          let return_stmt =
            if is_void then
              [ Utils.mk_stmt A.AilSreturnVoid ]
            else
              [ Utils.mk_stmt (A.AilSreturn (Utils.mk_expr (A.AilEident cn_ret_sym))) ]
          in
          label_stmt @ return_stmt
        in
        let ctx =
          { in_scope_vars = [];
            break_vars = [];
            continue_vars = [];
            cn_ret_sym;
            epilogue_sym;
            is_void;
            loop_invariants;
            in_stmt_injs = ref in_stmt_injs
          }
        in
        let instrumented_ss, declared_vars =
          instrument_block_stmts ctx body_bs [] body_ss
        in
        (* Exit cleanup for variables declared in the function body *)
        let body_var_exit_stmts = make_exit_stmts declared_vars in
        (* Any remaining in-stmt injections that weren't matched go at the end *)
        let trailing =
          List.concat_map
            (fun (_, bs_and_ss) -> bs_and_ss_to_stmts bs_and_ss)
            !(ctx.in_stmt_injs)
        in
        let new_body =
          Utils.mk_stmt
            (A.AilSblock
               ( extra_bs @ pre_bs @ body_bs,
                 extra_decl_ss
                 @ pre_ss
                 @ instrumented_ss
                 @ trailing
                 @ body_var_exit_stmts
                 @ epilogue_stmts ))
        in
        let function_definitions =
          List.map
            (fun ((sym, _def) as orig) ->
               if Sym.equal sym fn_sym then
                 (sym, (floc, n, attrs, params, new_body))
               else
                 orig)
            sigm.function_definitions
        in
        { sigm with function_definitions }
      | _ -> sigm)
  | _ -> sigm


(* ===== Static Wrappers ===== *)

let generate_static_wrapper filename (fn_sym : Sym.t) (decl : A.sigma_declaration) =
  let prefix = Utils.static_prefix filename in
  let fsym = Sym.fresh (prefix ^ "_" ^ Sym.pp_string fn_sym) in
  let ret_ty, arg_tys =
    match snd decl with
    | _, _, A.Decl_function (_, (_, ret_ty), arg_tys, _, _, _) -> (ret_ty, arg_tys)
    | _ -> failwith __LOC__
  in
  let args =
    let rec aux n tys =
      match tys with
      | _ :: tys' -> Sym.fresh ("arg_" ^ string_of_int n) :: aux (n + 1) tys'
      | [] -> []
    in
    aux 0 arg_tys
  in
  let e_call =
    Utils.mk_expr
      (A.AilEcall
         ( Utils.mk_expr (A.AilEident fn_sym),
           List.map (fun x -> Utils.mk_expr (A.AilEident x)) args ))
  in
  let wrapper_decl : A.sigma_declaration =
    ( fsym,
      ( Locations.other __LOC__,
        CF.Annot.Attrs [],
        A.Decl_function (false, (C.no_qualifiers, ret_ty), arg_tys, false, false, false)
      ) )
  in
  let wrapper_def : CF.GenTypes.genTypeCategory A.sigma_function_definition =
    ( fsym,
      ( Locations.other __LOC__,
        0,
        CF.Annot.Attrs [],
        args,
        Utils.mk_stmt
          A.(
            AilSblock
              ( [],
                [ Utils.mk_stmt
                    (if C.ctypeEqual C.void ret_ty then
                       AilSexpr e_call
                     else
                       AilSreturn e_call)
                ] )) ) )
  in
  (wrapper_decl, wrapper_def)


(* ===== Filtering ===== *)

let filter_selected_fns
      (is_sym_selected : Sym.t -> bool)
      ( (sigm : CF.GenTypes.genTypeCategory CF.AilSyntax.sigma),
        (instrumentation : Extract.instrumentation list) )
  =
  let filtered_instrumentation =
    List.filter
      (fun (i : Extract.instrumentation) -> is_sym_selected i.fn)
      instrumentation
  in
  (* Keep declarations for selected functions AND global variables (those in object_definitions) *)
  let object_syms = List.map fst sigm.object_definitions |> Sym.Set.of_list in
  let filtered_ail_prog_decls =
    List.filter
      (fun (decl_sym, _) -> is_sym_selected decl_sym || Sym.Set.mem decl_sym object_syms)
      sigm.declarations
  in
  let filtered_ail_prog_defs =
    List.filter (fun (def_sym, _) -> is_sym_selected def_sym) sigm.function_definitions
  in
  let filtered_sigm =
    { sigm with
      declarations = filtered_ail_prog_decls;
      function_definitions = filtered_ail_prog_defs
    }
  in
  (filtered_instrumentation, filtered_sigm)


let get_main_sym sym_list =
  List.filter (fun sym -> String.equal (Sym.pp_string sym) "main") sym_list


let filter_using_skip_and_only
      skip_and_only
      ( (prog5 : unit Mucore.file),
        (sigm : CF.GenTypes.genTypeCategory CF.AilSyntax.sigma),
        (instrumentation : Extract.instrumentation list) )
  =
  let prog5_fns_list = List.map fst (Pmap.bindings_list prog5.funs) in
  let all_fns_sym_set = Sym.Set.of_list prog5_fns_list in
  let main_sym = get_main_sym prog5_fns_list in
  let selected_function_syms =
    Sym.Set.elements (Check.select_functions skip_and_only all_fns_sym_set)
  in
  let is_sym_selected =
    fun sym -> List.mem Sym.equal sym (selected_function_syms @ main_sym)
  in
  filter_selected_fns is_sym_selected (sigm, instrumentation)


let output_to_oc oc str_list = List.iter (Stdlib.output_string oc) str_list

open Internal

let get_instrumented_filename filename =
  Filename.(remove_extension (basename filename)) ^ ".exec.c"


let get_filename_with_prefix output_dir filename = Filename.concat output_dir filename

(* TODO: fix + add CLI flag *)
let _gen_compile_commands_json cc output_dir out_filename =
  let compile_commands_json_oc =
    Stdlib.open_out (get_filename_with_prefix output_dir "compile_commands.json")
  in
  let opam_switch_prefix =
    match Sys.getenv_opt "OPAM_SWITCH_PREFIX" with
    | Some p -> p
    | None -> failwith "OPAM_SWITCH_PREFIX not set"
  in
  let compile_commands_json_str =
    [ "[";
      "\n\t{ \"directory\": \"" ^ output_dir ^ "\",";
      "\n\t\"command\": \""
      ^ cc
      ^ " -I"
      ^ opam_switch_prefix
      ^ "/lib/cn/runtime/include/ "
      ^ out_filename
      ^ "\",";
      "\n\t\"file\": \"" ^ out_filename ^ "\" }";
      "\n]"
    ]
  in
  output_to_oc compile_commands_json_oc compile_commands_json_str;
  close_out compile_commands_json_oc


let main
      ~without_ownership_checking
      ~without_loop_invariants
      ~with_loop_leak_checks
      ~without_lemma_checks
      ~exec_c_locs_mode
      ~experimental_ownership_stack_mode
      ~experimental_curly_braces
      ~with_testing
      ~skip_and_only
      ?max_bump_blocks
      ?bump_block_size
      filename
      _cc
      in_filename (* WARNING: this file will be deleted after this function *)
      out_filename
      output_dir
      cabs_tunit
      ((_startup_sym_opt, (sigm : CF.GenTypes.genTypeCategory CF.AilSyntax.sigma)) as
       _ail_prog)
      prog5
  =
  let out_filename = get_filename_with_prefix output_dir out_filename in
  let (full_instrumentation : Extract.instrumentation list), _ =
    Extract.collect_instrumentation cabs_tunit prog5
  in
  (* Filters based on functions passed to --only and/or --skip *)
  let filtered_instrumentation, filtered_sigm =
    filter_using_skip_and_only skip_and_only (prog5, sigm, full_instrumentation)
  in
  let static_funcs =
    full_instrumentation
    |> List.filter (fun (inst : Extract.instrumentation) -> inst.is_static)
    |> List.map (fun (inst : Extract.instrumentation) -> inst.fn)
    |> Sym.Set.of_list
  in
  Records.populate_record_map filtered_instrumentation prog5;
  let executable_spec =
    generate_c_specs
      without_ownership_checking
      without_loop_invariants
      with_loop_leak_checks
      without_lemma_checks
      filename
      filtered_instrumentation
      cabs_tunit
      sigm
      prog5
  in
  let c_datatype_defs = generate_c_datatypes sigm in
  let c_function_defs, c_function_decls, _c_function_locs =
    generate_c_functions filename cabs_tunit prog5 sigm
  in
  let c_predicate_defs, c_predicate_decls, _c_predicate_locs =
    generate_c_predicates filename cabs_tunit prog5 sigm
  in
  let c_lemma_defs, c_lemma_decls =
    if without_lemma_checks then
      ("", "")
    else
      generate_c_lemmas filename cabs_tunit sigm prog5
  in
  let conversion_function_defs, conversion_function_decls =
    generate_conversion_and_equality_functions filename sigm
  in
  let ownership_function_defs, ownership_function_decls =
    generate_ownership_functions without_ownership_checking !Cn_to_ail.ownership_ctypes
  in
  let ordered_ail_tag_defs = order_ail_tag_definitions sigm.tag_definitions in
  let c_tag_defs = generate_c_tag_def_strs ordered_ail_tag_defs in
  let cn_converted_struct_defs = generate_cn_versions_of_structs ordered_ail_tag_defs in
  let record_fun_defs, record_fun_decls = Records.generate_c_record_funs sigm in
  let record_defs = Records.generate_all_record_strs () in
  let cn_ghost_enum = generate_ghost_enum prog5 in
  let cn_ghost_call_site_glob = generate_ghost_call_site_glob () in
  (* Forward declarations and CN types *)
  let cn_header_decls_list =
    List.concat
      [ [ "#include <cn-executable/cerb_types.h>\n";
          "typedef __cerbty_intptr_t intptr_t;\n";
          "typedef __cerbty_uintptr_t uintptr_t;\n";
          "typedef __cerbty_intmax_t intmax_t;\n";
          "typedef __cerbty_uintmax_t uintmax_t;\n";
          "static const int __cerbvar_INT_MAX = 0x7fffffff;\n";
          "static const int __cerbvar_INT_MIN = ~0x7fffffff;\n";
          "static const unsigned long long __cerbvar_SIZE_MAX = ~(0ULL);\n";
          "_Noreturn void abort(void);"
        ];
        [ c_tag_defs ];
        [ (if not (String.equal record_defs "") then "\n/* CN RECORDS */\n\n" else "");
          record_defs;
          cn_converted_struct_defs
        ];
        (if List.is_empty c_datatype_defs then [] else [ "/* CN DATATYPES */" ]);
        List.map snd c_datatype_defs;
        [ "\n\n/* OWNERSHIP FUNCTIONS */\n\n";
          ownership_function_decls;
          "/* CONVERSION FUNCTIONS */\n";
          conversion_function_decls;
          "/* RECORD FUNCTIONS */\n";
          record_fun_decls;
          c_function_decls;
          "\n";
          c_predicate_decls;
          c_lemma_decls;
          cn_ghost_enum
        ];
        cn_ghost_call_site_glob
      ]
  in
  (* Definitions for CN helper functions *)
  let cn_defs_list =
    [ "/* RECORD */\n";
      record_fun_defs;
      "/* CONVERSION */\n";
      conversion_function_defs;
      "/* OWNERSHIP FUNCTIONS */\n";
      ownership_function_defs;
      "/* CN FUNCTIONS */\n";
      c_function_defs;
      "\n";
      c_predicate_defs;
      c_lemma_defs
    ]
  in
  (* === Build the AST modification pipeline === *)
  (* 1. Start with filtered sigma *)
  let sigma = filtered_sigm in
  (* 2. Optionally wrap single-statement bodies in blocks *)
  let sigma =
    if experimental_curly_braces then ensure_all_block_bodies sigma else sigma
  in
  (* 3. Rewrite memory accesses *)
  let sigma =
    if not without_ownership_checking then
      rewrite_memory_accesses_in_sigma sigma
    else
      sigma
  in
  (* 4. Build pre_post pairs including global ownership for main *)
  let pre_post_pairs =
    if with_testing || without_ownership_checking then
      executable_spec.pre_post
    else (
      let global_ownership_init_pair =
        generate_global_assignments
          ~exec_c_locs_mode
          ~experimental_ownership_stack_mode
          ?max_bump_blocks
          ?bump_block_size
          cabs_tunit
          sigm
          prog5
      in
      global_ownership_init_pair @ executable_spec.pre_post)
  in
  (* 5. Instrument each function body with pre/post/returns/in-stmt *)
  let sigma =
    List.fold_left
      (fun sigma (fn_sym, (pre, post)) ->
         let fn_in_stmt =
           match List.assoc_opt Sym.equal fn_sym executable_spec.in_stmt with
           | Some injs -> injs
           | None -> []
         in
         let fn_loops =
           match List.assoc_opt Sym.equal fn_sym executable_spec.loops with
           | Some loops -> loops
           | None -> []
         in
         instrument_function_body ~with_testing fn_sym pre post fn_in_stmt fn_loops sigma)
      sigma
      pre_post_pairs
  in
  (* 6. Add static wrappers *)
  let sigma =
    Sym.Set.fold
      (fun fn_sym sigma ->
         match List.assoc_opt Sym.equal fn_sym sigm.A.declarations with
         | Some decl ->
           let wrapper_decl, wrapper_def =
             generate_static_wrapper filename fn_sym (fn_sym, decl)
           in
           A.
             { sigma with
               declarations = sigma.A.declarations @ [ wrapper_decl ];
               function_definitions = sigma.A.function_definitions @ [ wrapper_def ]
             }
         | None -> sigma)
      static_funcs
      sigma
  in
  (* 7. Filter sigma for pretty-printing: only keep declarations that have
     corresponding function definitions or object definitions (drops stdlib declarations like
     calloc, qsort etc. that use size_t which isn't defined in our output) *)
  let print_sigma =
    let defined_syms = List.map fst sigma.function_definitions |> Sym.Set.of_list in
    let object_syms = List.map fst sigma.object_definitions |> Sym.Set.of_list in
    let keep_syms = Sym.Set.union defined_syms object_syms in
    let filtered_decls =
      List.filter (fun (sym, _) -> Sym.Set.mem sym keep_syms) sigma.declarations
    in
    { sigma with declarations = filtered_decls }
  in
  let instrumented_source =
    Pp.plain
      CF.Pp_ail.(with_executable_spec (pp_program ~show_include:true) (None, print_sigma))
  in
  (* 8. Write output *)
  let oc = Stdlib.open_out out_filename in
  output_to_oc oc [ "#define __CN_INSTRUMENT\n"; "#include <cn-executable/utils.h>\n" ];
  output_to_oc oc [ "#ifndef NULL\n"; "#define NULL ((void*)0)\n"; "#endif\n" ];
  output_to_oc oc cn_header_decls_list;
  output_to_oc
    oc
    [ "#ifndef offsetof\n";
      "#define offsetof(st, m) ((__cerbty_size_t)((char *)&((st *)0)->m - (char *)0))\n";
      "#endif\n"
    ];
  output_string oc "#pragma GCC diagnostic ignored \"-Wattributes\"\n";
  output_string oc "\n/* GLOBAL ACCESSORS */\n";
  output_string
    oc
    ("void* memcpy(void* dest, const void* src, __cerbty_size_t count );\n"
     ^ Globals.accessors_prototypes filename cabs_tunit prog5);
  (* Pretty-printed instrumented program *)
  output_string oc instrumented_source;
  output_to_oc oc [ Globals.accessors_str filename cabs_tunit prog5 ];
  output_to_oc oc cn_defs_list;
  close_out oc;
  Stdlib.Sys.remove in_filename
