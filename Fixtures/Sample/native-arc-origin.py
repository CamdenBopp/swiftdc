#!/usr/bin/env python3
"""One scalar native control in a fresh process, after ABI/provider checks."""
from pathlib import Path
import argparse, hashlib, json, os, struct

if not __debug__:
    raise RuntimeError("Native ABI and origin validation requires Python assertions enabled")

TARGET = "_swift_nonatomic_retain"

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def legacy_bindings(raw, start, extent, libraries, segments, lazy=False, weak=False):
    """Decode the fixture's ordinary dyld bind programs, retaining weak flags."""
    assert 0 <= start <= len(raw) and 0 <= extent <= len(raw) - start
    data = raw[start:start + extent]
    position, steps, bindings = 0, 0, []
    ordinal = segment = offset = addend = flags = 0
    kind = 1
    name = None
    def leb(signed=False):
        nonlocal position
        value = shift = 0
        while True:
            assert position < len(data) and shift < 64
            byte = data[position]; position += 1
            value |= (byte & 127) << shift
            shift += 7
            if byte < 128:
                return value - (1 << shift) if signed and byte & 64 else value
    def emit():
        assert kind == 1 and name and 1 <= ordinal <= len(libraries)
        assert 0 <= segment < len(segments)
        vm, size, file, file_size = segments[segment]
        assert 0 <= offset and offset + 8 <= min(size, file_size), (segment, offset, size, file_size, name)
        bindings.append({"name": name, "ordinal": ordinal, "library": libraries[ordinal - 1],
                         "weak": weak or bool(flags & 1), "addend": addend, "type": kind,
                         "address": vm + offset, "file_offset": file + offset})
    while position < len(data):
        steps += 1
        assert steps <= 4096
        byte = data[position]; position += 1
        opcode, immediate = byte & 0xf0, byte & 15
        if opcode == 0:
            if not lazy: break
            ordinal = segment = offset = addend = flags = 0
            kind = 1
            name = None
        elif opcode == 0x10: ordinal = immediate
        elif opcode == 0x20: ordinal = leb()
        elif opcode == 0x30: ordinal = immediate - 16 if immediate else 0
        elif opcode == 0x40:
            flags = immediate
            end = data.index(0, position)
            name = data[position:end].decode(); position = end + 1
        elif opcode == 0x50: kind = immediate
        elif opcode == 0x60: addend = leb(signed=True)
        elif opcode == 0x70: segment, offset = immediate, leb()
        elif opcode == 0x80: offset = (offset + leb()) & ((1 << 64) - 1)
        elif opcode == 0x90: emit(); offset = (offset + 8) & ((1 << 64) - 1)
        elif opcode == 0xa0: emit(); offset = (offset + 8 + leb()) & ((1 << 64) - 1)
        elif opcode == 0xb0: emit(); offset = (offset + 8 * (immediate + 1)) & ((1 << 64) - 1)
        elif opcode == 0xc0:
            count, skip = leb(), leb()
            assert count <= 4096
            for _ in range(count): emit(); offset = (offset + 8 + skip) & ((1 << 64) - 1)
        else: raise RuntimeError("Unsupported fixture bind opcode: " + hex(byte))
    return bindings

def macho(path, target=TARGET):
    data = path.read_bytes()
    magic, cpu, subtype, kind, count, size, flags, reserved = struct.unpack_from("<8I", data)
    assert magic == 0xfeedfacf and cpu == 0x100000c and kind == 6
    assert flags & 0x80 and not flags & 0x100  # MH_TWOLEVEL, no MH_FORCE_FLAT
    assert 32 + size <= len(data)
    libraries, sections, symbols, imports, rpaths, segments = [], [], [], [], [], []
    image_id = None
    chains = symtab = exports = programs = None
    position = 32
    for _ in range(count):
        command, length = struct.unpack_from("<II", data, position)
        assert length >= 8 and position + length <= 32 + size
        if command in [0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023, 0xd, 0x8000001c]:
            offset = struct.unpack_from("<I", data, position + 8)[0]
            name = data[position + offset:position + length].split(b"\0")[0].decode()
            if command == 0xd: image_id = name
            elif command == 0x8000001c: rpaths.append(name)
            else: libraries.append(name)
        if command == 0x19:
            segments.append(struct.unpack_from("<QQQQ", data, position + 24))
            number = struct.unpack_from("<I", data, position + 64)[0]
            assert 72 + 80 * number <= length
            for index in range(number):
                start = position + 72 + 80 * index
                section = data[start:start + 16].split(b"\0")[0].decode()
                segment = data[start + 16:start + 32].split(b"\0")[0].decode()
                address, extent, file_offset = struct.unpack_from("<QQI", data, start + 32)
                section_flags = struct.unpack_from("<I", data, start + 64)[0]
                assert section not in ["__interpose", "__mod_init_func", "__mod_term_func", "__init_offsets"]
                assert section_flags & 255 not in [9, 10, 22]
                sections.append((segment, section, address, extent))
        if command == 0x1a:
            assert struct.unpack_from("<Q", data, position + 8)[0] == 0
        if command == 0x80000034:
            chains = struct.unpack_from("<II", data, position + 8)
        if command == 0x80000033:
            exports = struct.unpack_from("<II", data, position + 8)
        if command in [0x22, 0x80000022]:
            info = struct.unpack_from("<10I", data, position + 8)
            programs = [(info[2], info[3], False, False), (info[4], info[5], False, True),
                        (info[6], info[7], True, False)]
            if info[9]: exports = info[8:10]
        if command == 2:
            symtab = struct.unpack_from("<IIII", data, position + 8)
        position += length
    assert position == 32 + size
    assert symtab and exports
    offset, number, strings, string_size = symtab
    assert offset + 16 * number <= len(data) and strings + string_size <= len(data)
    for index in range(number):
        name_offset, typ, sect, desc, value = struct.unpack_from("<IBBHQ", data, offset + 16 * index)
        assert name_offset < string_size
        name = data[strings + name_offset:strings + string_size].split(b"\0")[0].decode()
        if name == target:
            symbols.append({"name": name, "type": typ, "section": sect, "description": desc, "value": value})
    if chains:
        start, extent = chains
        version, starts, imports_offset, names, number, fmt, names_format = struct.unpack_from("<7I", data, start)
        assert start + extent <= len(data) and version == 0 and fmt == 1 and names_format == 0
        for index in range(number):
            raw = struct.unpack_from("<I", data, start + imports_offset + 4 * index)[0]
            ordinal = raw & 255
            assert 1 <= ordinal <= len(libraries) and not (raw >> 8) & 1
            name = data[start + names + (raw >> 9):start + extent].split(b"\0")[0].decode()
            imports.append({"name": name, "ordinal": ordinal, "library": libraries[ordinal - 1]})
    legacy = []
    if programs:
        assert not chains
        for start, extent, lazy, weak in programs:
            legacy += legacy_bindings(data, start, extent, libraries, segments, lazy=lazy, weak=weak)
        imports += [{key: item[key] for key in ["name", "ordinal", "library"]} for item in legacy]
    start, extent = exports
    assert start + extent <= len(data)
    trie = data[start:start + extent]
    seen, export_names = set(), []
    def uleb(pos):
        value = shift = 0
        while True:
            assert pos < len(trie) and shift < 64
            byte = trie[pos]; pos += 1
            value |= (byte & 127) << shift
            if byte < 128: return value, pos
            shift += 7
    def walk(pos, prefix):
        assert pos not in seen and len(seen) < 4096
        seen.add(pos)
        terminal, pos = uleb(pos)
        end = pos + terminal
        assert end < len(trie)
        if terminal:
            export_flags, unused = uleb(pos)
            assert export_flags == 0
            export_names.append(prefix)
        pos = end
        children = trie[pos]; pos += 1
        for _ in range(children):
            end = trie.index(0, pos)
            suffix = trie[pos:end].decode(); pos = end + 1
            child, pos = uleb(pos)
            walk(child, prefix + suffix)
    walk(0, "")
    return {"image_id": image_id, "rpaths": rpaths, "libraries": libraries, "sections": sections, "target_symbols": symbols,
            "imports": imports, "exports": export_names, "legacy_bindings": legacy,
            "binding_format": "chained" if chains else "legacy" if programs else "none"}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    options = parser.parse_args()
    library = options.library.resolve(strict=True)
    proof = json.loads(Path(str(library) + ".abi.json").read_text())
    assert proof["schema"] == 1 and proof["compiler_ABI_verified"] is True
    assert proof["library_file"] == library.name and proof["library_sha256"] == sha(library)
    assert proof["expected_arguments"] == [7, 99] and proof["expected_result"] == 116
    assert proof["case"] in ["local", "import"] and proof["level"] in ["Onone", "O", "Osize"]
    assert proof["entry_symbol"] == "arc_origin_" + proof["case"] + "_probe"
    for key in ["C_target", "Clang_import", "C_entry", "Swift_body"]:
        abi = proof[key]
        assert abi["return_type"] == "i64" and abi["parameter_types"] == ["i64", "i64"]
        assert abi["calling_convention"] == ("swift" if key == "Swift_body" else "C")
    assert proof["C_target"]["return_semantics"]["actual_return_expression"] == "second + 17"
    for key in ["C_entry_to_Swift_body", "Swift_body_to_C_target"]:
        assert proof[key]["formals_forwarded_in_order"] and proof[key]["returns_actual_call_result"]
    client = macho(library)
    assert client["image_id"] == "@rpath/" + library.name
    assert client["rpaths"] == ["@loader_path"]
    assert client["exports"] == ["_" + proof["entry_symbol"]]
    assert len(client["target_symbols"]) == 1
    symbol = client["target_symbols"][0]
    if proof["case"] == "local":
        assert client["imports"] == [] and symbol["type"] & 14 == 14 and not symbol["type"] & 1
        assert symbol["section"] != 0 and symbol["description"] >> 8 == 0
    else:
        filename = proof["provider_file"]
        assert filename == "libArcOriginProvider." + proof["level"] + ".dylib"
        provider = library.parent / filename
        assert sha(provider) == proof["provider_sha256"]
        actual = macho(provider)
        assert actual["image_id"] == "@rpath/" + provider.name and actual["rpaths"] == []
        assert actual["libraries"] == ["/usr/lib/libSystem.B.dylib"]
        assert actual["imports"] == [] and actual["exports"] == [TARGET]
        assert all(segment == "__TEXT" and section in ["__text", "__unwind_info"]
                   for segment, section, address, extent in actual["sections"])
        assert client["imports"] == [{"name": TARGET, "ordinal": 1, "library": "@rpath/" + filename}]
        assert symbol["type"] == 1 and symbol["section"] == 0 and symbol["description"] >> 8 == 1
    forbidden = {"DYLD_INSERT_LIBRARIES", "DYLD_FORCE_FLAT_NAMESPACE", "DYLD_LIBRARY_PATH",
                 "DYLD_FRAMEWORK_PATH", "DYLD_VERSIONED_LIBRARY_PATH", "DYLD_VERSIONED_FRAMEWORK_PATH", "LD_PRELOAD"}
    assert not forbidden.intersection(os.environ)
    import ctypes
    handle = ctypes.CDLL(str(library), mode=os.RTLD_LOCAL | os.RTLD_NOW)
    entry = getattr(handle, proof["entry_symbol"])
    entry.argtypes = [ctypes.c_int64, ctypes.c_int64]
    entry.restype = ctypes.c_int64
    value = entry(7, 99)
    print(json.dumps({"actual": value, "expected": 116, "arguments": [7, 99],
                      "case": proof["case"], "level": proof["level"], "passed": value == 116}))
    assert value == 116

if __name__ == "__main__":
    main()
