// Ivars whose header type the metadata does not fully record. True
// declarations: `_bits` is `unsigned : 1` and `_sbits` `int : 3`, but a
// bitfield's encoding is only its width (`b1`, `b3`), so the header can
// say the width and not the type. `_letter` is a `char` (`c`) and `_byte`
// an `unsigned char` (`C`); on arm64 `BOOL` is `bool` and encodes `B`, so
// only `_flag` is a BOOL.
#import <Foundation/Foundation.h>
@interface IvarKinds : NSObject {
  unsigned _bits : 1;
  int _sbits : 3;
  char _letter;
  unsigned char _byte;
  BOOL _flag;
}
@end
@implementation IvarKinds
@end
