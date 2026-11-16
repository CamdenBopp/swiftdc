#!/usr/bin/env python3
"""Create a disassembly-only conflicting-import control. Never load the image."""
from pathlib import Path
import argparse, hashlib, json, struct

KINDS = ["provider-mismatch", "pointer-addend", "import-addend", "weak-import", "weak-bind-only",
         "weak-nlist-only", "weak-dylib", "other-symbol", "nlist-mismatch", "flat-namespace",
         "self-ordinal", "flat-lookup", "weak-lookup", "stub-non-jump", "normal-after-done",
         "missing-binding", "lazy-helper-mismatch", "non-twolevel", "force-flat",
         "weak-use-flags", "ref-to-weak-nlist", "other-identity-symbol"]


def append_payload(data, payload, offset_field, size_field, linkedit):
    """Move one metadata payload without moving any code or existing data."""
    data += bytes((-len(data)) % 16)
    position = len(data)
    data += payload
    struct.pack_into("<II", data, offset_field, position, len(payload))
    assert size_field == offset_field + 4
    file_start = struct.unpack_from("<Q", data, linkedit + 40)[0]
    file_size = len(data) - file_start
    vm_size = struct.unpack_from("<Q", data, linkedit + 32)[0]
    struct.pack_into("<Q", data, linkedit + 48, file_size)
    struct.pack_into("<Q", data, linkedit + 32, max(vm_size, (file_size + 0x3fff) & ~0x3fff))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--kind", required=True, choices=KINDS)
    options = parser.parse_args()
    original = options.library.read_bytes()
    proof = json.loads(Path(str(options.library) + ".abi.json").read_text())
    assert proof["compiler_ABI_verified"] and hashlib.sha256(original).hexdigest() == proof["library_sha256"]
    data = bytearray(original)
    u32 = lambda offset: struct.unpack_from("<I", data, offset)[0]
    assert u32(0) == 0xfeedfacf and u32(4) == 0x100000c
    position, dependencies, got, sections = 32, [], [], {}
    fixups = fixup_command = symtab = indirect = dyld_info = linkedit = None
    for _ in range(u32(16)):
        command, size = struct.unpack_from("<II", data, position)
        assert size >= 8 and position + size <= 32 + u32(20)
        if command in [0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023]:
            offset = u32(position + 8)
            name = data[position + offset:position + size].split(b"\0")[0].decode()
            dependencies.append((position, name))
        if command == 0x80000034:
            fixup_command = position
            fixups = u32(position + 8)
        if command in [0x22, 0x80000022]:
            dyld_info = position
        if command == 2:
            symtab = struct.unpack_from("<IIII", data, position + 8)
        if command == 0xb:
            indirect = struct.unpack_from("<II", data, position + 56)
        if command == 0x19:
            if data[position + 8:position + 24].split(b"\0")[0] == b"__LINKEDIT":
                linkedit = position
            for index in range(u32(position + 64)):
                section = position + 72 + index * 80
                name = data[section:section + 16].split(b"\0")[0]
                address, extent, offset = struct.unpack_from("<QQI", data, section + 32)
                sections[bytes(name)] = (address, extent, offset, u32(section + 68), u32(section + 72))
                if name == b"__got":
                    got += list(range(offset, offset + extent, 8))
        position += size
    assert position == 32 + u32(20) and symtab is not None and linkedit is not None
    assert (fixups is not None) != (dyld_info is not None)
    assert dependencies[2][1] == "/usr/lib/swift/libswiftCore.dylib"
    offset, number, strings, extent = symtab
    symbols = []
    for i in range(number):
        address = offset + 16 * i
        string, typ, section, description, value = struct.unpack_from("<IBBHQ", data, address)
        assert string < extent
        start = strings + string
        name = data[start:data.index(0, start)].decode()
        if name == "_swift_bridgeObjectRetain":
            assert (typ, section, description, value) == (1, 0, 3 << 8, 0)
            symbols.append(address)
    assert len(symbols) == 1
    symbol = symbols[0]
    if options.kind in ["weak-import", "weak-nlist-only", "ref-to-weak-nlist"]:
        flag = 0x80 if options.kind == "ref-to-weak-nlist" else 0x40
        struct.pack_into("<H", data, symbol + 6, (3 << 8) | flag)
    if options.kind == "weak-dylib":
        struct.pack_into("<I", data, dependencies[2][0], 0x80000018)
    elif options.kind == "weak-use-flags":
        # SDK loader.h: dylib_use_command is the alternate LC_LOAD_DYLIB
        # encoding, with nameoff28, marker0x1a741800 and flags at byte24.
        dependency, library = dependencies[2]
        size = u32(dependency + 4)
        name = library.encode() + b"\0"
        assert u32(dependency) == 0xc and 28 + len(name) <= size
        current, compatible = u32(dependency + 16), u32(dependency + 20)
        struct.pack_into("<7I", data, dependency, 0xc, size, 28, 0x1a741800, current, compatible, 1)
        data[dependency + 28:dependency + size] = name + bytes(size - 28 - len(name))
    elif options.kind == "non-twolevel":
        assert u32(24) & 0x80 and not u32(24) & 0x100
        struct.pack_into("<I", data, 24, u32(24) & ~0x80)
    elif options.kind == "force-flat":
        assert u32(24) & 0x80 and not u32(24) & 0x100
        struct.pack_into("<I", data, 24, u32(24) | 0x100)
    elif options.kind == "nlist-mismatch":
        struct.pack_into("<H", data, symbol + 6, 1 << 8)
    elif options.kind == "flat-namespace":
        struct.pack_into("<I", data, 24, (u32(24) & ~0x80) | 0x100)
    elif options.kind == "stub-non-jump":
        assert indirect is not None
        address, extent, offset, first, size = sections[b"__stubs"]
        symbol_index = (symbol - symtab[0]) // 16
        matches = [i for i in range(extent // size)
                   if u32(indirect[0] + (first + i) * 4) == symbol_index]
        assert len(matches) == 1 and size == 12
        struct.pack_into("<I", data, offset + matches[0] * size + 8, 0xd65f03c0)

    if fixups is not None:
        version, starts, imports, names, count, fmt, namesfmt = struct.unpack_from("<7I", data, fixups)
        assert version == 0 and fmt == 1 and namesfmt == 0
        entries = {}
        for index in range(count):
            entry = fixups + imports + 4 * index
            raw = u32(entry)
            start = fixups + names + (raw >> 9)
            entries[bytes(data[start:data.index(0, start)]).decode()] = (index, entry, raw)
        index, entry, raw = entries["_swift_bridgeObjectRetain"]
        assert raw & 0x1ff == 3
        slots = [offset for offset in got if (struct.unpack_from("<Q", data, offset)[0] >> 63) == 1
                 and struct.unpack_from("<Q", data, offset)[0] & 0xffffff == index]
        assert len(slots) == 1
        slot = slots[0]
        pointer = struct.unpack_from("<Q", data, slot)[0]
        assert (pointer >> 24) & 255 == 0
        if options.kind == "provider-mismatch":
            struct.pack_into("<I", data, entry, (raw & ~255) | 1)
        elif options.kind == "pointer-addend":
            struct.pack_into("<Q", data, slot, pointer | (4 << 24))
        elif options.kind == "import-addend":
            length = u32(fixup_command + 12)
            payload = bytearray(data[fixups:fixups + imports])
            assert names >= imports + 4 * count
            for i in range(count):
                payload += struct.pack("<Ii", u32(fixups + imports + 4 * i), 4 if i == index else 0)
            symbol_start = len(payload)
            payload += data[fixups + names:fixups + length]
            struct.pack_into("<I", payload, 12, symbol_start)
            struct.pack_into("<I", payload, 20, 2)  # DYLD_CHAINED_IMPORT_ADDEND
            append_payload(data, payload, fixup_command + 8, fixup_command + 12, linkedit)
        elif options.kind in ["weak-import", "weak-bind-only"]:
            struct.pack_into("<I", data, entry, raw | (1 << 8))
        elif options.kind == "other-identity-symbol":
            start = fixups + names + (raw >> 9)
            original_name = b"_swift_bridgeObjectRetain\0"
            replacement = b"_swift_retain_n\0"
            assert data[start:start + len(original_name)] == original_name
            data[start:start + len(original_name)] = replacement + bytes(len(original_name) - len(replacement))
        elif options.kind == "other-symbol":
            other = entries["_swift_release"][0]
            struct.pack_into("<Q", data, slot, (pointer & ~0xffffff) | other)
        elif options.kind in ["self-ordinal", "flat-lookup", "weak-lookup"]:
            ordinal = {"self-ordinal": 0, "flat-lookup": 0xfe, "weak-lookup": 0xfd}[options.kind]
            struct.pack_into("<I", data, entry, (raw & ~255) | ordinal)
    else:
        lazy_offset, lazy_size = struct.unpack_from("<II", data, dyld_info + 32)
        lazy = bytearray(data[lazy_offset:lazy_offset + lazy_size])
        name = b"_swift_bridgeObjectRetain\0"
        assert lazy.count(name) == 1
        name_at = lazy.index(name)
        flags_at, ordinal_at, entry_at = name_at - 1, name_at - 2, name_at - 4
        bind_at = name_at + len(name)
        assert lazy[flags_at] == 0x40 and lazy[ordinal_at] == 0x13
        assert lazy[entry_at] == 0x72 and lazy[bind_at:bind_at + 2] == b"\x90\x00"
        if options.kind == "provider-mismatch": data[lazy_offset + ordinal_at] = 0x11
        elif options.kind in ["weak-import", "weak-bind-only"]: data[lazy_offset + flags_at] |= 1
        elif options.kind in ["self-ordinal", "flat-lookup", "weak-lookup"]:
            data[lazy_offset + ordinal_at] = {"self-ordinal": 0x30, "flat-lookup": 0x3e, "weak-lookup": 0x3d}[options.kind]
        elif options.kind == "other-identity-symbol":
            replacement = b"_swift_retain_n\0"
            payload = lazy[:name_at] + replacement + lazy[name_at + len(name):]
            append_payload(data, payload, dyld_info + 32, dyld_info + 36, linkedit)
            delta = len(replacement) - len(name)
            _, helper_size, helper, _, _ = sections[b"__stub_helper"]
            for offset in range(helper + 24, helper + helper_size, 12):
                assert u32(offset) == 0x18000050 and u32(offset + 4) & 0xfc000000 == 0x14000000
                value = u32(offset + 8)
                if value >= bind_at: struct.pack_into("<I", data, offset + 8, value + delta)
        elif options.kind == "other-symbol":
            data[lazy_offset + name_at:lazy_offset + name_at + len(name)] = b"_switf_bridgeObjectRetain\0"
        elif options.kind in ["pointer-addend", "normal-after-done", "missing-binding", "lazy-helper-mismatch"]:
            vm, extent, file, first, size = sections[b"__la_symbol_ptr"]
            slot = file + lazy[entry_at + 1]
            if options.kind == "pointer-addend":
                payload = lazy[:bind_at] + b"\x60\x04" + lazy[bind_at:]
                append_payload(data, payload, dyld_info + 32, dyld_info + 36, linkedit)
                _, helper_size, helper, _, _ = sections[b"__stub_helper"]
                for offset in range(helper + 24, helper + helper_size, 12):
                    assert u32(offset) == 0x18000050 and u32(offset + 4) & 0xfc000000 == 0x14000000
                    value = u32(offset + 8)
                    if value >= bind_at: struct.pack_into("<I", data, offset + 8, value + 2)
            elif options.kind in ["normal-after-done", "missing-binding"]:
                data[lazy_offset + bind_at] = 0
                if options.kind == "normal-after-done":
                    normal, normal_size = struct.unpack_from("<II", data, dyld_info + 16)
                    payload = data[normal:normal + normal_size] + lazy[entry_at:bind_at] + b"\x51\x90\x00"
                    append_payload(data, payload, dyld_info + 16, dyld_info + 20, linkedit)
            else:
                _, helper_size, helper, _, _ = sections[b"__stub_helper"]
                original_helper = struct.unpack_from("<Q", data, slot)[0]
                assert original_helper != helper + 24
                struct.pack_into("<Q", data, slot, helper + 24)
    assert data != original and options.output.resolve() != options.library.resolve()
    options.output.write_bytes(data)
    print(json.dumps({"kind": options.kind, "source_sha256": proof["library_sha256"],
                      "native_invocations": 0, "output_sha256": hashlib.sha256(data).hexdigest()}))


if __name__ == "__main__":
    main()
