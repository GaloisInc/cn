# CN Incremental Verification Test Suite

This directory contains tests for CN's incremental verification caching system.

## Running Tests

```bash
# Run all tests
./run_all.sh

# Run individual tests
cd spec_change && ./run.sh
```

## Test Cases

### ✅ spec_change
Tests that changing a function specification triggers re-verification.

**Expected**: Function re-verified after spec change.

### ✅ body_change  
Tests that changing only the function body does NOT trigger re-verification.

**Expected**: Function skipped (spec hash unchanged).

### ✅ predicate_change
Tests that changing a predicate definition triggers re-verification of dependent functions.

**Expected**: Functions using the predicate are re-verified.

### ✅ logical_function_change
Tests that changing a logical function definition triggers re-verification of dependent functions.

**Expected**: Functions using the logical function are re-verified.

### ✅ comment_change
Tests that changing comments does NOT trigger re-verification.

**Expected**: Function skipped (comments don't affect parsing).

### ⚠️  argument_rename
Tests argument renaming behavior.

**Current**: Re-verifies (no alpha-renaming yet).
**Desired**: Should skip (semantically equivalent).

### ⚠️  transitive_dependency
Tests transitive dependency tracking (A → B → C).

**Current**: Only direct dependencies checked.
**Desired**: Should check transitive dependencies.

## Implementation Status

### ✅ Implemented
- Function spec hashing (ignores body changes)
- Predicate dependency tracking and invalidation
- Logical function dependency tracking and invalidation  
- Struct/datatype dependency tracking and invalidation
- Database persistence with SQLite
- Incremental verification (skip unchanged functions)

### ⏳ TODO
- Alpha-renaming normalization in spec hashing
- Transitive dependency tracking
- Function call dependency tracking (track callee specs)
- Loop invariant change tracking

## Architecture

- **Database**: `.cn/verification.db` (per-project SQLite database)
- **Hash Strategy**: Content-based hashing of function specifications
- **Dependency Policy**:
  - Function calls → callee spec hash (body changes don't invalidate)
  - Predicates → full content hash (body matters)
  - Logical functions → full content hash (body matters)
  - Structs/datatypes → full definition hash

## Performance

Incremental verification provides significant speedups when:
- Making localized changes to specifications
- Changing function bodies without spec changes
- Working with large codebases with many verified functions

Measurements on `tests/cn/append.c`:
- First run: ~460ms total (IntList_append: 87ms, split: 376ms)
- Second run: ~0ms (both functions skipped)
