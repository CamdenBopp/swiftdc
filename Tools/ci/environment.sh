#!/bin/bash
# Check that this machine can run swiftdc's enforcing suite, and print the
# exact toolchain so a run can be compared with another.
#
# Usage: Tools/ci/environment.sh [--print]
#   --print   print the versions only and exit 0, whatever they are
#
# The fixtures are compiled from source, so the suite's result depends on
# the compiler that built them. The versions below are the ones the suite
# is known to pass with (measured 2026-11-13). An older Swift fails while
# building fixtures: 6.2.4 rejects coroaccessors.swift. Swift 6.3 has not
# been tried.
set -u
TESTED_SWIFT="6.4"
TESTED_XCODE="27.1"
MIN_SWIFT_MAJOR=6
MIN_SWIFT_MINOR=4
MIN_FREE_GB=15

arch=$(uname -m)
macos=$(sw_vers -productVersion 2>/dev/null || echo unknown)
xcode=$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')
swift_line=$(xcrun swiftc --version 2>/dev/null | head -1)
swift=$(printf '%s' "$swift_line" | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p')
go_version=$(go version 2>/dev/null | awk '{print $3}')
free_gb=$(df -g "$HOME" | awk 'NR==2{print $4}')
memory_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))

echo "swiftdc environment"
echo "  architecture  $arch"
echo "  macOS         $macos"
echo "  Xcode         ${xcode:-not found}"
echo "  Swift         ${swift:-not found}"
echo "  Go            ${go_version:-not found}"
echo "  memory        ${memory_gb} GB"
echo "  free disk     ${free_gb} GB"
echo "  tested with   Swift $TESTED_SWIFT, Xcode $TESTED_XCODE"
[ "${1:-}" = "--print" ] && exit 0

failures=0
fail() { echo "environment: $1" >&2; failures=$((failures + 1)); }

[ "$arch" = "arm64" ] || fail "Apple Silicon is required (this is $arch): the fixtures are arm64 and some tests run them."
if [ -z "$swift" ]; then
    fail "no Swift compiler: install Xcode and run 'sudo xcode-select -s /Applications/Xcode.app'."
else
    major=${swift%%.*}; rest=${swift#*.}; minor=${rest%%.*}
    if [ "$major" -lt "$MIN_SWIFT_MAJOR" ] || { [ "$major" -eq "$MIN_SWIFT_MAJOR" ] && [ "$minor" -lt "$MIN_SWIFT_MINOR" ]; }; then
        fail "Swift $swift is older than $MIN_SWIFT_MAJOR.$MIN_SWIFT_MINOR: the fixture build fails on it. Install a newer Xcode and select it with xcode-select."
    fi
fi
[ -n "$go_version" ] || fail "Go is not on the PATH: the Go fixtures cannot be built, and the enforcing suite names them as missing. 'brew install go'."
[ "${free_gb:-0}" -ge "$MIN_FREE_GB" ] || fail "only ${free_gb} GB free: a checkout, its build and the fixtures need about $MIN_FREE_GB GB."

if [ "$failures" -gt 0 ]; then
    echo "environment: $failures problem(s); the suite is not expected to pass here." >&2
    exit 1
fi
if [ "$swift" != "$TESTED_SWIFT" ] || [ "$xcode" != "$TESTED_XCODE" ]; then
    echo "environment: usable, but not the tested toolchain. A fixture can lower differently on another compiler; a failure here may be the toolchain's, not the change's."
fi
exit 0
