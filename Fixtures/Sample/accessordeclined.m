// Property accessors the classifier gets no verdict for. True behaviour:
//   `-depth`: an entry block past the 4 KB decode prefix (a long run of
//   loads of a global, so nothing in the prefix is custom either). Its line
//   stays, marked as running past the limit.
//   `-width`: an IMP outside __TEXT,__text, where no body is decoded. Its
//   line stays, marked as such.
//   `count`: synthesized, as a control. Its lines go.
#import <Foundation/Foundation.h>
#define R4(x) x x x x
#define R1280(x) R4(R4(R4(R4(x x x x x))))
static volatile int sink;
@interface Unsure : NSObject
@property (nonatomic, readonly) int depth;
@property (nonatomic, readonly) int width;
@property (nonatomic) int count;
@end
@implementation Unsure
@synthesize depth = _depth;
- (int)depth { R1280((void)sink;) return _depth; }
@synthesize width = _width;
- (int)width __attribute__((section("__TEXT,__alt,regular,pure_instructions"))) { return _width; }
@end
