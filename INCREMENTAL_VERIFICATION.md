# CN Incremental Verification System

## Overview

CN supports incremental verification through content-based caching with SQLite. The system tracks verification status, dependencies, and uses alpha-renaming normalization to avoid spurious re-verification.

## Features

✅ **Fully Implemented**:
- Content-based hashing with alpha-renaming (variable renames don't trigger re-verification)
- Full dependency tracking for all entity types:
  - Functions → functions (spec-only), predicates, logical functions, lemmata, structs, datatypes
  - Predicates → predicates, logical functions, structs, datatypes
  - Logical functions → logical functions, structs, datatypes
  - Lemmata → predicates, logical functions, structs, datatypes
- Transitive dependency checking (recursive invalidation)
- Failure caching (failed verifications cached like successes)
- Query cache integration (both caches work together)
- Cache inspection tools (`cn cache` subcommand)

## Usage

### Verification with Caching

```bash
# Use default cache location (~/.cache/cn/verification.db)
cn verify --use-db file.c

# Use custom cache location
cn verify --use-db --db-path=/tmp/my-cache.db file.c

# Clear cache before verification
cn verify --use-db --clear-db file.c

# With query cache (recommended)
cn verify --use-db --enable-query-cache file.c
```

### Cache Inspection

```bash
# Show summary statistics
cn cache summary
cn cache summary --db-path=/tmp/my-cache.db

# List all failed functions
cn cache failures

# Show functions from specific file (substring match)
cn cache file my_module

# Clear the cache
cn cache clear          # Prompts for confirmation
cn cache clear --force  # No confirmation
```

## Dependency Policy

**Hybrid approach** for optimal cache hits:

- **Function calls**: Only track callee **spec** (pre/postconditions)
  - Changing function body doesn't invalidate callers
  - Changing spec does invalidate callers
  
- **Predicates/Logical functions/Lemmata**: Track **full content**
  - Any change invalidates users (body is part of contract)

- **Structs/Datatypes**: Track **full definition**
  - Field changes, type changes invalidate users

## Test Suite

Comprehensive tests in `tests/cn/caching/`:

**Basic changes:**
- `spec_change` - Function spec changes trigger re-verification
- `body_change` - Function body changes trigger re-verification
- `comment_change` - Comments DON'T trigger re-verification
- `argument_rename` - Parameter renames DON'T trigger re-verification
- `split_case_change` - split_case annotation changes trigger re-verification
- `assert_change` - Assert statement changes trigger re-verification

**Dependency tracking:**
- `function_call` - Function → function dependencies
- `predicate_change` - Function → predicate dependencies
- `logical_function_change` - Function → logical function dependencies
- `lemma` - Function → lemma dependencies
- `struct_change` - Function → struct dependencies
- `datatype_change` - Function → datatype dependencies

**All 24 dependency type combinations:**
- Predicate → predicate, logical function, struct, datatype
- Logical function → logical function (recursive), struct, datatype
- Lemma → predicate, logical function, struct, datatype

**Transitive dependencies:**
- `transitive_dependency` - Changes propagate through call chains
- `transitive_predicate` - Changes propagate through predicate uses

**Failure handling:**
- `cached_failure` - Failed verifications are cached
- `broken_implementation` - Failures with unchanged dependencies aren't re-run

Run all tests:
```bash
cd tests/cn/caching
for dir in */; do (cd "$dir" && bash test.sh); done
```

## Performance

Typical speedups on second run:
- Small files: 1.8-2x faster
- Large projects: Variable (depends on what changed)
- Fixed costs: Parsing, hashing (typically 3-5s for large codebases)

Both query cache and verification database contribute to performance:
- Query cache: Reuses SMT solver results for identical queries
- Verification DB: Skips entire function verifications when nothing changed

## Implementation

### Core OCaml Modules

**lib/verificationDb.ml** (~1200 lines)
- SQLite database operations (open, init schema, close)
- Record verification results (pass/fail with timing, error messages)
- Store and query dependencies for all entity types
- Functions for checking staleness:
  - `get_function_status`, `get_predicate_status`, etc.
  - `is_predicate_up_to_date` (recursive with visited tracking)
  - `is_logical_function_up_to_date` (recursive)
  - `is_struct_up_to_date`, `is_datatype_up_to_date`
- List and count functions: `list_functions`, `get_entity_counts`

**lib/contentHash.ml** (~500 lines)
- Content-based hashing with MD5
- Alpha-renaming normalization (variables → canonical names)
- Hash functions for all entity types:
  - `hash_function` - Full function (body + spec)
  - `hash_function_spec` - Just spec (for call dependencies)
  - `hash_predicate`, `hash_logical_function`, `hash_lemma`
  - `hash_struct_definition`, `hash_datatype_definition`
- Normalization utilities:
  - `normalize_it` - Index terms with alpha-renaming
  - `normalize_lc` - Logical constraints
  - `serialize_*` - Canonical string representation

**lib/dependencyExtractor.ml** (~800 lines)
- Extract dependencies from CN definitions
- Functions for each entity type:
  - `extract_function_calls` - Find function calls in bodies
  - `extract_predicate_uses` - Find predicates in specs/bodies
  - `extract_logical_function_uses` - Find logical functions
  - `extract_lemma_uses` - Find lemmas
  - `extract_struct_uses` - Find struct types
  - `extract_datatype_uses` - Find datatype types
- Recursive extraction from nested constructs
- Traverses: IT.t, LC.t, BT.t, LAT.t, RT.t, Mucore expressions

**lib/check.ml** (modifications ~300 lines)
- Integration into verification pipeline
- Filter stale functions before verification (lines 3383-3512):
  - Compute content hashes for all definitions
  - Query database for cached results
  - Check content changes, dependency changes (recursive)
  - Return filtered list of functions needing verification
- Record results after verification (lines 3046-3103):
  - Store success/failure with timing
  - Extract and record all dependencies
  - Handle errors gracefully

**bin/cache.ml** (~200 lines)
- Cache inspection CLI tool
- Four commands:
  - `show_summary` - Statistics (counts by status)
  - `show_failures` - List failed functions with errors
  - `show_file` - Functions in specific file
  - `clear_cache` - Delete database
- Uses Cmdliner for argument parsing

**bin/verify.ml** (modifications ~50 lines)
- Add CLI flags: `--use-db`, `--db-path`, `--clear-db`
- Open/close database handle
- Pass db to `time_check_c_functions`

### Database Schema

SQLite tables (see lib/verificationDb.ml for full schema):
- `functions`, `predicates`, `logical_functions`, `lemmata` - Entity status
- `struct_definitions`, `datatype_definitions` - Type definitions
- 15+ dependency junction tables (e.g., `function_calls_function`, `function_uses_predicate`)
- Indexes on content_hash, status for performance

### Test Structure

All tests in `tests/cn/caching/` follow this pattern:

**Directory structure:**
```
test_name/
├── foo_1.c        # Initial version
├── foo_2.c        # Modified version
├── test.sh        # Test script
└── README.md      # Documentation
```

**Test script pattern:**
```bash
#!/bin/bash
# 1. Clear cache, verify foo_1.c (should run)
# 2. Verify foo_1.c again (should be cached)
# 3. Verify foo_2.c (should re-run due to change)
```

**Test categories:**

1. **Basic change detection** (9 tests):
   - `spec_change` - Pre/postcondition changes
   - `body_change` - Function implementation changes
   - `comment_change` - Comments don't trigger re-verification ✓
   - `argument_rename` - Parameter renames don't trigger (alpha-renaming) ✓
   - `split_case_change` - Proof guidance annotation changes
   - `assert_change` - Assertion statement changes
   - `cached_failure` - Failed verifications are cached
   - `broken_implementation` - Spec passes, implementation fails

2. **Function dependencies** (4 tests):
   - `function_call` - Function → function (spec-only policy)
   - `predicate_change` - Function → predicate
   - `logical_function_change` - Function → logical function
   - `lemma` - Function → lemma

3. **Struct/datatype dependencies** (2 tests):
   - `struct_change` - Function → struct
   - `datatype_change` - Function → datatype

4. **Predicate dependencies** (3 tests):
   - `predicate_uses_logical_function` - Predicate → logical function
   - `predicate_uses_struct` - Predicate → struct
   - `predicate_uses_datatype` - Predicate → datatype

5. **Logical function dependencies** (3 tests):
   - `logical_function_recursive` - Logical function → logical function
   - `logical_function_uses_struct` - Logical function → struct
   - `logical_function_uses_datatype` - Logical function → datatype

6. **Lemma dependencies** (3 tests):
   - `lemma_uses_logical_function` - Lemma → logical function
   - `lemma_uses_struct` - Lemma → struct
   - `lemma_uses_datatype` - Lemma → datatype

7. **Transitive dependencies** (2 tests):
   - `transitive_dependency` - Changes propagate through call chains
   - `transitive_predicate` - Changes propagate through predicate uses

**Total: 26 tests covering all dependency types**

Each test verifies:
- First run performs verification ✓
- Second run (identical) uses cache (no output) ✓
- Third run (with change) re-verifies ✓

Run all tests:
```bash
cd tests/cn/caching
for dir in */; do 
  echo "Testing $dir"
  (cd "$dir" && bash test.sh) || exit 1
done
```

### Key Design Decisions

1. **Alpha-renaming normalization**: Variable names normalized to `v_type_N` to ignore renames
2. **Hybrid dependency policy**: Spec-only for calls, full-content for predicates/logical functions
3. **Recursive dependency checking**: Uses visited set to handle cycles
4. **Failure caching**: Failures cached exactly like successes (skipped if nothing changed)
5. **SQLite vs files**: Database chosen for efficient queries and concurrent access
6. **Content hashing**: MD5 of normalized AST (not source text) for accurate change detection
