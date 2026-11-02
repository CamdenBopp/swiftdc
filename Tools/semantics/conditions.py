#!/usr/bin/env python3
"""Prove the structurer's text-path branch conditions against the Arm ARM.

Each sequence is an optional definition (an instruction from check.py's
generator, retargeted to x8), a flag-setting test or nothing, and a
conditional branch: `b.cond`, `cbz`/`cbnz` or `tbz`/`tbnz`. The Swift test
`exportTextConditionsIfRequested` lays it out as `def; test; branch; ret;
ret` and exports the condition the text path renders for the taken branch.
This script parses that text and asks z3 whether it can disagree with the
branch's real condition (NZCV from the Arm pseudocode) for any register
values.

    conditions.py generate sequences.txt
    SWIFTDC_CONDITIONS_WORDS=sequences.txt SWIFTDC_CONDITIONS_OUT=conds.jsonl \\
        swift test --skip-build --filter exportTextConditionsIfRequested
    conditions.py check sequences.txt conds.jsonl

How the text reads: a register name is its value at the branch; an
expression over w registers is a 32-bit operation and over x registers a
64-bit one; a comparison compares at the wider of its operands' widths,
a w operand zero-extended, with the signedness its operator names (`<`
signed, `<ᵁ` unsigned). A condition that does not parse under that
grammar is reported as unparsed: a reader could not know what it means.
"""
import json
import os
import random
import re
import sys
from collections import Counter

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check  # noqa: E402
import z3  # noqa: E402

CONDITIONS = ["eq", "ne", "cs", "cc", "mi", "pl", "vs", "vc", "hi", "ls", "ge", "lt", "gt", "le"]


# ---------------------------------------------------------------------------
# Sequences. A test is described by a tuple the spec reads back:
# (kind, sf, rn, operand2) with operand2 ("imm", value) or ("reg", m, shift, amount).


def tests():
    out = []
    for sf in (0, 1):
        for imm12, sh in ((0, 0), (1, 0), (7, 0), (0xFFF, 0), (1, 1)):
            for op, kind in ((1, "subs"), (0, "adds")):
                word = sf << 31 | op << 30 | 1 << 29 | 0b100010 << 23 | sh << 22 | imm12 << 10 | 8 << 5 | 31
                out.append((word, (kind, sf, 8, ("imm", imm12 << (12 * sh)))))
        for shift, amount in ((0, 0), (1, 1), (2, 2), (0, 3)):
            for op, kind in ((1, "subs"), (0, "adds")):
                word = sf << 31 | op << 30 | 1 << 29 | 0b01011 << 24 | shift << 22 | 3 << 16 | amount << 10 | 8 << 5 | 31
                out.append((word, (kind, sf, 8, ("reg", 3, shift, amount))))
        for n, immr, imms in ((0, 0, 7), (sf, 0, 0), (0, 1, 0x3C)):
            mask = check.decode_bit_masks(n, imms, immr, 64 if sf else 32)
            word = sf << 31 | 3 << 29 | 0b100100 << 23 | n << 22 | immr << 16 | imms << 10 | 8 << 5 | 31
            out.append((word, ("ands", sf, 8, ("imm", mask))))
        word = sf << 31 | 3 << 29 | 0b01010 << 24 | 3 << 16 | 8 << 5 | 31
        out.append((word, ("ands", sf, 8, ("reg", 3, 0, 0))))
        # subs x9, x8, #3 keeps the difference in x9.
        word = sf << 31 | 1 << 30 | 1 << 29 | 0b100010 << 23 | 3 << 10 | 8 << 5 | 9
        out.append((word, ("subs", sf, 8, ("imm", 3))))
    return out


def branches(sf):
    out = [(0x54000000 | 2 << 5 | c, ("b", c)) for c in range(14)]
    for op in (0, 1):
        out.append((sf << 31 | 0b011010 << 25 | op << 24 | 2 << 5 | 8, ("cb", op, sf)))
    for op in (0, 1):
        for bit in ((0, 3, 31, 63) if sf else (0, 7, 31)):
            out.append(((bit >> 5) << 31 | 0b011011 << 25 | op << 24 | (bit & 31) << 19 | 2 << 5 | 8, ("tb", op, bit)))
    return out


def retarget(word):
    return (word & ~0x1F) | 8


def generate():
    rng = random.Random(20261102)
    defs = [retarget(w) for _, w in check.generate()]
    rng.shuffle(defs)
    sequences = []
    # No definition: the test reads x8 as it arrived.
    for word, _ in tests():
        for c in range(14):
            sequences.append([word, 0x54000000 | 2 << 5 | c])
    for definition in defs[:4000]:
        sf = definition >> 31
        for word, _ in rng.sample(tests(), 2):
            sequences.append([definition, word, 0x54000000 | 2 << 5 | rng.randrange(14)])
        word, _ = rng.choice(branches(sf)[14:])
        sequences.append([definition, word])
    return sequences


# ---------------------------------------------------------------------------
# The branch's real condition.


def real_condition(words, x):
    """The branch's condition and the registers as the branch sees them."""
    regs = list(x)
    test = dict(tests())
    index = 0
    if len(words) == 3 or (len(words) == 2 and words[0] not in test and not is_branch(words[0])):
        value = check.spec(words[0], regs)
        if value is None:
            return None
        regs[8] = value
        index = 1
    flags = None
    if words[index] in test:
        kind, sf, rn, operand2 = test[words[index]]
        w = 64 if sf else 32
        a = z3.Extract(w - 1, 0, regs[rn])
        if operand2[0] == "imm":
            b = z3.BitVecVal(operand2[1] & ((1 << w) - 1), w)
        else:
            _, m, shift, amount = operand2
            b = z3.Extract(w - 1, 0, regs[m])
            b = [b << amount, z3.LShR(b, amount), b >> amount][shift]
        if kind == "subs":
            res = a - b
            c = z3.UGE(a, b)
            v = z3.And((a < 0) != (b < 0), (res < 0) != (a < 0))
        elif kind == "adds":
            res = a + b
            c = z3.ULT(res, a)
            v = z3.And((a < 0) == (b < 0), (res < 0) != (a < 0))
        else:
            res = a & b
            c, v = z3.BoolVal(False), z3.BoolVal(False)
        flags = (res < 0, res == 0, c, v)
        if (words[index] & 0x1F) != 31:
            regs[words[index] & 0x1F] = z3.ZeroExt(64 - w, res)
        index += 1
    branch = words[index]
    if branch >> 24 == 0x54:
        if flags is None:
            return None
        n, zf, c, v = flags
        return regs, [zf, z3.Not(zf), c, z3.Not(c), n, z3.Not(n), v, z3.Not(v),
                z3.And(c, z3.Not(zf)), z3.Not(z3.And(c, z3.Not(zf))), n == v, n != v,
                z3.And(z3.Not(zf), n == v), z3.Not(z3.And(z3.Not(zf), n == v))][branch & 0xF]
    rt = branch & 0x1F
    if (branch >> 25) & 0x3F == 0b011010:
        sf = branch >> 31
        value = z3.Extract((64 if sf else 32) - 1, 0, regs[rt])
        zero = value == 0
        return regs, z3.Not(zero) if (branch >> 24) & 1 else zero
    bit = (branch >> 31) << 5 | (branch >> 19) & 31
    clear = z3.Extract(bit, bit, regs[rt]) == 0
    return regs, z3.Not(clear) if (branch >> 24) & 1 else clear


def is_branch(word):
    return word >> 24 == 0x54 or (word >> 25) & 0x3F in (0b011010, 0b011011)


# ---------------------------------------------------------------------------
# The rendered condition.


class Unparsed(Exception):
    pass


TOKEN = re.compile(r"\s*(0x[0-9a-f]+|\d+|[xw]\d+|bit|of|clear|set|>>ᵁ|>>ˢ|<<|<=ᵁ|>=ᵁ|<ᵁ|>ᵁ|==|!=|<=|>=|[-+*&|^~!()<>])")
COMPARISONS = {"==", "!=", "<", "<=", ">", ">=", "<ᵁ", "<=ᵁ", ">ᵁ", ">=ᵁ"}
ARITHMETIC = {"+", "-", "*", "&", "|", "^", "<<", ">>ᵁ", ">>ˢ"}


def tokenize(text):
    tokens, position = [], 0
    while position < len(text):
        if text[position:].strip() == "":
            break
        match = TOKEN.match(text, position)
        if not match:
            raise Unparsed(f"token at {text[position:]!r}")
        tokens.append(match.group(1))
        position = match.end()
    return tokens


class Value:
    """A z3 term and its width; a literal has none until it meets a register."""

    def __init__(self, term=None, width=None, literal=None):
        self.term, self.width, self.literal = term, width, literal

    def at(self, width):
        if self.literal is not None:
            return z3.BitVecVal(self.literal & ((1 << width) - 1), width)
        return self.term if self.width == width else z3.ZeroExt(width - self.width, self.term)


def parse(text, regs):
    tokens = tokenize(text)
    position = 0

    def peek():
        return tokens[position] if position < len(tokens) else None

    def take(expected=None):
        nonlocal position
        token = peek()
        if token is None or (expected is not None and token != expected):
            raise Unparsed(f"expected {expected or 'a token'} at {tokens[position:]}")
        position += 1
        return token

    def atom():
        token = take()
        if token == "(":
            value = inner()
            take(")")
            return value
        if token in ("-", "~", "!"):
            operand = atom()
            if token == "!":
                width = operand.width or 64
                return truth(operand.at(width) == 0)
            if operand.literal is not None:
                return Value(literal=(-operand.literal if token == "-" else ~operand.literal) & check.MASK64)
            return Value(-operand.term if token == "-" else ~operand.term, operand.width)
        if re.fullmatch(r"0x[0-9a-f]+|\d+", token):
            return Value(literal=int(token, 0))
        if re.fullmatch(r"[xw]\d+", token):
            number = int(token[1:])
            if number > 30:
                raise Unparsed(token)
            width = 64 if token[0] == "x" else 32
            return Value(z3.Extract(width - 1, 0, regs[number]), width)
        raise Unparsed(f"unexpected {token}")

    def binary(op, a, b):
        # Two literals (a folded constant) compare as 64-bit numbers.
        width = max([v.width for v in (a, b) if v.width] or [64])
        l, r = a.at(width), b.at(width)
        if op in COMPARISONS:
            return truth({"==": l == r, "!=": l != r, "<": l < r, "<=": l <= r, ">": l > r, ">=": l >= r,
                          "<ᵁ": z3.ULT(l, r), "<=ᵁ": z3.ULE(l, r), ">ᵁ": z3.UGT(l, r),
                          ">=ᵁ": z3.UGE(l, r)}[op])
        if op in ("<<", ">>ᵁ", ">>ˢ") and b.literal is not None and b.literal >= width:
            raise Unparsed(f"shift by {b.literal} at {width} bits")
        return Value({"+": l + r, "-": l - r, "*": l * r, "&": l & r, "|": l | r, "^": l ^ r,
                      "<<": l << r, ">>ᵁ": z3.LShR(l, r), ">>ˢ": l >> r}[op], width)

    def inner():
        # One operator per parenthesised level: the renderer brackets every
        # binary term, so an unbracketed chain would leave precedence to the
        # reader.
        left = atom()
        if peek() in ARITHMETIC or peek() in COMPARISONS:
            op = take()
            left = binary(op, left, atom())
        return left

    def truth(condition):
        return Value(z3.If(condition, z3.BitVecVal(1, 1), z3.BitVecVal(0, 1)), 1)

    if tokens[:1] == ["bit"]:
        # bit N of X clear|set
        take("bit")
        bit = atom()
        take("of")
        value = inner()
        state = take()
        width = value.width or 64
        if bit.literal is None or bit.literal >= width or state not in ("clear", "set"):
            raise Unparsed(text)
        clear = z3.Extract(bit.literal, bit.literal, value.at(width)) == 0
        result = clear if state == "clear" else z3.Not(clear)
    else:
        value = inner()
        result = value.at(value.width or 64) != 0
    if position != len(tokens):
        raise Unparsed(f"trailing {tokens[position:]}")
    return result


def check_conditions(sequences_path, traced_path):
    x = [z3.BitVec(f"x{i}", 64) for i in range(31)]
    records = {}
    for line in open(traced_path):
        record = json.loads(line, strict=False)
        records[" ".join(record["words"])] = record
    counts, failures = Counter(), []
    for line in open(sequences_path):
        key = " ".join(f"{int(w, 16):x}" for w in line.split())
        words = [int(w, 16) for w in line.split()]
        record = records.get(key)
        if record is None:
            counts["missing"] += 1
            failures.append((key, None, "no exported record"))
            continue
        if record["texts"] is None:
            counts["unallocated"] += 1
            continue
        real = real_condition(words, x)
        if real is None:
            counts["unallocated"] += 1
            continue
        regs, expected = real
        text = record["condition"]
        if text == "?" or text.startswith("cond ") or "overflow" in text or text.startswith(("b.", "cb", "tb")):
            counts["declined"] += 1
            continue
        try:
            actual = parse(text, regs)
        except (Unparsed, ValueError) as error:
            counts["unparsed"] += 1
            failures.append((key, record, f"unparsed: {error}"))
            continue
        solver = z3.Solver()
        solver.set("timeout", 20000)
        solver.add(actual != expected)
        outcome = solver.check()
        if outcome == z3.unsat:
            counts["verified"] += 1
        elif outcome == z3.sat:
            counts["refuted"] += 1
            model = solver.model()
            named = sorted({str(d) for d in model.decls()}, key=lambda n: int(n[1:]))
            values = ", ".join(f"{n}=0x{model.eval(z3.BitVec(n, 64), model_completion=True).as_long():x}" for n in named)
            failures.append((key, record, f"{values}: renders {z3.is_true(model.eval(actual, model_completion=True))}"
                                          f", branch {z3.is_true(model.eval(expected, model_completion=True))}"))
        else:
            counts["unknown"] += 1
            failures.append((key, record, "z3 could not settle it"))
    order = ("verified", "declined", "refuted", "unparsed", "unknown", "unallocated", "missing")
    print("  ".join(f"{k} {counts[k]}" for k in order if counts[k]))
    for key, record, detail in failures:
        texts = " ; ".join(t.replace("\t", " ") for t in (record or {}).get("texts") or [])
        condition = (record or {}).get("condition")
        print(f"{texts:60}  {condition!s:40}  {detail}")
    return 1 if counts["refuted"] or counts["missing"] else 0


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "generate":
        with open(sys.argv[2], "w") as out:
            for sequence in generate():
                out.write(" ".join(f"{w:08x}" for w in sequence) + "\n")
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "check":
        return check_conditions(sys.argv[2], sys.argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
