// Fixture 4: CFString literals whose bytes are not one ASCII C string.
#import <Foundation/Foundation.h>
@interface S : NSObject
@end
@implementation S
- (NSString *)nulStr { return @"a\0b"; }   // returns @"a\0b" (UTF-16, length 3), not @"a"
- (NSString *)cjk { return @"日本"; }       // returns UTF-16 @"日本" (length 2)
- (NSString *)ete { return @"été"; }       // returns UTF-16 @"été" (length 3)
- (NSString *)plain { return @"ok"; }      // returns @"ok"
- (BOOL)eq:(NSString *)s { return [s isEqualToString:@"été"]; } // compares s to @"été"
@end
