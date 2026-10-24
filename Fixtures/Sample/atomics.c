// C11 atomics on a plain arm64 slice (-O2). Clang's default macOS arm64
// target (apple-m1) emits ARMv8.1 LSE and ARMv8.3 RCpc instructions for
// them, which llvm-objdump without a CPU or features prints as data:
// `.long 0xf8e80000` where the CPU executes `ldaddal x8, x0, [x0]`.
//
// True behaviour: bump returns the old *p and adds 1 (ldaddal); swapIf
// compares *p with old and stores new_ if equal (casal), returning whether
// it did; acquire returns *p with acquire ordering (ldapr).
#include <stdatomic.h>

long bump(_Atomic long *p) { return atomic_fetch_add(p, 1); }
int swapIf(_Atomic int *p, int old, int new_) { return atomic_compare_exchange_strong(p, &old, new_); }
long acquire(_Atomic long *p) { return atomic_load_explicit(p, memory_order_acquire); }
