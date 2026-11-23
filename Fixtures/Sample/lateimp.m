// An ordinary method implementation with a method's symbol name and no
// method-list record (-O1).
//
// A direct method (objc_direct) has no method-list record and takes no
// _cmd: its first keyword argument is in x1. The function below has no
// record either, because it is installed at runtime, and it is an
// ordinary IMP: self in x0, _cmd in x1, its first keyword argument in
// x2. The difference a binary shows is how each is reached. A direct
// method is called by its symbol. This one is never branched to; its
// address is passed to class_addMethod. Each body's true behaviour is its
// source.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

void lateimp_record(long first, long second);

@interface LICrate : NSObject
- (long)listed:(long)a with:(long)b;
@end

@implementation LICrate
// In the class's method list: record(a, b), return a.
- (long)listed:(long)a with:(long)b { lateimp_record(a, b); return a; }
@end

__attribute__((noinline)) void lateimp_record(long first, long second) { NSLog(@"%ld %ld", first, second); }

// The same body, named like a method, reached only as data.
long lateimp_imp(id self, SEL _cmd, long a, long b) __asm__("-[LICrate late:with:]");
__attribute__((noinline)) long lateimp_imp(id self, SEL _cmd, long a, long b) { lateimp_record(a, b); return a; }

__attribute__((constructor)) static void lateimp_install(void) {
    class_addMethod([LICrate class], sel_registerName("late:with:"), (IMP)lateimp_imp, "q@:qq");
}
