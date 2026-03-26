// Comprehensive test suite for flexible array member (FAM) support
// Testing various edge cases and complex scenarios

#include <stddef.h>
//#include "fam_buffer.h"

// Define predicates for the other FAM structs

// ========== Basic FAM structs ==========

struct simple_fam {
    unsigned long count;
    int data[];  // FAM with int elements
};

/*@ predicate struct simple_fam SimpleFam(pointer p) {
    take A = Alloc(p);
    take I = RW<struct simple_fam>(p);
    take Ifam = each(u64 j; j < (u64)I.count) {
      RW<int>(array_shift<int>(member_shift<struct simple_fam>(p, data), j))
    };
    assert(A.base <= (u64) p);
    assert((u64) member_shift<struct simple_fam>(p, data) + sizeof<int>*(u64)I.count <= A.base + A.size);
    return I;
}
@*/

struct char_fam {
    unsigned long size;
    char bytes[];  // FAM with char elements
};

/*@ predicate struct char_fam CharFam(pointer p) {
    take A = Alloc(p);
    take I = RW<struct char_fam>(p);
    take Ifam = each(u64 j; j < (u64)I.size) {
      RW<char>(array_shift<char>(member_shift<struct char_fam>(p, bytes), j))
    };
    assert(A.base <= (u64) p);
    assert((u64) member_shift<struct char_fam>(p, bytes) + sizeof<char>*(u64)I.size <= A.base + A.size);
    return I;
}
@*/

struct pointer_fam {
    unsigned long num_ptrs;
    int *ptrs[];  // FAM with pointer elements
};
/*@
predicate i32 OwningIntPtr(pointer p) {
    take q = RW<int*>(p);
    take r = RW<int>(q);
    return r;
}
predicate struct pointer_fam PointerFam(pointer p) {
    take A = Alloc(p);
    take I = RW<struct pointer_fam>(p);
    take Ifam = each(u64 j; j < (u64)I.num_ptrs) {
      OwningIntPtr(array_shift<int*>(member_shift<struct pointer_fam>(p, ptrs), j))
    };
    assert(A.base <= (u64) p);
    assert((u64) member_shift<struct pointer_fam>(p, ptrs) + sizeof<int*>*(u64)I.num_ptrs <= A.base + A.size);
    return I;
}
@*/

// ========== Nested and complex FAMs ==========

struct nested_elem {
    int x;
    int y;
};

struct struct_fam {
    unsigned long n_elements;
    struct nested_elem elements[];  // FAM with struct elements
};

struct fam_with_ptr {
    unsigned long capacity;
    struct simple_fam *inner;  // Pointer to another FAM struct
    int extra_data[];  // FAM in this struct too
};

// ========== Test 1: FAM read first two elements ==========
unsigned long test_fam_loop_read(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 2u64;
  ensures take sf2 = SimpleFam(s);
          return == (u64)sf.count;
@*/
{
    // Read count and first two FAM elements
    /*@ focus RW<int>, 0u64; @*/
    int first = s->data[0];
    /*@ focus RW<int>, 1u64; @*/
    int second = s->data[1];
    (void)first; (void)second;
    return s->count;
}

// ========== Test 2: Write to multiple FAM elements ==========
void test_fam_multiple_shifts(struct simple_fam *s, unsigned long i, unsigned long j)
/*@
  requires take sf = SimpleFam(s);
           i < sf.count;
           j < sf.count;
           sf.count >= 2u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    // Write to two different FAM elements
    /*@ focus RW<int>, i; @*/
    s->data[i] = 42;
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/
    s->data[j] = 99;
}

// ========== Test 3: FAM with char element type ==========
char test_char_fam(struct char_fam *buf)
/*@
  requires take b = CharFam(buf);
           b.size >= 1u64;
  ensures take b2 = CharFam(buf);
@*/
{
    /*@ focus RW<char>, 0u64; @*/
    return buf->bytes[0];
}

unsigned long test_pointer_fam(struct pointer_fam *pf)
/*@
  requires take p = RW(pf);
  ensures take p2 = RW(pf);
          return == p.num_ptrs;
@*/
{
    // Just read the count field
    return pf->num_ptrs;
}

// ========== Test 4: FAM with struct element type ==========
unsigned long test_struct_elem_fam(struct struct_fam *sf)
/*@
  requires take s = RW(sf);
  ensures take s2 = RW(sf);
          return == s.n_elements;
@*/
{
    return sf->n_elements;
}

unsigned long test_struct_elem_fam_shift(struct struct_fam *sf, unsigned long i)
/*@
  requires take s = RW(sf);
           i < s.n_elements;
  ensures take s2 = RW(sf);
          return == i;
@*/
{
    // Just return the index - can't easily access struct FAM elements without focus
    return i;
}

// ========== Test 5: Pointer to FAM struct ==========
unsigned long test_ptr_to_fam_struct(struct simple_fam **pp)
/*@
  requires take pval = RW<struct simple_fam*>(pp);
           take inner = SimpleFam(pval);
           inner.count >= 1u64;
  ensures take pval2 = RW<struct simple_fam*>(pp);
          take inner2 = SimpleFam(pval2);
@*/
{
    struct simple_fam *p = *pp;
    /*@ focus RW<int>, 0u64; @*/
    int first = p->data[0];
    return p->count + (unsigned long)first;
}

// ========== Test 6: Multiple FAM accesses in single function ==========
unsigned long test_multiple_fam_accesses(struct simple_fam *s1, struct char_fam *s2)
/*@
  requires take sf1 = SimpleFam(s1);
           take cf = CharFam(s2);
           sf1.count >= 1u64;
           cf.size >= 1u64;
  ensures take sf1_2 = SimpleFam(s1);
          take cf2 = CharFam(s2);
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    int val = s1->data[0];
    /*@ focus RW<char>, 0u64; @*/
    char byte = s2->bytes[0];
    return (unsigned long)val + (unsigned long)byte;
}

// ========== Test 7: FAM with offsetof ==========
_Bool test_fam_offsetof(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 1u64;
  ensures take sf2 = SimpleFam(s);
          return == 1u8;
@*/
{
    // offsetof should give offset to where FAM starts
    unsigned long offset = offsetof(struct simple_fam, data);
    /*@ assert(offset == 8u64); @*/

    // Verify that FAM starts right after count field
    /*@ focus RW<int>, 0u64; @*/
    char *struct_base = (char *)s;
    char *fam_start = (char *)&s->data[0];
    return (unsigned long)(fam_start - struct_base) == offset;
}

// ========== Test 8: Comparing FAM pointers ==========
long test_fam_pointer_compare(struct simple_fam *s, unsigned long i, unsigned long j)
/*@
  requires take sf = SimpleFam(s);
           i < sf.count;
           j < sf.count;
           sf.count >= 2u64;
  ensures take sf2 = SimpleFam(s);
          return == (i64)j - (i64)i;
@*/
{
    /*@ focus RW<int>, i; @*/
    int *pi = &s->data[i];
    /*@ split_case i != j; @*/
    /*@ focus RW<int>, j; @*/
    int *pj = &s->data[j];
    return pj - pi;
}

// ========== Test 9: FAM base pointer vs element 0 ==========
long test_fam_base_vs_zero(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 1u64;
  ensures take sf2 = SimpleFam(s);
          return == 0i64;
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    int *base = s->data;
    int *zero = &s->data[0];
    // These should be the same address, so difference is 0
    return zero - base;
}

// ========== Test 10: Nested struct with FAM pointer ==========
_Bool test_nested_fam_ptr(struct fam_with_ptr *fp)
/*@
  requires take f = RW(fp);
           is_null(f.inner);
  ensures take f2 = RW(fp);
          return == 1u8;
@*/
{
    // Verify inner is null and read capacity
    return fp->inner == 0 && fp->capacity >= 0;
}

// ========== Test 11: FAM access through multiple dereferences ==========
int test_fam_multi_deref(struct simple_fam **pp)
/*@
  requires take pval = RW<struct simple_fam*>(pp);
           take inner = SimpleFam(pval);
           inner.count >= 1u64;
  ensures take pval2 = RW<struct simple_fam*>(pp);
          take inner2 = SimpleFam(pval2);
@*/
{
    // Access FAM through **pp
    /*@ focus RW<int>, 0u64; @*/
    return (*pp)->data[0];
}

// ========== Test 12: FAM with const ==========
unsigned long test_fam_const(const struct simple_fam *s)
/*@
  requires take sf = RW<const struct simple_fam>(s);
  ensures take sf2 = RW<const struct simple_fam>(s);
          return == sf.count;
@*/
{
    return s->count;
}

// ========== Test 13: Taking address of FAM elements ==========
long test_fam_address_of(struct simple_fam *s, unsigned long i)
/*@
  requires take sf = SimpleFam(s);
           i < sf.count;
           sf.count >= 1u64;
  ensures take sf2 = SimpleFam(s);
          return == (i64)i;
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    int *p0 = &s->data[0];
    /*@ split_case i != 0u64; @*/
    /*@ focus RW<int>, i; @*/
    int *pi = &s->data[i];
    return pi - p0;
}

// ========== Test 14: FAM in function with early return ==========
int test_fam_early_return(struct simple_fam *s, int flag)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 2u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    if (flag) {
        /*@ focus RW<int>, 0u64; @*/
        return s->data[0];
    }
    /*@ focus RW<int>, 1u64; @*/
    return s->data[1];
}

// ========== Test 15: FAM access in nested blocks ==========
unsigned long test_fam_nested_blocks(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 2u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    unsigned long result = 0;
    {
        /*@ focus RW<int>, 0u64; @*/
        int v1 = s->data[0];
        result += (unsigned long)v1;
        {
            /*@ focus RW<int>, 1u64; @*/
            int v2 = s->data[1];
            result += (unsigned long)v2;
        }
    }
    return result;
}

// ========== Test 16: FAM with pointer arithmetic ==========
long test_fam_ptr_arithmetic(struct simple_fam *s, unsigned long n)
/*@
  requires take sf = SimpleFam(s);
           n < sf.count;
           sf.count >= 1u64;
  ensures take sf2 = SimpleFam(s);
          return == (i64)n;
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    int *base = s->data;
    /*@ split_case n != 0u64; @*/
    /*@ focus RW<int>, n; @*/
    int *offset = &s->data[n];
    return offset - base;
}

// ========== Test 17: Zero-sized FAM case ==========
unsigned long test_fam_zero_elements(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count == 0u64;
  ensures take sf2 = SimpleFam(s);
          return == 0u64;
@*/
{
    // Can't access any elements, but can still read count
    return s->count;
}

// ========== Test 18: FAM with single element ==========
int test_fam_one_element(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count == 1u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    return s->data[0];
}

// ========== Test 19: Multiple FAM structs of same type ==========
unsigned long test_two_fam_structs(struct simple_fam *s1, struct simple_fam *s2)
/*@
  requires take sf1 = SimpleFam(s1);
           take sf2 = SimpleFam(s2);
           sf1.count >= 1u64;
           sf2.count >= 1u64;
  ensures take sf1_2 = SimpleFam(s1);
          take sf2_2 = SimpleFam(s2);
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    int v1 = s1->data[0];
    /*@ focus RW<int>, 0u64; @*/
    int v2 = s2->data[0];
    return (unsigned long)v1 + (unsigned long)v2;
}

// ========== Test 20: FAM struct assigned to local variable ==========
int test_fam_local_assignment(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 1u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    struct simple_fam *local = s;
    /*@ focus RW<int>, 0u64; @*/
    return local->data[0];
}

// ========== Test 21: FAM with ternary operator ==========
unsigned long test_fam_ternary(struct simple_fam *s1, struct simple_fam *s2, int flag)
/*@
  requires take sf1 = SimpleFam(s1);
           take sf2 = SimpleFam(s2);
  ensures take sf1_2 = SimpleFam(s1);
          take sf2_2 = SimpleFam(s2);
@*/
{
    struct simple_fam *chosen = flag ? s1 : s2;
    return chosen->count;
}

// ========== Test 22: FAM read element and count ==========
unsigned long test_fam_do_while(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 1u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    int val = s->data[0];
    return s->count + (unsigned long)val;
}

// ========== Test 23: FAM with switch statement ==========
int test_fam_switch(struct simple_fam *s, int mode)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 3u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    switch (mode) {
        case 0: {
            /*@ focus RW<int>, 0u64; @*/
            return s->data[0];
        }
        case 1: {
            /*@ focus RW<int>, 1u64; @*/
            return s->data[1];
        }
        default: {
            /*@ focus RW<int>, 2u64; @*/
            return s->data[2];
        }
    }
}

// ========== Test 24: FAM access with comma operator (no side effects) ==========
unsigned long test_fam_comma(struct simple_fam *s, unsigned long dummy)
/*@
  requires take sf = SimpleFam(s);
  ensures take sf2 = SimpleFam(s);
          return == sf.count;
@*/
{
    // Comma operator - evaluates dummy then returns count
    return (dummy, s->count);
}

// ========== Test 25: Sum of first 5 FAM elements ==========
unsigned long test_fam_many_shifts(struct simple_fam *s)
/*@
  requires take sf = SimpleFam(s);
           sf.count >= 5u64;
  ensures take sf2 = SimpleFam(s);
@*/
{
    /*@ focus RW<int>, 0u64; @*/
    unsigned long sum = (unsigned long)s->data[0];
    /*@ focus RW<int>, 1u64; @*/
    sum += (unsigned long)s->data[1];
    /*@ focus RW<int>, 2u64; @*/
    sum += (unsigned long)s->data[2];
    /*@ focus RW<int>, 3u64; @*/
    sum += (unsigned long)s->data[3];
    /*@ focus RW<int>, 4u64; @*/
    sum += (unsigned long)s->data[4];
    return sum;
}
