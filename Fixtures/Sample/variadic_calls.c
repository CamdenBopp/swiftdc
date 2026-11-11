// Calls to C functions the SDK declares variadic with a fixed part, and no
// format string: `int open(const char *, int, ...)` and `int fcntl(int,
// int, ...)`. Apple arm64 passes the fixed arguments in registers and every
// variadic one on the stack, so the fixed ones are provable from x0 and w1;
// the variadic part's count is not. True behaviour: openReadOnly calls
// open(path, O_RDONLY = 0); openCreate open(path, O_CREAT | O_WRONLY =
// 0x201, 0644); dupFrom fcntl(fd, F_DUPFD = 0, 10); openNegative
// open(path, -1), whose int is -1 at its declared width, not 0xffffffff.
#include <fcntl.h>

int openReadOnly(const char *path) { return open(path, O_RDONLY); }
int openCreate(const char *path) { return open(path, O_CREAT | O_WRONLY, 0644); }
int dupFrom(int fd) { return fcntl(fd, F_DUPFD, 10); }
int openNegative(const char *path) { return open(path, -1); }
