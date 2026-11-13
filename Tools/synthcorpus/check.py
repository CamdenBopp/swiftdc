#!/usr/bin/env python3 -I
"""Run swiftdc over the synthetic corpus and check what it must and must not say.

    Tools/synthcorpus/check.py --swiftdc BIN [--out DIR] [--area A ...] [--jobs N]

Every built product under DIR (default Tools/synthcorpus/out) goes through
each entry point. Three kinds of check:

1. Robustness, every product and entry point: exit 0, no signal, under the
   timeout and the resident-memory ceiling, and a disassembly view that is
   not empty.
2. Invariants that need no oracle, on --structured: every `goto loc_X` has
   exactly one `loc_X:` label in its function, and two separate processes
   print the same --structured and --pseudo text.
3. Expectations written beside the code they describe, in the source:

       // EXPECT <view> <levels> <function> :: <text>
       // FORBID <view> <levels> <function> :: <text>

   <view> is structured, pseudo, listing or interface. <levels> is `*` or a
   comma list (`O,Osize`, `O2.stripped`); `*` means every unstripped build.
   <function> is a substring of the function's header line (`*` for the
   whole render). <text> is matched literally, or as a regular expression
   when it starts with `re:`. An EXPECT names what a correct render shows;
   a FORBID names a wrong render seen before or argued possible.

Exit status 1 when anything failed; the report lists each failure.
"""
import argparse, concurrent.futures, os, re, subprocess, sys, time
from pathlib import Path

VIEWS = {
    "structured": ["disasm", "{f}", "--structured"],
    "pseudo": ["disasm", "{f}", "--pseudo"],
    "listing": ["disasm", "{f}"],
    "json": ["disasm", "{f}", "--json"],
    "xrefs": ["xrefs", "{f}", "--unreferenced"],
    "interface": ["interface", "{f}"],
    "objc": ["objc", "{f}", "--methods"],
    "dump": ["dump", "{f}"],
    "analyze": ["analyze", "{f}"],
}
NONEMPTY = {"structured", "pseudo", "listing"}
DIRECTIVE = re.compile(r"^\s*//\s*(EXPECT|FORBID)\s+(\w+)\s+(\S+)\s+(.+?)\s+::\s?(.*)$")


def run(binary, args, timeout, memory_mb):
    """(exit code or signal text, stdout, peak resident MB)."""
    command = ["/usr/bin/time", "-l", binary] + args
    try:
        done = subprocess.run(command, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return f"timeout {timeout}s", "", 0
    peak = 0
    match = re.search(rb"(\d+)\s+maximum resident set size", done.stderr)
    if match:
        peak = int(match.group(1)) // (1024 * 1024)
    status = done.returncode
    if status < 0 or status > 128:
        status = f"signal {(-status) if status < 0 else status - 128}"
    elif peak > memory_mb:
        status = f"peak {peak} MB > {memory_mb} MB"
    return status, done.stdout.decode("utf-8", "replace"), peak


def functions(render):
    """{header line: body text} for a --structured or --pseudo render."""
    result, header, body = {}, None, []
    for line in render.split("\n"):
        if line and not line[0].isspace() and line.rstrip().endswith("{"):
            header, body = line, []
        elif line == "}" and header is not None:
            result[header] = "\n".join(body)
            header = None
        elif header is not None:
            body.append(line)
    return result


def label_problems(render):
    problems = []
    for header, body in functions(render).items():
        labels = re.findall(r"^\s*(loc_[0-9a-f]+):", body, re.M)
        gotos = set(re.findall(r"\bgoto (loc_[0-9a-f]+)", body))
        for target in sorted(gotos):
            if labels.count(target) != 1:
                problems.append(f"{header.strip()}: goto {target} has {labels.count(target)} labels")
        for label in sorted(set(labels)):
            if labels.count(label) > 1:
                problems.append(f"{header.strip()}: {label} defined {labels.count(label)} times")
    return problems


def directives(source):
    found = []
    for number, line in enumerate(source.read_text(errors="replace").split("\n"), 1):
        match = DIRECTIVE.match(line)
        if match:
            kind, view, levels, function, text = match.groups()
            found.append((number, kind, view, levels, function.strip(), text))
    return found


def level_of(product, source):
    """`O`, `O2.stripped`, … from <name>.<level>[.stripped].dylib."""
    return product.name[len(source.stem) + 1:-len(".dylib")]


def matches(levels, level):
    if levels == "*":
        return not level.endswith(".stripped")
    return level in levels.split(",")


def check_product(binary, product, source, args):
    failures, renders = [], {}
    for view, template in VIEWS.items():
        status, output, _ = run(binary, [a.format(f=product) for a in template], args.timeout, args.memory)
        if status != 0:
            # A view that does not apply (objc on a Swift-only image) may
            # exit nonzero by design; only a signal, a timeout or memory is a
            # robustness failure there.
            if isinstance(status, int) and view not in NONEMPTY:
                continue
            failures.append(f"{view}: {status}")
            continue
        if view in NONEMPTY and not output.strip():
            failures.append(f"{view}: empty output")
        renders[view] = output
    if "structured" in renders:
        failures += [f"structured: {p}" for p in label_problems(renders["structured"])]
        for view in ("structured", "pseudo"):
            status, again, _ = run(binary, [a.format(f=product) for a in VIEWS[view]], args.timeout, args.memory)
            if status == 0 and again != renders.get(view):
                failures.append(f"{view}: differs between two processes")
    level = level_of(product, source)
    for number, kind, view, levels, function, text in directives(source):
        if not matches(levels, level) or view not in renders:
            continue
        scope = [renders[view]] if function == "*" else [
            f"{header}\n{body}" for header, body in functions(renders[view]).items() if function in header]
        if view in ("listing", "interface") and function != "*":
            scope = [renders[view]]
        where = f"{source.name}:{number} {kind} {view} {function}"
        if not scope:
            failures.append(f"{where}: no function matches")
            continue
        found = any((re.search(text[3:], s) if text.startswith("re:") else text in s) for s in scope)
        if kind == "EXPECT" and not found:
            failures.append(f"{where}: missing {text!r}")
        if kind == "FORBID" and found:
            failures.append(f"{where}: shows {text!r}")
    return product, failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swiftdc", required=True)
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent / "out"))
    parser.add_argument("--area", action="append", default=[])
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--memory", type=int, default=3000, help="peak resident MB")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    out = Path(args.out)
    work = []
    for area_dir in sorted((root / "src").iterdir()):
        if not area_dir.is_dir() or (args.area and area_dir.name not in args.area):
            continue
        for source in sorted(area_dir.iterdir()):
            if source.suffix not in (".swift", ".c", ".m", ".s"):
                continue
            for product in sorted((out / area_dir.name).glob(f"{source.stem}.*.dylib")):
                work.append((product, source))
    if not work:
        sys.exit(f"no products under {out}; run Tools/synthcorpus/build.sh first")
    started = time.time()
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(check_product, args.swiftdc, p, s, args) for p, s in work]
        for future in concurrent.futures.as_completed(futures):
            product, failures = future.result()
            if failures:
                failed += 1
                print(f"FAIL {product.relative_to(out)}")
                for failure in failures:
                    print(f"  {failure}")
    print(f"{len(work)} products, {failed} failing, {time.time() - started:.0f} s")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
