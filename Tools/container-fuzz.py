#!/usr/bin/env python3
"""Bounded, seeded fuzz over a Mach-O's load-command region.

Why this exists
---------------
`MachOPreflight` rejects containers MachOKit would abort on. This measures how
much still gets through: each mutant flips 1-4 random bytes inside the load
commands, then every in-process subcommand runs on it. A negative exit status
(or >= 128) is a crash: the process died instead of reporting an error.

The sibling `metadata-fuzz.py` covers the `__swift5_*`/`__objc_*` contents.

Usage
-----
    python3 Tools/container-fuzz.py <binary> [mutants] [seed] [swiftdc ...]

Deterministic for a given (binary, mutants, seed). Pass several swiftdc builds
to compare them on the same mutants. Exits nonzero if any build crashed.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

SUBCOMMANDS = [["dump"], ["layout"], ["objc"], ["interface"], ["swift-version"]]


def main():
    source = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 7
    builds = sys.argv[4:] or [".build/debug/swiftdc"]
    data = open(source, "rb").read()
    sizeofcmds, = struct.unpack_from("<I", data, 20)
    rng = random.Random(seed)
    tally = {b: {"accepted": 0, "rejected": 0, "crashed": []} for b in builds}
    with tempfile.TemporaryDirectory() as work:
        for index in range(count):
            mutant = bytearray(data)
            for _ in range(rng.randint(1, 4)):
                mutant[32 + rng.randrange(sizeofcmds)] = rng.randrange(256)
            path = os.path.join(work, f"m{index:03}.dylib")
            open(path, "wb").write(mutant)
            for build in builds:
                worst = 0
                for sub in SUBCOMMANDS:
                    try:
                        code = subprocess.run([build] + sub + [path], capture_output=True, timeout=60).returncode
                    except subprocess.TimeoutExpired:
                        code = 999
                    if code < 0 or code >= 128:
                        worst = code
                        break
                    worst = max(worst, code)
                if worst == 0:
                    tally[build]["accepted"] += 1
                elif 0 < worst < 128:
                    tally[build]["rejected"] += 1
                else:
                    tally[build]["crashed"].append((index, worst))
    crashed = False
    for build, t in tally.items():
        crashed = crashed or bool(t["crashed"])
        print(f"{build}: accepted {t['accepted']}, rejected {t['rejected']}, "
              f"crashed {len(t['crashed'])} {t['crashed']}")
    sys.exit(1 if crashed else 0)


if __name__ == "__main__":
    main()
