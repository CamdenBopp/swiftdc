// Linked with -no_data_const, the layout of images from linkers before
// __DATA_CONST: the GOT and the selector references sit in the writable
// __DATA segment. Only dyld and the
// Objective-C runtime write those sections, so a pointer loaded from one is
// still the symbol it is bound to, unlike a bind in __DATA,__data that the
// program itself can overwrite (writablepointer.c).
//
// True behaviour: `makeDefaults` sends standardUserDefaults to the
// NSUserDefaults class, loaded from a bind in __DATA,__got, and `passPuts`
// passes the address of puts, loaded the same way.
#import <Foundation/Foundation.h>
#include <stdio.h>

int (*kept)(const char *);
__attribute__((noinline)) void keep(int (*f)(const char *)) { kept = f; }
void passPuts(void) { keep(puts); }

id makeDefaults(void) { return [NSUserDefaults standardUserDefaults]; }
