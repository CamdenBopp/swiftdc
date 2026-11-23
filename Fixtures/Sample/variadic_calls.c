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

// Library calls whose headers the prototype table once never compiled
// (sys/ioctl.h, dirent.h, sys/sysctl.h). True behaviour: setNonBlocking
// calls ioctl(fd, FIONBIO = 0x8004667e, &on), whose request is the fixed
// unsigned long and &on the variadic part; closeAfterUse calls touch(5,
// 6) and then closedir(d), its own parameter, which it keeps in x19
// across the first call; cpuCount calls sysctl(mib, 2, &n, &len, NULL, 0).
#include <sys/ioctl.h>
#include <dirent.h>
#include <sys/sysctl.h>

__attribute__((noinline)) int touch(int a, int b) { return a + b; }
int setNonBlocking(int fd) { int on = 1; return ioctl(fd, FIONBIO, &on); }
int closeAfterUse(DIR *d) { int t = touch(5, 6); return closedir(d) + t; }
int cpuCount(void) {
    int mib[2] = { CTL_HW, HW_NCPU };
    int n = 0;
    size_t len = sizeof n;
    return sysctl(mib, 2, &n, &len, 0, 0) == 0 ? n : -1;
}
