(* Simple S-expression parser for SMT-LIB commands *)

type sexp =
  | Atom of string
  | List of sexp list

exception Parse_error of string

(* Tokenize the string into atoms and parens *)
let tokenize s =
  let len = String.length s in
  let rec aux acc i =
    if i >= len then
      List.rev acc
    else (
      match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> aux acc (i + 1)
      | '(' -> aux ("(" :: acc) (i + 1)
      | ')' -> aux (")" :: acc) (i + 1)
      | _ ->
        (* Read atom until delimiter *)
        let rec read_atom j =
          if j >= len then
            (j, String.sub s i (j - i))
          else (
            match s.[j] with
            | ' ' | '\t' | '\n' | '\r' | '(' | ')' -> (j, String.sub s i (j - i))
            | _ -> read_atom (j + 1))
        in
        let j, atom = read_atom i in
        aux (atom :: acc) j)
  in
  aux [] 0


(* Parse tokens into s-expression *)
let parse_tokens tokens =
  let rec parse tokens =
    match tokens with
    | [] -> raise (Parse_error "Unexpected end of input")
    | "(" :: rest ->
      let sexps, rest' = parse_list [] rest in
      (List sexps, rest')
    | ")" :: _ -> raise (Parse_error "Unexpected closing paren")
    | atom :: rest -> (Atom atom, rest)
  and parse_list acc tokens =
    match tokens with
    | [] -> raise (Parse_error "Unclosed list")
    | ")" :: rest -> (List.rev acc, rest)
    | _ ->
      let sexp, rest' = parse tokens in
      parse_list (sexp :: acc) rest'
  in
  match parse tokens with
  | sexp, [] -> Some sexp
  | sexp, _ -> Some sexp (* Ignore trailing tokens *)
  | exception Parse_error _ -> None


let parse_string s =
  let tokens = tokenize s in
  parse_tokens tokens


let rec to_string = function
  | Atom s -> s
  | List [] -> "()"
  | List sexps -> "(" ^ String.concat " " (List.map to_string sexps) ^ ")"


let atom name = Atom name

let list sexps = List sexps
