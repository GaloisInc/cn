/* Test: Cerberus parser fails when comment appears between type and identifier
 *
 * This is valid C but Cerberus parser cannot handle it.
 * GCC compiles successfully.
 */

// Variable declaration with comment between type and name
int /* comment */ x;

void test(void) {
    x = 1;
}
