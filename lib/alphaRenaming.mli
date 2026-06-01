(** Canonical alpha-renaming for deterministic hashing

    This module provides alpha-renaming that produces canonical, deterministic
    names for bound variables, essential for content-based hashing.
*)

(** Renaming context *)
type ctx

(** Empty renaming context *)
val empty_ctx : ctx

(** Alpha-rename a function type (specification) to canonical form *)
val rename_ft : ArgumentTypes.ft -> ArgumentTypes.ft

(** Alpha-rename a lemma type to canonical form *)
val rename_lemmat : ArgumentTypes.lemmat -> ArgumentTypes.lemmat

(** Alpha-rename an index term to canonical form *)
val rename_it : ctx -> IndexTerms.t -> IndexTerms.t * ctx

(** Alpha-rename Mucore args_and_body for deterministic hashing *)
val rename_args_and_body
  :  BaseTypes.t Mucore.args_and_body ->
  BaseTypes.t Mucore.args_and_body
