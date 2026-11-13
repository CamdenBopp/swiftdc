#!/usr/bin/env python3 -I
"""Targeted malformed-input mutants of the synthetic corpus, run through every entry point.

    Tools/synthcorpus/mutate.py --swiftdc BIN [--out DIR] [--input DYLIB ...]
        [--kind SUBSTRING ...] [--seeds N] [--per-kind K] [--jobs N] [--list] [--no-run]

Tools/fuzz.swift flips random bytes in the load commands or in the metadata
sections. Random bytes almost never form a well-shaped hostile structure:
a ULEB of 2^62, an export trie whose child points back at its parent, a
chained-fixup page start one pointer short of the page end. This harness
writes those shapes on purpose, one mutation per mutant, into the linkedit
streams and tables fuzz.swift does not reach:

  dyld-info   LC_DYLD_INFO rebase, bind, weak and lazy opcode streams
  trie        the export trie (LC_DYLD_INFO export or LC_DYLD_EXPORTS_TRIE)
  fstarts     LC_FUNCTION_STARTS
  chained     LC_DYLD_CHAINED_FIXUPS headers, starts, chains and imports
  symtab      LC_SYMTAB / LC_DYSYMTAB offsets, counts and entries
  objc        class list, class, class_ro and method/ivar/property lists

Inputs: every *.dylib under DIR (default Tools/synthcorpus/out, the
malformed/ folder excluded) plus Fixtures/Sample/libOpcodeFixups.dylib
(opcode fixups, LC_DYLD_INFO) and libOpcodeFixups.chained.dylib, and any
--input. A kind runs on at most --per-kind inputs that have its structure
(0 means all), picked by the seed. A new stream or table is appended to
__LINKEDIT, which grows to cover it, so the mutant stays well formed
everywhere else. Mutants go to DIR/malformed/<input>__<kind>__s<seed>.dylib;
the same arguments always write the same bytes.

Each mutant goes through disasm (listing, --structured, --pseudo, --json),
dump, objc --methods, xrefs --unreferenced, analyze, interface and layout
under Tools/audit/guard.sh (footprint kill at --memory MB) with a
--timeout. Malformed input must end in an error or an output, so a signal,
a timeout, a memory kill or an exit status other than 0 or 1 is a failure.
Per-run stderr and mem.log stay in DIR/malformed/runs/; stdout is kept only
for failures. At most two swiftdc processes run at once (the host has
16 GB). Exit status 1 when anything failed.
"""
import argparse, concurrent.futures, os, random, signal, struct, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
GUARD = REPO / "Tools/audit/guard.sh"
FIXTURES = [REPO / "Fixtures/Sample/libOpcodeFixups.dylib", REPO / "Fixtures/Sample/libOpcodeFixups.chained.dylib"]
ENTRY_POINTS = {
    "listing": ["disasm", "{f}"],
    "structured": ["disasm", "{f}", "--structured"],
    "pseudo": ["disasm", "{f}", "--pseudo"],
    "json": ["disasm", "{f}", "--json"],
    "dump": ["dump", "{f}"],
    "objc": ["objc", "{f}", "--methods"],
    "xrefs": ["xrefs", "{f}", "--unreferenced"],
    "analyze": ["analyze", "{f}"],
    "interface": ["interface", "{f}"],
    "layout": ["layout", "{f}"],
}

LC_SEGMENT_64, LC_SYMTAB, LC_DYSYMTAB = 0x19, 0x2, 0xB
LC_DYLD_INFO, LC_DYLD_INFO_ONLY = 0x22, 0x80000022
LC_FUNCTION_STARTS, LC_EXPORTS_TRIE, LC_CHAINED_FIXUPS = 0x26, 0x80000033, 0x80000034
MASK36 = (1 << 36) - 1
FAR = 0x7FFF_FFF0_0000  # an address no image here maps


def uleb(value):
    out = bytearray()
    while True:
        byte, value = value & 0x7F, value >> 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def overlong(value, length):
    """`value` as a ULEB padded with continuation bytes to `length` bytes."""
    return bytes(((value >> (7 * i)) & 0x7F) | (0x80 if i < length - 1 else 0) for i in range(length))


class Image:
    """The parts of a 64-bit little-endian Mach-O the mutations touch."""

    def __init__(self, path):
        self.path = Path(path)
        d = self.data = self.path.read_bytes()
        magic, _, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", d, 0)
        if magic != 0xFEEDFACF:
            raise ValueError("not a 64-bit little-endian Mach-O")
        self.cmds, self.segments, off = [], [], 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", d, off)
            self.cmds.append((cmd, off))
            if cmd == LC_SEGMENT_64:
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", d, off + 24)
                nsects = struct.unpack_from("<I", d, off + 64)[0]
                sections = []
                for s in range(nsects):
                    so = off + 72 + 80 * s
                    addr, ssize = struct.unpack_from("<QQ", d, so + 32)
                    sections.append(dict(name=d[so:so + 16].rstrip(b"\0").decode(errors="replace"),
                                         addr=addr, size=ssize, offset=struct.unpack_from("<I", d, so + 48)[0], hdr=so))
                self.segments.append(dict(name=d[off + 8:off + 24].rstrip(b"\0").decode(errors="replace"), cmd=off,
                                          vmaddr=vmaddr, vmsize=vmsize, fileoff=fileoff, filesize=filesize,
                                          sections=sections))
            off += size
        text = [s for s in self.segments if s["name"] == "__TEXT"]
        self.base = text[0]["vmaddr"] if text else 0
        self.formats = self._chained_formats()

    def cmd(self, *kinds):
        return next((off for cmd, off in self.cmds if cmd in kinds), None)

    def sections(self, name):
        return [s for seg in self.segments for s in seg["sections"] if s["name"] == name and s["size"]]

    def u32(self, off):
        return struct.unpack_from("<I", self.data, off)[0]

    def u64(self, off):
        return struct.unpack_from("<Q", self.data, off)[0]

    def file_of(self, addr):
        for seg in self.segments:
            if seg["filesize"] and seg["vmaddr"] <= addr and addr + 8 <= seg["vmaddr"] + seg["filesize"]:
                return seg["fileoff"] + addr - seg["vmaddr"]
        return None

    def chained(self):
        """(header offset, size) of LC_DYLD_CHAINED_FIXUPS, or None."""
        c = self.cmd(LC_CHAINED_FIXUPS)
        return (self.u32(c + 8), self.u32(c + 12)) if c is not None else None

    def chained_segments(self):
        """[(segment index, absolute offset of dyld_chained_starts_in_segment)]."""
        ch = self.chained()
        if not ch:
            return []
        header, _ = ch
        starts = header + self.u32(header + 4)
        out = []
        for i in range(self.u32(starts)):
            rel = self.u32(starts + 4 + 4 * i)
            if rel:
                out.append((i, starts + rel))
        return out

    def _chained_formats(self):
        return {i: struct.unpack_from("<H", self.data, s + 6)[0] for i, s in self.chained_segments()}

    def format_at(self, fileoff):
        for i, seg in enumerate(self.segments):
            if seg["fileoff"] <= fileoff < seg["fileoff"] + seg["filesize"]:
                return self.formats.get(i)
        return None

    def read_ptr(self, fileoff):
        """('rebase', address) or ('bind', raw) or (None, raw) for the slot at fileoff."""
        v = self.u64(fileoff)
        fmt = self.format_at(fileoff) if self.formats else None
        if fmt is None:
            return ("rebase", v) if v else (None, v)
        if fmt in (2, 6):
            if v >> 63:
                return "bind", v
            target = v & MASK36
            return "rebase", (target if fmt == 2 else self.base + target) | (((v >> 36) & 0xFF) << 56)
        if fmt in (1, 9, 12):
            if (v >> 62) & 1:
                return "bind", v
            if v >> 63:
                return "rebase", self.base + (v & 0xFFFFFFFF)
            target = v & ((1 << 43) - 1)
            return "rebase", target if fmt == 1 else self.base + target
        return None, v

    def resolve(self, fileoff):
        """File offset of the local address the pointer at fileoff holds, or None."""
        kind, addr = self.read_ptr(fileoff)
        return self.file_of(addr & 0x00007FFFFFFFFFF8) if kind == "rebase" else None


class Mutant:
    def __init__(self, image):
        self.image, self.d = image, bytearray(image.data)

    def put32(self, off, v):
        struct.pack_into("<I", self.d, off, v & 0xFFFFFFFF)

    def put16(self, off, v):
        struct.pack_into("<H", self.d, off, v & 0xFFFF)

    def put64(self, off, v):
        struct.pack_into("<Q", self.d, off, v & 0xFFFFFFFFFFFFFFFF)

    def get32(self, off):
        return struct.unpack_from("<I", self.d, off)[0]

    def get64(self, off):
        return struct.unpack_from("<Q", self.d, off)[0]

    def append(self, blob):
        """Append blob inside a grown __LINKEDIT; returns its file offset."""
        seg = next(s for s in self.image.segments if s["name"] == "__LINKEDIT")
        while len(self.d) % 8:
            self.d.append(0)
        off = len(self.d)
        self.d += blob
        filesize = len(self.d) - seg["fileoff"]
        self.put64(seg["cmd"] + 48, filesize)
        self.put64(seg["cmd"] + 32, max(seg["vmsize"], (filesize + 0x3FFF) & ~0x3FFF))
        return off

    def set_stream(self, cmd_off, field, blob):
        """Point the (offset, size) pair at cmd_off+field to an appended blob."""
        self.put32(cmd_off + field, self.append(blob))
        self.put32(cmd_off + field + 4, len(blob))

    def write_ptr(self, fileoff, addr, far=False):
        """Store addr in a slot, keeping its fixup encoding (next bits)."""
        img, v = self.image, self.get64(fileoff)
        fmt = img.format_at(fileoff) if img.formats else None
        if fmt in (2, 6):
            target = MASK36 if far else (addr if fmt == 2 else addr - img.base) & MASK36
            self.put64(fileoff, (v & (0xFFF << 51)) | target)
        elif fmt in (1, 9, 12):
            target = (1 << 43) - 1 if far else (addr if fmt == 1 else addr - img.base) & ((1 << 43) - 1)
            self.put64(fileoff, (v & (0x7FF << 51)) | target)
        else:
            self.put64(fileoff, FAR if far else addr)


# --- LC_DYLD_INFO opcode streams -------------------------------------------

STREAM_FIELD = {"rebase": 8, "bind": 16, "weak": 24, "lazy": 32, "export": 40}


def data_segment(img):
    """Index of the first writable segment with file bytes (where rebases land)."""
    for i, seg in enumerate(img.segments):
        if seg["name"].startswith("__DATA") and seg["filesize"]:
            return i
    return None


def opcode_stream(build):
    """A dyld-info mutation that replaces one stream with build(img, seg)."""
    def apply(img, rng, stream):
        info, seg = img.cmd(LC_DYLD_INFO, LC_DYLD_INFO_ONLY), data_segment(img)
        if info is None or seg is None or seg > 15:
            return None
        m = Mutant(img)
        blob = build(img, seg, rng, m)
        if blob is None:
            return None
        m.set_stream(info, STREAM_FIELD[stream], blob)
        return m
    return apply


def original(img, stream):
    info = img.cmd(LC_DYLD_INFO, LC_DYLD_INFO_ONLY)
    off, size = img.u32(info + STREAM_FIELD[stream]), img.u32(info + STREAM_FIELD[stream] + 4)
    return img.data[off:off + size]


SYM = b"_objc_msgSend\0"


def bind_prefix(seg, offset=0):
    """Ordinal 1, a symbol, pointer type, and a cursor at seg+offset."""
    return bytes([0x11, 0x40]) + SYM + bytes([0x51, 0x70 | seg]) + uleb(offset)


REBASE_STREAMS = {
    # 9bfb66a bounded these two; they guard that the bound holds.
    "uleb-times-2^62": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg, 0, 0x60]) + uleb(1 << 62) + b"\0",
    "skipping-stays-put": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg, 0, 0x80]) + uleb(1 << 40) + uleb((1 << 64) - 8) + b"\0",
    "offset-65-bit": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg]) + uleb((1 << 64) + 8) + bytes([0x51, 0]),
    "overlong-uleb": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg]) + overlong(8, 40) + bytes([0x51, 0]),
    "add-addr-wraps": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg]) + uleb(8) + b"\x30" + uleb((1 << 64) - 16) + bytes([0x51, 0]),
    "imm-scaled-past-segment": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg, 0]) + b"\x4f" * 4096 + bytes([0x5f, 0]),
    "add-addr-uleb-runs-off": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg, 0]) + (b"\x70" + uleb(1 << 33)) * 512 + b"\0",
    "segment-15": lambda img, seg, rng, m: bytes([0x11, 0x2F, 0, 0x51, 0]),
    "no-segment-set": lambda img, seg, rng, m: bytes([0x11, 0x51, 0]),
    "type-15": lambda img, seg, rng, m: bytes([0x1F, 0x20 | seg, 0, 0x51, 0]),
    "unknown-opcodes": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg, 0, 0x90, 0xA0, 0xF0, 0x51, 0]),
    # The shipped stream with its DONE dropped and a ULEB that never ends.
    "unterminated": lambda img, seg, rng, m: original(img, "rebase").rstrip(b"\0") + b"\x60" + b"\x80" * 16,
    "times-zero-loop": lambda img, seg, rng, m: bytes([0x11, 0x20 | seg, 0, 0x80, 0]) + uleb(1 << 50) + b"\0",
}

BIND_STREAMS = {
    "ordinal-uleb-2^63": lambda img, seg, rng, m: bytes([0x20]) + uleb(1 << 63) + bind_prefix(seg)[1:] + bytes([0x90, 0]),
    "ordinal-past-dylibs": lambda img, seg, rng, m: bytes([0x1F]) + bind_prefix(seg)[1:] + bytes([0x90, 0]),
    "special-ordinal-minus-4": lambda img, seg, rng, m: bytes([0x3C]) + bind_prefix(seg)[1:] + bytes([0x90, 0]),
    "segment-15": lambda img, seg, rng, m: bind_prefix(seg)[:-2] + bytes([0x7F, 0, 0x90, 0]),
    "offset-2^63": lambda img, seg, rng, m: bind_prefix(seg)[:-2] + bytes([0x70 | seg]) + uleb(1 << 63) + bytes([0x90, 0]),
    "add-addr-wraps": lambda img, seg, rng, m: bind_prefix(seg, 8) + b"\x80" + uleb((1 << 64) - 16) + bytes([0x90, 0]),
    "times-skipping-2^62": lambda img, seg, rng, m: bind_prefix(seg) + b"\xc0" + uleb(1 << 62) + uleb((1 << 64) - 8) + b"\0",
    "imm-scaled-past-segment": lambda img, seg, rng, m: bind_prefix(seg) + b"\xbf" * 4096 + b"\0",
    "add-addr-uleb-runs-off": lambda img, seg, rng, m: bind_prefix(seg) + (b"\xa0" + uleb(1 << 33)) * 512 + b"\0",
    "no-symbol": lambda img, seg, rng, m: bytes([0x11, 0x51, 0x70 | seg, 0, 0x90, 0]),
    "symbol-unterminated": lambda img, seg, rng, m: bytes([0x11, 0x51, 0x70 | seg, 0, 0x40]) + b"A" * 300,
    "addend-sleb-overlong": lambda img, seg, rng, m: bind_prefix(seg) + b"\x60" + b"\xff" * 30 + bytes([0x7F, 0x90, 0]),
    "threaded-table-2^62": lambda img, seg, rng, m: b"\xd0" + uleb(1 << 62) + bind_prefix(seg) + bytes([0x90, 0xD1, 0]),
    # Treat the segment's ordinary pointers as a threaded-rebase chain.
    "threaded-apply-on-plain-data": lambda img, seg, rng, m: b"\xd0" + uleb(1) + bind_prefix(seg) + bytes([0x90, 0x70 | seg, 0, 0xD1, 0]),
    "type-15": lambda img, seg, rng, m: bytes([0x11, 0x40]) + SYM + bytes([0x5F, 0x70 | seg, 0, 0x90, 0]),
    "unknown-opcodes": lambda img, seg, rng, m: bind_prefix(seg) + bytes([0xE0, 0xF5, 0x90, 0]),
    "unterminated-uleb": lambda img, seg, rng, m: bind_prefix(seg) + b"\x80" + b"\xff" * 16,
}


def stream_size_past_eof(stream):
    def apply(img, rng):
        info = img.cmd(LC_DYLD_INFO, LC_DYLD_INFO_ONLY)
        if info is None or not img.u32(info + STREAM_FIELD[stream]):
            return None
        m = Mutant(img)
        m.put32(info + STREAM_FIELD[stream] + 4, 0xFFFFFFF0)
        return m
    return apply


# --- export trie ------------------------------------------------------------

def trie_location(img):
    """(command offset, field) of the trie's (offset, size) pair."""
    t = img.cmd(LC_EXPORTS_TRIE)
    if t is not None:
        return t, 8
    info = img.cmd(LC_DYLD_INFO, LC_DYLD_INFO_ONLY)
    if info is not None and img.u32(info + 44):
        return info, 40
    return None


def text_section(img):
    return next(iter(img.sections("__text")), None)


def node(terminal=b"", children=()):
    """An export-trie node; children are (edge bytes, child offset)."""
    out = uleb(len(terminal)) + terminal + bytes([len(children) & 0xFF])
    for edge, child in children:
        out += edge + b"\0" + uleb(child)
    return out


def regular(img, extra=0):
    text = text_section(img)
    return uleb(0) + uleb((text["addr"] - img.base + extra) if text else 0)


def deep_chain(img, depth, terminal_every):
    """depth nodes in a line, each one edge "a" to the next."""
    nodes, offsets, off = [], [], 0
    widths = 4  # every child offset is a fixed-width overlong ULEB
    for i in range(depth):
        term = regular(img) if terminal_every and i % terminal_every == 0 else b""
        size = len(uleb(len(term))) + len(term) + (3 + widths if i < depth - 1 else 1)
        offsets.append(off)
        nodes.append(term)
        off += size
    out = bytearray()
    for i, term in enumerate(nodes):
        out += uleb(len(term)) + term
        if i < depth - 1:
            out += b"\x01a\0" + overlong(offsets[i + 1], widths)
        else:
            out += b"\0"
    return bytes(out)


TRIES = {
    "self-cycle": lambda img: node(children=[(b"_a", 0)]),
    # node0 -> node1 -> node0 with non-empty edges: a name that grows forever.
    "two-node-cycle": lambda img: node(children=[(b"_a", 6)]) + node(children=[(b"b", 0)]),
    "child-past-end": lambda img: node(children=[(b"_a", 1 << 31)]),
    "child-offset-2^64-1": lambda img: node(children=[(b"_a", (1 << 64) - 1)]),
    "child-into-own-edge": lambda img: node(children=[(b"_abc", 3)]),
    "terminal-size-2^62": lambda img: uleb(1 << 62) + regular(img) + b"\0",
    "terminal-size-past-end": lambda img: b"\x7f" + regular(img),
    "flags-overlong": lambda img: node(children=[(b"_a", 6)]) + uleb(32) + overlong(0, 31) + uleb(0) + b"\0",
    "address-2^63": lambda img: node(children=[(b"_a", 6)]) + node(terminal=uleb(0) + uleb(1 << 63)),
    "address-mid-instruction": lambda img: node(children=[(b"_a", 6)]) + node(terminal=regular(img, 2)),
    "reexport-ordinal-2^40-unterminated": lambda img: node(children=[(b"_a", 6)]) + uleb(40) + uleb(0x08) + uleb(1 << 40) + b"B" * 37 + b"\0",
    "stub-resolver-far": lambda img: node(children=[(b"_a", 6)]) + node(terminal=uleb(0x10) + uleb(1 << 40) + uleb(1 << 41)),
    "unknown-kind-flags": lambda img: node(children=[(b"_a", 6)]) + node(terminal=uleb(0x03 | 0x80) + uleb(0)),
    "child-count-255": lambda img: bytes([0, 0xFF]) + b"_a\0" + uleb(0x20),
    "edge-unterminated": lambda img: bytes([0, 1]) + b"_" * 200,
    "deep-chain-100k": lambda img: deep_chain(img, 100_000, 0),
    "wide-names-4k": lambda img: deep_chain(img, 4_000, 1),
    "empty": lambda img: b"",
}


def trie_mutation(build):
    def apply(img, rng):
        loc = trie_location(img)
        if loc is None:
            return None
        m = Mutant(img)
        m.set_stream(loc[0], loc[1], build(img))
        return m
    return apply


def trie_size_past_eof(img, rng):
    loc = trie_location(img)
    if loc is None:
        return None
    m = Mutant(img)
    m.put32(loc[0] + loc[1] + 4, 0xFFFFFFF0)
    return m


# --- LC_FUNCTION_STARTS ------------------------------------------------------

def fstarts(build):
    def apply(img, rng):
        c, text = img.cmd(LC_FUNCTION_STARTS), text_section(img)
        if c is None or text is None:
            return None
        m = Mutant(img)
        m.set_stream(c, 8, build(img, text["addr"] - img.base, text["size"], rng))
        return m
    return apply


def fstarts_field(field, value):
    def apply(img, rng):
        c = img.cmd(LC_FUNCTION_STARTS)
        if c is None:
            return None
        m = Mutant(img)
        m.put32(c + field, value(img))
        return m
    return apply


def data_start(img):
    seg = img.segments[data_segment(img)] if data_segment(img) is not None else None
    return seg["vmaddr"] - img.base if seg else 0


FSTARTS = {
    # An overlong zero is not the terminator byte: a duplicate start.
    "overlong-zero-delta": lambda img, t, n, rng: uleb(t) + b"\x80\x00" + b"\x04" + b"\x80\x80\x00" + b"\x08\x00",
    "wraps-below-previous": lambda img, t, n, rng: uleb(t + 16) + uleb((1 << 64) - 8) + b"\x04\x00",
    "65-bit-delta": lambda img, t, n, rng: uleb(t) + uleb((1 << 64) + 4) + b"\x04\x00",
    "past-text": lambda img, t, n, rng: uleb(t) + uleb(n + 0x40) + b"\x04\x00",
    "past-image": lambda img, t, n, rng: uleb(t) + uleb(1 << 40) + b"\x04\x00",
    "into-data": lambda img, t, n, rng: uleb(t) + uleb(max(4, data_start(img) - t)) + b"\x00",
    "misaligned": lambda img, t, n, rng: uleb(t + 1) + b"\x02\x01\x01\x00",
    "every-instruction-and-1m-past": lambda img, t, n, rng: uleb(t) + b"\x04" * (n // 4 + 1_000_000) + b"\x00",
    "unterminated-uleb": lambda img, t, n, rng: uleb(t) + b"\x84" + b"\x80" * 32,
    "first-is-zero": lambda img, t, n, rng: b"\x80\x00" + uleb(t) + b"\x00",
}


# --- LC_DYLD_CHAINED_FIXUPS -------------------------------------------------

def chained(build):
    def apply(img, rng):
        ch = img.chained()
        if not ch:
            return None
        m = Mutant(img)
        return m if build(img, m, ch[0], rng) is not False else None
    return apply


def pick_segment(img, rng, need_pages=True):
    segs = [(i, s) for i, s in img.chained_segments() if not need_pages or struct.unpack_from("<H", img.data, s + 20)[0]]
    return rng.choice(segs) if segs else None


def first_fixup(img, rng):
    """(file offset, format) of the first fixup of a page that has one."""
    choices = []
    for i, s in img.chained_segments():
        page_size, fmt = struct.unpack_from("<HH", img.data, s + 4)
        seg_off = img.u64(s + 8)
        for p in range(struct.unpack_from("<H", img.data, s + 20)[0]):
            start = struct.unpack_from("<H", img.data, s + 22 + 2 * p)[0]
            if start & 0x8000:
                continue
            fo = img.file_of(img.base + seg_off + p * page_size + start)
            if fo is not None:
                choices.append((fo, fmt))
    return rng.choice(choices) if choices else None


def set_page_start(value):
    def build(img, m, h, rng):
        pick = pick_segment(img, rng)
        if not pick:
            return False
        s = pick[1]
        page_size = struct.unpack_from("<H", img.data, s + 4)[0]
        m.put16(s + 22, value(page_size))
    return build


def set_segment_field(off, width, value):
    def build(img, m, h, rng):
        pick = pick_segment(img, rng, need_pages=False)
        if not pick:
            return False
        (m.put16 if width == 2 else m.put32 if width == 4 else m.put64)(pick[1] + off, value)
    return build


def set_header(off, value):
    def build(img, m, h, rng):
        m.put32(h + off, value(img, h))
    return build


def chain_next(value):
    """Rewrite the next field of a page's first fixup."""
    def build(img, m, h, rng):
        fx = first_fixup(img, rng)
        if not fx:
            return False
        fo, fmt = fx
        v = m.get64(fo)
        if fmt in (2, 6):
            m.put64(fo, (v & ~(0xFFF << 51)) | ((value & 0xFFF) << 51))
        elif fmt in (1, 9, 12):
            m.put64(fo, (v & ~(0x7FF << 51)) | ((value & 0x7FF) << 51))
        else:
            return False
    return build


def fixup_rewrite(kind):
    def build(img, m, h, rng):
        fx = first_fixup(img, rng)
        if not fx or fx[1] not in (2, 6):
            return False
        fo, _ = fx
        v = m.get64(fo)
        keep = v & (0xFFF << 51)
        if kind == "bind-ordinal-oob":
            m.put64(fo, (1 << 63) | keep | 0xFFFFFF)
        elif kind == "rebase-target-max":
            m.put64(fo, keep | MASK36)
        elif kind == "rebase-to-own-slot":
            # A pointer to itself: anything that follows it as data loops.
            addr = next(seg["vmaddr"] + fo - seg["fileoff"] for seg in img.segments
                        if seg["fileoff"] <= fo < seg["fileoff"] + seg["filesize"])
            m.put64(fo, keep | ((addr if fx[1] == 2 else addr - img.base) & MASK36))
    return build


def multi_start(index):
    """Page 0 takes the overflow form (MULTI | index into page_start). Index 0
    is the entry itself, which then reads as LAST at offset 0; index 1 on a
    one-page segment walks entries past the array with no LAST bit."""
    def build(img, m, h, rng):
        pick = pick_segment(img, rng)
        if not pick:
            return False
        m.put16(pick[1] + 22, 0x8000 | index)
    return build


def import_field(name_offset=None, ordinal=None):
    def build(img, m, h, rng):
        count, fmt = img.u32(h + 16), img.u32(h + 20)
        if not count or fmt != 1:
            return False
        at = h + img.u32(h + 8) + 4 * rng.randrange(count)
        v = m.get32(at)
        if name_offset is not None:
            v = (v & 0x1FF) | (name_offset << 9)
        if ordinal is not None:
            v = (v & ~0xFF) | ordinal
        m.put32(at, v)
    return build


def symbols_unterminated(img, m, h, rng):
    _, size = img.chained()
    start, end = h + img.u32(h + 12), h + size
    if start >= end:
        return False
    for i in range(start, end):
        if m.d[i] == 0:
            m.d[i] = 0x41


def seg_info_past_end(img, m, h, rng):
    pick = pick_segment(img, rng, False)
    if not pick:
        return False
    m.put32(h + img.u32(h + 4) + 4 + 4 * pick[0], 0xFFFFFF00)


CHAINED = {
    "page-start-last-2-bytes": set_page_start(lambda ps: ps - 2),
    "page-start-past-page": set_page_start(lambda ps: 0x7FF0),
    "page-count-65535": set_segment_field(20, 2, 0xFFFF),
    "segment-offset-2^63": set_segment_field(8, 8, 1 << 63),
    "page-size-zero": set_segment_field(4, 2, 0),
    "pointer-format-unknown": set_segment_field(6, 2, 0x7F),
    "pointer-format-zero": set_segment_field(6, 2, 0),
    "pointer-format-arm64e": set_segment_field(6, 2, 1),
    "pointer-format-32-bit": set_segment_field(6, 2, 3),
    "starts-size-zero": set_segment_field(0, 4, 0),
    "chain-next-max": chain_next(0xFFF),
    "chain-next-misaligned": chain_next(1),
    "multi-start-self": multi_start(0),
    "multi-start-past-array": multi_start(1),
    "multi-start-index-max": multi_start(0x7FFF),
    "bind-ordinal-oob": fixup_rewrite("bind-ordinal-oob"),
    "rebase-target-max": fixup_rewrite("rebase-target-max"),
    "rebase-to-own-slot": fixup_rewrite("rebase-to-own-slot"),
    "fixups-version-7": set_header(0, lambda img, h: 7),
    "starts-offset-past-end": set_header(4, lambda img, h: 0xFFFFFF00),
    "imports-offset-past-end": set_header(8, lambda img, h: 0xFFFFFF00),
    "symbols-offset-past-end": set_header(12, lambda img, h: 0xFFFFFF00),
    "imports-count-huge": set_header(16, lambda img, h: 0x7FFFFFFF),
    "imports-format-unknown": set_header(20, lambda img, h: 7),
    "imports-format-addend64": set_header(20, lambda img, h: 3),
    "symbols-format-zlib": set_header(24, lambda img, h: 1),
    "seg-count-huge": lambda img, m, h, rng: m.put32(h + img.u32(h + 4), 0xFFFFFFFF),
    "seg-info-offset-past-end": seg_info_past_end,
    "import-name-past-pool": import_field(name_offset=0x7FFFFF),
    "import-ordinal-unknown-special": import_field(ordinal=0xF0),
    "import-ordinal-past-dylibs": import_field(ordinal=0x7F),
    "symbols-unterminated": symbols_unterminated,
}


def chained_datasize(img, rng):
    c = img.cmd(LC_CHAINED_FIXUPS)
    if c is None:
        return None
    m = Mutant(img)
    m.put32(c + 12, 0xFFFFFFF0)
    return m


# --- symbol table -----------------------------------------------------------

def symtab(build):
    def apply(img, rng):
        s = img.cmd(LC_SYMTAB)
        if s is None or not img.u32(s + 12):
            return None
        m = Mutant(img)
        return m if build(img, m, s, rng) is not False else None
    return apply


def nlists(img, s, defined=False):
    symoff, nsyms = img.u32(s + 8), img.u32(s + 12)
    out = []
    for i in range(nsyms):
        at = symoff + 16 * i
        if at + 16 > len(img.data):
            break
        n_type = img.data[at + 4]
        if n_type & 0xE0:  # stabs
            continue
        if defined and (n_type & 0x0E) != 0x0E:
            continue
        out.append(at)
    return out


def each_symbol(defined, edit):
    def build(img, m, s, rng):
        syms = nlists(img, s, defined)
        if not syms:
            return False
        edit(img, m, s, rng.choice(syms))
    return build


def strtab_unterminated(img, m, s, rng):
    stroff, strsize = img.u32(s + 16), img.u32(s + 20)
    for i in range(max(stroff, stroff + strsize - 64), min(stroff + strsize, len(m.d))):
        if m.d[i] == 0:
            m.d[i] = 0x41


def all_same_value(img, m, s, rng):
    syms = nlists(img, s, True)
    if len(syms) < 2:
        return False
    for at in syms:
        m.put64(at + 8, img.u64(syms[0] + 8))


def dysymtab(build):
    def apply(img, rng):
        d, s = img.cmd(LC_DYSYMTAB), img.cmd(LC_SYMTAB)
        if d is None or s is None:
            return None
        m = Mutant(img)
        return m if build(img, m, d, s, rng) is not False else None
    return apply


def indirect_oob(img, m, d, s, rng):
    off, count = img.u32(d + 56), img.u32(d + 60)
    if not count:
        return False
    m.put32(off + 4 * rng.randrange(count), 0x0FFFFFFF)


def stub_reserved1(img, m, d, s, rng):
    sections = img.sections("__stubs") + img.sections("__got") + img.sections("__auth_got") + img.sections("__la_symbol_ptr")
    if not sections:
        return False
    m.put32(rng.choice(sections)["hdr"] + 68, 0x0FFFFFF0)


SYMTAB = {
    "nsyms-huge": lambda img, m, s, rng: m.put32(s + 12, 0x0FFFFFFF),
    "symoff-past-eof": lambda img, m, s, rng: m.put32(s + 8, 0xFFFFFFF0),
    "stroff-past-eof": lambda img, m, s, rng: m.put32(s + 16, 0xFFFFFFF0),
    "strsize-huge": lambda img, m, s, rng: m.put32(s + 20, 0xFFFFFFF0),
    "strsize-zero": lambda img, m, s, rng: m.put32(s + 20, 0),
    "strx-past-table": each_symbol(False, lambda img, m, s, at: m.put32(at, 0xFFFFFFF0)),
    "strx-at-table-end": each_symbol(False, lambda img, m, s, at: m.put32(at, img.u32(s + 20))),
    "strtab-unterminated": strtab_unterminated,
    "nsect-255": each_symbol(True, lambda img, m, s, at: m.d.__setitem__(at + 5, 0xFF)),
    "value-far": each_symbol(True, lambda img, m, s, at: m.put64(at + 8, 0xFFFFFFFFFFFFFFF0)),
    "value-mid-instruction": each_symbol(True, lambda img, m, s, at: m.put64(at + 8, img.u64(at + 8) + 2)),
    "type-indirect": each_symbol(True, lambda img, m, s, at: (m.d.__setitem__(at + 4, 0x0B), m.put64(at + 8, 0xFFFFFFF0))),
    "all-same-value": all_same_value,
}

DYSYMTAB = {
    "extdef-range-past-nsyms": lambda img, m, d, s, rng: (m.put32(d + 16, max(0, img.u32(s + 12) - 1)), m.put32(d + 20, 0xFFFF)),
    "local-range-huge": lambda img, m, d, s, rng: (m.put32(d + 8, 0xFFFFFFF0), m.put32(d + 12, 0x20)),
    "indirect-index-past-nsyms": indirect_oob,
    "nindirect-huge": lambda img, m, d, s, rng: m.put32(d + 60, 0x0FFFFFFF),
    "indirect-off-past-eof": lambda img, m, d, s, rng: m.put32(d + 56, 0xFFFFFFF0),
    "stub-section-reserved1-huge": stub_reserved1,
}


# --- Objective-C metadata ---------------------------------------------------

def objc_classes(img):
    """[(class-list slot, class, metaclass or None, ro, meta ro or None)] as file offsets."""
    out = []
    for sec in img.sections("__objc_classlist"):
        for i in range(sec["size"] // 8):
            slot = sec["offset"] + 8 * i
            cls = img.resolve(slot)
            if cls is None:
                continue
            ro = img.resolve(cls + 32)
            meta = img.resolve(cls)
            meta_ro = img.resolve(meta + 32) if meta is not None else None
            if ro is not None:
                out.append((slot, cls, meta, ro, meta_ro))
    return out


def objc(build):
    def apply(img, rng):
        classes = objc_classes(img)
        if not classes:
            return None
        m = Mutant(img)
        return m if build(img, m, classes, rng) is not False else None
    return apply


def ros(classes):
    return [r for c in classes for r in (c[3], c[4]) if r is not None]


def lists(img, classes, field):
    """File offsets of the method (32), protocol (40), ivar (48) or property (64) lists."""
    found = []
    for ro in ros(classes):
        at = img.resolve(ro + field)
        if at is not None:
            found.append(at)
    return found


def edit_list(field, edit):
    def build(img, m, classes, rng):
        found = lists(img, classes, field)
        if not found:
            return False
        return edit(img, m, rng.choice(found), rng)
    return build


def pointer_edit(where, to):
    """Point a field of a random class/ro at a target: 'far', 'text', 'self', 'misaligned'."""
    def build(img, m, classes, rng):
        slot_of = {
            "classlist": lambda c: c[0], "superclass": lambda c: c[1] + 8, "isa": lambda c: c[1],
            "data": lambda c: c[1] + 32, "ro-name": lambda c: c[3] + 24, "ro-methods": lambda c: c[3] + 32,
            "ro-ivars": lambda c: c[3] + 48,
        }[where]
        c = rng.choice(classes)
        slot = slot_of(c)
        cls_addr = next(seg["vmaddr"] + c[1] - seg["fileoff"] for seg in img.segments
                        if seg["fileoff"] <= c[1] < seg["fileoff"] + seg["filesize"])
        text = text_section(img)
        if to == "far":
            m.write_ptr(slot, 0, far=True)
        elif to == "text" and text:
            m.write_ptr(slot, text["addr"])
        elif to == "self-class":
            m.write_ptr(slot, cls_addr)
        elif to == "misaligned":
            kind, addr = img.read_ptr(slot)
            m.write_ptr(slot, addr + 3)
        else:
            return False
    return build


def ro_name_unterminated(img, m, classes, rng):
    """ro.name at the last byte of __TEXT, made non-NUL: a string that runs off the segment."""
    seg = next((s for s in img.segments if s["name"] == "__TEXT"), None)
    if seg is None:
        return False
    last = seg["vmaddr"] + seg["filesize"] - 1
    m.d[seg["fileoff"] + seg["filesize"] - 1] = 0x41
    m.write_ptr(rng.choice(classes)[3] + 24, last)


def methlist_rel(name, imp):
    def edit(img, m, at, rng):
        if not m.get32(at) & 0x80000000 or not m.get32(at + 4):
            return False
        m.put32(at + 8, name)
        m.put32(at + 16, imp)
    return edit


OBJC = {
    "classlist-entry-far": pointer_edit("classlist", "far"),
    "classlist-entry-into-text": pointer_edit("classlist", "text"),
    "classlist-entry-misaligned": pointer_edit("classlist", "misaligned"),
    "superclass-is-self": pointer_edit("superclass", "self-class"),
    "isa-is-self": pointer_edit("isa", "self-class"),
    "data-far": pointer_edit("data", "far"),
    "data-is-class": pointer_edit("data", "self-class"),
    "ro-name-far": pointer_edit("ro-name", "far"),
    "ro-name-unterminated": ro_name_unterminated,
    "ro-methods-far": pointer_edit("ro-methods", "far"),
    "ro-methods-into-text": pointer_edit("ro-methods", "text"),
    "ro-ivars-far": pointer_edit("ro-ivars", "far"),
    "ro-instance-size-huge": lambda img, m, classes, rng: m.put32(rng.choice(classes)[3] + 8, 0xFFFFFFFF),
    "ro-flags-all-set": lambda img, m, classes, rng: m.put32(rng.choice(classes)[3], 0xFFFFFFFF),
    "methlist-count-huge": edit_list(32, lambda img, m, at, rng: m.put32(at + 4, 0xFFFFFFFF)),
    "methlist-entsize-zero": edit_list(32, lambda img, m, at, rng: m.put32(at, m.get32(at) & 0xFFFF0000)),
    "methlist-entsize-max": edit_list(32, lambda img, m, at, rng: m.put32(at, (m.get32(at) & 0xFFFF0000) | 0xFFFC)),
    "methlist-entsize-odd": edit_list(32, lambda img, m, at, rng: m.put32(at, (m.get32(at) & 0xFFFF0000) | 13)),
    "methlist-small-flag-toggled": edit_list(32, lambda img, m, at, rng: m.put32(at, m.get32(at) ^ 0x80000000)),
    "methlist-relative-far": edit_list(32, methlist_rel(0x7FFFFFFC, 0x80000000)),
    "methlist-relative-self": edit_list(32, methlist_rel(0, 0)),
    "ivarlist-count-huge": edit_list(48, lambda img, m, at, rng: m.put32(at + 4, 0xFFFFFFFF)),
    "ivarlist-entsize-zero": edit_list(48, lambda img, m, at, rng: m.put32(at, 0)),
    "proplist-count-huge": edit_list(64, lambda img, m, at, rng: m.put32(at + 4, 0xFFFFFFFF)),
    "protolist-count-huge": edit_list(40, lambda img, m, at, rng: m.put64(at, 0xFFFFFFFFFFFFFFF)),
}


def selref_far(img, rng):
    secs = img.sections("__objc_selrefs")
    if not secs:
        return None
    sec = rng.choice(secs)
    m = Mutant(img)
    m.write_ptr(sec["offset"] + 8 * rng.randrange(sec["size"] // 8), 0, far=True)
    return m


def classlist_size_huge(img, rng):
    secs = img.sections("__objc_classlist")
    if not secs:
        return None
    m = Mutant(img)
    m.put64(secs[0]["hdr"] + 40, 0xFFFFFFF0)
    return m


# --- registry ---------------------------------------------------------------

def kinds():
    table = {}
    for stream in ("rebase",):
        for name, build in REBASE_STREAMS.items():
            table[f"dyld-info.rebase.{name}"] = (lambda b, s: lambda img, rng: opcode_stream(b)(img, rng, s))(build, stream)
    for stream in ("bind", "weak", "lazy"):
        for name, build in BIND_STREAMS.items():
            table[f"dyld-info.{stream}.{name}"] = (lambda b, s: lambda img, rng: opcode_stream(b)(img, rng, s))(build, stream)
    for stream in ("rebase", "bind", "lazy"):
        table[f"dyld-info.{stream}.size-past-eof"] = stream_size_past_eof(stream)
    for name, build in TRIES.items():
        table[f"trie.{name}"] = trie_mutation(build)
    table["trie.size-past-eof"] = trie_size_past_eof
    for name, build in FSTARTS.items():
        table[f"fstarts.{name}"] = fstarts(build)
    table["fstarts.datasize-past-eof"] = fstarts_field(12, lambda img: 0xFFFFFFF0)
    table["fstarts.dataoff-past-eof"] = fstarts_field(8, lambda img: len(img.data) + 0x1000)
    for name, build in CHAINED.items():
        table[f"chained.{name}"] = chained(build)
    table["chained.datasize-past-eof"] = chained_datasize
    for name, build in SYMTAB.items():
        table[f"symtab.{name}"] = symtab(build)
    for name, build in DYSYMTAB.items():
        table[f"symtab.dysymtab.{name}"] = dysymtab(build)
    for name, build in OBJC.items():
        table[f"objc.{name}"] = objc(build)
    table["objc.selref-far"] = selref_far
    table["objc.classlist-section-size-huge"] = classlist_size_huge
    return table


def input_label(path, out):
    try:
        rel = path.relative_to(out)
        return "-".join(rel.with_suffix("").parts)
    except ValueError:
        return path.stem


def run_one(binary, mutant, entry, runs, timeout, memory):
    outdir = runs / mutant.stem / entry
    outdir.mkdir(parents=True, exist_ok=True)
    args = [a.format(f=mutant) for a in ENTRY_POINTS[entry]]
    command = [str(GUARD), str(outdir), str(memory), "--", binary] + args
    started = time.time()
    proc = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        rc = proc.wait(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        rc = proc.wait()
    elapsed = time.time() - started
    mem = (outdir / "mem.log").read_text(errors="replace") if (outdir / "mem.log").exists() else ""
    peak = max((int(l.split()[1]) for l in mem.splitlines() if len(l.split()) == 2 and l.split()[1].isdigit()), default=0)
    if timed_out:
        verdict = f"timeout {timeout}s (peak {peak} MB)"
    elif "KILLED" in mem:
        verdict = "memory kill: " + next(l for l in mem.splitlines() if "KILLED" in l)
    elif rc > 128:
        try:
            verdict = f"signal {signal.Signals(rc - 128).name}"
        except ValueError:
            verdict = f"signal {rc - 128}"
    elif rc not in (0, 1):
        verdict = f"exit {rc}"
    else:
        verdict = None
    stderr = (outdir / "stderr").read_text(errors="replace") if (outdir / "stderr").exists() else ""
    if verdict is None and (outdir / "stdout").exists():
        os.remove(outdir / "stdout")
    tail = [l for l in stderr.splitlines() if l.strip()][-3:]
    return mutant, entry, rc, verdict, elapsed, peak, tail


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--swiftdc")
    parser.add_argument("--out", default=str(ROOT / "out"))
    parser.add_argument("--input", action="append", default=[])
    parser.add_argument("--kind", action="append", default=[], help="only kinds containing this text")
    parser.add_argument("--entry", action="append", default=[], help=f"only these entry points: {', '.join(ENTRY_POINTS)}")
    parser.add_argument("--seeds", type=int, default=1)
    parser.add_argument("--per-kind", type=int, default=2)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--memory", type=int, default=3000, help="footprint kill, MB")
    parser.add_argument("--list", action="store_true", help="list the mutation kinds and exit")
    parser.add_argument("--no-run", action="store_true", help="write the mutants only")
    args = parser.parse_args()
    table = kinds()
    if args.list:
        print("\n".join(table))
        return 0
    if not args.swiftdc and not args.no_run:
        parser.error("--swiftdc is required unless --no-run or --list")
    jobs = max(1, min(args.jobs, 2))
    out = Path(args.out).resolve()
    malformed = out / "malformed"
    runs = malformed / "runs"
    malformed.mkdir(parents=True, exist_ok=True)
    paths = sorted(p for p in out.rglob("*.dylib") if malformed not in p.parents)
    paths += [p for p in FIXTURES if p.exists()] + [Path(p).resolve() for p in args.input]
    images = []
    for p in paths:
        try:
            images.append(Image(p))
        except (ValueError, struct.error) as error:
            print(f"skip {p}: {error}", file=sys.stderr)
    selected = {k: f for k, f in table.items() if not args.kind or any(s in k for s in args.kind)}
    entries = args.entry or list(ENTRY_POINTS)
    mutants, manifest = [], []
    for kind, mutate in selected.items():
        for seed in range(args.seeds):
            # Fixture inputs carry structures the corpus may lack: try them
            # first, then the corpus in a seeded order, until --per-kind apply.
            order = [i for i in images if i.path in FIXTURES]
            rest = [i for i in images if i.path not in FIXTURES]
            random.Random(f"inputs:{kind}:{seed}").shuffle(rest)
            applicable = []
            for img in order + rest:
                if args.per_kind and len(applicable) >= max(args.per_kind, 1):
                    break
                try:
                    m = mutate(img, random.Random(f"{kind}:{seed}:{img.path.name}"))
                except (StopIteration, struct.error, IndexError) as error:
                    print(f"skip {kind} on {img.path.name}: {type(error).__name__} {error}", file=sys.stderr)
                    continue
                if m is not None and bytes(m.d) != img.data:
                    applicable.append((img, m))
            for img, m in applicable:
                name = f"{input_label(img.path, out)}__{kind}__s{seed}.dylib"
                dst = malformed / name
                dst.write_bytes(bytes(m.d))
                mutants.append(dst)
                manifest.append(f"{name}\t{img.path}\t{kind}\t{seed}")
    (malformed / "manifest.tsv").write_text("\n".join(manifest) + "\n")
    print(f"{len(selected)} kinds, {len(images)} inputs, {len(mutants)} mutants in {malformed}")
    if args.no_run:
        return 0
    failures, total, started = [], 0, time.time()
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        futures = [pool.submit(run_one, args.swiftdc, mt, e, runs, args.timeout, args.memory)
                   for mt in mutants for e in entries]
        for future in concurrent.futures.as_completed(futures):
            mutant, entry, rc, verdict, elapsed, peak, tail = future.result()
            total += 1
            if verdict:
                failures.append((mutant, entry, verdict, tail))
                print(f"FAIL {entry:10} {verdict:40} {mutant}", flush=True)
                for line in tail:
                    print(f"     {line[:200]}", flush=True)
    lines = [f"{len(mutants)} mutants x {len(entries)} entry points = {total} runs, "
             f"{len(failures)} failing, {time.time() - started:.0f} s"]
    for mutant, entry, verdict, tail in sorted(failures, key=lambda f: (str(f[0]), f[1])):
        lines.append(f"{mutant}\t{entry}\t{verdict}\t{' | '.join(tail)[:300]}")
    (malformed / "report.txt").write_text("\n".join(lines) + "\n")
    print(lines[0])
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
