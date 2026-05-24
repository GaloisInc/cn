(* Simple S-expression type and parser for SMT-LIB *)

type sexp =
  | Atom of string
  | List of sexp list

exception Parse_error of string

(** Parse a single S-expression from a string. Returns None if string is empty/whitespace. *)
val parse_string : string -> sexp option

(** Convert S-expression back to string *)
val to_string : sexp -> string

(** Constructors *)
val atom : string -> sexp

val list : sexp list -> sexp
