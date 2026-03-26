// Minimal test case for comma operator + FAM bug
//
// BUG: cn: internal error, uncaught exception: Not_found
//      Raised at Stdlib__List.find in file "list.ml", line 232
//      Called from Cn__ResourceInference.General.parametric_ftyp_args_request_step
//               in file "lib/resourceInference.ml", line 154
//
// The bug occurs when ALL of these conditions are present:
// 1. Comma operator expression: (left, right)
// 2. Left side: struct member modification with side effect (e.g., s->count++)
// 3. Right side: Flexible Array Member access (e.g., s->data)
// 4. Ensures clause contains: let binding for the FAM member
//
// Root cause: CN's resource inference tries to look up a parametric type
// argument that doesn't exist when tracking FAM access after struct mutation
// in a comma expression.

struct simple_fam {
    unsigned long count;
    int data[];  // Flexible Array Member
};

// This exact pattern triggers the Not_found exception
void test_comma_fam_increment_bug(struct simple_fam *s)
/*@
  requires take sf = RW(s);
  ensures take sf2 = RW(s);
          let ptr = s->data;
          sf2.count == sf.count + 1u64;
@*/
{
    // Comma operator: increment count, then access FAM
    int *p = (s->count++, s->data);
    (void)p;
}

// Variant: without the let binding in ensures - does it still trigger?
void test_comma_fam_no_let(struct simple_fam *s)
/*@
  requires take sf = RW(s);
  ensures take sf2 = RW(s);
          sf2.count == sf.count + 1u64;
@*/
{
    int *p = (s->count++, s->data);
    (void)p;
}

// Variant: with simple assignment instead of increment
void test_comma_fam_assign(struct simple_fam *s)
/*@
  requires take sf = RW(s);
  ensures take sf2 = RW(s);
          let ptr = s->data;
          sf2.count == 10u64;
@*/
{
    int *p = (s->count = 10, s->data);
    (void)p;
}
