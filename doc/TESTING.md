# CN Testing

CN has testing capabilities available via the `cn test` subcommand.

## Overview

Currently, CN supports only per-function tests, but additional types of testing may become available in the future.

Running `cn test <filename.c>` generates C files with the testing infrastructure, the instrumented program under test, and a build script named `run_tests.sh`.
This script compiles the C files and runs the tests.

By default, running `cn test` will automatically run `run_tests.sh`, which produces a test executable `tests.out`.
This can be disabled by using the `--no-run` flag.

The default behavior of testing is to rely on Fulminate for checking, which does not detect undefined behavior.
If you would like to also check for undefined behavior, you can use a sanitizer via `--sanitize=undefined`.

The output directory for these files can be set by using `--output-dir=<DIR>`.
If the directory does not already exist, it is created.

### Per-function tests

When testing, there are currently two types of tests, constant tests and generator-based tests.
For *each function with a body*, CN will create either a constant test or generator-based test.

If a function takes no arguments, does not use accesses on global variables, and is correct, it should always return the same value and free any memory it allocates.
In this case, a constant test is generated, which runs the function once and uses [Fulminate](FULMINATE_README.md) to check for post-condition violations.

In all other cases, it creates generator-based tests, which are in the style of property-based testing.
A "generator" is created, which randomly generates function arguments, values for globals accessed and heap states, all of which adhere to the given function's pre-condition.
It calls the function with this input and uses [Fulminate](FULMINATE_README.md) similar to the constant tests.

#### Understanding errors

By default, the tool will attempt to synthesize a C program which reproduces the failure.
However, due to non-determinism of `malloc`, if your code include complex relationships between pointer, we cannot guarantee it will consistently reproduce the failure.

If the C program provided does not reproduce the failure, `tests.out` can be run with the `--trap` flag in a debugger.
Since seeds are printed each time the tool runs, `--seed <seed>` can be used to reproduce the test case.
The debugger should automatically pause right before rerunning the failing test case.

#### Writing custom tests

There is currently no way to write custom property-based tests.
However, once lemmas can be tested, a lemma describing the desired property could be written to test it.

In terms of unit tests, one can simply define a function that performs the desired operations.
This function will get detected by `cn test` and turned into a constant test.
Any assertions that one would make about the result would have to be captured by the post-condition.
In the future, existing infrastructure like `cn_assert` might be adapted for general use.

## Test Baselines and Verification

CN uses a baseline comparison system for regression testing. Test outputs are compared against expected baseline files.

### Baseline File Format

Baseline files (`.verify`, `.test`, etc.) contain the expected output including:
1. Return code on first line: `return code: N`
2. All stdout/stderr output from the CN command
3. Path normalization applied (opam paths replaced with `<OPAM_PREFIX>`)

**Example baseline file** (`tests/cn/example.c.verify`):
```
return code: 0
[1/1]: example_function -- pass
```

### Running Tests

From project root:
```bash
make test-verify           # Run all cn verify tests
make test-verify-cn        # Run verify tests on cn/ directory only
make test-test             # Run all cn test tests
```

From tests/ directory:
```bash
./run-all-commands.sh verify cn              # Run verify on cn/
./run-all-commands.sh test cn-test-gen       # Run test on cn-test-gen/
./run-all-commands.sh verify all             # Run verify on all dirs
```

### Regenerating Baselines

After making changes that affect output format:

**Option 1: Regenerate all baselines** (use with caution)
```bash
make test-regen-verify     # From project root
# or
cd tests && ./run-all-commands.sh verify all --regen
```

**Option 2: Regenerate single baseline**
```bash
cd tests
./regenerate-baseline.sh verify cn/example.c
```

**Option 3: Manual baseline creation**
```bash
cd tests
{ echo "return code: 0"; cn verify cn/example.c 2>&1; } > cn/example.c.verify
```
Note: This only works for successful tests (return code 0).

### Adding New Tests

1. Create test file: `tests/cn/new_test.c`
2. Run once to generate initial baseline:
   ```bash
   cd tests
   ./regenerate-baseline.sh verify cn/new_test.c
   ```
3. Review the generated baseline in `tests/cn/new_test.c.verify`
4. Commit both the test and baseline files

### Troubleshooting

**"FAILED" but output looks correct:**
- Check if baseline file is missing `return code:` prefix
- Regenerate with `./regenerate-baseline.sh`

**Tests fail when run from project root:**
- Use Makefile targets: `make test-verify` instead of calling scripts directly
