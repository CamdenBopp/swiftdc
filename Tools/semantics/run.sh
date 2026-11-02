#!/bin/zsh
# Generate the encodings, trace each with the current build, and prove the
# traced values against the Arm ARM spec. PYTHON names an interpreter that
# has z3 (default python3). Exits 1 on any refutation.
set -e
root=${0:A:h:h:h}
work=${1:-$(mktemp -d)}
python=${PYTHON:-python3}
cd $root
$python -I Tools/semantics/check.py generate $work/words.txt
swift build --build-tests 2>&1 | grep -E "error:|Build complete"
SWIFTDC_SEMANTICS_WORDS=$work/words.txt SWIFTDC_SEMANTICS_OUT=$work/traced.jsonl \
    swift test --skip-build --filter exportTracerSemanticsIfRequested > $work/export.log 2>&1
$python -I Tools/semantics/check.py check $work/words.txt $work/traced.jsonl
