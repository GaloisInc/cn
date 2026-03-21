open Cerb_frontend

type ail_bindings_and_statements =
  AilSyntax.bindings * GenTypes.genTypeCategory AilSyntax.statement_ list

val cn_stack_depth_incr_sym : Sym.t

val cn_stack_depth_decr_sym : Sym.t

val cn_postcondition_leak_check_sym : Sym.t

val cn_loop_put_back_ownership_sym : Sym.t

val cn_loop_leak_check_sym : Sym.t

val get_ownership_global_init_stats
  :  ?ghost_array_size:int ->
  ?max_bump_blocks:int ->
  ?bump_block_size:int ->
  unit ->
  GenTypes.genTypeCategory AilSyntax.statement_ list

val generate_c_local_ownership_entry_fcall
  :  AilSyntax.ail_identifier * Ctype.ctype ->
  GenTypes.genTypeCategory AilSyntax.expression

val generate_c_local_ownership_entry_bs_and_ss
  :  AilSyntax.ail_identifier * Ctype.ctype ->
  ail_bindings_and_statements

val generate_c_local_ownership_exit
  :  AilSyntax.ail_identifier * Ctype.ctype ->
  GenTypes.genTypeCategory AilSyntax.statement_

val get_c_local_ownership_checking
  :  (AilSyntax.ail_identifier * Ctype.ctype) list ->
  ail_bindings_and_statements * ail_bindings_and_statements
