# CN Map Merge Patterns

**Status**: ✅ Verified with CN

CN does not have a built-in `map_merge` or `map_union` operation. However, you can express map merging using multiple `each` statements that cover disjoint index ranges.

## Pattern 1: Basic Two-Way Merge (Concatenation)

```c
void concat_arrays(int *result, int *arr1, uint64_t n1, int *arr2, uint64_t n2)
/*@
requires
    take map1 = IntArray(arr1, n1);
    take map2 = IntArray(arr2, n2);
    take result_in = IntArray(result, n1 + n2);
ensures
    take map1_out = IntArray(arr1, n1);
    take map2_out = IntArray(arr2, n2);
    take result_out = IntArray(result, n1 + n2);
    map1_out == map1;
    map2_out == map2;

    // MERGE EXPRESSED AS TWO EACH STATEMENTS:

    // Range 1: result[0..n1) == arr1[0..n1)
    each(u64 i; i < n1) {
        result_out[i] == map1[i]
    };

    // Range 2: result[n1..n1+n2) == arr2[0..n2)
    each(u64 i; i < n2) {
        result_out[n1 + i] == map2[i]
    };
@*/
```

**Key insight**: The two `each` statements with non-overlapping index ranges together express that `result_out` is the union/merge of `map1` and `map2` on disjoint ranges.

## Pattern 2: Non-Contiguous Disjoint Ranges

```c
void scatter_merge(int *result, int *arr1, uint64_t start1, uint64_t len1,
                   int *arr2, uint64_t start2, uint64_t len2, uint64_t total)
/*@
requires
    take map1 = IntArray(arr1, len1);
    take map2 = IntArray(arr2, len2);
    take result_in = IntArray(result, total);
    // Assert disjointness
    start1 + len1 <= start2 || start2 + len2 <= start1;
    start1 + len1 <= total;
    start2 + len2 <= total;
ensures
    take map1_out = IntArray(arr1, len1);
    take map2_out = IntArray(arr2, len2);
    take result_out = IntArray(result, total);
    map1_out == map1;
    map2_out == map2;

    // MERGE AT ARBITRARY DISJOINT POSITIONS:

    // Range 1: result[start1..start1+len1) == arr1[0..len1)
    each(u64 i; i < len1) {
        result_out[start1 + i] == map1[i]
    };

    // Range 2: result[start2..start2+len2) == arr2[0..len2)
    each(u64 i; i < len2) {
        result_out[start2 + i] == map2[i]
    };
@*/
```

This pattern works for **any** disjoint ranges, not just contiguous concatenation.

## Pattern 3: Three-Way Merge (N-Way Generalization)

```c
void triple_concat(int *result,
                   int *arr1, uint64_t n1,
                   int *arr2, uint64_t n2,
                   int *arr3, uint64_t n3)
/*@
requires
    take map1 = IntArray(arr1, n1);
    take map2 = IntArray(arr2, n2);
    take map3 = IntArray(arr3, n3);
    take result_in = IntArray(result, n1 + n2 + n3);
ensures
    take map1_out = IntArray(arr1, n1);
    take map2_out = IntArray(arr2, n2);
    take map3_out = IntArray(arr3, n3);
    take result_out = IntArray(result, n1 + n2 + n3);
    map1_out == map1;
    map2_out == map2;
    map3_out == map3;

    // THREE-WAY MERGE: Use three 'each' statements

    each(u64 i; i < n1) {
        result_out[i] == map1[i]
    };
    each(u64 i; i < n2) {
        result_out[n1 + i] == map2[i]
    };
    each(u64 i; i < n3) {
        result_out[n1 + n2 + i] == map3[i]
    };
@*/
```

This generalizes to N-way merges - just use N `each` statements covering N disjoint ranges.

## Why This Works

1. **Each statement = constraint on range**: Each `each(u64 i; condition) { map[i] == value }` constrains the map on the indices satisfying `condition`.

2. **Multiple each statements = multiple constraints**: When you have multiple `each` statements with disjoint conditions, you're specifying what the map should be on multiple disjoint regions.

3. **Together they express merge**: The combination of all the `each` statements fully specifies the merged map's values on the union of all the ranges.

## Limitations

1. **No function for merging**: You can't write a CN function that takes two maps and returns their merge. The pattern only works in specifications (requires/ensures).

2. **First argument must be pointer**: CN predicates require the first argument to be a pointer, so you can't create a `IsMerge(map1, map2, result)` predicate directly.

3. **Must specify ranges explicitly**: You need to explicitly state the index ranges for each source map in the merge.

## Working Example

See `claude_scratch/map_merge_spec_only.c` for a complete, verified example demonstrating all three patterns.

## Use Cases

- Array concatenation
- Scatter/gather operations
- Partitioning and reassembly
- Hardware register state merging on disjoint address ranges
- Any operation that combines data from disjoint sources
