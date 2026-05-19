# CN Allocation ID and Provenance Tests

This directory contains comprehensive tests and documentation for CN's provenance separation features, particularly the `__cerbvar_copy_alloc_id` builtin.

## Quick Start

```bash
# Verify all positive tests pass
cn verify tests/cn/alloc_id/copy_alloc_id_with_spec.c        # 5/5 pass
cn verify tests/cn/alloc_id/copy_alloc_id_complete_demo.c    # 9/9 pass
cn verify tests/cn/alloc_id/provenance_demo_simple.c         # 16/16 pass

# Verify all negative tests fail (as expected)
cn verify tests/cn/alloc_id/copy_alloc_id_negative_tests.c   # 10/10 fail correctly
```

## Test Files

### Positive Tests (Demonstrate What Works)

| File | Tests | Status | Description |
|------|-------|--------|-------------|
| `copy_alloc_id_with_spec.c` | 5 | ✅ All pass | Core __cerbvar_copy_alloc_id examples |
| `copy_alloc_id_complete_demo.c` | 9 | ✅ All pass | Complete provenance operations |
| `provenance_demo_simple.c` | 16 | ✅ All pass | Provenance without __cerbvar_copy_alloc_id |

**Total: 30 passing tests**

### Negative Tests (Demonstrate What's Prevented)

| File | Tests | Status | Description |
|------|-------|--------|-------------|
| `copy_alloc_id_negative_tests.c` | 10 | ✅ All fail | Safety property verification |

**Total: 10 correctly failing tests**

## Documentation Files

### Main Documentation

- **`README.md`** - Complete index of all tests and documentation
- **`SUCCESS_SUMMARY.md`** - Overview of successful verification
- **`provenance_separation_guide.md`** - Comprehensive guide to provenance in CN

### Detailed Guides

- **`pointer_integer_casts_guide.md`** - Pointer/integer conversion patterns
- **`copy_alloc_id_spec_findings.md`** - Investigation into spec-level availability
- **`NEGATIVE_TESTS_SUMMARY.md`** - Analysis of safety properties

### Analysis Documents

- **`FAILING_FUNCTIONS_ANALYSIS.md`** - Notes on fixing failing tests
- **`MAP_MERGE_PATTERNS.md`** - Map merge patterns (related work)

## The Key Spec

All tests rely on this spec for `__cerbvar_copy_alloc_id`:

```c
void* __cerbvar_copy_alloc_id(uintptr_t addr, void* ptr);

/*@ spec __cerbvar_copy_alloc_id(u64 addr_val, pointer prov_source);
    requires has_alloc_id(prov_source);
             take A = Alloc(prov_source);
             A.base <= addr_val;
             addr_val <= A.base + A.size;
    ensures  (u64)return == addr_val;
             (alloc_id)return == (alloc_id)prov_source;
             take A2 = Alloc(prov_source);
             A2 == A;
@*/
```

## What This Tests

### Provenance Operations

✅ Extract address: `(u64)ptr`  
✅ Extract allocation ID: `(alloc_id)ptr`  
✅ Check provenance: `has_alloc_id(ptr)`  
✅ Combine address + provenance: `__cerbvar_copy_alloc_id(addr, ptr)`  
✅ Access allocation metadata: `Alloc(ptr)`  
✅ Tagged pointers (set/clear bits)  
✅ Pointer arithmetic via integers  
✅ Pointer alignment  
✅ Bit masking operations  

### Safety Properties

❌ Cannot access below allocation base  
❌ Cannot access past allocation end  
❌ Cannot mix allocations  
❌ Cannot forge arbitrary pointers  
❌ Must have allocation metadata  
❌ Must prove all bounds constraints  

## Test Results Summary

```
Positive Tests: 30/30 PASS ✅
Negative Tests: 10/10 FAIL ✅ (as expected)
Total Coverage: 40 tests
```

## Integration with CN Test Suite

These tests are part of CN's standard test suite under `tests/cn/`. They can be run with:

```bash
# Run all CN tests (includes alloc_id tests)
cd tests
./run-all-commands.sh verify all

# Or specifically test alloc_id directory
cn verify tests/cn/alloc_id/*.c
```

## Key Insights

1. **Provenance is separate from address** - Can extract and reason about each independently
2. **The spec works!** - Providing a proper spec for `__cerbvar_copy_alloc_id` enables full verification
3. **Safety is enforced** - All attempted violations are caught
4. **Practical patterns** - Tagged pointers, alignment, MMIO all work

## For More Information

Start with `README.md` for a complete overview, then see `SUCCESS_SUMMARY.md` for the achievement summary.

For implementation details, see `provenance_separation_guide.md`.

For safety properties, see `NEGATIVE_TESTS_SUMMARY.md`.

---

**Created:** 2026-05-19  
**Status:** All 40 tests verified and documented
