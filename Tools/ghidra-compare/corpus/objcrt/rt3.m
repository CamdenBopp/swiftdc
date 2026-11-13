// Fixture 3: constant literal objects passed as arguments. Truth in comments.
#import <Foundation/Foundation.h>
@interface L : NSObject
@end
@implementation L
- (void)addInt:(NSMutableArray *)a { [a addObject:@42]; }            // passes constant NSNumber 42 (__objc_intobj)
- (void)addDbl:(NSMutableArray *)a { [a addObject:@(3.5)]; }         // constant NSNumber 3.5 (__objc_doubleobj)
- (void)addYes:(NSMutableArray *)a { [a addObject:@YES]; }           // kCFBooleanTrue
- (void)addChar:(NSMutableArray *)a { [a addObject:@'c']; }          // constant NSNumber 'c'
- (void)addArr:(NSMutableArray *)a { [a addObject:@[@"p", @"q"]]; }  // constant NSArray ["p","q"]
- (void)addDict:(NSMutableArray *)a { [a addObject:@{@"k": @"v"}]; } // constant NSDictionary {k:v}
- (void)addStr:(NSMutableArray *)a { [a addObject:@"hello"]; }       // CFString "hello"
- (void)addUni:(NSMutableArray *)a { [a addObject:@"héllo"]; }  // UTF-16 CFString "héllo"
- (void)addEmpty:(NSMutableArray *)a { [a addObject:@""]; }          // empty CFString
- (void)addNeg:(NSMutableArray *)a { [a addObject:@(-7)]; }          // constant NSNumber -7
- (void)addLL:(NSMutableArray *)a { [a addObject:@(1LL<<40)]; }      // constant NSNumber 2^40
- (void)addF:(NSMutableArray *)a { [a addObject:@(1.5f)]; }          // constant NSNumber 1.5f
@end
