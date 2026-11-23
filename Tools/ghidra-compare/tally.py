#!/usr/bin/env python3
"""Total the per-function score tables.

Usage: Tools/ghidra-compare/tally.py <scores-dir>

Each <area>.md holds markdown table rows of seven cells:
  function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note
with each score CORRECT, PARTIAL, WRONG or DECLINED (or its first letter);
MISSING (the tool did not emit the function) counts as declined. A row
whose level cell lists several builds, comma-separated, counts once per
build. Rows with any other cell are not scores and are skipped, and so is
any section whose heading says it is outside the totals. Prints counts and
rates per area and in total, so a headline number can be recomputed from
the committed tables instead of quoted.
"""
import re, sys
from pathlib import Path

CODES = {"C": "correct", "P": "partial", "W": "wrong", "D": "declined", "M": "declined"}
ORDER = ["correct", "partial", "wrong", "declined"]
COLUMNS = ["Ghidra interface", "Ghidra body", "swiftdc interface", "swiftdc body"]


def score(cell):
    word = re.sub(r"[*`]", "", cell).strip().upper()
    return CODES.get(word[:1]) if word and word in ("C", "P", "W", "D", "CORRECT", "PARTIAL", "WRONG", "DECLINED", "MISSING") else None


def tally(path):
    counts = [dict.fromkeys(ORDER, 0) for _ in COLUMNS]
    rows = 0
    counted = True
    for line in path.read_text().split("\n"):
        if line.startswith("#"):
            counted = "outside the totals" not in line.lower()
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if not counted or len(cells) < 6:
            continue
        scores = [score(c) for c in cells[2:6]]
        if None in scores:
            continue
        weight = len([b for b in cells[1].split(",") if b.strip()]) or 1
        rows += weight
        for column, value in zip(counts, scores):
            column[value] += weight
    return rows, counts


def show(name, rows, counts):
    cells = []
    for column in counts:
        cells.append(" / ".join(str(column[k]) for k in ORDER))
    print(f"{name:14} {rows:5}  " + "  |  ".join(cells))


def main():
    directory = Path(sys.argv[1])
    total_rows, total = 0, [dict.fromkeys(ORDER, 0) for _ in COLUMNS]
    print(f"{'area':14} {'rows':>5}  " + "  |  ".join(f"{c} (C/P/W/D)" for c in COLUMNS))
    for path in sorted(directory.glob("*.md")):
        if path.stem == "RUBRIC":
            continue
        rows, counts = tally(path)
        show(path.stem, rows, counts)
        total_rows += rows
        for into, column in zip(total, counts):
            for key in ORDER:
                into[key] += column[key]
    show("total", total_rows, total)
    print()
    for name, column in zip(COLUMNS, total):
        rates = ", ".join(f"{k} {100 * column[k] / max(total_rows, 1):.1f}%" for k in ORDER)
        print(f"{name}: {rates}")


if __name__ == "__main__":
    main()
