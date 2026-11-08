#!/bin/zsh
# Builds each app listed in a config at its current checkout, Debug (-Onone)
# and Release (-O), for the arm64 simulator, and records provenance next to
# each build. Derived data goes to the output directory: nothing is written
# into the app repositories, and nothing is signed.
#
# Usage: build-apps.sh <apps.conf> <output-dir>
# apps.conf, one app per line:  Name|/path/to/Project.xcodeproj|Scheme
# (keep it out of this repository; see apps.conf.example)
conf=$1; out=${2:A}
[[ -f $conf && -n $out ]] || { echo "usage: build-apps.sh <apps.conf> <output-dir>" >&2; exit 2; }
mkdir -p $out
while IFS='|' read -r app proj scheme; do
  [[ -z $app || $app == \#* ]] && continue
  repo=${proj:h}
  srcroot=$(git -C $repo rev-parse --show-toplevel 2>/dev/null || echo $repo)
  for config in Debug Release; do
    dd=$out/$app-$config; log=$out/$app-$config.log; prov=$out/$app-$config.provenance
    {
      echo "app: $app"; echo "config: $config"; echo "project: $proj"; echo "scheme: $scheme"
      echo "revision: $(git -C $repo rev-parse HEAD 2>/dev/null || echo 'not a git repository')"
      echo "uncommitted-files: $(git -C $repo status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      echo "uncommitted-diff-sha256: $(git -C $repo diff HEAD 2>/dev/null | shasum -a 256 | cut -c1-16)"
      echo "swift-source-tree-sha256: $(find $srcroot -name '*.swift' -not -path '*/build*' -not -path '*/DerivedData*' -not -path '*/.build/*' -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-16)"
      echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
      echo "swiftc: $(xcrun swiftc --version 2>&1 | head -1)"
      echo "built: $(date -u +%FT%TZ)"
    } > $prov
    xcodebuild -project $proj -scheme $scheme -configuration $config \
      -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
      -derivedDataPath $dd -jobs 4 CODE_SIGNING_ALLOWED=NO \
      DEBUG_INFORMATION_FORMAT=dwarf-with-dsym build > $log 2>&1
    rc=$?
    echo "xcodebuild-exit: $rc" >> $prov
    xcodebuild -project $proj -scheme $scheme -configuration $config -sdk iphonesimulator \
      -derivedDataPath $dd -showBuildSettings 2>/dev/null \
      | grep -E "^\s+(SWIFT_OPTIMIZATION_LEVEL|SWIFT_COMPILATION_MODE|ENABLE_DEBUG_DYLIB|GCC_OPTIMIZATION_LEVEL|SWIFT_VERSION) =" \
      | sort -u | sed 's/^ */setting: /' >> $prov
    find $dd/Build/Products -path "*.app/*" -type f -perm +111 \( -name "$app" -o -name "*.debug.dylib" \) 2>/dev/null |
      while read -r bin; do
        echo "binary: $bin" >> $prov
        xcrun dwarfdump --uuid $bin 2>/dev/null | sed 's/^/uuid: /' >> $prov
      done
    echo "$app $config exit=$rc"
  done
done < $conf
