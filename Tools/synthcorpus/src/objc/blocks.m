// LEVELS: O0 O1 O2 Os
// Blocks under ARC.
//
// A block literal is a stack Block_layout {isa=_NSConcreteStackBlock,
// flags, reserved, invoke, descriptor, captures...}. A block with no
// captures is a global block (_NSConcreteGlobalBlock, a constant in
// __DATA). Storing a capturing block in a strong variable that escapes
// makes ARC call objc_retainBlock (the copy to the heap). A __block
// variable lives in a Block_byref struct reached through its forwarding
// pointer, and the block's copy/dispose helpers call _Block_object_assign
// / _Block_object_dispose.
// TRUE behaviours:
//   runWith(f, x)     calls f(x * 2) through the block's invoke pointer
//                     (the block is the first argument of invoke)
//   makeAdder(n)      returns a heap block capturing n
//   countTo(n)        increments a __block counter n times via a block
//                     passed to SBApply, returns the counter
//   globalBlock()     returns a constant global block (no copy needed)
#import <Foundation/Foundation.h>

typedef int (^SBIntFn)(int);

__attribute__((noinline)) void SBApply(int n, void (^body)(void)) {
    for (int i = 0; i < n; i++) body();
}

// invoke(block, x * 2): the block is invoke's first argument, x*2 its second.
// EXPECT structured O0 runWith :: << 1
// FORBID structured * runWith :: recovered_args: [(((arg1
int runWith(SBIntFn f, int x) {
    return f(x * 2);
}

// EXPECT listing * makeAdder :: objc_retainBlock
SBIntFn makeAdder(int n) {
    SBIntFn add = ^(int v) { return v + n; };
    return add;
}

// At -O1 and up w0 is never written before `bl SBApply`: n passes through.
// EXPECT structured * countTo :: SBApply
// EXPECT structured * countTo :: re:SBApply\([^,\n]*arg0
// FORBID structured * countTo :: re:SBApply\([^,\n]*,\s*arg0
int countTo(int n) {
    __block int count = 0;
    SBApply(n, ^{ count++; });
    return count;
}

// FORBID structured * globalBlock :: objc_retainBlock
SBIntFn globalBlock(void) {
    return ^(int v) { return v + 1; };
}
