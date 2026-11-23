// Native oracle for hand-written AArch64 register-view tests.
#include <stdint.h>
#include <stdio.h>
extern uint64_t wordbranch_w_cbz(uint64_t);
extern uint64_t wordbranch_w_cbz_copy(uint64_t);
extern uint64_t wordbranch_w_cbnz(uint64_t);
extern uint64_t wordbranch_w_cbnz_copy(uint64_t);
extern uint64_t wordbranch_x_cbz(uint64_t);
extern uint64_t wordbranch_x_cbz_copy(uint64_t);
extern uint64_t wordbranch_x_cbnz(uint64_t);
extern uint64_t wordbranch_x_cbnz_copy(uint64_t);
typedef uint64_t (*probe)(uint64_t);
int main(void) {
    const uint64_t inputs[] = {0, 1, 0x7fffffff, 0x80000000, 0xffffffff,
        0x100000000, 0x100000001, 0xffffffff00000000, UINT64_MAX};
    const struct { const char *name; probe call; int word; int nonzero; } cases[] = {
    {"wordbranch_w_cbz", wordbranch_w_cbz, 1, 0},
    {"wordbranch_w_cbz_copy", wordbranch_w_cbz_copy, 1, 0},
    {"wordbranch_w_cbnz", wordbranch_w_cbnz, 1, 1},
    {"wordbranch_w_cbnz_copy", wordbranch_w_cbnz_copy, 1, 1},
    {"wordbranch_x_cbz", wordbranch_x_cbz, 0, 0},
    {"wordbranch_x_cbz_copy", wordbranch_x_cbz_copy, 0, 0},
    {"wordbranch_x_cbnz", wordbranch_x_cbnz, 0, 1},
    {"wordbranch_x_cbnz_copy", wordbranch_x_cbnz_copy, 0, 1},
    };
    unsigned observations = 0;
    for (unsigned c = 0; c < sizeof(cases) / sizeof(cases[0]); ++c) {
        for (unsigned i = 0; i < sizeof(inputs) / sizeof(inputs[0]); ++i) {
            uint64_t produced = inputs[i] | UINT64_C(0x100000000);
            uint64_t tested = cases[c].word ? produced & UINT64_C(0xffffffff) : produced;
            uint64_t expected = ((tested != 0) == cases[c].nonzero) ? 1 : 2;
            uint64_t actual = cases[c].call(inputs[i]);
            if (actual != expected) {
                fprintf(stderr, "%s input=%llx actual=%llu expected=%llu\n",
                    cases[c].name, (unsigned long long)inputs[i],
                    (unsigned long long)actual, (unsigned long long)expected);
                return 1;
            }
            ++observations;
        }
    }
    printf("PASS %u native compare-branch-width observations\n", observations);
    return 0;
}
