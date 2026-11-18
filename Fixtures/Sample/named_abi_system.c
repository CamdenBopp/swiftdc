// This image never links the foreign provider. Function-pointer stores are
// volatile to keep real SDK calls at every optimization level.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int64_t named_real_pid(void) { return getpid(); }
double named_real_sqrt(double value) {
    double (*volatile operation)(double) = sqrt;
    return operation(value);
}
int64_t named_real_free(int64_t value) {
    void (*volatile release)(void *) = free;
    int64_t *memory = malloc(sizeof(*memory));
    if (!memory) return INT64_MIN;
    *memory = value;
    release(memory);
    return value;
}
double named_real_rect(double dx, double dy) {
    CGRect result = CGRectInset(CGRectMake(1, 2, 20, 30), dx, dy);
    return result.origin.x;
}
int64_t named_real_format(double value, int64_t integer) {
    int (*volatile format)(char *, size_t, const char *, ...) = snprintf;
    char buffer[64];
    int count = format(buffer, sizeof(buffer), "%.1f:%lld", value, (long long)integer);
    return strcmp(buffer, "1.5:7") == 0 ? count : -1;
}
