// Clang returns Triple through x8 and FloatTriple directly through v0-v2.
// The native driver checks every field and the scalar control at O0/O2/Os.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
typedef struct { unsigned long a,b,c; } Triple;
typedef struct { double a,b,c; } FloatTriple;
@interface EntryResultObject : NSObject
- (Triple)wide:(unsigned long)k;
- (FloatTriple)floats:(double)k;
- (unsigned long)scalar:(unsigned long)k;
@end
@implementation EntryResultObject
- (Triple)wide:(unsigned long)k { return (Triple){k,k+1,k+2}; }
- (FloatTriple)floats:(double)k { return (FloatTriple){k+0.25,k+1.25,k+2.25}; }
- (unsigned long)scalar:(unsigned long)k { return k ^ 0xa5; }
@end
#ifdef BUILD_DRIVER
int main(void) {
 @autoreleasepool {
    EntryResultObject *o=[EntryResultObject new];
    const unsigned long ks[]={0,1,2,37,123456,UINT64_MAX-2,UINT64_MAX};
    for (unsigned i=0;i<sizeof(ks)/sizeof(ks[0]);++i) {
        unsigned long k=ks[i]; Triple a=[o wide:k];
        assert(a.a==k && a.b==k+1 && a.c==k+2);
        double f=(double)i/4; FloatTriple b=[o floats:f];
        assert(b.a==f+0.25 && b.b==f+1.25 && b.c==f+2.25);
        assert([o scalar:k]==(k^0xa5));
    }
 }
 puts("PASS 21 native Objective-C entry-result observations");
}
#endif
