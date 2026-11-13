#!/usr/bin/env python3
"""Check swiftdc's entry conventions against the compiler's own lowering.

Usage: Tools/ghidra-compare/interface_oracle.py <swiftdc> <built-corpus-dir> [--list]

The oracle is the compiler, not a reader: each corpus source is compiled
to LLVM IR (`swiftc -emit-ir`, `clang -S -emit-llvm`), whose `define`
lines give every function's lowered parameters in order, with `swiftself`,
`swifterror`, `sret` and `swiftasync` marked. On arm64 that fixes the
entry registers: integers and pointers in x0…x7, floats in v0…v7, self in
x20, the async context in x22, an indirect result's buffer in x8.

swiftdc's side is what its analysis seeded at each function's entry (the
`analysis.entry` probe record of `disasm --structured --probe`), matched by
the function's symbol.

Per function:
  wrong      swiftdc seeded an argument register, or self in x20, that the
             compiler does not pass a parameter in
  complete   every parameter register the compiler uses is seeded
  partial    some are, and nothing is wrong
  none       none is (a decline), though the function has parameters
  no-params  the function takes nothing, and swiftdc seeded nothing
Functions whose lowering this cannot place (an aggregate passed as an
array or by value, more than eight of a bank, a symbol whose signature
differs between optimization levels, hand-written assembly) are counted
as `unchecked`, never guessed.

x8 is not scored: swiftdc seeds it in every function as a possible result
buffer, which is reported as its own count beside `sret`.
"""
import json, re, subprocess, sys, tempfile
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
INT = re.compile(r"^(i1|i8|i16|i32|i64|ptr)$")
FLOAT = re.compile(r"^(half|float|double)$")


def run(command):
    return subprocess.run(command, capture_output=True, text=True).stdout


def split_parameters(text):
    parts, depth, current = [], 0, ""
    for ch in text:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current.strip())
    return parts


def lowered(define_line):
    """(registers a parameter arrives in, has sret) or None when not placeable."""
    match = re.search(r'@(?:"((?:[^"\\]|\\.)*)"|([\w.$]+))\((.*)\)[^)]*$', define_line)
    if not match:
        return None
    name = match.group(1) if match.group(1) is not None else match.group(2)
    name = name.replace("\\01", "")
    registers, gpr, fpr, sret = set(), 0, 0, False
    for parameter in split_parameters(match.group(3)):
        if parameter == "...":
            return name, None
        kind = parameter.split()[0]
        if " sret(" in parameter or parameter.startswith("ptr sret"):
            sret = True
            continue
        if "swiftself" in parameter:
            registers.add("x20")
            continue
        if "swifterror" in parameter:
            continue
        if "swiftasync" in parameter:
            registers.add("x22")
            continue
        if " byval(" in parameter:
            return name, None
        if INT.match(kind):
            if gpr >= 8:
                return name, None
            registers.add(f"x{gpr}")
            gpr += 1
        elif FLOAT.match(kind):
            if fpr >= 8:
                return name, None
            registers.add(f"v{fpr}")
            fpr += 1
        else:
            return name, None
    return name, (frozenset(registers), sret)


def oracle_for(area_dir):
    """{symbol: lowering, or None when levels disagree or it is unplaceable}."""
    table = defaultdict(set)
    with tempfile.TemporaryDirectory() as tmp:
        for source in sorted(area_dir.iterdir()):
            if source.suffix == ".swift":
                variants = [["xcrun", "swiftc", level, "-parse-as-library", "-emit-ir", str(source),
                             "-module-name", "M", "-enable-experimental-feature", "Lifetimes"] + extra
                            for level in ("-Onone", "-O", "-Osize") for extra in ([], ["-enable-library-evolution"])]
            elif source.suffix in (".c", ".m"):
                arc = ["-fobjc-arc"] if source.suffix == ".m" else []
                variants = [["xcrun", "clang", level, "-S", "-emit-llvm", "-o", "-", str(source)] + arc
                            for level in ("-O0", "-O1", "-O2", "-Os")]
            else:
                continue
            for command in variants:
                for line in run(command).split("\n"):
                    if line.startswith("define "):
                        found = lowered(line)
                        if found:
                            table[found[0]].add(found[1])
    return {name: (next(iter(values)) if len(values) == 1 else None) for name, values in table.items()}


def symbols(dylib):
    """{address: symbol without its leading underscore} for defined text symbols."""
    result = {}
    for line in run(["nm", "-n", str(dylib)]).split("\n"):
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tT":
            name = parts[2][1:] if parts[2].startswith("_") else parts[2]
            result.setdefault(int(parts[0], 16), name)
    return result


def seeds(swiftdc, dylib):
    with tempfile.NamedTemporaryFile(suffix=".jsonl") as probe:
        subprocess.run([swiftdc, "disasm", str(dylib), "--structured", "--probe", probe.name],
                       capture_output=True)
        entries = {}
        for line in open(probe.name):
            if '"analysis.entry"' not in line:
                continue
            record = json.loads(line)
            if record.get("event") != "analysis.entry" or "function" not in record:
                continue
            entries[int(record["function"], 16)] = {
                register: value.get("expression", {}).get("kind", "?")
                for register, value in (record.get("fields") or {}).get("seeds", {}).items()}
        return entries


def judge(expected, seeded):
    registers, _ = expected
    claimed = {r for r in seeded if r != "x8" and re.match(r"^(x[0-7]|v[0-7]|x20|x22)$", r)}
    if claimed - registers:
        return "wrong"
    if not registers:
        return "no-params"
    if registers <= claimed:
        return "complete"
    return "partial" if claimed else "none"


def main():
    swiftdc, built = sys.argv[1], Path(sys.argv[2])
    listing = "--list" in sys.argv
    totals, per_area, wrong, sret = Counter(), defaultdict(Counter), [], Counter()
    for area in sorted(p for p in built.iterdir() if p.is_dir()):
        source_dir = HERE / "corpus" / area.name
        if not source_dir.is_dir():
            continue
        oracle = oracle_for(source_dir)
        for dylib in sorted(area.glob("*.dylib")):
            entry = seeds(swiftdc, dylib)
            for address, name in symbols(dylib).items():
                if name not in oracle:
                    continue
                expected = oracle[name]
                if expected is None or address not in entry:
                    verdict = "unchecked"
                else:
                    verdict = judge(expected, entry[address])
                    sret["sret, x8 seeded" if expected[1] else "no sret, x8 seeded"] += "x8" in entry[address]
                    if verdict == "wrong":
                        extra = sorted({r for r in entry[address] if r != "x8"} - expected[0])
                        wrong.append(f"{area.name}/{dylib.name} {name}: seeds {extra}, compiler passes {sorted(expected[0])}")
                totals[verdict] += 1
                per_area[area.name][verdict] += 1
    order = ["complete", "partial", "none", "wrong", "no-params", "unchecked"]
    print(f"{'area':14} " + " ".join(f"{k:>10}" for k in order))
    for area, counts in sorted(per_area.items()):
        print(f"{area:14} " + " ".join(f"{counts[k]:>10}" for k in order))
    print(f"{'total':14} " + " ".join(f"{totals[k]:>10}" for k in order))
    checked = sum(totals[k] for k in ("complete", "partial", "none", "wrong"))
    if checked:
        print("\nof the %d functions with parameters: " % checked
              + ", ".join(f"{k} {100 * totals[k] / checked:.1f}%" for k in ("complete", "partial", "none", "wrong")))
    print("x8: " + ", ".join(f"{k} {v}" for k, v in sorted(sret.items())))
    if listing or len(wrong) <= 40:
        for line in wrong:
            print("WRONG " + line)
    else:
        print(f"{len(wrong)} wrong entries; --list prints them")
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
