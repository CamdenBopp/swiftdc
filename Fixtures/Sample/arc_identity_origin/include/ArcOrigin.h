#ifndef ARC_ORIGIN_FOREIGN_C_H
#define ARC_ORIGIN_FOREIGN_C_H

#include <stdint.h>

#ifndef ARC_ORIGIN_LOCAL
#define ARC_ORIGIN_LOCAL 0
#endif

#if ARC_ORIGIN_LOCAL
#define ARC_ORIGIN_VISIBILITY __attribute__((visibility("hidden")))
#else
#define ARC_ORIGIN_VISIBILITY __attribute__((visibility("default")))
#endif

/* This is deliberately an ordinary scalar C declaration. Its C identifier is
 * unrelated to ARC; the assembler label requests the misleading Mach-O name.
 * Fresh compiler IR, not this spelling, must prove the actual target and ABI.
 */
extern int64_t arc_origin_misleading(int64_t first, int64_t second)
    __asm__("_swift_nonatomic_retain") ARC_ORIGIN_VISIBILITY;

#endif
