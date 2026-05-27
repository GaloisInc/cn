(** Content-based hashing of CN definitions with alpha-renaming normalization *)

(** Hash a function definition including spec and body *)
val hash_function
  :  Definition.Function.t ->
  (* Function definition *)
  ArgumentTypes.ft option ->
  (* Function type with spec *)
  BaseTypes.t Mucore.pexpr ->
  (* Function body *)
  string
(* MD5 hash hex string *)

(** Hash a predicate definition *)
val hash_predicate
  :  Definition.Predicate.t ->
  (* Predicate definition *)
  string

(** Hash a logical function definition *)
val hash_logical_function
  :  Definition.Function.t ->
  (* Logical function definition *)
  string

(** Hash just the specification (pre/post) of a function *)
val hash_function_spec : ArgumentTypes.ft option -> string

(** Hash args_and_body including spec and full body with loop invariants *)
val hash_args_and_body : BaseTypes.t Mucore.args_and_body -> string

(** Hash a struct definition *)
val hash_struct_definition
  :  Memory.struct_decl ->
  (* Struct declaration *)
  string

(** Hash a datatype definition *)
val hash_datatype_definition
  :  BaseTypes.dt_info ->
  (* Datatype info *)
  string

(** Normalize and hash an index term (with alpha-renaming) *)
val hash_index_term : IndexTerms.t -> string

(** Hash a lemma definition *)
val hash_lemma : ArgumentTypes.lemmat -> string
