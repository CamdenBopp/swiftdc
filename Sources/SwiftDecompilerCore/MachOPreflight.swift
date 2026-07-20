import Foundation

/// Structural validation of a Mach-O or fat header, run **before** the file is
/// handed to MachOKit.
///
/// Why this exists: MachOKit and its `FileIOBinary` dependency use `try!` and
/// `precondition` on malformed input, so a bad file does not throw — it aborts
/// the process. Those traps are in a dependency and **cannot be caught**, which
/// makes validation beforehand the only available mitigation. A survey of nine
/// hand-written malformed inputs crashed seven of them, including an empty file
/// (`Precondition failed: Invalid Data Size`) and one SIGSEGV.
///
/// The checks are deliberately **conservative**: they reject only what is
/// provably inconsistent with the file's own declared sizes. Anything merely
/// unusual is allowed through, because wrongly rejecting a real binary is a
/// worse failure than passing a weird one to a parser that can handle it. Every
/// check compares two numbers the file itself provides; none encodes a
/// heuristic about what binaries "normally" look like.
public enum MachOPreflight {
    /// Sizes of the fixed-layout structures we bounds-check against.
    private enum Layout {
        static let machHeader32 = 28
        static let machHeader64 = 32
        static let fatHeader = 8
        static let fatArch = 20
        static let fatArch64 = 32
        /// The smallest possible load command: `cmd` + `cmdsize`.
        static let minLoadCommand = 8
    }

    /// The load commands whose payloads declare file ranges. Anything not listed
    /// is walked for size consistency but its payload is left alone — an unknown
    /// command is not evidence of a bad file.
    private enum Command {
        static let segment32: UInt32 = 0x1
        static let segment64: UInt32 = 0x19
        static let symtab: UInt32 = 0x2
    }

    /// Section types that occupy no bytes in the file: their `size` describes
    /// memory to be zeroed, so it must NOT be bounds-checked against the file.
    /// `__bss` is routinely larger than the binary that declares it.
    private enum SectionType {
        static let zerofill: Set<UInt32> = [0x1, 0xc, 0x13]
    }

    private enum Magic {
        static let machO64LE: UInt32 = 0xfeed_facf
        static let machO64BE: UInt32 = 0xcffa_edfe
        static let machO32LE: UInt32 = 0xfeed_face
        static let machO32BE: UInt32 = 0xcefa_edfe
        static let fatBE: UInt32 = 0xbeba_feca
        static let fatLE: UInt32 = 0xcafe_babe
        static let fat64BE: UInt32 = 0xbfba_feca
        static let fat64LE: UInt32 = 0xcafe_babf
    }

    /// Validate the file at `url`, throwing `BinaryLoadError` rather than
    /// letting a dependency trap.
    ///
    /// Only a prefix is read — enough for the header and, where it fits, the
    /// load commands. Nothing here needs the whole file.
    public static func validate(url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let fileSize = size else {
            throw BinaryLoadError("Cannot determine size of \(url.path)")
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw BinaryLoadError("Cannot open \(url.path)")
        }
        defer { try? handle.close() }
        // 1 MiB covers the header plus load commands of any binary in practice;
        // where it does not, the arithmetic checks still apply and the
        // load-command walk simply stops at the end of what was read.
        let prefix = (try? handle.read(upToCount: min(fileSize, 1 << 20))) ?? Data()
        try validate(prefix: prefix, fileSize: fileSize, path: url.path)
    }

    /// The pure core, separated so it is testable without touching the disk —
    /// which matters here, because the inputs that trigger this are exactly the
    /// ones that are awkward to keep as fixture files.
    public static func validate(prefix: Data, fileSize: Int, path: String = "<data>") throws {
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — \(why)")
        }

        guard fileSize > 0 else { throw fail("file is empty") }
        guard let magic = prefix.u32(at: 0) else {
            throw fail("file is \(fileSize) byte(s); too short to contain a magic number")
        }

        switch magic {
        case Magic.machO64LE, Magic.machO32LE:
            try validateThin(
                prefix: prefix, fileSize: fileSize,
                is64: magic == Magic.machO64LE, bigEndian: false, fail: fail
            )
        case Magic.machO64BE, Magic.machO32BE:
            try validateThin(
                prefix: prefix, fileSize: fileSize,
                is64: magic == Magic.machO64BE, bigEndian: true, fail: fail
            )
        case Magic.fatBE, Magic.fatLE, Magic.fat64BE, Magic.fat64LE:
            let is64 = (magic == Magic.fat64BE || magic == Magic.fat64LE)
            // The classic fat header is big-endian on disk; the byte-swapped
            // spellings are the little-endian ones.
            let bigEndian = (magic == Magic.fatBE || magic == Magic.fat64BE)
            try validateFat(
                prefix: prefix, fileSize: fileSize, is64: is64, bigEndian: bigEndian, fail: fail
            )
        default:
            // Not our file at all. Left to the caller's existing "Not a Mach-O
            // file" path rather than reported as malformed — a PNG is not a
            // corrupt binary.
            return
        }
    }

    // MARK: - Thin

    private static func validateThin(
        prefix: Data, fileSize: Int, is64: Bool, bigEndian: Bool,
        fail: (String) -> BinaryLoadError
    ) throws {
        let headerSize = is64 ? Layout.machHeader64 : Layout.machHeader32
        guard fileSize >= headerSize else {
            throw fail("file is \(fileSize) byte(s), shorter than its \(headerSize)-byte header")
        }
        // ncmds and sizeofcmds sit at offsets 16 and 20 in both header layouts.
        guard let ncmds = prefix.u32(at: 16, bigEndian: bigEndian),
              let sizeofcmds = prefix.u32(at: 20, bigEndian: bigEndian)
        else {
            throw fail("header is truncated")
        }

        let available = fileSize - headerSize
        guard Int(sizeofcmds) <= available else {
            throw fail(
                "header declares \(sizeofcmds) bytes of load commands but only \(available) byte(s) follow it"
            )
        }
        // Every load command is at least 8 bytes, so this bounds ncmds without
        // assuming anything about which commands are present.
        guard Int(ncmds) <= Int(sizeofcmds) / Layout.minLoadCommand else {
            throw fail(
                "header declares \(ncmds) load command(s), which cannot fit in \(sizeofcmds) byte(s)"
            )
        }

        try walkLoadCommands(
            prefix: prefix, start: headerSize, ncmds: Int(ncmds), sizeofcmds: Int(sizeofcmds),
            fileSize: fileSize, is64: is64, bigEndian: bigEndian, fail: fail
        )
    }

    /// Walk as many load commands as the prefix actually contains, checking each
    /// one's self-declared size for consistency. Stops early — without
    /// complaint — when the prefix runs out, since a short prefix is our own
    /// limitation, not evidence of a bad file.
    private static func walkLoadCommands(
        prefix: Data, start: Int, ncmds: Int, sizeofcmds: Int, fileSize: Int,
        is64: Bool, bigEndian: Bool, fail: (String) -> BinaryLoadError
    ) throws {
        var offset = start
        var consumed = 0
        for index in 0..<ncmds {
            guard offset + Layout.minLoadCommand <= prefix.count else { return }
            guard let cmd = prefix.u32(at: offset, bigEndian: bigEndian),
                  let cmdsize = prefix.u32(at: offset + 4, bigEndian: bigEndian) else { return }

            guard cmdsize >= UInt32(Layout.minLoadCommand) else {
                throw fail("load command \(index) declares a size of \(cmdsize) bytes")
            }
            // Load commands are 4-byte aligned (8 for 64-bit, but 4 is the
            // invariant both layouts share); a misaligned size desynchronises
            // every subsequent command.
            guard cmdsize % 4 == 0 else {
                throw fail("load command \(index) has a misaligned size of \(cmdsize) bytes")
            }
            consumed += Int(cmdsize)
            guard consumed <= sizeofcmds else {
                throw fail(
                    "load commands overrun their declared region (\(consumed) > \(sizeofcmds) bytes)"
                )
            }
            try validatePayload(
                cmd: cmd, at: offset, prefix: prefix, fileSize: fileSize,
                is64: is64, bigEndian: bigEndian, index: index, fail: fail
            )
            offset += Int(cmdsize)
        }
    }

    // MARK: - Load-command payloads

    /// A command's own declared file ranges must lie inside the file.
    ///
    /// The header-level checks say the command *table* is coherent; they say
    /// nothing about where a command points. MachOKit reads these ranges with
    /// trapping accessors, so a segment or symbol table addressing bytes that do
    /// not exist aborts the process — silently, with no diagnostic at all.
    /// Confirmed live: `dump`, `layout`, `interface` and `objc` each died by
    /// SIGTRAP on a segment `fileoff` past EOF, and `dump`/`interface` on all
    /// four `LC_SYMTAB` range fields. (`disasm` survives only incidentally,
    /// because llvm-objdump rejects the file first.)
    ///
    /// Only commands that declare file ranges are inspected; an unrecognised
    /// command is left alone rather than treated as suspect.
    private static func validatePayload(
        cmd: UInt32, at offset: Int, prefix: Data, fileSize: Int, is64: Bool,
        bigEndian: Bool, index: Int, fail: (String) -> BinaryLoadError
    ) throws {
        switch cmd {
        case Command.segment64:
            try validateSegment(
                at: offset, prefix: prefix, fileSize: fileSize, is64: true,
                bigEndian: bigEndian, index: index, fail: fail
            )
        case Command.segment32:
            try validateSegment(
                at: offset, prefix: prefix, fileSize: fileSize, is64: false,
                bigEndian: bigEndian, index: index, fail: fail
            )
        case Command.symtab:
            try validateSymtab(
                at: offset, prefix: prefix, fileSize: fileSize, is64: is64,
                bigEndian: bigEndian, fail: fail
            )
        default:
            break
        }
    }

    /// A segment's file range, and the file range of each of its sections.
    private static func validateSegment(
        at offset: Int, prefix: Data, fileSize: Int, is64: Bool, bigEndian: Bool,
        index: Int, fail: (String) -> BinaryLoadError
    ) throws {
        let name = segmentName(at: offset, prefix: prefix) ?? "\(index)"
        let fileoff: Int
        let filesize: Int
        let nsects: UInt32
        if is64 {
            guard let off = prefix.u64(at: offset + 40, bigEndian: bigEndian),
                  let size = prefix.u64(at: offset + 48, bigEndian: bigEndian),
                  let count = prefix.u32(at: offset + 64, bigEndian: bigEndian)
            else { return }   // beyond the prefix — our limit, not a bad file
            // Clamp rather than convert: `Int(_:)` traps above `Int.max`, which is
            // exactly the input this validator exists to survive. A clamped value
            // still fails the bounds check below.
            (fileoff, filesize, nsects) = (Int(clamping: off), Int(clamping: size), count)
        } else {
            guard let off = prefix.u32(at: offset + 32, bigEndian: bigEndian),
                  let size = prefix.u32(at: offset + 36, bigEndian: bigEndian),
                  let count = prefix.u32(at: offset + 48, bigEndian: bigEndian)
            else { return }
            (fileoff, filesize, nsects) = (Int(off), Int(size), count)
        }

        guard fileoff <= fileSize, filesize <= fileSize - fileoff else {
            throw fail(
                "segment \(name) claims \(filesize) byte(s) at offset \(fileoff) of a \(fileSize)-byte file"
            )
        }

        let sectionStart = offset + (is64 ? 72 : 56)
        let sectionSize = is64 ? 80 : 68
        for section in 0..<Int(nsects) {
            let base = sectionStart + section * sectionSize
            guard let flags = prefix.u32(at: base + (is64 ? 64 : 56), bigEndian: bigEndian)
            else { return }
            // A zero-fill section occupies no file bytes; its `size` is a memory
            // extent and is routinely larger than the whole binary.
            guard !SectionType.zerofill.contains(flags & 0xff) else { continue }

            let sectOffset: Int
            let sectSize: Int
            if is64 {
                guard let size = prefix.u64(at: base + 40, bigEndian: bigEndian),
                      let off = prefix.u32(at: base + 48, bigEndian: bigEndian)
                else { return }
                (sectOffset, sectSize) = (Int(off), Int(clamping: size))
            } else {
                guard let size = prefix.u32(at: base + 36, bigEndian: bigEndian),
                      let off = prefix.u32(at: base + 40, bigEndian: bigEndian)
                else { return }
                (sectOffset, sectSize) = (Int(off), Int(size))
            }
            guard sectOffset <= fileSize, sectSize <= fileSize - sectOffset else {
                throw fail(
                    "section \(section) of segment \(name) claims \(sectSize) byte(s) at offset \(sectOffset) of a \(fileSize)-byte file"
                )
            }
        }
    }

    private static func segmentName(at offset: Int, prefix: Data) -> String? {
        guard offset + 24 <= prefix.count else { return nil }
        let bytes = prefix[(prefix.startIndex + offset + 8)..<(prefix.startIndex + offset + 24)]
        let name = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    /// The symbol table and string table must lie inside the file.
    ///
    /// `nsyms` is checked through the size of one `nlist`, so an absurd count is
    /// rejected on the same arithmetic as an out-of-range offset — no separate
    /// notion of "too many symbols" is invented.
    private static func validateSymtab(
        at offset: Int, prefix: Data, fileSize: Int, is64: Bool, bigEndian: Bool,
        fail: (String) -> BinaryLoadError
    ) throws {
        guard let symoff = prefix.u32(at: offset + 8, bigEndian: bigEndian),
              let nsyms = prefix.u32(at: offset + 12, bigEndian: bigEndian),
              let stroff = prefix.u32(at: offset + 16, bigEndian: bigEndian),
              let strsize = prefix.u32(at: offset + 20, bigEndian: bigEndian)
        else { return }

        let entrySize = is64 ? 16 : 12   // nlist_64 / nlist
        let symbolBytes = Int(nsyms) * entrySize   // both are <= UInt32.max, so no overflow
        guard Int(symoff) <= fileSize, symbolBytes <= fileSize - Int(symoff) else {
            throw fail(
                "symbol table claims \(nsyms) symbol(s) (\(symbolBytes) bytes) at offset \(symoff) of a \(fileSize)-byte file"
            )
        }
        guard Int(stroff) <= fileSize, Int(strsize) <= fileSize - Int(stroff) else {
            throw fail(
                "string table claims \(strsize) byte(s) at offset \(stroff) of a \(fileSize)-byte file"
            )
        }
    }

    // MARK: - Fat

    private static func validateFat(
        prefix: Data, fileSize: Int, is64: Bool, bigEndian: Bool,
        fail: (String) -> BinaryLoadError
    ) throws {
        guard let nfat = prefix.u32(at: 4, bigEndian: bigEndian) else {
            throw fail("fat header is truncated")
        }
        let archSize = is64 ? Layout.fatArch64 : Layout.fatArch
        // Guard the multiplication itself: a large nfat_arch would otherwise
        // overflow before it could be compared against the file size.
        guard Int(nfat) <= (Int.max - Layout.fatHeader) / archSize else {
            throw fail("fat header declares \(nfat) architectures")
        }
        let needed = Layout.fatHeader + Int(nfat) * archSize
        guard needed <= fileSize else {
            throw fail(
                "fat header declares \(nfat) architecture(s), needing \(needed) bytes, but the file is \(fileSize)"
            )
        }

        // Each slice must lie inside the file. This is the check that turns a
        // lying fat header from a segmentation fault into an error message.
        for index in 0..<Int(nfat) {
            // `offset` sits at +8 in both fat_arch and fat_arch_64 (each is
            // preceded by cputype and cpusubtype); only the field WIDTHS differ.
            let offsetField = Layout.fatHeader + index * archSize + 8
            let sliceOffset: Int
            let sliceSize: Int
            if is64 {
                guard let offset = prefix.u64(at: offsetField, bigEndian: bigEndian),
                      let size = prefix.u64(at: offsetField + 8, bigEndian: bigEndian)
                else { return }  // beyond the prefix; arithmetic above already bounded it
                // `Int(exactly:)`/`Int(_:)` would TRAP on a 64-bit value larger
                // than Int.max — which is precisely the kind of hostile input
                // this file exists to survive. Clamp instead: a clamped value is
                // still far past `fileSize` and fails the bounds check below.
                sliceOffset = Int(clamping: offset)
                sliceSize = Int(clamping: size)
            } else {
                guard let offset = prefix.u32(at: offsetField, bigEndian: bigEndian),
                      let size = prefix.u32(at: offsetField + 4, bigEndian: bigEndian)
                else { return }
                sliceOffset = Int(offset)
                sliceSize = Int(size)
            }

            guard sliceOffset <= fileSize, sliceSize <= fileSize - sliceOffset else {
                throw fail(
                    "architecture \(index) claims bytes \(sliceOffset)…\(sliceOffset + sliceSize) of a \(fileSize)-byte file"
                )
            }
        }
    }
}

// MARK: - Bounds-checked scalar reads

private extension Data {
    /// Read a `UInt32`, returning nil rather than trapping when out of bounds.
    /// `Data`'s own subscripting is exactly what traps in the dependency this
    /// file exists to protect against, so every read here is checked.
    func u32(at offset: Int, bigEndian: Bool = false) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        var value: UInt32 = 0
        for byte in 0..<4 {
            value |= UInt32(self[startIndex + offset + byte]) << (8 * UInt32(byte))
        }
        return bigEndian ? value.byteSwapped : value
    }

    func u64(at offset: Int, bigEndian: Bool = false) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        var value: UInt64 = 0
        for byte in 0..<8 {
            value |= UInt64(self[startIndex + offset + byte]) << (8 * UInt64(byte))
        }
        return bigEndian ? value.byteSwapped : value
    }
}
