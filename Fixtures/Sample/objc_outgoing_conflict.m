#include "objc_outgoing.m"
// Runtime selector names alone do not prove a register layout. This separate
// image intentionally contains an incompatible declaration for the same name.
@interface SDOutgoingConflict : NSObject
- (void)whole:(double)whole fraction:(long)fraction object:(id)object tail:(long)tail;
@end
@implementation SDOutgoingConflict
- (void)whole:(double)whole fraction:(long)fraction object:(id)object tail:(long)tail {}
@end
