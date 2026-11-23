#!/bin/bash
# Exercise Tools/test.sh in an isolated Git repo without a Swift toolchain.
set -euo pipefail

# A caller's Git environment may point straight at a different repository.
git_local_vars=$(git rev-parse --local-env-vars)
for variable in $git_local_vars GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_TEMPLATE_DIR; do
  unset "$variable"
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1

source_script=${1:-"$(dirname "$0")/test.sh"}
fixture=$(mktemp -d)
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$fixture"' EXIT
mkdir -p "$fixture/Tools" "$fixture/bin" "$fixture/Sources" "$fixture/Tests"
cp "$source_script" "$fixture/Tools/test.sh"
cd "$fixture"
git init -q --template=
git config --local core.hooksPath /dev/null
git config --local commit.gpgSign false
git add Tools
git -c user.name=Probe -c user.email=probe@example.invalid commit -qm base
git branch origin/dev

cat > bin/swift <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_CALLS"
case $1 in
  build)
    if [ "${STUB_BUILD_FAIL:-0}" = 1 ]; then
      echo 'error: stub build failure'
      exit 17
    fi
    echo 'Build complete' ;;
  test) [ "${SWIFTDC_REQUIRE_FIXTURES:-}" = 1 ] ;;
esac
STUB
chmod +x bin/swift
export PATH="$fixture/bin:$PATH" STUB_CALLS="$fixture/calls.log"

touch 'Sources/ValueTracking New.swift' 'Tests/Odd+NameTests.swift'
bash Tools/test.sh affected > mapped.log 2>&1
grep -Fxq 'build --build-tests' "$STUB_CALLS"
grep -Fq '|Tracer' "$STUB_CALLS"
grep -Fq 'Odd\+NameTests\.swift' "$STUB_CALLS"
grep -Fq 'Determinism|FixturePresence' "$STUB_CALLS"
test "$(wc -l < "$STUB_CALLS" | tr -d ' ')" = 2

touch 'Sources/Unmapped New.swift'
: > "$STUB_CALLS"
bash Tools/test.sh affected > fallback.log 2>&1
grep -Fxq 'test --skip-build' "$STUB_CALLS"
grep -Fq 'unmapped source' fallback.log

# Keep each shared-input scenario independent of the earlier source fallback.
mv 'Sources/Unmapped New.swift' "$fixture/unmapped.saved"
mv 'Sources/ValueTracking New.swift' "$fixture/mapped.saved"
mv 'Tests/Odd+NameTests.swift' "$fixture/test.saved"
touch Tools/notes.md
: > "$STUB_CALLS"
bash Tools/test.sh affected > tooling-doc.log 2>&1
grep -Fxq 'test --skip-build --filter Determinism|FixturePresence' "$STUB_CALLS"

touch Tools/build-helper.sh
: > "$STUB_CALLS"
bash Tools/test.sh affected > tooling.log 2>&1
grep -Fxq 'test --skip-build' "$STUB_CALLS"
grep -Fq 'shared test/build input Tools/build-helper.sh' tooling.log
mv Tools/build-helper.sh "$fixture/tooling.saved"
mv Tools/notes.md "$fixture/docs.saved"

mkdir -p .github/workflows
touch .github/workflows/ci.yml
: > "$STUB_CALLS"
bash Tools/test.sh affected > workflow.log 2>&1
grep -Fxq 'test --skip-build' "$STUB_CALLS"
grep -Fq 'shared test/build input .github/workflows/ci.yml' workflow.log

: > "$STUB_CALLS"
if STUB_BUILD_FAIL=1 bash Tools/test.sh full > build-failure.log 2>&1; then
  echo 'expected stub build to fail' >&2
  exit 1
fi
grep -Fxq 'build --build-tests' "$STUB_CALLS"
test "$(wc -l < "$STUB_CALLS" | tr -d ' ')" = 1
grep -Fq 'error: stub build failure' build-failure.log

git branch -D origin/dev >/dev/null
: > "$STUB_CALLS"
if bash Tools/test.sh affected > missing.log 2>&1; then
  echo 'expected missing origin/dev to fail' >&2
  exit 1
fi
test ! -s "$STUB_CALLS"
grep -Fq 'cannot determine changed paths; run Tools/test.sh full' missing.log

echo 'PASS test-tier mapping, fallback, and failure paths'
