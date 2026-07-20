#!/usr/bin/env python3
"""Bounded, seeded fuzz over a Mach-O's Swift/Objective-C metadata sections.

Why this exists
---------------
`MachOPreflight` validates the Mach-O *container* — headers, load commands, and
their payload ranges. It says nothing about the CONTENTS of `__swift5_*` and
`__objc_*`, which are parsed by MachOSwiftSection / MachOObjCSection and reached
by `dump`, `interface`, `objc`, `analyze`, `disasm` and `xrefs`.

Those parsers resolve *relative pointers* and then read straight out of the
mapped file with no bounds check, so a corrupted offset reads unmapped memory:

    ObjCMethodList.indirectMethod -> readString(offset:) -> strlen   => SIGSEGV
    AssociatedTypeRecord.name     -> readString(offset:) -> strlen   => SIGSEGV
    MangledName.resolve -> readElement(offset:) -> numericCast       => SIGTRAP

All three die with EMPTY stderr, so the process vanishes without a diagnostic.

Usage
-----
    python3 Tools/metadata-fuzz.py <binary> [mutants] [seed]

Deterministic for a given (binary, mutants, seed). Exits nonzero if any mutant
kills the CLI, so it can be used as a gate once the class is contained.
"""
import collections
import os
import random
import subprocess
import sys

BIN = ".build/debug/swiftdc"
# Every subcommand that reads metadata. `disasm` is included deliberately: it is
# shielded from CONTAINER corruption by llvm-objdump, but ObjC metadata is parsed
# in-process, so it is NOT shielded here. Assuming otherwise is what let an
# earlier survey record a live crash class as fixed.
SUBCOMMANDS = [
    ["dump"], ["interface"], ["objc"], ["objc", "--methods"],
    ["layout"], ["disasm"], ["xrefs", "--unreferenced"], ["analyze"],
]


def metadata_sections(path):
    """(file offset, size, name) for each __swift5_* / __objc_* section."""
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True).stdout
    sections, current = [], None
    for line in out.split("\n"):
        token = line.strip()
        if token.startswith("sectname"):
            current = {"name": token.split()[1]}
        elif current is not None and token.startswith("size "):
            current["size"] = int(token.split()[1], 0)
        elif current is not None and token.startswith("offset "):
            current["off"] = int(token.split()[1])
            sections.append(current)
            current = None
    return [(s["off"], s["size"], s["name"]) for s in sections
            if s["size"] > 0 and ("swift5" in s["name"] or "objc" in s["name"])]


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "Fixtures/Sample/libSample.dylib"
    mutants = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1234

    ranges = metadata_sections(source)
    if not ranges:
        print(f"no metadata sections in {source}", file=sys.stderr)
        return 2

    base = open(source, "rb").read()
    rng = random.Random(seed)
    scratch = os.path.join(os.path.dirname(BIN), "metadata-fuzz-tmp")
    os.makedirs(scratch, exist_ok=True)

    crashes = collections.Counter()
    samples, accepted, rejected = [], 0, 0

    for index in range(mutants):
        offset, size, name = rng.choice(ranges)
        data = bytearray(base)
        edits = []
        for _ in range(rng.choice([1, 1, 2, 4])):
            position = offset + rng.randrange(size)
            data[position] = rng.randrange(256)
            edits.append(position)
        path = os.path.join(scratch, f"mutant{index}")
        open(path, "wb").write(bytes(data))
        os.chmod(path, 0o755)

        for command in SUBCOMMANDS:
            result = subprocess.run([BIN] + command + [path], capture_output=True, timeout=180)
            code = result.returncode
            # A signal (negative) or any status above 1 is a crash, not a decline.
            if code < 0 or code > 1:
                crashes[(" ".join(command), name, code)] += 1
                if len(samples) < 10:
                    samples.append(
                        (index, name, [hex(e) for e in edits], " ".join(command), code,
                         len(result.stdout), result.stderr[:100].decode("utf8", "replace"))
                    )
            elif code == 0:
                accepted += 1
            else:
                rejected += 1
        os.remove(path)

    runs = mutants * len(SUBCOMMANDS)
    total = sum(crashes.values())
    print(f"binary={source} mutants={mutants} seed={seed} sections={len(ranges)}")
    print(f"runs={runs} accepted={accepted} clean_nonzero={rejected} "
          f"crashes={total} ({100 * total / max(runs, 1):.1f}%)")
    for (command, name, code) in sorted(crashes, key=lambda k: -crashes[k]):
        print(f"  {crashes[(command, name, code)]:4d}x rc={code:<5d} {command:22s} {name}")
    for sample in samples:
        print("  sample:", sample)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
