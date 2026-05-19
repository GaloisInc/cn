// Demonstration of CN provenance separation features
// Focuses on features that work without __cerbvar_copy_alloc_id specs

#include <stdint.h>
#include <stddef.h>
#include <assert.h>

// =============================================================================
// Example 1: Extract Address from Pointer - (u64)ptr
// =============================================================================

void example_extract_address(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
    ensures  take Px2 = RW<int>(p);
             take Qx2 = RW<int>(q);
             Px2 == Px;
             Qx2 == Qx;
@*/
{
    // Extract addresses as u64 values
    uintptr_t p_addr = (uintptr_t)p;
    uintptr_t q_addr = (uintptr_t)q;

    // Can reason about addresses in specs
    /*@ assert((u64)p == p_addr); @*/
    /*@ assert((u64)q == q_addr); @*/

    // Addresses of different allocations are different
    /*@ assert(p_addr != q_addr); @*/
}

// =============================================================================
// Example 2: Compare Addresses (Ignoring Provenance)
// =============================================================================

_Bool addresses_equal(void *p, void *q)
/*@ requires true;
    ensures  return == (((u64)p == (u64)q) ? 1u8 : 0u8);
@*/
{
    // Compare only the numeric addresses
    uintptr_t p_addr = (uintptr_t)p;
    uintptr_t q_addr = (uintptr_t)q;
    return p_addr == q_addr;
}

// =============================================================================
// Example 3: Check Has Allocation ID
// =============================================================================

void must_have_provenance(int *p)
/*@ requires has_alloc_id(p);
             take Px = RW<int>(p);
             Px < 1000i32;  // Avoid overflow
    ensures  take Px2 = RW<int>(p);
             Px2 == Px + 1i32;
@*/
{
    // Can safely dereference because has_alloc_id ensures provenance
    int val = *p;
    *p = val + 1;
}

// =============================================================================
// Example 4: Check Specific Address Value
// =============================================================================

void check_address_value(int *p)
/*@ requires take Px = RW<int>(p);
             (u64)p == 0x1000u64;
    ensures  take Px2 = RW<int>(p);
             Px2 == Px;
@*/
{
    // Verify address is at expected value
    uintptr_t addr = (uintptr_t)p;
    /*@ assert(addr == 0x1000u64); @*/
}

// =============================================================================
// Example 5: Extract and Compare Allocation IDs
// =============================================================================

void same_allocation(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
             (alloc_id)p == (alloc_id)q;  // Same allocation
             (u64)p + 4u64 == (u64)q;      // Adjacent
    ensures  take Px2 = RW<int>(p);
             take Qx2 = RW<int>(q);
             Px2 == Px;
             Qx2 == Qx;
@*/
{
    // Two pointers in same allocation
    /*@ assert((alloc_id)p == (alloc_id)q); @*/

    // Can verify they're adjacent
    uintptr_t p_addr = (uintptr_t)p;
    uintptr_t q_addr = (uintptr_t)q;
    /*@ assert(q_addr == p_addr + 4u64); @*/
}

void different_allocations(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
             (alloc_id)p != (alloc_id)q;  // Different allocations
    ensures  take Px2 = RW<int>(p);
             take Qx2 = RW<int>(q);
             Px2 == Px;
             Qx2 == Qx;
@*/
{
    // Two pointers to different allocations
    /*@ assert((alloc_id)p != (alloc_id)q); @*/
}

// =============================================================================
// Example 6: Use Allocation Metadata
// =============================================================================

_Bool pointer_in_bounds_check(char *p, size_t access_size)
/*@ requires has_alloc_id(p);
             take A = Alloc(p);
             A.base <= (u64)p;
             (u64)p + access_size <= A.base + A.size;
    ensures  take A2 = Alloc(p);
             A2 == A;
             return == 1u8;
@*/
{
    // Demonstrating access to Alloc predicate fields
    // A.base - base address of allocation
    // A.size - size of allocation in bytes
    return 1;
}

// =============================================================================
// Example 7: Stored Address Pattern (Common in Hardware Descriptors)
// =============================================================================

struct Descriptor {
    uintptr_t buffer_addr;
    size_t size;
};

void init_descriptor(struct Descriptor *desc, char *buffer, size_t size)
/*@ requires take D = RW<struct Descriptor>(desc);
             size > 0u64;
    ensures  take D2 = RW<struct Descriptor>(desc);
             D2.buffer_addr == (u64)buffer;
             D2.size == size;
@*/
{
    // Store address as integer (this loses provenance!)
    desc->buffer_addr = (uintptr_t)buffer;
    desc->size = size;
}

void use_descriptor_safe(struct Descriptor *desc, char *buffer_with_provenance)
/*@ requires take D = RW<struct Descriptor>(desc);
             take B = RW<char>(buffer_with_provenance);
             D.buffer_addr == (u64)buffer_with_provenance;  // Addresses match
    ensures  take D2 = RW<struct Descriptor>(desc);
             take B2 = RW<char>(buffer_with_provenance);
             D2.buffer_addr == D.buffer_addr;
             D2.size == D.size;
             B2 == 0xFFu8;
@*/
{
    // The descriptor stores address as integer (no provenance)
    uintptr_t stored_addr = desc->buffer_addr;

    // Verify addresses match
    /*@ assert((u64)buffer_with_provenance == stored_addr); @*/

    // Use the pointer WITH provenance, not the stored integer
    *buffer_with_provenance = 0xFF;

    // Cannot do this: char *p = (char*)stored_addr; *p = 0xFF;
    // That would fail because stored_addr is just integer, no provenance
}

// =============================================================================
// Example 8: MMIO Pattern (Trusted Function)
// =============================================================================

// Axiomatically assert that hardware address has provenance
uint32_t* mmio_base();
/*@ spec mmio_base();
    trusted;
    ensures
        // At fixed hardware address
        (u64)return == 0xE0000000u64;
        // Has valid provenance
        has_alloc_id(return);
        // Has allocation bounds
        take A = Alloc(return);
        A.base == 0xE0000000u64;
        A.size >= 4096u64;
        // Has ownership for reading
        take reg = RW<unsigned int>(return);
@*/

uint32_t mmio_read()
/*@ trusted;
    requires true;
    ensures  true;
@*/
{
    uint32_t *mmio = mmio_base();

    // Can verify address
    /*@ assert((u64)mmio == 0xE0000000u64); @*/

    // Can verify provenance exists
    /*@ assert(has_alloc_id(mmio)); @*/

    // Can dereference (has provenance from trusted function)
    return *mmio;
}

// =============================================================================
// Example 9: Pointer Arithmetic Preserves Provenance
// =============================================================================

int* array_next(int *p)
/*@ requires take P = RW<int>(p);
             take Next = RW<int>(array_shift<int>(p, 1u64));
    ensures  take P2 = RW<int>(p);
             take Next2 = RW<int>(array_shift<int>(p, 1u64));
             P2 == P;
             Next2 == Next;
             (u64)return == (u64)p + 4u64;
             (alloc_id)return == (alloc_id)p;
@*/
{
    // Regular pointer arithmetic preserves provenance
    int *next = p + 1;

    // Verify address and provenance
    /*@ assert((u64)next == (u64)p + 4u64); @*/
    /*@ assert((alloc_id)next == (alloc_id)p); @*/

    return next;
}

// =============================================================================
// Example 10: Member Access Preserves Provenance
// =============================================================================

struct Container {
    int header;
    char data[100];
};

char* get_data_ptr(struct Container *c)
/*@ requires take C = RW<struct Container>(c);
    ensures  take C2 = RW<struct Container>(c);
             C2 == C;
             // Result points within container
             (u64)c <= (u64)return;
             // Result has same provenance as container
             (alloc_id)return == (alloc_id)c;
@*/
{
    // Member access preserves provenance
    char *data = c->data;

    /*@ assert((alloc_id)data == (alloc_id)c); @*/

    return data;
}

// =============================================================================
// Example 11: Array Shift Preserves Provenance
// =============================================================================

int* get_array_element(int *arr, size_t idx)
/*@ requires take Elem = RW<int>(array_shift<int>(arr, idx));
    ensures  take Elem2 = RW<int>(array_shift<int>(arr, idx));
             Elem2 == Elem;
             (u64)return == (u64)arr + (idx * 4u64);
             (alloc_id)return == (alloc_id)arr;
@*/
{
    int *elem = arr + idx;

    /*@ assert((alloc_id)elem == (alloc_id)arr); @*/

    return elem;
}

// =============================================================================
// Example 12: Provenance Lost with Plain Cast (Anti-Pattern)
// =============================================================================

int* broken_roundtrip_demo(int *p)
/*@ requires take Px = RW<int>(p);
    ensures  take Px2 = RW<int>(p);
             Px2 == Px;
             // Result has same address
             (u64)return == (u64)p;
             // But we can guarantee same provenance because we return p
             (alloc_id)return == (alloc_id)p;
@*/
{
    uintptr_t addr = (uintptr_t)p;

    // If we did: int *q = (int*)addr;
    // Then q would have the same address but NO provenance!
    // We can't dereference q

    // Must use original p (which has provenance)
    return p;
}

// =============================================================================
// Example 13: Comparing Pointer Components
// =============================================================================

void pointer_analysis(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
    ensures  take Px2 = RW<int>(p);
             take Qx2 = RW<int>(q);
             Px2 == Px;
             Qx2 == Qx;
@*/
{
    // Three levels of pointer equality:

    // 1. Full pointer equality (address AND provenance)
    _Bool ptrs_equal = (p == q);

    // 2. Address equality only
    _Bool addrs_equal = ((uintptr_t)p == (uintptr_t)q);

    // 3. Provenance equality only
    // (Would need: ((alloc_id)p == (alloc_id)q)
    // but can't extract as bool in C code, only in specs)

    // Can have: same address, different provenance (after int->ptr cast)
    // Can have: different address, same provenance (pointers into same array)
}

// =============================================================================
// Example 14: Reasoning About Address Arithmetic
// =============================================================================

size_t address_arithmetic(int *p, int *q)
/*@ requires take Px = RW<int>(p);
             take Qx = RW<int>(q);
             (alloc_id)p == (alloc_id)q;
             (u64)p < (u64)q;
    ensures  take Px2 = RW<int>(p);
             take Qx2 = RW<int>(q);
             Px2 == Px;
             Qx2 == Qx;
             return == ((u64)q - (u64)p) / 4u64;
@*/
{
    // Can compute distance between pointers in same allocation
    uintptr_t p_addr = (uintptr_t)p;
    uintptr_t q_addr = (uintptr_t)q;
    size_t byte_diff = q_addr - p_addr;
    size_t elem_diff = byte_diff / sizeof(int);

    /*@ assert((u64)elem_diff == ((u64)q - (u64)p) / 4u64); @*/

    return elem_diff;
}

// =============================================================================
// Example 15: Null Pointer Special Case
// =============================================================================

void handle_null_pointer(int *p)
/*@ requires true;
    ensures  true;
@*/
{
    if (p == 0) {
        // Null pointer: address is 0, no allocation ID
        /*@ assert((u64)p == 0u64); @*/
        return;
    }

    // Non-null: could check has_alloc_id(p) but would need resources
    // This is a simplified demo
}

// =============================================================================
// Main (for compilation test)
// =============================================================================

int main()
/*@ trusted; @*/
{
    int x = 42;
    int y = 100;

    example_extract_address(&x, &y);

    _Bool addrs_eq = addresses_equal(&x, &x);
    assert(addrs_eq);

    must_have_provenance(&x);

    // Note: same_allocation and different_allocations require specific
    // resource arrangements that are demonstrated in their specs
    // but not easily callable from main without precise setup

    struct Descriptor desc;
    unsigned char buffer = 0;
    init_descriptor(&desc, (char*)&buffer, 1);
    use_descriptor_safe(&desc, (char*)&buffer);
    assert(buffer == 0xFF);

    struct Container cont = { .header = 0 };
    char *data = get_data_ptr(&cont);

    int arr[10] = {0};
    int *next = array_next(arr);
    assert(next == &arr[1]);

    int *elem = get_array_element(arr, 5);
    assert(elem == &arr[5]);

    int *roundtrip = broken_roundtrip_demo(&x);
    assert(roundtrip == &x);

    handle_null_pointer(0);
    handle_null_pointer(&x);

    return 0;
}
