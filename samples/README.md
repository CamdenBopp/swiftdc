# Decompilation samples

What swiftdc makes of real open-source Swift, beside the source it came
from and beside Ghidra's output for the same function. Both projects are
built here from source at a pinned commit, in release mode, so anyone
can rebuild the same binaries and check every line.

| Project | Licence | Pages | Functions selected | Own body | Only specialized | Inlined everywhere |
|---|---|---|---|---|---|---|
| [swift-argument-parser examples](argument-parser/README.md) | Apache-2.0 | `math`, `repeat`, `roll`, `count-lines`, `color` | 17 | 12 | 3 | 2 |
| [mas](mas/README.md) | MIT | `commands` | 23 | 14 | 4 | 5 |

## How the functions were chosen

By a rule fixed before any output was looked at: every `func` declared
in the listed source files, in source order. For the argument-parser
examples that is each example's own source file; for mas it is every
file in `Sources/mas/Commands`. Nothing was left out for rendering
badly, so the pages show swiftdc's weak spots as well as its strong
ones.

The optimizer decides what is left of each function. One it inlined
into every caller has no body in the binary, and the page says so
instead of showing something else. One it kept only as a rewritten copy
(`function signature specialization <Arg[0] = Exploded> of …`) is shown
as that copy.

## How to read a page

Each function has three parts:

- **The source**, from the project at the pinned commit.
- **swiftdc**, `disasm --structured`. A `?` is a value swiftdc could not
  prove and declined to guess. `x8`, `w1` and the like are registers it
  did not name. `sub_…` is a function with no symbol. An async function
  is one body with its resume points listed at the top.
- **Ghidra**, its default analysis and its own C, with Swift names
  demangled. It is shown unedited for comparison, not as a target: it
  names every value, and some of those names are guesses.

## Rebuilding

```bash
Tools/samples/build.sh ~/swiftdc-samples
```

```bash
Tools/samples/render.py .build-release/release/swiftdc ~/swiftdc-samples
```

The first clones and builds both projects (about 1 GB while it builds,
then only the binaries). The second rewrites these pages; it needs
Ghidra (`brew install ghidra`, or `GHIDRA_HOME`) and takes about 20
minutes, most of it Ghidra analysing mas. Output depends on the
compiler, so each page names the Swift and swiftdc it was made with.
Rendering again after a swiftdc change shows, line by line, what the
change did to real code.

One build change is needed for mas on Swift 6.4: mas treats every
warning as an error, and this compiler warns about two `unsafe` markers
it no longer needs. `build.sh` removes that setting from mas's
`Package.swift` before building; mas's source is not changed.
