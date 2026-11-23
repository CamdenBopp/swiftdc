// Code with no function start covering it. `Lorphan` is a temporary label,
// so neither LC_FUNCTION_STARTS nor the symbol table names it; it sits after
// `Odd.owner()`'s `ret` and is reached only through the pointer
// `Odd.getOrphan()` materialises with `adr`. True behaviour: owner()
// returns 1; getOrphan() returns the address of the orphan code, which,
// called, returns 2. The orphan is not part of owner: no path from owner's
// entry reaches it, so its `return 2` must not be rendered as owner's.
.text
.globl _$s3Odd5ownerSiyF
.p2align 2
_$s3Odd5ownerSiyF:
    mov x0, #1
    ret
Lorphan:
    mov x0, #2
    ret

.globl _$s3Odd9getOrphanSiyF
.p2align 2
_$s3Odd9getOrphanSiyF:
    adr x0, Lorphan
    ret

// EXPECT structured * Odd.owner( :: return 1
// FORBID structured * Odd.owner( :: return 2
// FORBID pseudo * Odd.owner( :: return 2
// FORBID structured * Odd.getOrphan( :: re:(?m)return (1|2)[ \t]*$
