#!/bin/bash
# Build the binaries the published samples are decompiled from.
#
# Usage: Tools/samples/build.sh <workdir>
#
# Clones each project at its pinned commit into <workdir>, builds the
# release binaries with the Swift on the PATH, and copies them to
# <workdir>/bin. Then run Tools/samples/render.py <swiftdc> <workdir>.
# Output depends on the compiler: Tools/ci/environment.sh --print records
# it, and the sample pages name it.
set -euo pipefail
work=${1:?usage: build.sh <workdir>}
mkdir -p "$work/bin"
work=$(cd "$work" && pwd)

fetch() { # name url commit
    if [ ! -d "$work/$1/.git" ]; then git clone -q "$2" "$work/$1"; fi
    git -C "$work/$1" fetch -q origin "$3" 2>/dev/null || git -C "$work/$1" fetch -q --unshallow origin
    git -C "$work/$1" checkout -q --force "$3"
}

echo "==> swift-argument-parser examples (Apache-2.0)"
fetch swift-argument-parser https://github.com/apple/swift-argument-parser.git \
    d7b6cebecb27311771a3249275259edaccf61972
for product in math repeat roll count-lines color; do
    (cd "$work/swift-argument-parser" && swift build -c release --product "$product" >/dev/null)
    cp "$work/swift-argument-parser/.build/release/$product" "$work/bin/"
done
rm -rf "$work/swift-argument-parser/.build"

echo "==> mas (MIT)"
fetch mas https://github.com/mas-cli/mas.git 6c5032dc8da74668c407b76d02463eea20b732a5
# mas treats every warning as an error, and Swift 6.4 warns about two
# `unsafe` markers it no longer needs (MAS.Config.swift, MAS.Reset.swift).
# The setting comes after any -Xswiftc flag on the compile line, so it is
# dropped from Package.swift instead. The source is unchanged.
sed -i '' '/\.treatAllWarnings(as: \.error),/d' "$work/mas/Package.swift"
(cd "$work/mas" && swift build -c release --product mas >/dev/null)
cp "$work/mas/.build/release/mas" "$work/bin/"
rm -rf "$work/mas/.build"
git -C "$work/mas" checkout -q -- Package.swift

ls -l "$work/bin"
