#!/usr/bin/env python3
"""Render the published decompilation samples: source, swiftdc, Ghidra.

Usage: Tools/samples/render.py <swiftdc> <workdir> [<outdir>]

<workdir> is what Tools/samples/build.sh produced: the sources at their
pinned commits and the binaries built from them. <outdir> defaults to
samples/ in the repository.

Which functions appear is decided by a rule, not by hand, so the set is
not picked for what swiftdc does well: every `func` declared in the
listed source files, in source order. For each one the page shows its
source, what swiftdc renders (`disasm --structured`) and what Ghidra
renders (default analysis, its own C), both for the same address. A
function the optimizer inlined everywhere has no body of its own and is
listed as such; one that survives only as a specialization shows that.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent

PROJECTS = [
    {
        "name": "argument-parser",
        "title": "swift-argument-parser examples",
        "url": "https://github.com/apple/swift-argument-parser",
        "checkout": "swift-argument-parser",
        "licence": "Apache License 2.0 with Runtime Library Exception",
        "licence_file": "LICENSE.txt",
        "pages": [
            {"page": "math", "binary": "math", "module": "math", "sources": ["Examples/math/Math.swift"]},
            {"page": "repeat", "binary": "repeat", "module": "repeat", "sources": ["Examples/repeat/Repeat.swift"]},
            {"page": "roll", "binary": "roll", "module": "roll", "sources": ["Examples/roll/SplitMix64.swift"]},
            {"page": "count-lines", "binary": "count-lines", "module": "count_lines",
             "sources": ["Examples/count-lines/CountLines.swift"]},
            {"page": "color", "binary": "color", "module": "color", "sources": ["Examples/color/Color.swift"]},
        ],
    },
    {
        "name": "mas",
        "title": "mas, the Mac App Store command line",
        "url": "https://github.com/mas-cli/mas",
        "checkout": "mas",
        "licence": "MIT License",
        "licence_file": "LICENSE",
        "pages": [
            {"page": "commands", "binary": "mas", "module": "mas", "sources": "Sources/mas/Commands/MAS.*.swift"},
        ],
    },
]

TYPE_KEYWORDS = ("struct", "enum", "class", "actor", "extension", "protocol")
DECL = re.compile(r"^\s*(?:@[\w()., ]+\s+)*(?:(?:public|private|fileprivate|internal|package|open|static|class|"
                  r"mutating|nonmutating|nonisolated|override|final|required|convenience|dynamic|isolated)\s+)*"
                  r"(func|struct|enum|class|actor|extension|protocol)\s+([`\w.]+)")


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def declared_functions(path):
    """Each `func` in a Swift file: (type path, name, first line, last line), in order.

    Scopes come from brace depth: a type or extension declaration opens one
    at its `{`. Braces inside strings and comments are skipped.
    """
    lines = path.read_text().split("\n")
    scopes = []          # (name, depth at which it closes)
    pending = None       # a type name whose `{` has not been seen yet
    open_funcs = []      # (path, name, start, depth)
    found = []
    depth = 0
    in_block_comment = False
    for number, line in enumerate(lines, 1):
        code, i, in_string = [], 0, False
        while i < len(line):
            two = line[i:i + 2]
            if in_block_comment:
                if two == "*/":
                    in_block_comment, i = False, i + 2
                    continue
                i += 1
                continue
            if not in_string and two == "/*":
                in_block_comment, i = True, i + 2
                continue
            if not in_string and two == "//":
                break
            if line[i] == '"' and (i == 0 or line[i - 1] != "\\"):
                in_string = not in_string
            code.append(" " if in_string and line[i] in "{}" else line[i])
            i += 1
        text = "".join(code)
        match = DECL.match(text)
        if match:
            keyword, name = match.group(1), match.group(2).strip("`")
            if keyword == "func":
                path_now = ".".join(s[0] for s in scopes)
                open_funcs.append((path_now, name, number, depth))
            elif keyword in TYPE_KEYWORDS:
                pending = name
        for ch in text:
            if ch == "{":
                depth += 1
                if pending is not None:
                    scopes.append((pending, depth))
                    pending = None
            elif ch == "}":
                for f in [f for f in open_funcs if f[3] == depth - 1]:
                    found.append((f[0], f[1], f[2], number))
                    open_funcs.remove(f)
                if scopes and scopes[-1][1] == depth:
                    scopes.pop()
                depth -= 1
        # A protocol requirement or an abstract declaration has no body.
        for f in [f for f in open_funcs if f[2] == number and "{" not in text and f[3] == depth]:
            if not text.rstrip().endswith(("(", ",")):
                open_funcs.remove(f)
    return sorted(found, key=lambda f: f[2]), lines


def symbols(binary):
    """[(address, demangled name)] for every defined text symbol."""
    table = []
    for line in run(["nm", "-n", str(binary)]).stdout.split("\n"):
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tT":
            table.append((int(parts[0], 16), parts[2][1:] if parts[2].startswith("_$") else parts[2]))
    names = run(["xcrun", "swift-demangle", "--compact"], input="\n".join(s for _, s in table)).stdout.split("\n")
    return [(address, name) for (address, _), name in zip(table, names)]


def split_top_level(text):
    parts, depth, current = [], 0, ""
    for ch in text:
        if ch in "([<{":
            depth += 1
        elif ch in ")]>}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current.strip())
    return parts


def balanced(text, start):
    """The index just past the bracket group opening at text[start]."""
    pairs = {"(": ")", "<": ">", "[": "]"}
    depth, close = 0, pairs[text[start]]
    for i in range(start, len(text)):
        if text[i] == text[start]:
            depth += 1
        elif text[i] == close:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def source_labels(declaration):
    """The argument labels of a `func` declaration: `func f(_ a: Int, b c: Int)` is [None, "b"]."""
    open_at = declaration.find("(")
    if open_at < 0:
        return []
    labels = []
    for parameter in split_top_level(declaration[open_at + 1:balanced(declaration, open_at) - 1]):
        words = parameter.split(":", 1)[0].split()
        words = [w for w in words if not w.startswith("@") and w not in ("inout", "borrowing", "consuming")]
        label = words[0] if words else None
        labels.append(None if label == "_" else label)
    return labels


def symbol_labels(symbol, qualified):
    """The argument labels in a demangled name, after `qualified`."""
    start = symbol.find(qualified) + len(qualified)
    if start < len(qualified) or start >= len(symbol):
        return None
    if symbol[start] == "<":
        start = balanced(symbol, start)
    if start >= len(symbol) or symbol[start] != "(":
        return None
    labels = []
    for parameter in split_top_level(symbol[start + 1:balanced(symbol, start) - 1]):
        match = re.match(r"^(\w+): ", parameter)
        labels.append(match.group(1) if match else None)
    return labels


def bodies_for(module, type_path, name, labels, table):
    """The symbols that are this function's body: the function itself, or,
    when it survives only specialized, each specialization of it. An
    overload is told apart by its argument labels."""
    qualified = ".".join(p for p in (module, type_path, name) if p)

    def same(symbol):
        # An async function's later funclets (`(1) await resume partial
        # function for …`) are parts of its body, not bodies of their own:
        # swiftdc renders them joined under the entry.
        return not symbol.startswith("(") and symbol_labels(symbol, qualified) == labels

    direct = [(a, n) for a, n in table if (n.startswith(qualified + "(") or n.startswith(qualified + "<")) and same(n)]
    if direct:
        return direct, "its own body"
    specialized = [(a, n) for a, n in table
                   if (f" of {qualified}(" in n or f" of {qualified}<" in n or f" of static {qualified}(" in n)
                   and same(n)]
    if specialized:
        return specialized, "only specialized"
    return [], "inlined everywhere"


def swiftdc_render(swiftdc, binary, address):
    out = run([swiftdc, "disasm", str(binary), "--structured", "-f", hex(address)])
    return out.stdout.strip() if out.returncode == 0 else f"// swiftdc failed: {out.stderr.strip()[:300]}"


def ghidra_render(binary, addresses, scratch):
    """{address: Ghidra's prototype and C} for the listed addresses."""
    home = os.environ.get("GHIDRA_HOME") or (run(["brew", "--prefix", "ghidra"]).stdout.strip() + "/libexec")
    headless = Path(home) / "support" / "analyzeHeadless"
    if not headless.exists():
        sys.exit(f"no Ghidra at {home} (set GHIDRA_HOME)")
    (scratch / "projects").mkdir(parents=True, exist_ok=True)
    listing, output = scratch / f"{binary.name}.addresses", scratch / f"{binary.name}.ghidra.c"
    listing.write_text("\n".join(f"{a:x}" for a in addresses) + "\n")
    env = dict(os.environ, GHIDRA_SWIFT_DEMANGLER=run(["xcrun", "-f", "swift-demangle"]).stdout.strip(),
               GHIDRA_HEADLESS_MAXMEM=os.environ.get("GHIDRA_HEADLESS_MAXMEM", "3G"))
    result = run([str(headless), str(scratch / "projects"), binary.name, "-import", str(binary), "-overwrite",
                  "-scriptPath", str(HERE), "-postScript", "DumpSelected.java", str(listing), str(output),
                  "-deleteProject", "-max-cpu", "2"], env=env)
    if not output.exists():
        sys.exit(f"Ghidra produced nothing for {binary}:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    renders, current = {}, None
    for line in output.read_text().split("\n"):
        if line.startswith("=== 0x"):
            current = int(line[6:], 16)
            renders[current] = []
        elif current is not None:
            renders[current].append(line)
    version = ""
    properties = Path(home) / "Ghidra" / "application.properties"
    if properties.exists():
        version = next((l.split("=", 1)[1] for l in properties.read_text().split("\n")
                        if l.startswith("application.version=")), "")
    return {a: "\n".join(v).strip() for a, v in renders.items()}, version


def fence(language, text):
    return f"```{language}\n{text.rstrip()}\n```\n"


def main():
    swiftdc, workdir = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    outdir = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else REPO / "samples"
    swiftdc_revision = run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"]).stdout.strip()
    toolchain = run(["xcrun", "swiftc", "--version"]).stdout.split("\n")[0]
    summary = []
    for project in PROJECTS:
        checkout = workdir / project["checkout"]
        commit = run(["git", "-C", str(checkout), "rev-parse", "HEAD"]).stdout.strip()
        target = outdir / project["name"]
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy(checkout / project["licence_file"], target / "LICENSE.txt")
        counts = {"its own body": 0, "only specialized": 0, "inlined everywhere": 0}
        for page in project["pages"]:
            binary = workdir / "bin" / page["binary"]
            sources = page["sources"]
            files = sorted(checkout.glob(sources)) if isinstance(sources, str) else [checkout / s for s in sources]
            table = symbols(binary)
            entries = []
            for source in files:
                functions, lines = declared_functions(source)
                for type_path, name, first, last in functions:
                    header = " ".join(lines[first - 1:last])
                    labels = source_labels(header[header.find("func"):])
                    found, how = bodies_for(page["module"], type_path, name, labels, table)
                    counts[how] += 1
                    entries.append((source, type_path, name, "\n".join(lines[first - 1:last]), found, how))
            addresses = sorted({a for e in entries for a, _ in e[4]})
            ghidra, ghidra_version = ghidra_render(binary, addresses, workdir / "ghidra") if addresses else ({}, "")
            body = [f"# {project['title']}: `{page['page']}`\n",
                    f"Built from [{project['url']}]({project['url']}) at `{commit[:12]}`. Every `func` declared in "
                    + ", ".join(f"`{f.relative_to(checkout)}`" for f in files)
                    + ", in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same "
                    "address in the same release binary.\n",
                    f"swiftdc `{swiftdc_revision}`, Ghidra {ghidra_version}, {toolchain}. Regenerate with "
                    "`Tools/samples/build.sh` and `Tools/samples/render.py`.\n"]
            for source, type_path, name, text, found, how in entries:
                title = ".".join(p for p in (type_path, name) if p)
                body.append(f"\n## `{title}`\n")
                body.append(f"From `{source.relative_to(checkout)}`.\n")
                body.append(fence("swift", text))
                if not found:
                    body.append("\nThe optimizer inlined it into every caller, so the binary has no body of its "
                                "own to decompile.\n")
                    continue
                if how == "only specialized":
                    body.append("\nThe binary keeps it only as the specialization below, a copy the optimizer "
                                "rewrote for its callers.\n")
                for address, symbol in found:
                    body.append(f"\n### `{symbol}` at `{address:#x}`\n")
                    body.append("\nswiftdc:\n\n" + fence("swift", swiftdc_render(swiftdc, binary, address)))
                    body.append("\nGhidra:\n\n" + fence("c", ghidra.get(address, "// not rendered")))
            (target / f"{page['page']}.md").write_text(re.sub(r"\n{3,}", "\n\n", "\n".join(body)))
        readme = [f"# {project['title']}\n",
                  f"Source: [{project['url']}]({project['url']}) at `{commit}`, under the {project['licence']} "
                  "(`LICENSE.txt` here). The source excerpts and the decompiled output of its binaries are "
                  "published under that licence.\n",
                  "Pages: " + ", ".join(f"[{p['page']}]({p['page']}.md)" for p in project["pages"]) + ".\n",
                  f"Of the functions the rule selects, {counts['its own body']} have a body of their own, "
                  f"{counts['only specialized']} survive only as specializations, and "
                  f"{counts['inlined everywhere']} were inlined everywhere.\n"]
        (target / "README.md").write_text(re.sub(r"\n{3,}", "\n\n", "\n".join(readme)))
        summary.append((project["name"], counts))
    for name, counts in summary:
        print(name, counts)


if __name__ == "__main__":
    main()
