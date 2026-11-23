#include <stdint.h>
#include <stdio.h>
#include <limits.h>
extern int64_t named_buffer_foreign_probe(int64_t), named_buffer_foreign_indirect_probe(int64_t);
extern int64_t named_buffer_system_probe(int64_t), named_buffer_system_indirect_probe(int64_t);
#define CHECK(expression) do { if (!(expression)) { fprintf(stderr, "native named buffer failure at line %d\n", __LINE__); return 1; } ++observations; } while (0)
int main(void) {
    unsigned observations = 0;
    const int64_t values[] = {-7, -1, 0, 1, 37, INT64_MAX};
    for (unsigned i = 0; i < 6; ++i) {
        uint64_t expected = (uint64_t)values[i] + 11;
        CHECK((uint64_t)named_buffer_foreign_probe(values[i]) == expected);
        CHECK((uint64_t)named_buffer_foreign_indirect_probe(values[i]) == expected);
        CHECK(named_buffer_system_probe(values[i]) == 1);
        CHECK(named_buffer_system_indirect_probe(values[i]) == 1);
    }
    if (observations != 24) return 1;
    puts("PASS 24 native named result-buffer observations");
    return 0;
}
