// A switch callee that takes nothing, called right after printf. At -O2
// clang lowers the dense switch to a jump table: `cmp x8, #9; b.hi …;
// adr x10, …; ldrb w11, [x9, x8]; add x10, x10, x11, lsl #2; br x10`.
// True behaviour: dispatchTable() reads only globals, so the tail call in
// printThenDispatch passes nothing, and printf's result in x0 is not an
// argument to it.
#include <stdio.h>

volatile long selector, left, right;

__attribute__((noinline)) long dispatchTable(void) {
    switch (selector) {
    case 0: return left + 1;
    case 1: return left * right;
    case 2: return left - right * 3;
    case 3: return (left ^ right) + 7;
    case 4: return left << 3;
    case 5: return right - 9;
    case 6: return left | right;
    case 7: return (left & right) + 2;
    case 8: return right * 5;
    case 9: return left - 11;
    default: return 0;
    }
}

long printThenDispatch(void) {
    printf("dispatching %ld\n", selector);
    return dispatchTable();
}
