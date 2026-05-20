/* Test for sizeof crash on extern incomplete array
 *
 * CN crashes when trying to compute size of extern array
 * with unspecified size.
 */

const char * test(void) {
    extern const char arr[];
    return arr;
}
