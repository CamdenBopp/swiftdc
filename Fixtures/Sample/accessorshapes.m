// Accessors one basic block long, with no call, that the classifier must
// tell apart by what they do to the value. True behaviour:
//   Plain: every property synthesized, so its lines are implied and dropped.
//     Scalars of every width, floats, a struct, strong, weak and copy
//     objects, and atomic ones. A synthesized accessor moves its value
//     unchanged between the ivar and the argument or result register. A
//     struct over 16 bytes moves through memory: `ldp q0, q1, [x2]; stp q0,
//     q1, [x0, #off]`, and `ldp …, [x0, #off]; stp …, [x8]`.
//   Computed: every accessor written by hand and worth keeping.
//     `csel; str`: a clamp. `add; str`: arithmetic. `mov; str`: a constant.
//     `str; str`: one argument, two ivars. `ldr; add`, `ldr; csel`: a getter
//     that computes. `ldr; ldr`: a getter through a pointer ivar. The wide
//     setter copies through x2 and then overwrites a word. `ignored` reads
//     its ivar and returns 3: at -O0 a load through self whose value is
//     stored to the stack, then `mov w0, #3; ret`.
#import <Foundation/Foundation.h>
struct Pair { int x, y; };
struct Node { long tag; long value; };
struct Wide { long a, b, c, d, e; };
@interface Plain : NSObject
@property (nonatomic) int count;
@property (nonatomic) BOOL flag;
@property (nonatomic) char letter;
@property (nonatomic) short small;
@property (nonatomic) long wide;
@property (nonatomic) float ratio;
@property (nonatomic) double scale;
@property (nonatomic) struct Pair pair;
@property (nonatomic) struct Wide wide5;
@property (nonatomic, strong) id owner;
@property (nonatomic, weak) id delegate;
@property (nonatomic, copy) NSString *name;
@property int atomicCount;
@property (strong) id atomicOwner;
@property struct Pair atomicPair;
@end
@implementation Plain
@end
@interface Computed : NSObject {
    struct Node *_node;
}
@property (nonatomic) int clamped;
@property (nonatomic) int bumped;
@property (nonatomic) int fixedValue;
@property (nonatomic) int twice;
@property (nonatomic) int twiceShadow;
@property (nonatomic, readonly) int next;
@property (nonatomic, readonly) int floorValue;
@property (nonatomic, readonly) long nodeValue;
@property (nonatomic, readonly) int ignored;
@property (nonatomic) struct Wide patched;
@end
@implementation Computed
- (void)setClamped:(int)clamped { _clamped = clamped > 10 ? 10 : clamped; }
- (void)setBumped:(int)bumped { _bumped = bumped + 1; }
- (void)setFixedValue:(int)fixedValue { _fixedValue = 7; }
- (void)setTwice:(int)twice { _twice = twice; _twiceShadow = twice; }
@synthesize next = _next;
- (int)next { return _next + 1; }
@synthesize floorValue = _floorValue;
- (int)floorValue { return _floorValue > 3 ? _floorValue : 3; }
- (long)nodeValue { return _node->value; }
@synthesize ignored = _ignored;
- (int)ignored { int seen = _ignored; (void)seen; return 3; }
- (void)setPatched:(struct Wide)patched { _patched = patched; _patched.a = 0; }
@end
