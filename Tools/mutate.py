#!/usr/bin/env python3
"""Run a table of mutations against a set of tests, one at a time.

    Tools/mutate.py <table.json> --filter '<swift test filter>' [--only <text>…]

The table is a JSON array. Each entry replaces one exact string in one file:

    [{"name": "the gate off",
      "file": "Sources/SwiftDecompilerCore/ValueTracking.swift",
      "old": "} else if call.returnsNeverByName {",
      "new": "} else if false {"}]

`old` must occur exactly once, or the entry is reported and skipped: a
mutation applied in the wrong place proves nothing. `new` may be empty to
delete the text. An optional "command" replaces the build step for that
entry (a fixture or a C harness that `swift build` does not rebuild).

For each entry the file is rewritten, the package is rebuilt, the filtered
tests are run and the file is put back. The verdicts:

    killed     a test failed: the mutation is caught
    SURVIVED   every test passed: write the test, or remove the code
    BUILDERR   the mutant did not compile: it proves nothing, rewrite it

After the last entry the tree is rebuilt and the tests are run once more,
so the run ends on the real code. Exit status is 1 when anything survived,
failed to build, was skipped, or the final run is not green.

Never run two of these at once in one checkout, and do not edit the files
it names while it runs: it restores each file from the copy it read.
"""
import argparse
import json
import re
import subprocess
import sys


def shell(command):
    return subprocess.run(command, shell=True, capture_output=True, text=True)


def build(command):
    result = shell(command or "swift build --build-tests 2>&1")
    output = result.stdout + result.stderr
    return result.returncode == 0 and "error:" not in output


def test(test_filter):
    result = shell(f"swift test --skip-build --filter {json.dumps(test_filter)} 2>&1")
    output = result.stdout + result.stderr
    failed = sorted(set(re.findall(r"Test (\w+)\(.*?recorded an issue", output)))
    ran = re.search(r"Test run with (\d+) tests?", output)
    passed = result.returncode == 0 and "passed after" in output and not failed
    return passed, failed, int(ran.group(1)) if ran else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("table")
    parser.add_argument("--filter", required=True, help="swift test --filter expression")
    parser.add_argument("--only", action="append", default=[], help="run entries whose name contains this")
    arguments = parser.parse_args()

    with open(arguments.table) as handle:
        entries = json.load(handle)
    if arguments.only:
        entries = [e for e in entries if any(text in e["name"] for text in arguments.only)]

    originals = {}
    for entry in entries:
        if entry["file"] not in originals:
            with open(entry["file"]) as handle:
                originals[entry["file"]] = handle.read()

    if not build(None):
        sys.exit("mutate: the tree does not build before any mutation")
    passed, failed, ran = test(arguments.filter)
    if not passed or ran == 0:
        sys.exit(f"mutate: the tests are not green before any mutation ({ran} ran, failed: {failed})")
    print(f"green before: {ran} tests", flush=True)

    counts = {"killed": 0, "SURVIVED": 0, "BUILDERR": 0, "SKIPPED": 0}
    try:
        for entry in entries:
            original = originals[entry["file"]]
            occurrences = original.count(entry["old"])
            if occurrences != 1:
                counts["SKIPPED"] += 1
                print(f"SKIPPED   {entry['name']}: old text occurs {occurrences} times", flush=True)
                continue
            with open(entry["file"], "w") as handle:
                handle.write(original.replace(entry["old"], entry["new"]))
            try:
                if not build(entry.get("command")):
                    verdict, detail = "BUILDERR", ""
                else:
                    passed, failed, ran = test(arguments.filter)
                    verdict = "SURVIVED" if passed else "killed"
                    detail = ", ".join(failed)
            finally:
                with open(entry["file"], "w") as handle:
                    handle.write(original)
                if entry.get("command"):
                    shell(entry["command"])
            counts[verdict] += 1
            print(f"{verdict:9} {entry['name']}" + (f": {detail}" if detail else ""), flush=True)
    finally:
        for path, text in originals.items():
            with open(path, "w") as handle:
                handle.write(text)

    green = build(None)
    if green:
        green, failed, ran = test(arguments.filter)
    print(f"restored: {'green' if green else 'NOT GREEN'}", flush=True)
    print(", ".join(f"{count} {verdict}" for verdict, count in counts.items() if count), flush=True)
    clean = green and not (counts["SURVIVED"] or counts["BUILDERR"] or counts["SKIPPED"])
    sys.exit(0 if clean else 1)


if __name__ == "__main__":
    main()
