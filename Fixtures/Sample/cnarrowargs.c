// Narrow C integer arguments to SDK functions (clang -O2). The caller
// materialises `int -1` with `mov w0, #-1`, leaving 0xffffffff in x0; the
// SDK declares `int close(int)`, so the argument reads -1, not 0xffffffff.
// `usleep(useconds_t)` takes an unsigned 32-bit value. lseek's off_t
// offset is 64-bit and reads -5 either way.
#include <unistd.h>
int closeBad(void) { return close(-1); }
int sleepLong(void) { return usleep(4000000000u); }
int seekBack(int fd) { return (int)lseek(fd, -5, SEEK_END); }
