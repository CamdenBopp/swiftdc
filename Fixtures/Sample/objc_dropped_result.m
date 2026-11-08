// A call whose result reaches only a register an untyped send does not
// print (-O2). setSpan: is declared but implemented elsewhere, so its
// NSRange is laid out by colon position: x2 is its one argument, and x3,
// the range's length, is secondValue's result. The send printed only x2,
// and secondValue, taken as printed in it, appeared nowhere.
//
// formatFirst passes firstValue's result to stringWithFormat: as a
// variadic argument, which the send prints after its format, so the call
// prints once, inside it.
//
// discardDescription discards a send's result under ARC, which clang
// claims with objc_unsafeClaimAutoreleasedReturnValue: bookkeeping like
// the rest of the autorelease family, which is not printed.
//
// True behaviour: spanSend calls firstValue(o), then secondValue(o), then
// sends setSpan: with the range (first, second); formatFirst returns
// [NSString stringWithFormat:@"%ld", firstValue(o)]; discardDescription
// sends description to o and ignores the result.
#import <Foundation/Foundation.h>

__attribute__((noinline)) long firstValue(id o) { return (long)[o hash]; }
__attribute__((noinline)) long secondValue(id o) { return (long)[o hash] * 2; }

@interface NSObject (RemoteSpan)
- (void)setSpan:(NSRange)r;
@end

void spanSend(id o) { [o setSpan:NSMakeRange(firstValue(o), secondValue(o))]; }

NSString *formatFirst(id o) { return [NSString stringWithFormat:@"%ld", firstValue(o)]; }

void discardDescription(id o) { (void)[o description]; }
