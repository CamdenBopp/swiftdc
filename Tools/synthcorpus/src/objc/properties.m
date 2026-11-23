// LEVELS: O0 O1 O2 Os
// Property accessors and ivar access under ARC.
//
// Synthesized accessors lower differently by attribute:
//   atomic strong object  getter objc_getProperty(self, _cmd, off, YES),
//                         setter objc_setProperty_atomic(self, _cmd, v, off)
//   nonatomic copy        setter objc_setProperty_nonatomic_copy
//   weak                  getter objc_loadWeakRetained, setter objc_storeWeak
//   nonatomic assign int  plain ldr/str at the ivar offset
// The ivar offset comes from the OBJC_IVAR_$_Class.ivar symbol (loaded at
// run time, non-fragile ivars), so field access goes self + [offset].
// TRUE behaviours:
//   -[PRHolder setCount:]     stores the int argument into _count
//   bump(h)                   h.count = h.count + 1 through the accessors
//   setName(h, s)             sends setName: with s (copied by the setter)
//   peekDelegate(h)           sends delegate to h
//   readIvar(h)               reads h->_raw directly via the ivar offset
#import <Foundation/Foundation.h>

@interface PRHolder : NSObject { @public long _raw; }
@property (atomic, strong) id thing;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, weak) id delegate;
@property (nonatomic) int count;
@end
@implementation PRHolder
@end

// EXPECT structured * bump :: count]
// EXPECT structured * bump :: setCount:
// FORBID structured * bump :: re:setCount:(arg0|1)\]
void bump(PRHolder *h) { h.count = h.count + 1; }

// EXPECT structured * _setName :: setName:
// FORBID structured * _setName :: re:setName:arg0\]
// EXPECT structured O1,O2,Os _setName :: [arg0 setName:arg1]
void setName(PRHolder *h, NSString *s) { h.name = s; }

// EXPECT structured * peekDelegate :: delegate]
id peekDelegate(PRHolder *h) { return h.delegate; }

// EXPECT structured * _setThing :: setThing:
// The stub loads _cmd itself; x1 still holds t (arg1) but is not _cmd.
// FORBID listing O1,O2,Os setThing :: re:setThing:\s+args\([^,\n]*, arg1,
void setThing(PRHolder *h, id t) { h.thing = t; }

long readIvar(PRHolder *h) { return h->_raw; }

// Messaging a nil receiver is legal and returns zero: nilCount sends
// count to nil and returns 0 at run time. TRUE: the send is still
// rendered (the compiler emits it), with a nil receiver, never folded away
// or given a fabricated receiver.
// FORBID structured O1,O2,Os nilCount :: re:\[self count\]
int nilCount(void) {
    PRHolder *h = nil;
    return [h count];
}
