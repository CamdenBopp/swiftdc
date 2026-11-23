// The same Objective-C built for two deployment targets. Below macOS 12 the
// linker rebases by opcode (LC_DYLD_INFO), and a rebased slot holds its
// target's unslid address on disk; from macOS 12 it uses chained fixups,
// where the slot holds an encoding. Read only through the chained form, the
// opcode build lost every selector reference and CFString: `NSLog(0x4000)`
// and a send as an unresolved call, and a tail-called send left the
// function looking like a leaf.
//
// True behaviour: report(a, n) logs "n=<n>", empties a and adds @"x";
// tailClear(a) tail-calls [a removeAllObjects].
#import <Foundation/Foundation.h>

void report(NSMutableArray *a, long n) {
    NSLog(@"n=%ld", n);
    [a removeAllObjects];
    [a addObject:@"x"];
}
void tailClear(NSMutableArray *a) { [a removeAllObjects]; }
