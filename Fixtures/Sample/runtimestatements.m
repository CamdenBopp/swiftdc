// Runtime calls that are statements, though their names start like the
// retain/autorelease noise swiftdc hides:
//   pool:  @autoreleasepool { work(); }  objc_autoreleasePoolPush, then
//          objc_autoreleasePoolPop(token): the pool's scope.
//   heap:  returns a block copied to the heap: objc_retainBlock returns a
//          new object, not its argument.
#import <Foundation/Foundation.h>
extern void work(void);
void pool(void) { @autoreleasepool { work(); } }
typedef long (^Adder)(long);
Adder heap(long k) { return ^long(long x) { return x + k; }; }
