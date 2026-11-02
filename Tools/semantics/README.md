# Semantics equivalence check

Proves the value tracer's integer semantics, and the structurer's text-path
branch conditions, against the Arm ARM with z3,
for every value of the input registers. It runs only on a dev host and is
not part of `swift test`: z3 is a test oracle, never a dependency.

```bash
python3 -m venv /tmp/z3venv && /tmp/z3venv/bin/pip install z3-solver
PYTHON=/tmp/z3venv/bin/python Tools/semantics/run.sh [workdir]
```

`check.py generate` enumerates about 58,500 encodings of the integer
data-processing instructions: logical and add/subtract with every shift
type and amount, every extend, every bitfield `immr`/`imms`, extract,
the 1-, 2- and 3-source groups, move wide, and a sample of the logical
immediates. `exportTracerSemanticsIfRequested` traces each word alone as
`insn; ret` with x0-x3 as arguments 0-3 and exports x0 at the `ret`.
`check.py check` writes each word's meaning from its encoding fields, from
the Arm pseudocode (`DecodeBitMasks`, `ShiftReg`, `ExtendReg`, the
bitfield `wmask`/`tmask` merge), with no swiftdc code, and asks z3 whether
the traced value can differ.

The check covers the whole tracer path: operand shifts and extends, the
table in `InstructionSemantics.swift`, constant folding and the W write.
Each shift in a traced value also has to be proven below 64, the domain
`evaluateInteger` accepts.

Outcomes per instruction class:

- **verified**: equal for all inputs.
- **sampled**: z3 could not settle it in 20 s (only `sdiv w`, lowered to
  64-bit division); matched on edge and random inputs. Tested, not proven.
- **declined**: the tracer claims nothing. Sound, and the list of what to
  model next.
- **refuted**: a counterexample, printed with the inputs. Exit status 1.

## Branch conditions

`conditions.py` does the same for the structurer's text-path branch
conditions, the ones a function without tracer facts renders.
`exportTextConditionsIfRequested` lays out about 12,600 sequences
(`definition; test; branch`, the definition drawn from `check.py`'s
encodings and retargeted to x8, the test a `cmp`, `cmn`, `tst`, `subs`,
`adds` or `ands` against an immediate or a shifted register, every
condition code, and `cbz`/`tbz` after a definition) and exports the
condition rendered for the taken branch. The script parses it and proves
it against NZCV from the Arm pseudocode.

```bash
PYTHON=/tmp/z3venv/bin/python Tools/semantics/run.sh [workdir]
```

How the text is read: a register name is its value at the branch; an
expression over w registers is a 32-bit operation and over x registers a
64-bit one; a comparison is at the wider of its operands' widths, a w
operand zero-extended; `<` is signed and `<ᵁ` unsigned. Outcomes:
verified, declined (`?`), refuted (with the registers that show it), and
unparsed, a rendering this grammar cannot read, which is reported as a
defect: a reader cannot know what it means either.

To prove a semantics change, run it before and after, and break the change
once to see it refuted: `sbfx` read as unsigned gave 2,507 refutations and
a 32-bit `asr` without its sign extension 33.
