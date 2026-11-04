#!/bin/bash
# Print an Objective-C source with <classes> classes of eight properties
# each: `objc`'s accessor classification at scale. Its memory must not grow
# with the accessor count (each accessor is decoded, classified and
# released), and its classification must not change.
#
# True behaviour, per class N:
#   count, flag (int, BOOL)          synthesized getter and setter
#   name (copy NSString)             synthesized (objc_setProperty, ARC)
#   owner (strong id)                synthesized (objc_storeStrong)
#   delegate (weak id)               synthesized (objc_loadWeakRetained,
#                                    objc_storeWeak)
#   total (readonly int)             custom getter: count * 2 + 1
#   label (readonly NSString)        custom getter: sends -description
#   limit (int)                      custom setter: stores, then sends
#                                    -description to the owner
# so 11 synthesized and 3 custom accessors a class (14 in all): `-total`, `-label` and
# `-setLimit:` stay in the header; every other accessor line is dropped.
#
#   gen-manyaccessors.sh <classes> > out.m
set -euo pipefail
classes=${1:?usage: gen-manyaccessors.sh <classes>}

echo '#import <Foundation/Foundation.h>'
for ((n = 0; n < classes; n++)); do
  cat <<EOF
@interface Many$n : NSObject
@property (nonatomic) int count;
@property (nonatomic) BOOL flag;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id owner;
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) int total;
@property (nonatomic, readonly) NSString *label;
@property (nonatomic) int limit;
@end
@implementation Many$n
- (int)total { return self.count * 2 + 1; }
- (NSString *)label { return [self.owner description]; }
- (void)setLimit:(int)limit { _limit = limit + $n; [self.owner description]; }
@end
EOF
done
