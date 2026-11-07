#include <stdint.h>
struct Token { int64_t a; double b; int64_t c; };
const struct Token *operator_arity_source(void) {
    static const struct Token values[] = {{3, 1.5, 7}, {11, 2.5, 13}};
    return values;
}
