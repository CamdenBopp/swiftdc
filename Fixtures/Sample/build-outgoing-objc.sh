#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcrun clang -fobjc-arc -O0 -g -dynamiclib -framework Foundation objc_outgoing.m -o libObjCOutgoing.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_outgoing.m -o libObjCOutgoing.opt.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_outgoing_conflict.m -o libObjCOutgoing.conflict.dylib
# Packed stack arguments: two ints share one eight-byte slot.
xcrun clang -fobjc-arc -O0 -dynamiclib -framework Foundation objc_packed_stack.m -o libObjCPackedStack.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_packed_stack.m -o libObjCPackedStack.opt.dylib
# Untyped sends that pass a double: no signature in the image.
xcrun clang -fobjc-arc -O0 -dynamiclib -framework Foundation objc_untyped_float.m -o libObjCUntypedFloat.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_untyped_float.m -o libObjCUntypedFloat.opt.dylib
# Struct arguments: HFAs in v registers, small structs in x registers, large
# ones by address, and the stack (closing a bank) when they do not fit.
xcrun clang -fobjc-arc -O0 -dynamiclib -framework Foundation objc_aggregate_args.m -o libObjCAggregateArgs.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_aggregate_args.m -o libObjCAggregateArgs.opt.dylib
# Untyped sends of selectors an in-image implementation takes a struct for:
# the arguments do not take one x register each.
xcrun clang -fobjc-arc -O0 -dynamiclib -framework Foundation objc_untyped_struct.m -o libObjCUntypedStruct.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_untyped_struct.m -o libObjCUntypedStruct.opt.dylib
# Untyped sends of selectors only the SDK declares, struct and float ones
# among them: the public declarations doubt their layout.
xcrun clang -fobjc-arc -O0 -dynamiclib -framework AppKit objc_sdk_selectors.m -o libObjCSDKSelectors.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework AppKit objc_sdk_selectors.m -o libObjCSDKSelectors.opt.dylib
