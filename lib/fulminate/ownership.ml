open Utils
module CF = Cerb_frontend
module A = CF.AilSyntax
module C = CF.Ctype

type ail_bindings_and_statements =
  A.bindings * CF.GenTypes.genTypeCategory A.statement_ list

let get_cn_stack_depth_sym = Sym.fresh "get_cn_stack_depth"

let cn_stack_depth_incr_sym = Sym.fresh "ghost_stack_depth_incr"

let cn_stack_depth_decr_sym = Sym.fresh "ghost_stack_depth_decr"

let cn_postcondition_leak_check_sym = Sym.fresh "cn_postcondition_leak_check"

let cn_loop_put_back_ownership_sym = Sym.fresh "cn_loop_put_back_ownership"

let cn_loop_leak_check_sym = Sym.fresh "cn_loop_leak_check"

let c_add_ownership_fn_sym = Sym.fresh "c_add_to_ghost_state"

let c_remove_ownership_fn_sym = Sym.fresh "c_remove_from_ghost_state"

let get_ownership_global_init_stats
      ?(ghost_array_size = 100)
      ?max_bump_blocks
      ?bump_block_size
      ()
  =
  let bump_config_calls =
    let make_bump_config_call fn_name n =
      mk_expr
        A.(
          AilEcall
            ( mk_expr (AilEident (Sym.fresh fn_name)),
              [ mk_expr
                  (AilEconst (ConstantInteger (IConstant (Z.of_int n, Decimal, None))))
              ] ))
    in
    [ Option.map (make_bump_config_call "cn_bump_set_max_blocks") max_bump_blocks;
      Option.map (make_bump_config_call "cn_bump_set_block_size") bump_block_size
    ]
    |> List.filter_map Fun.id
  in
  let cn_ghost_state_init_fcall =
    mk_expr
      A.(
        AilEcall (mk_expr (AilEident (Sym.fresh "initialise_ownership_ghost_state")), []))
  in
  let cn_ghost_stack_depth_init_fcall =
    mk_expr
      A.(AilEcall (mk_expr (AilEident (Sym.fresh "initialise_ghost_stack_depth")), []))
  in
  let cn_ghost_arg_array_alloc_fcall =
    mk_expr
      A.(
        AilEcall
          ( mk_expr (AilEident (Sym.fresh "alloc_ghost_array")),
            [ mk_expr
                (AilEconst
                   (ConstantInteger (IConstant (Z.of_int ghost_array_size, Decimal, None))))
            ] ))
  in
  List.map
    (fun e -> A.(AilSexpr e))
    (bump_config_calls
     @ [ cn_ghost_state_init_fcall;
         cn_ghost_stack_depth_init_fcall;
         cn_ghost_arg_array_alloc_fcall
       ])


let generate_c_local_cn_addr_var sym =
  (* Hardcoding parts of cn_to_ail_base_type to prevent circular dependency between
      this module and Cn_internal_to_ail, which includes Ownership already. *)
  let cn_addr_sym = generate_sym_with_suffix ~suffix:"_addr_cn" sym in
  let annots = [ CF.Annot.Atypedef (Sym.fresh "cn_pointer") ] in
  (* Ctype_ doesn't matter to pretty-printer when typedef annotations are present *)
  let inner_ctype = mk_ctype ~annots C.Void in
  let cn_ptr_ctype = mk_ctype C.(Pointer (C.no_qualifiers, inner_ctype)) in
  let binding = create_binding cn_addr_sym cn_ptr_ctype in
  let addr_of_sym = mk_expr A.(AilEunary (Address, mk_expr (AilEident sym))) in
  let fcall_sym = Sym.fresh "convert_to_cn_pointer" in
  let conversion_fcall = A.(AilEcall (mk_expr (AilEident fcall_sym), [ addr_of_sym ])) in
  let decl = A.(AilSdeclaration [ (cn_addr_sym, Some (mk_expr conversion_fcall)) ]) in
  (binding, decl)


let generate_c_local_ownership_entry_fcall (local_sym, local_ctype) =
  let local_ident = mk_expr A.(AilEident local_sym) in
  let arg1 = A.(AilEunary (Address, local_ident)) in
  let arg2 = A.(AilEsizeof (C.no_qualifiers, local_ctype)) in
  let arg3 = A.(AilEcall (mk_expr (AilEident get_cn_stack_depth_sym), [])) in
  mk_expr
    (AilEcall
       (mk_expr (AilEident c_add_ownership_fn_sym), List.map mk_expr [ arg1; arg2; arg3 ]))


let generate_c_local_ownership_entry (sym, ctype) =
  A.(AilSexpr (generate_c_local_ownership_entry_fcall (sym, ctype)))


let generate_c_local_ownership_entry_bs_and_ss (sym, ctype) =
  let entry_fcall_stat = generate_c_local_ownership_entry (sym, ctype) in
  let addr_cn_binding, addr_cn_decl = generate_c_local_cn_addr_var sym in
  ([ addr_cn_binding ], [ entry_fcall_stat; addr_cn_decl ])


let generate_c_local_ownership_exit (local_sym, local_ctype) =
  let local_ident = mk_expr A.(AilEident local_sym) in
  let arg1 = A.(AilEunary (Address, local_ident)) in
  let arg2 = A.(AilEsizeof (C.no_qualifiers, local_ctype)) in
  A.(
    AilSexpr
      (mk_expr
         A.(
           AilEcall
             ( mk_expr (AilEident c_remove_ownership_fn_sym),
               List.map mk_expr [ arg1; arg2 ] ))))


let get_c_local_ownership_checking params =
  let entry_ownership_bs_and_ss =
    List.map (fun param -> generate_c_local_ownership_entry_bs_and_ss param) params
  in
  let entry_ownership_bs, entry_ownership_ss = List.split entry_ownership_bs_and_ss in
  let exit_ownership_stats = List.map generate_c_local_ownership_exit params in
  ( (List.concat entry_ownership_bs, List.concat entry_ownership_ss),
    ([], exit_ownership_stats) )
