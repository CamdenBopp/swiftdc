#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcrun clang -fobjc-arc -O0 -g -dynamiclib -framework Foundation objc_outgoing.m -o libObjCOutgoing.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_outgoing.m -o libObjCOutgoing.opt.dylib
xcrun clang -fobjc-arc -O2 -dynamiclib -framework Foundation objc_outgoing_conflict.m -o libObjCOutgoing.conflict.dylib
