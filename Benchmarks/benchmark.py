#!/usr/bin/env python3
"""
swiftdc vs ipsw benchmark harness.

Runs swiftdc and blacktop/ipsw over the same set of Mach-O binaries on the same
three axes they both cover — Swift declarations, Objective-C headers, and ARM64
disassembly — and records, for each, wall-clock time (warm min/median over N
runs), output size, exit status, and determinism across runs. Full outputs are
written to outputs/ so the two tools' *direct output* can be diffed by hand.

Stdlib only. Run from anywhere:

    python3 Benchmarks/benchmark.py            # full matrix, writes RESULTS.md
    python3 Benchmarks/benchmark.py --runs 3   # fewer timed runs (faster)
    python3 Benchmarks/benchmark.py --quick    # fixtures only, skip self

The tool configs below are deliberately each tool's *best usable* invocation for
the axis (see FAIRNESS notes in README.md): e.g. `--demangle` is passed to
ipsw's Swift dump because that is strictly better output, but is omitted from its
ObjC dump because `--objc --demangle` errors out in ipsw 3.1.x.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = Path(__file__).resolve().parent / "outputs"

# Per-run wall-clock ceiling. A run that exceeds this is recorded as a timeout
# rather than hanging the matrix (whole-binary disassembly of a 40 MB image runs
# for minutes on both tools, so it is deliberately excluded from the timed set).
TIMEOUT_S = 180


def find_swiftdc() -> Path:
    for candidate in (REPO / ".build/release/swiftdc", REPO / ".build/debug/swiftdc"):
        if candidate.exists():
            return candidate
    sys.exit("swiftdc not built. Run: swift build -c release")


def find_ipsw() -> str:
    ipsw = shutil.which("ipsw")
    if not ipsw:
        sys.exit("ipsw not on PATH. Install: brew install ipsw")
    return ipsw


SWIFTDC = find_swiftdc()
IPSW = find_ipsw()


# ---- what to compare -------------------------------------------------------

# Binaries, smallest first. `fixture=True` are built by Fixtures/Sample/build.sh
# and shipped in the repo, so this matrix is reproducible by anyone.
@dataclass
class Binary:
    key: str
    path: Path
    label: str
    fixture: bool = True


BINARIES = [
    Binary("recon.opt.stripped", REPO / "Fixtures/Sample/libReconstruction.opt.stripped.dylib",
           "Reconstruction, -O, stripped"),
    Binary("sample", REPO / "Fixtures/Sample/libSample.dylib", "Sample dylib, -Onone"),
    Binary("recon.opt", REPO / "Fixtures/Sample/libReconstruction.opt.dylib",
           "Reconstruction, -O"),
    Binary("recon", REPO / "Fixtures/Sample/libReconstruction.dylib",
           "Reconstruction, -Onone"),
    Binary("recon.resilient", REPO / "Fixtures/Sample/libReconstruction.resilient.dylib",
           "Reconstruction, library-evolution"),
    Binary("swiftdc.self", SWIFTDC, "swiftdc itself (~30 MB Swift+ObjC binary)", fixture=False),
]


# An axis: a capability both tools implement, with the best usable invocation of
# each. `argv(tool_bin, target)` returns the full command line.
@dataclass
class Axis:
    key: str
    title: str
    swiftdc_argv: object
    ipsw_argv: object
    # Which binaries this axis runs on. Disassembly of a whole 40 MB __text runs
    # for minutes on both tools, so the timed disasm axis skips self.
    include_self: bool = True


AXES = [
    Axis(
        "swift", "Swift declarations",
        lambda b, t: [str(b), "dump", str(t)],
        lambda b, t: [b, "macho", "info", "--swift", "--demangle", "--no-color", str(t)],
    ),
    Axis(
        "objc", "Objective-C headers",
        lambda b, t: [str(b), "objc", str(t)],
        # --objc --demangle exits non-zero in ipsw 3.1.x, so plain --objc.
        lambda b, t: [b, "macho", "info", "--objc", "--no-color", str(t)],
    ),
    Axis(
        "disasm", "ARM64 disassembly (whole __text)",
        lambda b, t: [str(b), "disasm", str(t)],
        lambda b, t: [b, "macho", "disass", "--section", "__TEXT.__text", "--no-color", str(t)],
        include_self=False,
    ),
]


# ---- measurement -----------------------------------------------------------

@dataclass
class Measurement:
    tool: str
    axis: str
    binary: str
    argv: list
    ok: bool = False
    exit_code: int | None = None
    times_s: list = field(default_factory=list)
    min_s: float | None = None
    median_s: float | None = None
    stdout_bytes: int = 0
    stdout_lines: int = 0
    deterministic: bool | None = None
    note: str = ""


def run_once(argv: list) -> tuple[int, bytes]:
    p = subprocess.run(argv, capture_output=True, timeout=TIMEOUT_S)
    return p.returncode, p.stdout


def measure(tool: str, axis: Axis, b: Binary, argv: list, runs: int) -> Measurement:
    m = Measurement(tool=tool, axis=axis.key, binary=b.key, argv=argv)
    try:
        # One warm-up (fills the OS page cache; discarded).
        code, first = run_once(argv)
    except subprocess.TimeoutExpired:
        m.note = f"timeout >{TIMEOUT_S}s"
        return m
    except Exception as e:  # noqa: BLE001 - report any launch failure, don't crash the matrix
        m.note = f"launch error: {e}"
        return m

    m.exit_code = code
    m.stdout_bytes = len(first)
    m.stdout_lines = first.count(b"\n")
    first_hash = hashlib.sha256(first).hexdigest()

    if code != 0 and m.stdout_bytes == 0:
        m.note = f"exit {code}, no output"
        return m

    last_hash = first_hash
    for _ in range(runs):
        t0 = time.perf_counter()
        try:
            _, out = run_once(argv)
        except subprocess.TimeoutExpired:
            m.note = f"timeout >{TIMEOUT_S}s"
            return m
        m.times_s.append(time.perf_counter() - t0)
        last_hash = hashlib.sha256(out).hexdigest()

    m.ok = True
    m.min_s = min(m.times_s)
    m.median_s = statistics.median(m.times_s)
    m.deterministic = (first_hash == last_hash)

    # Persist the warm-up output for direct-output comparison.
    OUT.mkdir(exist_ok=True)
    (OUT / f"{b.key}.{axis.key}.{tool}.txt").write_bytes(first)
    return m


# ---- driver ----------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--runs", type=int, default=5, help="timed runs per cell (default 5)")
    ap.add_argument("--quick", action="store_true", help="fixtures only; skip the self binary")
    args = ap.parse_args()

    binaries = [b for b in BINARIES if b.path.exists()]
    missing = [b for b in BINARIES if not b.path.exists()]
    for b in missing:
        print(f"skip (not built): {b.path}", file=sys.stderr)
    if args.quick:
        binaries = [b for b in binaries if b.fixture]

    results: list[Measurement] = []
    for axis in AXES:
        for b in binaries:
            if b.fixture is False and (args.quick or not axis.include_self):
                continue
            for tool, argv_fn, tool_bin in (
                ("swiftdc", axis.swiftdc_argv, SWIFTDC),
                ("ipsw", axis.ipsw_argv, IPSW),
            ):
                argv = argv_fn(tool_bin, b.path)
                print(f"  {axis.key:7s} {b.key:22s} {tool:8s} ...", end="", flush=True)
                m = measure(tool, axis, b, argv, args.runs)
                if m.ok:
                    print(f" {m.min_s*1000:8.1f} ms  {m.stdout_lines:6d} lines"
                          f"{'' if m.deterministic else '  NON-DETERMINISTIC'}")
                else:
                    print(f" -- {m.note}")
                results.append(m)

    env = {
        "date": time.strftime("%Y-%m-%d"),
        "machine": platform.machine(),
        "cpu": subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"],
                              capture_output=True, text=True).stdout.strip(),
        "macos": platform.mac_ver()[0],
        "swiftdc_path": str(SWIFTDC.relative_to(REPO)),
        "swiftdc_build": "release" if "release" in str(SWIFTDC) else "debug",
        "swiftdc_commit": subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"],
                                         capture_output=True, text=True).stdout.strip(),
        "ipsw_version": subprocess.run([IPSW, "version"], capture_output=True, text=True).stdout.strip(),
        "runs": args.runs,
    }

    (Path(__file__).resolve().parent / "results.json").write_text(
        json.dumps({"env": env, "results": [asdict(m) | {"argv": rel_argv(m.argv)}
                                             for m in results]}, indent=2, default=str))
    write_report(env, binaries, results)
    print("\nwrote Benchmarks/RESULTS.md and Benchmarks/results.json")


def write_report(env: dict, binaries: list, results: list) -> None:
    idx = {(m.tool, m.axis, m.binary): m for m in results}
    lines: list[str] = []
    w = lines.append

    w("# swiftdc vs ipsw — benchmark results\n")
    w("_Generated by `Benchmarks/benchmark.py`. See "
      "[README.md](README.md) for methodology and fairness notes._\n")
    w("## Environment\n")
    w(f"- {env['cpu']} ({env['machine']}), macOS {env['macos']}")
    w(f"- swiftdc `{env['swiftdc_commit']}`, **{env['swiftdc_build']}** build (`{env['swiftdc_path']}`)")
    w(f"- ipsw {env['ipsw_version'].splitlines()[0] if env['ipsw_version'] else 'unknown'}")
    w(f"- {env['runs']} warm runs per cell; wall-clock **min** reported (median in results.json)")
    w(f"- measured {env['date']}\n")

    for axis in AXES:
        bins = [b for b in binaries if not (b.fixture is False and not axis.include_self)]
        if not bins:
            continue
        w(f"## {axis.title}\n")
        w(f"swiftdc `{_show(axis.swiftdc_argv)}` vs ipsw `{_show(axis.ipsw_argv)}`\n")
        w("| binary | swiftdc | ipsw | speedup | swiftdc lines | ipsw lines |")
        w("| --- | ---: | ---: | ---: | ---: | ---: |")
        for b in bins:
            s = idx.get(("swiftdc", axis.key, b.key))
            i = idx.get(("ipsw", axis.key, b.key))
            w(f"| {b.label} | {_ms(s)} | {_ms(i)} | {_speedup(s, i)} "
              f"| {_lines(s)} | {_lines(i)} |")
        w("")

    w("## Determinism\n")
    nd = [m for m in results if m.ok and m.deterministic is False]
    if nd:
        for m in nd:
            w(f"- **non-deterministic**: {m.tool} {m.axis} {m.binary}")
    else:
        w("Every successful run produced byte-identical output across repeats.")
    w("")
    Path(Path(__file__).resolve().parent / "RESULTS.md").write_text("\n".join(lines))


def rel_argv(argv: list) -> list:
    """Portable argv for the JSON: repo-relative binary paths, bare tool names."""
    prefix = str(REPO) + "/"
    out = []
    for a in argv:
        a = str(a)
        if a == IPSW:
            a = "ipsw"
        elif a.startswith(prefix):
            a = a[len(prefix):]
        out.append(a)
    return out


def _show(fn) -> str:
    argv = fn("TOOL", "BIN")
    return " ".join(str(a) for a in argv[1:])


def _ms(m) -> str:
    if m is None:
        return "—"
    if not m.ok:
        return m.note or "fail"
    return f"{m.min_s*1000:.1f} ms"


def _lines(m) -> str:
    if m is None or not m.ok:
        return "—"
    return f"{m.stdout_lines:,}"


def _speedup(s, i) -> str:
    if not (s and i and s.ok and i.ok and s.min_s > 0):
        return "—"
    r = i.min_s / s.min_s
    faster = "swiftdc" if r >= 1 else "ipsw"
    r = r if r >= 1 else 1 / r
    return f"{r:.1f}× {faster}"


if __name__ == "__main__":
    main()
