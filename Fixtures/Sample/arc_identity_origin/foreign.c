#include "ArcOrigin.h"

/* No objects, constructors, callbacks, interpose section or runtime hooks.
 * At the admitted arguments 7 and 99 the signed addition cannot overflow.
 */
__attribute__((noinline, used))
int64_t arc_origin_misleading(int64_t first, int64_t second) {
    (void)first;
    return second + INT64_C(17);
}
