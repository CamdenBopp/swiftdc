# Remove one type's record from __swift5_types in a thin arm64 Mach-O, in
# place: move it to the end of the section and shrink the section by one
# 4-byte record. The descriptor and its field metadata stay.
# Usage: python3 -I droptyperecord.py <dylib> <descriptor symbol>
import struct, subprocess, sys
path, symbol = sys.argv[1], sys.argv[2]
data = bytearray(open(path, 'rb').read())
assert struct.unpack_from('<I', data, 0)[0] == 0xfeedfacf, 'thin 64-bit Mach-O only'
target = None
for line in subprocess.run(['nm', path], capture_output=True, text=True, check=True).stdout.splitlines():
    fields = line.split()
    if len(fields) == 3 and fields[2] == symbol:
        target = int(fields[0], 16)
assert target is not None, symbol
ncmds = struct.unpack_from('<I', data, 16)[0]
offset = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', data, offset)
    if cmd == 0x19:
        nsects = struct.unpack_from('<I', data, offset + 64)[0]
        for s in range(nsects):
            header = offset + 72 + s * 80
            name = data[header:header + 16].rstrip(b'\0').decode()
            if name != '__swift5_types':
                continue
            addr, sectsize = struct.unpack_from('<QQ', data, header + 32)
            fileoff = struct.unpack_from('<I', data, header + 48)[0]
            entries = [struct.unpack_from('<i', data, fileoff + 4 * i)[0] for i in range(sectsize // 4)]
            targets = [addr + 4 * i + (e & ~3) for i, e in enumerate(entries)]
            index = targets.index(target)
            # Re-point the kept records at their places after the removal.
            kept = [t for i, t in enumerate(targets) if i != index]
            for i, t in enumerate(kept):
                struct.pack_into('<i', data, fileoff + 4 * i, t - (addr + 4 * i))
            struct.pack_into('<i', data, fileoff + 4 * len(kept), 0)
            struct.pack_into('<Q', data, header + 40, sectsize - 4)
            open(path, 'wb').write(data)
            sys.exit(0)
    offset += size
sys.exit('no __swift5_types section')
