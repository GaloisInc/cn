# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

CN is a tool for verifying C code using separation logic refinement types. It's written in OCaml and builds on the Cerberus C semantics. CN can verify that C code is free of undefined behavior and meets user-written specifications, and can also translate specifications into runtime checks.

## Building and Testing

### Building
```bash
make install          # Build and install CN (required after any code changes)
make cn              # Build CN without installing
make cn-coq          # Build Coq components
make format          # Format OCaml and C code
```

Always rebuild with `make install` after making code changes before running tests.

### Running CN
```bash
cn verify FILE.c     # Verify a C file
cn test FILE.c       # Generate and run tests (uses Fulminate/Bennet)
cn --help            # See all options
```

### Testing
- Test suites in `tests/cn/`, `tests/cn-test-gen/`, `tests/cn-seq-test-gen/`
- See `doc/TESTING.md` for details on CN's testing capabilities

### Running Different Commands on Test Suites

To run any CN command on any test directory:

```bash
cd tests

# Run a specific command on a specific directory
./run-all-commands.sh verify cn
./run-all-commands.sh test cn-test-gen
./run-all-commands.sh seq-test cn-seq-test-gen

# Run a command on all test directories
./run-all-commands.sh verify all
./run-all-commands.sh test all

# Regenerate test baselines when test generation changes
./run-all-commands.sh test all --regen

# Or use diff-prog.py directly with JSON configs
./diff-prog.py cn cn/test.json              # Run cn test on verify tests
./diff-prog.py cn cn-test-gen/src/verify.json  # Run cn verify on test-gen tests
```

**Note:**
- Some tests may fail when run with incompatible commands (e.g., test-gen specs are too complex for verify baseline comparison). This is expected.
- Do NOT use `run-cn-test-gen.py` directly
  - it's a very long-running script that tests each case with 8 different parameter sets.
  - Use `run-all-commands.sh test all ` instead.

### Understanding diff-prog.py Test Output

`diff-prog.py` uses color-coded labels to clearly distinguish different test outcomes:

**Success (Green):**
- `[ PASSED ]` - Test passed, baseline matches exactly

**Baseline Updates (Cyan/Yellow - NOT failures):**
- `[ UPDATED ]` - Baseline was updated with `--accept` flag (cyan)
- `[ PASS (baseline updated) ]` - Test passed but output text changed, needs `--accept` (yellow)
- `[ ERROR (baseline updated) ]` - Test errored as expected but output text changed, needs `--accept` (yellow)

**True Regressions (Red - actual failures):**
- `[ PASS→ERROR ]` - Expected pass, now errors (breaking regression)
- `[ ERROR→PASS ]` - Expected error, now passes (test may be obsolete or bug fixed)
- `[ PASS→CRASH ]` - Expected pass, now crashes with exit code 125 (serious regression)
- `[ CRASH→PASS ]` - Expected crash, now passes (crash bug may be fixed)
- `[ CRASH→ERROR ]` - Expected crash, now errors (behavior changed)
- `[ ERROR (wrong code) ]` - Got error but with unexpected exit code

**Other:**
- `[ TIMEOUT ]` - Test exceeded time limit (magenta)

**How to interpret the output:**

1. **Green labels**: Everything is working correctly
2. **Yellow/Cyan labels**: Tests work correctly, but output text changed (e.g., improved error messages, line number changes from code edits). Use `--accept` to update baselines after reviewing the diffs.
3. **Red labels**: True regressions - test behavior changed. These require investigation and fixes, not just baseline updates.

**Test file naming conventions indicate expected behavior:**
- `.c` files - should pass (exit code 0)
- `.error.c` files - should error (exit code 1)
- `.crash.c` files - should crash with internal error (exit code 125)
- `.fail.c` files - should fail test generation (non-zero exit)

**Example workflow:**
```bash
# Run tests and see results
cd tests
./diff-prog.py cn cn/verify.json

# If you see yellow labels, review the diffs shown
# If diffs are acceptable (e.g., improved error messages), update baselines:
./diff-prog.py cn cn/verify.json --accept

# Red labels require investigation - don't just accept them!
```

**Important:** Never use `--accept` if you see red regression labels (PASS→ERROR, etc.) without understanding why the behavior changed. Yellow labels are safe to accept after reviewing the diff output.

### Debugging and Scratch Space

When debugging test generation or inspecting generated code:

- Use `claude_scratch/` directory for temporary work and analysis
- Create subdirectories within `claude_scratch/` for different debugging sessions
- The `claude_scratch/` directory is gitignored and safe for temporary files
- Use `cn test --output-dir` to save generated test files to a specific location

Example:
```bash
# Generate test with output saved to scratch directory
cn test tests/cn-test-gen/src/example.c --output-dir claude_scratch/my-debug-session

# Save test output log
cn test tests/cn-test-gen/src/example.c 2>&1 | tee claude_scratch/test-output.log
```

## Architecture

### Pipeline Overview
C code flows through these stages:
1. **Lexer/Parser** → Cabs (C Abstract Syntax)
2. **Desugaring** → Ail (intermediate language based on Clang)
3. **Translation** → Core
4. **Core to Mucore** (`lib/core_to_mucore.ml`) → Mucore (what CN typechecks)

CN annotations (`/*@ ... @*/`) are parsed at different entry points:
- `cn_statement`: proof guidance, debugging
- `function_spec`: pre/post conditions
- `loop_spec`: loop invariants
- `cn_toplevel`: declarations

### Key Source Files
- `bin/main.ml` - Entry point
- `lib/wellTyped.ml` - Specification well-formedness checking and pexpr inference
- `lib/check.ml` - C code type checking
- `lib/typing.ml{i}` - Type checking monad
- `lib/solver.ml` - SMT solver interface
- `lib/typeErrors.ml` - CN error messages
- `lib/report.ml` - HTML report generation

### Key Types
- `lib/baseTypes.ml` - Base types
- `lib/terms.ml` - Terms
- `lib/logicalArgumentTypes.ml` - Logical argument types (Define, Resource, Constraint)
- `lib/resourceTypes.ml` - Predicate signatures
- `lib/resourcePredicates.ml` - Predicate definitions
- `lib/mucore.ml{i}` - Mucore AST definitions

### Code Pattern: Adding Pexpr Cases

When adding support for a new pexpr constructor in `lib/wellTyped.ml`, follow this pattern:

1. In `infer_pexpr` (around line 1615), add a case that:
   - Infers types of sub-expressions using `infer_pexpr`
   - Validates type constraints (e.g., for struct member access, check the base type is a struct)
   - Uses `get_struct_member_type` or similar to get field types
   - Returns `(base_type, constructor_with_typed_subexprs)`

Example (PEmemberof):
```ocaml
| PEmemberof (tag, member, pe) ->
  let@ pe = infer_pexpr pe in
  let@ field_ct = get_struct_member_type loc tag member in
  return (Memory.bt_of_sct field_ct, PEmemberof (tag, member, pe))
```

Don't just call `todo()` - implement proper type inference to avoid crashes on valid C code.

## Development Workflow

### Contributing
- All work starts with a GitHub issue
- Fork the repo and keep it up-to-date: `git pull --rebase upstream main`
- Open PRs early (even in draft) to run CI
- Use trunk-based development
- See `doc/CONTRIBUTING.md` for full guidelines
- Use the ocaml LSP. If it's not working ask the user for help configuring it.

### Code Style
- OCaml: Formatted with `ocamlformat` (version 0.27.0)
- C: Formatted with `clang-format` (LLVM style, version 19)
- Run `make format` or `dune build @fmt` to check/apply formatting

### Commits
- Keep commits small and self-contained
- Write clear commit messages explaining "why" not just "what"
- Each commit should build successfully (supports `git bisect`)
- **NEVER use `git add -A` or `git add .`**
- always add specific files by name to avoid accidentally committing untracked files, build artifacts, or sensitive data

## Test Cases

### Test Directories

CN has different test suites with different conventions:

#### tests/cn/
- Tests for `cn verify` command
- Uses `tests/diff-prog.py` with `tests/cn/verify.json` config
- Expected output stored in `file.c.verify` files
- Run with: `cd tests && ./run-all-commands.sh verify`

#### tests/cn-test-gen/
- Tests for `cn test` command (test generation)
- Uses `tests/run-cn-test-gen.py` script
- No .verify files - uses filename suffix to determine expected behavior:
  - `.pass.c` - should pass (exit code 0)
  - `.fail.c` - should fail (non-zero exit code)
  - `.buggy.c` - skipped
  - `.flaky.c` - may pass or fail
- Run with: `cd tests && ./run-all-commands.sh test`

#### tests/cn_vip_testsuite/
- VIP testsuite tests
- Uses various JSON configs for different test modes
