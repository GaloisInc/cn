# Testing Infrastructure Issues and Improvements

## Current Issues with run-all-commands.sh

### 1. Baseline File Format Inconsistencies

**Problem:** Test baseline files (`.verify` files) need to start with `return code: 0` for passing tests, but this isn't always generated automatically by the test tools.

**Symptoms:**
- Running `cn verify file.c > file.c.verify 2>&1` doesn't include the return code prefix
- Need to manually add `return code: 0` at the beginning of baseline files
- This causes tests to fail even when the actual CN output is correct

**Current Workaround:**
```bash
echo "return code: 0" | cat - file.c.verify > /tmp/temp && mv /tmp/temp file.c.verify
```

**Suggested Fix:**
- Modify `diff-prog.py` or the test harness to automatically prepend return codes
- Or provide a helper script to regenerate baselines correctly: `./regenerate-baseline.sh verify cn/file.c`

### 2. Working Directory Confusion

**Problem:** Scripts like `run-all-commands.sh` and `diff-prog.py` must be run from the `tests/` directory, but this isn't always clear from error messages.

**Symptoms:**
- Running from root directory (`/Users/guso/tools/cn`) fails with cryptic errors
- Need to `cd tests` first, which breaks muscle memory for developers used to running `make test` from root

**Current Workaround:**
```bash
cd tests && ./run-all-commands.sh verify cn
```

**Suggested Fix:**
- Add a Makefile target at root level: `make test-verify-cn` that handles directory changes
- Or make scripts detect if they're in wrong directory and auto-change: `cd $(dirname $0)`

### 3. Test Output Duplication Issues

**Problem:** Some tests show duplicate warning messages in baselines but not in current output, or vice versa.

**Example:** `memcpy.c` had a "nothing instantiated" warning appearing twice in the old baseline but only once in current output.

**Suggested Fix:**
- Investigate why warnings are sometimes duplicated
- Ensure consistent warning output across CN invocations
- May be related to how errors/warnings are collected and printed

### 4. Return Code Handling

**Problem:** The test framework expects `return code: N` in baseline files, but this convention isn't documented in CLAUDE.md or TESTING.md.

**Suggested Fix:**
- Document the baseline file format in `doc/TESTING.md`
- Provide example baseline files
- Add validation to `diff-prog.py` to warn about malformed baselines

## Recommendations

1. **Standardize baseline generation:**
   ```bash
   ./scripts/gen-baseline.sh verify cn/file.c
   ```

2. **Add test validation:**
   ```bash
   ./scripts/validate-baselines.sh cn/
   ```

3. **Improve error messages:**
   - When run from wrong directory: "Error: must run from tests/ directory"
   - When baseline is malformed: "Warning: baseline missing return code prefix"

4. **Document conventions:**
   - Add section to `doc/TESTING.md` explaining baseline file format
   - Add examples of correct baseline files
   - Document the `return code: N` convention
