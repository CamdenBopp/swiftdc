// Constant NSStrings, each a __cfstring entry with flags and a length:
//   plain:  @"plain ascii"   flags 0x7c8, 11 bytes in __cstring
//   accent: @"héllo"         flags 0x7d0, 5 UTF-16 units in __ustring
//   kanji:  @"日本"           flags 0x7d0, 2 units
//   nul:    @"a\0b"          flags 0x7c8 or 0x7d0, length 3 (not a C string)
//   empty:  @""              length 0
// Read as C strings, accent read @"h", nul read @"a" and kanji was raw.
#import <Foundation/Foundation.h>

void plain(void) { NSLog(@"plain ascii"); }
void accent(void) { NSLog(@"héllo"); }
void kanji(void) { NSLog(@"日本"); }
void nul(void) { NSLog(@"a\0b"); }
void empty(void) { NSLog(@""); }
