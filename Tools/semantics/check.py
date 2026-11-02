#!/usr/bin/env python3
"""Prove the value tracer's integer semantics against the Arm ARM with z3.

The generator below enumerates encodings of the integer data-processing
instructions, with every shift, extend, lsb and width the encoding allows
(logical immediates sampled). Each word's meaning is written here from the
Arm ARM pseudocode, working from the encoding's bit fields: it shares no
code, decoder or table with swiftdc. The Swift test
`exportTracerSemanticsIfRequested` traces each word alone and exports what
the tracer holds in x0 afterwards; this script asks z3 whether that value
equals the specification for every value of x0-x3.

    check.py generate words.txt
    SWIFTDC_SEMANTICS_WORDS=words.txt SWIFTDC_SEMANTICS_OUT=traced.jsonl \\
        swift test --skip-build --filter exportTracerSemanticsIfRequested
    check.py check words.txt traced.jsonl

`check` prints counts per instruction class and every refutation with a
counterexample, and exits 1 on any refutation. verified is proven for all
inputs. sampled is a case the solver could not settle in 20 s (a 32-bit
sdiv lowered to 64-bit division) that matched on edge and random inputs:
tested, not proven. declined is the tracer claiming nothing, which is
sound and only counted.
"""
import json
import random
import sys
from collections import Counter, defaultdict

try:
    import z3
except ImportError:
    sys.exit("check.py needs z3: pip install z3-solver (a venv is enough)")

MASK64 = (1 << 64) - 1

# ---------------------------------------------------------------------------
# Encodings. Rd = x0, Rn = x1, Rm = x2, Ra = x3 unless a case needs the zero
# register. Each generator yields (class, word).


def bits(value, hi, lo):
    return (value >> lo) & ((1 << (hi - lo + 1)) - 1)


def decode_bit_masks(n, imms, immr, datasize):
    """DecodeBitMasks for a logical immediate: (wmask) or None if reserved."""
    combined = (n << 6) | (~imms & 0x3F)
    if combined == 0:
        return None
    length = combined.bit_length() - 1
    if length < 1:
        return None
    esize = 1 << length
    if esize > datasize:
        return None
    levels = esize - 1
    s = imms & levels
    r = immr & levels
    if s == levels:
        return None
    welem = (1 << (s + 1)) - 1
    elem = ((welem >> r) | (welem << (esize - r))) & ((1 << esize) - 1) if r else welem
    mask = 0
    for i in range(datasize // esize):
        mask |= elem << (i * esize)
    return mask


def generate():
    rng = random.Random(20261102)
    out = []
    for sf in (0, 1):
        width = 64 if sf else 32
        # Logical (shifted register): AND ORR EOR ANDS, N inverts (BIC ORN EON BICS).
        for opc in range(4):
            for shift in range(4):
                for n in (0, 1):
                    for imm6 in range(width):
                        for rn in (1, 31):
                            out.append(("logical-reg", sf << 31 | opc << 29 | 0b01010 << 24 | shift << 22
                                        | n << 21 | 2 << 16 | imm6 << 10 | rn << 5))
        # Logical (immediate), every valid mask for 32 bits, a sample for 64.
        for opc in range(4):
            valid = []
            for n in ((0, 1) if sf else (0,)):
                for immr in range(64):
                    for imms in range(64):
                        if decode_bit_masks(n, imms, immr, width) is not None:
                            valid.append((n, immr, imms))
            if sf:
                valid = rng.sample(valid, 600)
            for n, immr, imms in valid:
                for rn in (1, 31):
                    out.append(("logical-imm", sf << 31 | opc << 29 | 0b100100 << 23 | n << 22
                                | immr << 16 | imms << 10 | rn << 5))
        # Add/subtract (immediate).
        for op in (0, 1):
            for s in (0, 1):
                for sh in (0, 1):
                    for imm12 in (0, 1, 7, 0x123, 0xFFF):
                        out.append(("addsub-imm", sf << 31 | op << 30 | s << 29 | 0b100010 << 23
                                    | sh << 22 | imm12 << 10 | 1 << 5))
        # Add/subtract (shifted register); Rn = 31 is the zero register (neg).
        for op in (0, 1):
            for s in (0, 1):
                for shift in range(3):
                    for imm6 in range(width):
                        for rn in (1, 31):
                            out.append(("addsub-reg", sf << 31 | op << 30 | s << 29 | 0b01011 << 24
                                        | shift << 22 | 2 << 16 | imm6 << 10 | rn << 5))
        # Add/subtract (extended register).
        for op in (0, 1):
            for s in (0, 1):
                for option in range(8):
                    for imm3 in range(5):
                        out.append(("addsub-ext", sf << 31 | op << 30 | s << 29 | 0b01011 << 24
                                    | 1 << 21 | 2 << 16 | option << 13 | imm3 << 10 | 1 << 5))
        # Bitfield: SBFM BFM UBFM, every immr and imms.
        for opc in range(3):
            for immr in range(width):
                for imms in range(width):
                    out.append(("bitfield", sf << 31 | opc << 29 | 0b100110 << 23 | sf << 22
                                | immr << 16 | imms << 10 | 1 << 5))
        # Extract (EXTR, and ROR immediate when Rn = Rm).
        for imms in range(width):
            for rm in (1, 2):
                out.append(("extract", sf << 31 | 0b100111 << 23 | sf << 22 | rm << 16 | imms << 10 | 1 << 5))
        # Data-processing (2 source).
        for opcode in (0b000010, 0b000011, 0b001000, 0b001001, 0b001010, 0b001011):
            out.append(("dp2", sf << 31 | 0b11010110 << 21 | 2 << 16 | opcode << 10 | 1 << 5))
        # Data-processing (3 source).
        for op31, o0 in ((0, 0), (0, 1)) + (((1, 0), (1, 1), (2, 0), (5, 0), (5, 1), (6, 0)) if sf else ()):
            for ra in (3, 31):
                if op31 in (2, 6) and ra != 31:
                    continue
                out.append(("dp3", sf << 31 | 0b11011 << 24 | op31 << 21 | 2 << 16 | o0 << 15
                            | ra << 10 | 1 << 5))
        # Data-processing (1 source).
        for opcode in (0, 1, 2, 4, 5) + ((3,) if sf else ()):
            out.append(("dp1", sf << 31 | 1 << 30 | 0b11010110 << 21 | opcode << 10 | 1 << 5))
        # Move wide: MOVN MOVZ MOVK.
        for opc in (0, 2, 3):
            for hw in range(4 if sf else 2):
                for imm16 in (0, 1, 0x8000, 0xFFFF, 0x1234):
                    out.append(("movewide", sf << 31 | opc << 29 | 0b100101 << 23 | hw << 21 | imm16 << 5))
    return out


# ---------------------------------------------------------------------------
# Specification, from the Arm ARM pseudocode over the encoding fields.


def spec(word, x):
    """Rd after the instruction, as a 64-bit z3 term over the registers x
    (x[n] is xn at entry), or None for an encoding this spec does not
    cover (unallocated, or a destination of sp or the zero register)."""
    sf = bits(word, 31, 31)
    w = 64 if sf else 32
    rd, rn, rm = bits(word, 4, 0), bits(word, 9, 5), bits(word, 20, 16)

    def reg(index, size=w):
        value = z3.BitVecVal(0, 64) if index == 31 else x[index]
        return z3.Extract(size - 1, 0, value)

    def shift_reg(value, kind, amount):
        if kind == 0:
            return value << amount
        if kind == 1:
            return z3.LShR(value, amount)
        if kind == 2:
            return value >> amount
        return z3.RotateRight(value, amount)

    def result(value):
        assert value.size() == w
        return z3.ZeroExt(64 - w, value)

    if rd == 31:
        return None
    top = bits(word, 28, 24)
    if top == 0b01010:   # logical (shifted register)
        opc, kind, n, imm6 = bits(word, 30, 29), bits(word, 23, 22), bits(word, 21, 21), bits(word, 15, 10)
        if not sf and imm6 >= 32:
            return None
        op2 = shift_reg(reg(rm), kind, imm6)
        if n:
            op2 = ~op2
        op1 = reg(rn)
        return result([op1 & op2, op1 | op2, op1 ^ op2, op1 & op2][opc])
    if bits(word, 28, 23) == 0b100100:   # logical (immediate)
        opc, n, immr, imms = bits(word, 30, 29), bits(word, 22, 22), bits(word, 21, 16), bits(word, 15, 10)
        if not sf and n:
            return None
        mask = decode_bit_masks(n, imms, immr, w)
        if mask is None:
            return None
        imm = z3.BitVecVal(mask, w)
        op1 = reg(rn)
        return result([op1 & imm, op1 | imm, op1 ^ imm, op1 & imm][opc])
    if bits(word, 28, 23) == 0b100010:   # add/subtract (immediate)
        op, sh, imm12 = bits(word, 30, 30), bits(word, 22, 22), bits(word, 21, 10)
        imm = z3.BitVecVal(imm12 << (12 if sh else 0), w)
        if rn == 31:
            return None   # sp
        return result(reg(rn) - imm if op else reg(rn) + imm)
    if top == 0b01011 and bits(word, 21, 21) == 0:   # add/subtract (shifted register)
        op, kind, imm6 = bits(word, 30, 30), bits(word, 23, 22), bits(word, 15, 10)
        if kind == 3 or (not sf and imm6 >= 32):
            return None
        op2 = shift_reg(reg(rm), kind, imm6)
        return result(reg(rn) - op2 if op else reg(rn) + op2)
    if top == 0b01011 and bits(word, 23, 21) == 0b001:   # add/subtract (extended register)
        op, option, imm3 = bits(word, 30, 30), bits(word, 15, 13), bits(word, 12, 10)
        if imm3 > 4 or rn == 31:
            return None
        size = 8 << (option & 3)
        part = z3.Extract(min(size, 64) - 1, 0, x[rm] if rm != 31 else z3.BitVecVal(0, 64))
        extended = (z3.SignExt if option & 4 else z3.ZeroExt)(64 - part.size(), part) if part.size() < 64 else part
        op2 = z3.Extract(w - 1, 0, extended << imm3)
        return result(reg(rn) - op2 if op else reg(rn) + op2)
    if bits(word, 28, 23) == 0b100110:   # bitfield
        opc, n, immr, imms = bits(word, 30, 29), bits(word, 22, 22), bits(word, 21, 16), bits(word, 15, 10)
        if opc == 3 or n != sf or (not sf and (immr >= 32 or imms >= 32)):
            return None
        # DecodeBitMasks(N, imms, immr, FALSE): wmask, tmask.
        levels = w - 1
        s, r = imms & levels, immr & levels
        diff = (s - r) & levels
        welem = (1 << (s + 1)) - 1
        wmask = (((welem >> r) | (welem << (w - r))) & ((1 << w) - 1)) if r else welem
        tmask = (1 << (diff + 1)) - 1
        src = reg(rn)
        dst = reg(rd) if opc == 1 else z3.BitVecVal(0, w)
        bot = (dst & z3.BitVecVal(~wmask & ((1 << w) - 1), w)) | (z3.RotateRight(src, r) & z3.BitVecVal(wmask, w))
        if opc == 0:
            sign = z3.Extract(s, s, src)
            top_bits = z3.If(sign == 1, z3.BitVecVal((1 << w) - 1, w), z3.BitVecVal(0, w))
        else:
            top_bits = dst
        tm = z3.BitVecVal(tmask, w)
        return result((top_bits & ~tm) | (bot & tm))
    if bits(word, 28, 23) == 0b100111:   # extract
        imms = bits(word, 15, 10)
        if bits(word, 22, 22) != sf or (not sf and imms >= 32):
            return None
        concat = z3.Concat(reg(rn), reg(rm))
        return result(z3.Extract(imms + w - 1, imms, concat))
    if bits(word, 30, 21) == 0b0011010110:   # data-processing (2 source)
        opcode = bits(word, 15, 10)
        a, b = reg(rn), reg(rm)
        amount = z3.URem(b, z3.BitVecVal(w, w))
        if opcode == 0b000010:
            return result(z3.If(b == 0, z3.BitVecVal(0, w), z3.UDiv(a, b)))
        if opcode == 0b000011:
            # RoundTowardsZero(Int(a) / Int(b)), the overflow case wrapping.
            return result(z3.If(b == 0, z3.BitVecVal(0, w), a / b))
        if opcode == 0b001000:
            return result(a << amount)
        if opcode == 0b001001:
            return result(z3.LShR(a, amount))
        if opcode == 0b001010:
            return result(a >> amount)
        if opcode == 0b001011:
            return result(z3.RotateRight(a, amount))
        return None
    if top == 0b11011:   # data-processing (3 source)
        op31, o0, ra = bits(word, 23, 21), bits(word, 15, 15), bits(word, 14, 10)
        if op31 == 0:
            product = reg(rn) * reg(rm)
            acc = reg(ra)
            return result(acc - product if o0 else acc + product)
        if op31 in (1, 5):
            ext = z3.SignExt if op31 == 1 else z3.ZeroExt
            product = ext(32, reg(rn, 32)) * ext(32, reg(rm, 32))
            return acc_result(reg(ra), product, o0)
        if op31 in (2, 6):
            ext = z3.SignExt if op31 == 2 else z3.ZeroExt
            full = ext(64, reg(rn)) * ext(64, reg(rm))
            return z3.Extract(127, 64, full)
        return None
    if bits(word, 30, 21) == 0b1011010110 and bits(word, 20, 16) == 0:   # data-processing (1 source)
        opcode = bits(word, 15, 10)
        a = reg(rn)
        if opcode == 0:
            return result(z3.Concat(*[z3.Extract(i, i, a) for i in range(w)]))
        if opcode in (1, 2, 3):
            container = {1: 16, 2: 32 if sf else w, 3: 64}[opcode]
            if container > w or (opcode == 3 and not sf):
                return None
            chunks = []
            for c in range(w // container):
                lo = c * container
                piece = [z3.Extract(lo + 8 * b + 7, lo + 8 * b, a) for b in range(container // 8)]
                chunks.append(z3.Concat(*piece) if len(piece) > 1 else piece[0])
            return result(z3.Concat(*reversed(chunks)) if len(chunks) > 1 else chunks[0])
        if opcode == 4:
            return result(count_leading(a, w))
        if opcode == 5:
            sign = z3.Extract(w - 1, w - 1, a)
            flipped = a ^ z3.If(sign == 1, z3.BitVecVal((1 << w) - 1, w), z3.BitVecVal(0, w))
            return result(count_leading(z3.Concat(z3.Extract(w - 2, 0, flipped), z3.BitVecVal(1, 1)), w))
        return None
    if bits(word, 28, 23) == 0b100101:   # move wide
        opc, hw, imm16 = bits(word, 30, 29), bits(word, 22, 21), bits(word, 20, 5)
        if opc == 1 or (not sf and hw > 1):
            return None
        pos = hw * 16
        if opc == 3:
            keep = ((1 << w) - 1) & ~(0xFFFF << pos)
            return result((reg(rd) & z3.BitVecVal(keep, w)) | z3.BitVecVal(imm16 << pos, w))
        value = (imm16 << pos) & ((1 << w) - 1)
        return result(z3.BitVecVal(value if opc == 2 else ~value & ((1 << w) - 1), w))
    return None


def acc_result(acc, product, subtract):
    return acc - product if subtract else acc + product


def count_leading(value, width):
    count = z3.BitVecVal(width, width)
    for i in range(width):
        count = z3.If(z3.Extract(i, i, value) == 1, z3.BitVecVal(width - 1 - i, width), count)
    return count


# ---------------------------------------------------------------------------
# The tracer's exported value (swiftdc-value/1) as a z3 term. Shifts by 64 or
# more are outside the tracer's domain (evaluateInteger throws), so each
# shift adds an obligation that its amount is below 64.


class Unsupported(Exception):
    pass


def traced_term(node, x, obligations):
    kind = node["kind"]
    if kind == "immediate":
        text = node["bits"]
        return z3.BitVecVal(int(text, 16) if text.startswith("0x") else int(text), 64)
    if kind == "argument":
        index = node["index"]
        if not 0 <= index < len(x):
            raise Unsupported(f"argument {index}")
        return x[index]
    if kind == "select":
        condition = traced_term(node["condition"], x, obligations)
        return z3.If(condition != 0, traced_term(node["whenTrue"], x, obligations),
                     traced_term(node["whenFalse"], x, obligations))
    if kind == "unary":
        operand = traced_term(node["operand"], x, obligations)
        op = node["operator"]
        if op == "negate":
            return -operand
        if op == "bitwise-not":
            return ~operand
        if op == "byte-swap":
            size = node["bits"]
            chunks = []
            for c in range(64 // size):
                lo = c * size
                piece = [z3.Extract(lo + 8 * b + 7, lo + 8 * b, operand) for b in range(size // 8)]
                chunks.append(z3.Concat(*piece))
            return z3.Concat(*reversed(chunks)) if len(chunks) > 1 else chunks[0]
        if op in ("leading-zeros", "leading-sign-bits", "bit-reverse"):
            size = node["bits"]
            low = z3.Extract(size - 1, 0, operand)
            if op == "bit-reverse":
                return z3.ZeroExt(64 - size, z3.Concat(*[z3.Extract(i, i, low) for i in range(size)]))
            if op == "leading-sign-bits":
                sign = z3.Extract(size - 1, size - 1, low)
                flipped = low ^ z3.If(sign == 1, z3.BitVecVal((1 << size) - 1, size), z3.BitVecVal(0, size))
                low = z3.Concat(z3.Extract(size - 2, 0, flipped), z3.BitVecVal(1, 1))
            return z3.ZeroExt(64 - size, count_leading(low, size))
        raise Unsupported(f"unary {op}")
    if kind != "binary":
        raise Unsupported(kind)
    a = traced_term(node["lhs"], x, obligations)
    b = traced_term(node["rhs"], x, obligations)
    op = node["operator"]
    one, zero = z3.BitVecVal(1, 64), z3.BitVecVal(0, 64)
    min64 = z3.BitVecVal(1 << 63, 64)
    simple = {
        "add": lambda: a + b, "subtract": lambda: a - b, "multiply": lambda: a * b,
        "bit-and": lambda: a & b, "bit-or": lambda: a | b, "bit-xor": lambda: a ^ b,
        "unsigned-divide": lambda: z3.If(b == 0, zero, z3.UDiv(a, b)),
        "unsigned-remainder": lambda: z3.If(b == 0, a, z3.URem(a, b)),
        "divide": lambda: z3.If(b == 0, zero, z3.If(z3.And(a == min64, b == -1), a, a / b)),
        "remainder": lambda: z3.If(b == 0, a, z3.If(z3.And(a == min64, b == -1), zero, z3.SRem(a, b))),
        "unsigned-multiply-high": lambda: z3.Extract(127, 64, z3.ZeroExt(64, a) * z3.ZeroExt(64, b)),
        "multiply-high": lambda: z3.Extract(127, 64, z3.SignExt(64, a) * z3.SignExt(64, b)),
        "equal": lambda: z3.If(a == b, one, zero), "not-equal": lambda: z3.If(a != b, one, zero),
        "less": lambda: z3.If(a < b, one, zero), "less-equal": lambda: z3.If(a <= b, one, zero),
        "greater": lambda: z3.If(a > b, one, zero), "greater-equal": lambda: z3.If(a >= b, one, zero),
        "unsigned-less": lambda: z3.If(z3.ULT(a, b), one, zero),
        "unsigned-less-equal": lambda: z3.If(z3.ULE(a, b), one, zero),
        "unsigned-greater": lambda: z3.If(z3.UGT(a, b), one, zero),
        "unsigned-greater-equal": lambda: z3.If(z3.UGE(a, b), one, zero),
    }
    if op in simple:
        return simple[op]()
    if op in ("shift-left", "shift-right", "arithmetic-shift-right"):
        obligations.append(z3.ULT(b, 64))
        return {"shift-left": a << b, "shift-right": z3.LShR(a, b), "arithmetic-shift-right": a >> b}[op]
    raise Unsupported(f"binary {op}")


EDGES = [0, 1, 2, 7, 0x7F, 0x80, 0xFF, 0x7FFF, 0x8000, 0xFFFF, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
         0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, MASK64, MASK64 - 1, 0xFFFFFFFF80000000]


def sample(actual, expected, obligations, x, count=4000):
    """The first input on which the two terms differ, or None."""
    rng = random.Random(7)
    edge_tuples = [(a, b, c, d) for a in (0, MASK64) for b in EDGES for c in EDGES for d in (0, 3)]
    randoms = [tuple(rng.getrandbits(64) for _ in x) for _ in range(count)]
    for values in edge_tuples + randoms:
        bound = [(v, z3.BitVecVal(n, 64)) for v, n in zip(x, values)]
        got = z3.simplify(z3.substitute(actual, *bound)).as_long()
        want = z3.simplify(z3.substitute(expected, *bound)).as_long()
        held = all(z3.is_true(z3.simplify(z3.substitute(o, *bound))) for o in obligations)
        if got != want or not held:
            return ", ".join(f"x{i}=0x{n:x}" for i, n in enumerate(values)) + f": traced 0x{got:x}, Arm 0x{want:x}"
    return None


def check(words_path, traced_path):
    classes = {}
    for cls, word in generate():
        classes[word] = cls
    words = [int(line, 16) for line in open(words_path) if line.strip()]
    traced = {}
    for line in open(traced_path):
        record = json.loads(line, strict=False)
        traced[int(record["word"], 16)] = record
    x = [z3.BitVec(f"x{i}", 64) for i in range(4)]
    counts = defaultdict(Counter)
    failures = []
    for word in words:
        cls = classes.get(word, "?")
        record = traced.get(word)
        if record is None:
            counts[cls]["missing"] += 1
            failures.append((word, None, "no traced record"))
            continue
        expected = spec(word, x)
        if expected is None or record["text"] is None:
            counts[cls]["unallocated"] += 1
            continue
        if record["value"] is None:
            counts[cls]["declined"] += 1
            continue
        obligations = []
        try:
            actual = traced_term(record["value"]["expression"], x, obligations)
        except Unsupported as error:
            counts[cls]["unsupported"] += 1
            failures.append((word, record["text"], f"unsupported: {error}"))
            continue
        solver = z3.Solver()
        solver.set("timeout", 20000)
        solver.add(z3.Or(actual != expected, *[z3.Not(o) for o in obligations]))
        outcome = solver.check()
        if outcome == z3.unsat:
            counts[cls]["verified"] += 1
            continue
        if outcome == z3.unknown:
            # Wide division defeats the solver. Test edge and random inputs
            # instead, and count the case apart: sampled is not proven.
            mismatch = sample(actual, expected, obligations, x)
            if mismatch is None:
                counts[cls]["sampled"] += 1
                continue
            counts[cls]["refuted"] += 1
            failures.append((word, record["text"], mismatch))
            continue
        counts[cls]["refuted"] += 1
        model = solver.model()
        values = {str(v): model.eval(v, model_completion=True).as_long() for v in x}
        got = model.eval(actual, model_completion=True).as_long()
        want = model.eval(expected, model_completion=True).as_long()
        failures.append((word, record["text"], ", ".join(f"{k}=0x{v:x}" for k, v in values.items())
                         + f": traced 0x{got:x}, Arm 0x{want:x}"))
    order = ("verified", "sampled", "declined", "refuted", "unsupported", "unallocated", "missing")
    for cls in sorted(counts):
        print(f"{cls:12} " + "  ".join(f"{k} {counts[cls][k]}" for k in order if counts[cls][k]))
    total = Counter()
    for c in counts.values():
        total.update(c)
    print(f"{'total':12} " + "  ".join(f"{k} {total[k]}" for k in order if total[k]))
    for word, text, detail in failures:
        print(f"0x{word:08x}  {(text or '?').replace(chr(9), ' '):40}  {detail}")
    return 1 if total["refuted"] or total["missing"] else 0


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "generate":
        with open(sys.argv[2], "w") as out:
            for _, word in generate():
                out.write(f"{word:08x}\n")
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "check":
        return check(sys.argv[2], sys.argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
