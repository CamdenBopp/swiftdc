#include <stdint.h>
#include <stdio.h>
#include <limits.h>
extern double named_foreign_pid(double), named_foreign_pid_indirect(double);
extern int64_t named_foreign_sqrt(int64_t), named_foreign_sqrt_indirect(int64_t);
extern int64_t named_foreign_free(int64_t), named_foreign_free_indirect(int64_t);
extern int64_t named_foreign_rect(int64_t), named_foreign_rect_indirect(int64_t);
extern int64_t named_foreign_format(double, int64_t), named_foreign_format_indirect(double, int64_t);
extern int64_t named_real_pid(void), named_real_pid_indirect(void), named_real_free(int64_t);
extern double named_real_sqrt(double), named_real_sqrt_indirect(double), named_real_rect(double, double);
extern int64_t named_real_format(double, int64_t);

#define CHECK(expression) do { if (!(expression)) { fprintf(stderr, "native named ABI failure at line %d\n", __LINE__); return 1; } ++observations; } while (0)
int main(void) {
    unsigned observations = 0;
    const int64_t integers[] = {-7, -1, 0, 1, 37, INT64_MAX};
    const double floats[] = {-1, 0, 1, 2.5, 17};
    const int64_t weights[] = {2, 7};
    for (unsigned i = 0; i < 6; ++i) {
        int64_t x = integers[i];
        uint64_t a = x < 0 ? (uint64_t)-101 : (uint64_t)x + 40;
        uint64_t b = x < 0 ? (uint64_t)-102 : (uint64_t)x + 46;
        uint64_t c = x < 0 ? (uint64_t)-103 : ((uint64_t)x + 43) * 3;
        CHECK((uint64_t)named_foreign_sqrt(x) == a);
        CHECK((uint64_t)named_foreign_sqrt_indirect(x) == (x < 0 ? a : a + 1));
        CHECK((uint64_t)named_foreign_free(x) == b);
        CHECK((uint64_t)named_foreign_free_indirect(x) == (x < 0 ? b : b + 1));
        CHECK((uint64_t)named_foreign_rect(x) == c);
        CHECK((uint64_t)named_foreign_rect_indirect(x) == (x < 0 ? c : ((uint64_t)x + 43) * 4));
        CHECK(named_real_free(x) == x);
    }
    for (unsigned i = 0; i < 5; ++i) {
        double x = floats[i];
        double result = x < 0 ? -1001 : (x + 0.5) * 2;
        CHECK(named_foreign_pid(x) == result);
        CHECK(named_foreign_pid_indirect(x) == (x < 0 ? result : result * 2));
        for (unsigned j = 0; j < 2; ++j) {
            int64_t expected = x < 0 ? -104 : (int64_t)x * 3 + weights[j] + 7;
            CHECK(named_foreign_format(x, weights[j]) == expected);
            CHECK(named_foreign_format_indirect(x, weights[j]) == (x < 0 ? expected : expected + 1));
        }
    }
    for (unsigned i = 0; i < 4; ++i) {
        CHECK(named_real_sqrt(i * i) == i);
        CHECK(named_real_sqrt_indirect(i * i) == i);
    }
    CHECK(named_real_pid() > 0);
    CHECK(named_real_pid_indirect() > 0);
    CHECK(named_real_rect(0, 0) == 1);
    CHECK(named_real_rect(1, 2) == 2);
    CHECK(named_real_rect(3.5, 4) == 4.5);
    CHECK(named_real_format(1.5, 7) == 5);
    if (observations != 86) return 1;
    puts("PASS 86 native named-ABI observations");
    return 0;
}
