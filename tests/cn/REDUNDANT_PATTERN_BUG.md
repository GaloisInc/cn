# Bug Report: False "Redundant patterns" error in cn test

## Summary
`cn test` crashes with "Redundant patterns" error when translating match expressions that use wildcard patterns after concrete constructor patterns.

## Error Message
```
cn: internal error, uncaught exception:
    Failure("File \"lib/fulminate/cn_to_ail.ml\", line 1712, characters 46-53: Redundant patterns")
```

## Minimal Reproduction Case

File: `tests/cn/redundant_pattern_wildcard.c`

```c
/*@
datatype Reg {
    RDH {},
    RDT {},
    CTRL {}
}

function (boolean) check_reg(datatype Reg r) {
    match r {
        RDH{} => { true }
        _ => { true }
    }
}
@*/

void test()
/*@ requires true;
    ensures true;
@*/
{
    return;
}
```

## Expected Behavior
The match expression is valid and non-redundant:
- `RDH{}` matches the `RDH` constructor
- `_` matches the remaining constructors (`RDT{}` and `CTRL{}`)

`cn test` should successfully generate and run tests.

## Actual Behavior
`cn test` crashes with internal error in `lib/fulminate/cn_to_ail.ml:1712`

## Workaround
- `cn verify` works correctly on these files
- The bug only affects test generation (Fulminate component)
- Writing out all constructor patterns explicitly avoids the bug:
  ```c
  match r {
      RDH{} => { true }
      RDT{} => { true }
      CTRL{} => { true }
  }
  ```

## Root Cause
The pattern match redundancy checker in `cn_to_ail.ml` incorrectly analyzes wildcard patterns after concrete patterns, flagging valid matches as redundant.

## Original Discovery
Found while running `cn test` on the i210-model hardware verification project, which uses wildcard patterns extensively in register matching logic.

Reduced from 2953-line preprocessed file to 21-line minimal case using `creduce`.

## References
- Original issue: i210-model test files failing with `cn test`
- Location: `lib/fulminate/cn_to_ail.ml:1712`
- Related files:
  - `tests/cn/redundant_pattern_wildcard.c` (minimal 21-line reproduction)
  - `tests/cn/redundant_pattern_minimal.c` (245-line creduce output from i210)
