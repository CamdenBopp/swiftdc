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
            bigEndian: bigEndian, fail: fail
        )
    }

    /// Walk as many load commands as the prefix actually contains, checking each
    /// one's self-declared size for consistency. Stops early — without
    /// complaint — when the prefix runs out, since a short prefix is our own
    /// limitation, not evidence of a bad file.
    private static func walkLoadCommands(
        prefix: Data, start: Int, ncmds: Int, sizeofcmds: Int, bigEndian: Bool,
        fail: (String) -> BinaryLoadError
    ) throws {
        var offset = start
        var consumed = 0
        for index in 0..<ncmds {
            guard offset + Layout.minLoadCommand <= prefix.count else { return }
            guard let cmdsize = prefix.u32(at: offset + 4, bigEndian: bigEndian) else { return }

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
            offset += Int(cmdsize)
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
