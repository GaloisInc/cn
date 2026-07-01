# Using Cast Pointers with Resources in CN

## The Discovery

You **can** use `RW<int>((pointer)some_uintptr)` and make it work, but you need **both**:
1. A witness pointer with a resource
2. A resource at the cast pointer `(pointer)addr`
3. Proof that they have the same address

## The Working Pattern

```c
void use_cast_pointer(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;           // Same address
             take P1 = RW<int>(witness);      // Resource at witness
             take P2 = RW<int>((pointer)addr); // Resource at cast pointer
    ensures  take Q1 = RW<int>(witness);
             take Q2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;

    *p = 42;  // ✓ Works!
    *witness = 43;  // ✓ Also works!
}
```

**This verifies successfully!**

## Why This Works

When you have both resources:
- `RW<int>(witness)` - Establishes that memory at address `(u64)witness` is accessible
- `RW<int>((pointer)addr)` - Establishes that memory at address `addr` is accessible  
- `(u64)witness == addr` - Proves these are the same address

CN can then:
1. See that `p = (int *)addr` creates a pointer at address `addr`
2. Know that `RW<int>((pointer)addr)` provides access at that address
3. Use the resource to allow the write operation

## What Doesn't Work

### Just the witness (fails):
```c
void fail_witness_only(int *witness, uintptr_t addr)
/*@ requires (u64)witness == addr;
             take P = RW<int>(witness);  // Only witness resource
    ensures  take P2 = RW<int>(witness);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // ✗ Error: Missing resource for intToPtr
}
```

### Just the cast pointer resource (fails):
```c
void fail_cast_only(uintptr_t addr)
/*@ requires take P = RW<int>((pointer)addr);  // No witness
    ensures  take P2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // ✗ Error: Missing resource for intToPtr
}
```

### With witness but no address constraint (fails):
```c
void fail_no_address_link(int *witness, uintptr_t addr)
/*@ requires take P1 = RW<int>(witness);
             take P2 = RW<int>((pointer)addr);
             // Missing: (u64)witness == addr
    ensures  take Q1 = RW<int>(witness);
             take Q2 = RW<int>((pointer)addr);
@*/
{
    int *p = (int *)addr;
    *p = 42;  // Might fail - no proof they're the same address
}
```

## Understanding `(pointer)addr` in Specifications

When you write `RW<int>((pointer)addr)` in a CN spec:
- `(pointer)addr` is a **spec-level** cast from `u64` to `pointer`
- This creates a pointer value in the spec that has address `addr`
- **Importantly**: This pointer in the spec context may have provenance
- It's different from the C-level cast `(int *)addr` which creates `intToPtr`

## The Key Insight

The pattern works because:

1. **C-level cast loses provenance:**
   ```c
   int *p = (int *)addr;  // p is intToPtr, no provenance
   ```

2. **But the spec-level `(pointer)addr` can have provenance:**
   ```c
   /*@ take P = RW<int>((pointer)addr); @*/
   // This (pointer)addr in the spec context may have provenance
   ```

3. **With both + address equality:**
   - CN knows `witness` and `(pointer)addr` are at the same address
   - Both have resources
   - CN can connect the C-level `intToPtr` to the spec-level `(pointer)addr`
   - The write is allowed

## Practical Example: Array Element

```c
void use_array_element(int arr[10], uintptr_t elem5_addr)
/*@ requires (u64)array_shift<int>(arr, 5u64) == elem5_addr;
             take A = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             take P = RW<int>((pointer)elem5_addr);
    ensures  take A2 = each(u64 i; i < 10u64) {
                 RW<int>(array_shift<int>(arr, i))
             };
             take P2 = RW<int>((pointer)elem5_addr);
@*/
{
    int *p = (int *)elem5_addr;
    *p = 42;  // ✓ Works!
}
```

This works because:
- `array_shift<int>(arr, 5)` is the witness
- `(pointer)elem5_addr` has a resource
- They're proven to have the same address

## Comparison: Three Approaches

| Approach | Needs Alloc? | Needs Original Pointer? | Works? |
|----------|--------------|-------------------------|--------|
| `__cerbvar_copy_alloc_id` | Yes | Yes | ✓ Always |
| Dual resources (witness + cast) | No | Yes (as witness) | ✓ Yes |
| Cast alone | No | No | ✗ No |

### When to use `__cerbvar_copy_alloc_id`:
- You need actual provenance on the C-level pointer
- You're doing pointer arithmetic or manipulation
- You need to pass the pointer to other functions

### When to use dual resources:
- You're just accessing memory at a known address
- You have the witness pointer available
- You don't need the cast pointer to have actual provenance
- Simpler specs (no Alloc needed)

## Why Does This Design Make Sense?

The dual resource pattern is saying:
- "I have a witness that proves memory exists at this address"
- "I also explicitly take permission to access via the numeric address"
- "CN: please connect these two facts"

This is explicit and safe because:
1. You must provide proof the address is valid (witness pointer)
2. You must explicitly take resources at both
3. CN verifies they're at the same address

It prevents accidents while allowing intentional address-based access.

## Summary

**Yes, `RW<int>((pointer)some_uintptr)` works**, but only when combined with:

```c
/*@ requires (u64)witness == some_uintptr;
             take P1 = RW<int>(witness);
             take P2 = RW<int>((pointer)some_uintptr);
@*/
```

This gives you a way to access memory by address without using `__cerbvar_copy_alloc_id`, but you still need a witness pointer to prove the address is valid.

---

**Related:** See `PROVENANCE_AND_RESOURCES.md` for more on provenance in CN.
