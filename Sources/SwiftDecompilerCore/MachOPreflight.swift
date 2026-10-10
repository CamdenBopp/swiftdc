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
    /// `MH_EXECUTE`, `MH_DYLIB`, `MH_BUNDLE`: the images dyld loads.
    private enum FileType {
        static let loadable: Set<UInt32> = [0x2, 0x6, 0x8]
    }

    private enum SectionAttribute {
        static let debug: UInt32 = 0x0200_0000   // S_ATTR_DEBUG
    }

    private enum Command {
        static let segment32: UInt32 = 0x1
        static let segment64: UInt32 = 0x19
        static let symtab: UInt32 = 0x2
        static let chainedFixups: UInt32 = 0x8000_0034   // LC_DYLD_CHAINED_FIXUPS
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

        // A fat file's slices: the core `validateFat` above checks each slice's
        // *extent* (offset/size within the file), but not the thin Mach-O header
        // *inside* each slice. A slice whose extent is in-bounds but whose thin
        // header lies (e.g. `sizeofcmds` claims load commands past the slice)
        // sails through and then traps in MachOKit when `fat.machOFiles()` parses
        // it — `MachOFile.swift:61: Fatal error: 'try!'`, the same uncatchable
        // class. Confirmed by corrupting a real fat binary's slice header.
        //
        // Read each slice's header via the handle rather than from `prefix`: a
        // slice can begin well past the 1 MiB window, and validating only the
        // ones that happened to land in the prefix would leave large fat files
        // exposed.
        for slice in fatSliceExtents(prefix: prefix, fileSize: fileSize).enumerated() {
            let (index, extent) = slice
            guard extent.size >= Layout.machHeader32,
                  (try? handle.seek(toOffset: UInt64(extent.offset))) != nil,
                  let header = try? handle.read(upToCount: min(extent.size, 4096)),
                  header.count >= Layout.machHeader32
            else { continue }
            try validateSliceThinHeader(
                header: header, sliceSize: extent.size, index: index, path: url.path
            )
        }

        // Section CONTENTS, which the checks above say nothing about. Only the
        // flat relative-pointer tables (see `relativePointerTables`), and only
        // for a thin little-endian image — a fat file's slices are handled above.
        //
        // Read per section rather than from `prefix`: metadata sits after the
        // code, so in any real app it is far beyond the 1 MiB header window.
        // Validating only what the prefix happened to cover would leave exactly
        // the large binaries unprotected.
        // dyld: "chained fixups, seg_count exceeds number of segments". The
        // fixups record how many segments the image has; when a segment's
        // load command no longer reads as one (a flipped `cmd` byte), its
        // memory is gone and metadata pointers into it read unmapped pages
        // (SIGSEGV in `dump`/`interface`, measured by `container-fuzz.py`).
        if let fixups = chainedFixups(prefix: prefix),
           (try? handle.seek(toOffset: UInt64(fixups.dataoff))) != nil,
           let header = try? handle.read(upToCount: 8), header.count == 8,
           let startsOffset = header.u32(at: 4),
           UInt64(startsOffset) + 4 <= UInt64(fixups.datasize),
           (try? handle.seek(toOffset: UInt64(fixups.dataoff) + UInt64(startsOffset))) != nil,
           let starts = try? handle.read(upToCount: 4), let segCount = starts.u32(at: 0),
           Int(segCount) > fixups.segments {
            throw BinaryLoadError(
                "Malformed Mach-O: \(url.path) — chained fixups describe \(segCount) segment(s) but the image has \(fixups.segments); dyld refuses to load such an image"
            )
        }

        let objc = sectionExtents(named: ["__objc_methlist", "__objc_selrefs"], prefix: prefix)
        if let methlist = objc["__objc_methlist"], let selrefs = objc["__objc_selrefs"],
           methlist.size > 0, methlist.offset <= fileSize, methlist.size <= fileSize - methlist.offset,
           (try? handle.seek(toOffset: UInt64(methlist.offset))) != nil,
           let bytes = try? handle.read(upToCount: methlist.size), bytes.count == methlist.size {
            try validateObjCMethodLists(
                bytes: bytes, sectionAddress: methlist.addr,
                selrefs: (selrefs.addr, selrefs.size), path: url.path
            )
        }

        for table in relativePointerTables(prefix: prefix, fileSize: fileSize) {
            guard table.size > 0, let _ = try? handle.seek(toOffset: UInt64(table.offset)),
                  let bytes = try? handle.read(upToCount: table.size), bytes.count == table.size
            else { continue }
            if table.name == "__swift5_assocty" {
                try validateAssociatedTypeTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: url.path
                )
            } else {
                try validateRelativePointerTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize,
                    name: table.name, path: url.path
                )
            }
        }
    }

    /// `(offset, size)` of every slice in a fat file, or empty when the file is
    /// not fat. Parses the same fields `validateFat` bounds-checks; the extent
    /// checks there have already run by the time this is used, so the offsets are
    /// known in-bounds.
    static func fatSliceExtents(prefix: Data, fileSize: Int) -> [(offset: Int, size: Int)] {
        guard let magic = prefix.u32(at: 0) else { return [] }
        let is64: Bool, bigEndian: Bool
        switch magic {
        case Magic.fatBE: (is64, bigEndian) = (false, true)
        case Magic.fatLE: (is64, bigEndian) = (false, false)
        case Magic.fat64BE: (is64, bigEndian) = (true, true)
        case Magic.fat64LE: (is64, bigEndian) = (true, false)
        default: return []
        }
        guard let nfat = prefix.u32(at: 4, bigEndian: bigEndian) else { return [] }
        let archSize = is64 ? Layout.fatArch64 : Layout.fatArch
        guard Int(nfat) <= (Int.max - Layout.fatHeader) / max(archSize, 1) else { return [] }

        var extents: [(offset: Int, size: Int)] = []
        for index in 0..<Int(nfat) {
            let offsetField = Layout.fatHeader + index * archSize + 8
            let offset: Int, size: Int
            if is64 {
                guard let off = prefix.u64(at: offsetField, bigEndian: bigEndian),
                      let sz = prefix.u64(at: offsetField + 8, bigEndian: bigEndian)
                else { return extents }
                (offset, size) = (Int(clamping: off), Int(clamping: sz))
            } else {
                guard let off = prefix.u32(at: offsetField, bigEndian: bigEndian),
                      let sz = prefix.u32(at: offsetField + 4, bigEndian: bigEndian)
                else { return extents }
                (offset, size) = (Int(off), Int(sz))
            }
            // The extent must lie in the file (validateFat proved this for a valid
            // file; guard again so a caller that skipped it cannot read wild).
            guard offset >= 0, size >= 0, offset <= fileSize, size <= fileSize - offset else {
                continue
            }
            extents.append((offset, size))
        }
        return extents
    }

    /// Validate the thin Mach-O header at the start of a fat slice, bounded by
    /// the **slice** size (not the whole file). Same two consistency checks as
    /// `validateThin`: the load commands must fit, and the command count cannot
    /// exceed what its byte budget can hold. A non-Mach-O slice magic is left
    /// alone — MachOKit declines it cleanly (an unknown magic is not the trap).
    static func validateSliceThinHeader(
        header: Data, sliceSize: Int, index: Int, path: String = "<data>"
    ) throws {
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — slice \(index) \(why)")
        }
        guard let magic = header.u32(at: 0) else { return }
        let is64: Bool, bigEndian: Bool
        switch magic {
        case Magic.machO64LE: (is64, bigEndian) = (true, false)
        case Magic.machO64BE: (is64, bigEndian) = (true, true)
        case Magic.machO32LE: (is64, bigEndian) = (false, false)
        case Magic.machO32BE: (is64, bigEndian) = (false, true)
        default: return  // not a thin Mach-O magic — not the crash class
        }
        let headerSize = is64 ? Layout.machHeader64 : Layout.machHeader32
        guard sliceSize >= headerSize else {
            throw fail("is \(sliceSize) byte(s), shorter than its \(headerSize)-byte header")
        }
        guard let ncmds = header.u32(at: 16, bigEndian: bigEndian),
              let sizeofcmds = header.u32(at: 20, bigEndian: bigEndian)
        else { return }  // header truncated within the read chunk; extent guard covers the rest

        let available = sliceSize - headerSize
        guard Int(sizeofcmds) <= available else {
            throw fail("declares \(sizeofcmds) bytes of load commands but the slice holds \(available)")
        }
        guard Int(ncmds) <= Int(sizeofcmds) / Layout.minLoadCommand else {
            throw fail("declares \(ncmds) load command(s), which cannot fit in \(sizeofcmds) byte(s)")
        }
    }

    /// Sections that are a flat array of 4-byte relative pointers and nothing
    /// else, so their contents can be bounds-checked without modelling any
    /// record layout.
    ///
    /// Deliberately a short list. Fuzzing crashed at least six metadata
    /// sections, but the rest (`__swift5_assocty`, `__swift5_fieldmd`,
    /// `__objc_methlist`, …) carry structured records whose layout would have to
    /// be reimplemented here to find the pointers — with a real risk of
    /// rejecting valid binaries, which this project treats as worse than the
    /// crash. The ones covered here are the severe ones anyway: corrupting any
    /// of them kills **every** subcommand.
    /// `(vmaddr, file offset, size)` of the named sections of a thin
    /// little-endian image.
    static func sectionExtents(
        named names: Set<String>, prefix: Data
    ) -> [String: (addr: UInt64, offset: Int, size: Int)] {
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE,
              let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20)
        else { return [:] }
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        var cursor = Layout.machHeader64
        var found: [String: (addr: UInt64, offset: Int, size: Int)] = [:]
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { break }
            if cmd == Command.segment64, let nsects = prefix.u32(at: cursor + 64) {
                for section in 0..<Int(nsects) {
                    let base = cursor + 72 + section * 80
                    guard base + 80 <= limit,
                          let addr = prefix.u64(at: base + 32), let size = prefix.u64(at: base + 40),
                          let offset = prefix.u32(at: base + 48)
                    else { break }
                    let raw = prefix[(prefix.startIndex + base)..<(prefix.startIndex + base + 16)]
                    let name = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                    if names.contains(name) { found[name] = (addr, Int(offset), Int(clamping: size)) }
                }
            }
            cursor += Int(cmdsize)
        }
        return found
    }

    /// `__objc_methlist`, walked list by list. In a *relative* method list
    /// (`entsizeAndFlags & 0x80000000`, entsize 12) each method's name is a
    /// relative offset to a selector reference in `__objc_selrefs`; the
    /// runtime reads the pointer stored there. Redirected anywhere else, the
    /// bytes it lands on are read as a pointer and `strlen` walks off the
    /// mapping (SIGSEGV in `objc`, `disasm`, `xrefs`, `analyze`; fuzz mutant
    /// 13). Offsets are in VM space: the list is in `__TEXT`, the selrefs in
    /// `__DATA`.
    ///
    /// Strict only where the layout is unambiguous: a relative list must fit
    /// the section and name only selref slots. A zero word between lists is
    /// padding (no list has entsize 0); a pointer-based list (entsize 24, its
    /// names rebased pointers) is stepped over unchecked; anything else ends
    /// the walk without a verdict.
    static func validateObjCMethodLists(
        bytes: Data, sectionAddress: UInt64,
        selrefs: (addr: UInt64, size: Int), path: String = "<data>"
    ) throws {
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — __objc_methlist \(why)")
        }
        let selrefEnd = selrefs.addr &+ UInt64(selrefs.size)
        var cursor = 0
        while cursor + 8 <= bytes.count, let header = bytes.u32(at: cursor), let count = bytes.u32(at: cursor + 4) {
            if header == 0 { cursor += 4; continue }        // padding
            let entsize = Int(header & 0x0000_fffc)
            let relative = header & 0x8000_0000 != 0
            guard (relative && entsize == 12) || (!relative && entsize == 24) else { return }
            let (span, overflow) = Int(count).multipliedReportingOverflow(by: entsize)
            guard !overflow, span <= bytes.count - cursor - 8 else {
                throw fail("list at +\(cursor) declares \(count) method(s), past the section's end")
            }
            if relative {
                for method in 0..<Int(count) {
                    let field = cursor + 8 + method * 12
                    guard let raw = bytes.u32(at: field) else { break }
                    let target = (sectionAddress &+ UInt64(field)) &+ UInt64(bitPattern: Int64(Int32(bitPattern: raw)))
                    guard target >= selrefs.addr, target < selrefEnd, (target - selrefs.addr) % 8 == 0 else {
                        throw fail(
                            "list at +\(cursor) method \(method) names 0x\(String(target, radix: 16)), not a selector reference in __objc_selrefs"
                        )
                    }
                }
            }
            cursor += 8 + span
        }
    }

    /// The `LC_DYLD_CHAINED_FIXUPS` payload of a thin little-endian loadable
    /// image, in bounds, with the number of segment commands beside it.
    static func chainedFixups(prefix: Data) -> (dataoff: Int, datasize: Int, segments: Int)? {
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE,
              let filetype = prefix.u32(at: 12), FileType.loadable.contains(filetype),
              let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20)
        else { return nil }
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        var cursor = Layout.machHeader64
        var segments = 0
        var payload: (Int, Int)?
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { return nil }   // an unread command could be a segment: no count
            if cmd == Command.segment64 { segments += 1 }
            if cmd == Command.chainedFixups,
               let dataoff = prefix.u32(at: cursor + 8), let datasize = prefix.u32(at: cursor + 12) {
                payload = (Int(dataoff), Int(datasize))
            }
            cursor += Int(cmdsize)
        }
        guard let (dataoff, datasize) = payload, datasize >= 8 else { return nil }
        return (dataoff, datasize, segments)
    }

    private static func relativePointerTables(
        prefix: Data, fileSize: Int
    ) -> [(name: String, offset: Int, size: Int)] {
        // Exactly the sections the Swift ABI defines as a bare array of relative
        // pointers — protocol descriptors, protocol conformances, and nominal
        // type descriptors. Nothing else in them to misread.
        //
        // The list was NOT widened by measurement, though it was tempting: on
        // real binaries `__swift5_assocty` and `__swift5_capture` also have every
        // int32 resolve in-file, which looks like the same shape. They are
        // structured records, and some of those int32s are *counts*, not
        // pointers. They resolve in-file here only because the counts are small
        // and the sections sit far into the file; a large count in a small binary
        // would be rejected as an out-of-range pointer, refusing a valid input.
        // Over-rejection is worse than the crash, so those stay uncovered and
        // documented rather than guessed at.
        let wanted: Set<String> = [
            "__swift5_protos", "__swift5_proto", "__swift5_types", "__swift5_types2",
            // Not flat, but walked by its own record layout; see
            // `validateAssociatedTypeTable`.
            "__swift5_assocty",
        ]
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE else { return [] }
        guard let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20) else { return [] }

        var found: [(name: String, offset: Int, size: Int)] = []
        var cursor = Layout.machHeader64
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { break }
            if cmd == Command.segment64, let nsects = prefix.u32(at: cursor + 64) {
                for section in 0..<Int(nsects) {
                    let base = cursor + 72 + section * 80
                    guard base + 80 <= limit,
                          let size = prefix.u64(at: base + 40), let offset = prefix.u32(at: base + 48)
                    else { break }
                    let raw = prefix[(prefix.startIndex + base)..<(prefix.startIndex + base + 16)]
                    let name = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                    guard wanted.contains(name) else { continue }
                    let bytes = Int(clamping: size), start = Int(offset)
                    // The section-bounds check in `validateSegment` already ran;
                    // this guard only keeps a malformed entry from producing a
                    // nonsensical read here.
                    guard start <= fileSize, bytes <= fileSize - start else { continue }
                    found.append((name, start, bytes))
                }
            }
            cursor += Int(cmdsize)
        }
        return found
    }

    /// `__swift5_assocty`, walked by its record layout rather than as a flat
    /// table, so its counts are never mistaken for pointers (the reason it
    /// was left out before). Each `AssociatedTypeDescriptor`
    /// (swift/include/swift/RemoteInspection/Records.h:359) is two relative
    /// pointers, `NumAssociatedTypes`, `AssociatedTypeRecordSize`, then that
    /// many `AssociatedTypeRecord`s of two relative pointers each.
    ///
    /// One corrupted name pointer here killed every subcommand: SIGSEGV in
    /// `strlen` past the end of the file, or `Negative value is not
    /// representable` (6 of the 8 crashing mutants in `metadata-fuzz.py
    /// libSample.dylib 100 1234`).
    static func validateAssociatedTypeTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws {
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — __swift5_assocty \(why)")
        }
        func checkPointer(at offset: Int, _ what: String) throws {
            guard let raw = bytes.u32(at: offset) else { throw fail("\(what) is truncated") }
            let target = sectionOffset + offset + Int(Int32(bitPattern: raw))
            guard target >= 0, target < fileSize else {
                throw fail("\(what) is a relative pointer to offset \(target), outside the \(fileSize)-byte file")
            }
        }
        var cursor = 0
        var descriptor = 0
        while cursor < bytes.count {
            guard cursor + 16 <= bytes.count,
                  let count = bytes.u32(at: cursor + 8), let recordSize = bytes.u32(at: cursor + 12)
            else { throw fail("descriptor \(descriptor) is truncated") }
            // The compiler emits `sizeof(AssociatedTypeRecord)`, two Int32s.
            guard recordSize == 8 else {
                throw fail("descriptor \(descriptor) declares \(recordSize)-byte records, not 8")
            }
            let (body, overflow) = Int(count).multipliedReportingOverflow(by: 8)
            guard !overflow, body <= bytes.count - cursor - 16 else {
                throw fail("descriptor \(descriptor) declares \(count) record(s), past the section's end")
            }
            try checkPointer(at: cursor, "descriptor \(descriptor)'s conforming type name")
            try checkPointer(at: cursor + 4, "descriptor \(descriptor)'s protocol name")
            for record in 0..<Int(count) {
                let base = cursor + 16 + record * 8
                try checkPointer(at: base, "descriptor \(descriptor) record \(record)'s name")
                try checkPointer(at: base + 4, "descriptor \(descriptor) record \(record)'s type")
            }
            cursor += 16 + body
            descriptor += 1
        }
    }

    /// Every entry of a relative-pointer table must resolve inside the file.
    ///
    /// A Swift relative pointer is a **signed** 32-bit delta from the pointer's
    /// own location, so `target = pointerOffset + value`. Negative is entirely
    /// normal — verified on the fixtures, where every entry points *backwards*
    /// into `__TEXT`. The defect this guards is not sign but range: a resolved
    /// offset outside the file reaches
    /// `readElement(offset:)`/`readString(offset:)` in the dependency, which
    /// converts to unsigned before bounds-checking and so traps
    /// (`Negative value is not representable`) or walks off the mapping with
    /// `strlen` (SIGSEGV) — neither catchable from here.
    static func validateRelativePointerTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, name: String, path: String = "<data>"
    ) throws {
        for index in stride(from: 0, to: bytes.count - (bytes.count % 4), by: 4) {
            guard let raw = bytes.u32(at: index) else { break }
            let delta = Int(Int32(bitPattern: raw))
            let pointer = sectionOffset + index
            let target = pointer + delta
            guard target >= 0, target < fileSize else {
                throw BinaryLoadError(
                    """
                    Malformed Mach-O: \(path) — \(name)[\(index / 4)] is a relative pointer to \
                    offset \(target), outside the \(fileSize)-byte file
                    """
                )
            }
        }
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

        // An executable, dylib, or bundle is held to what dyld requires before
        // it will load one; an object file is not (see `walkLoadCommands`).
        let filetype = prefix.u32(at: 12, bigEndian: bigEndian) ?? 0
        try walkLoadCommands(
            prefix: prefix, start: headerSize, ncmds: Int(ncmds), sizeofcmds: Int(sizeofcmds),
            fileSize: fileSize, is64: is64, bigEndian: bigEndian,
            loadable: FileType.loadable.contains(filetype), fail: fail
        )
    }

    /// Walk as many load commands as the prefix actually contains, checking each
    /// one's self-declared size for consistency. Stops early — without
    /// complaint — when the prefix runs out, since a short prefix is our own
    /// limitation, not evidence of a bad file.
    ///
    /// A loadable image must also have the segments dyld requires, and each
    /// section must name the segment that contains it. A structurally valid
    /// file can break these (rename `__TEXT` to `__TEXTX`, or let an unknown
    /// `cmd` hide `__LINKEDIT`), and MachOKit then aborts the process. Each
    /// check is dyld's own, verified by `dlopen` on the mutated fixture:
    /// "section '__text' segment name '__TEXT' does not match containing
    /// segment's name '__TEXTX'", "missing __TEXT segment", "malformed mach-o
    /// has no LINKEDIT". An object file is exempt: it puts every section, of
    /// any segment name, in one unnamed segment, and swiftdc reads those today.
    private static func walkLoadCommands(
        prefix: Data, start: Int, ncmds: Int, sizeofcmds: Int, fileSize: Int,
        is64: Bool, bigEndian: Bool, loadable: Bool, fail: (String) -> BinaryLoadError
    ) throws {
        var offset = start
        var consumed = 0
        var segments = Set<String>()
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
                is64: is64, bigEndian: bigEndian, index: index, loadable: loadable, fail: fail
            )
            if cmd == Command.segment64 || cmd == Command.segment32 {
                guard offset + 24 <= prefix.count else { return }
                segments.insert(segmentName(at: offset, prefix: prefix) ?? "")
            }
            offset += Int(cmdsize)
        }
        // Reached only when every command was read, so an absence is proven.
        if loadable {
            for required in ["__TEXT", "__LINKEDIT"] where !segments.contains(required) {
                throw fail("has no \(required) segment; dyld refuses to load such an image")
            }
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
        bigEndian: Bool, index: Int, loadable: Bool, fail: (String) -> BinaryLoadError
    ) throws {
        switch cmd {
        case Command.segment64:
            try validateSegment(
                at: offset, prefix: prefix, fileSize: fileSize, is64: true,
                bigEndian: bigEndian, index: index, loadable: loadable, fail: fail
            )
        case Command.segment32:
            try validateSegment(
                at: offset, prefix: prefix, fileSize: fileSize, is64: false,
                bigEndian: bigEndian, index: index, loadable: loadable, fail: fail
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
        index: Int, loadable: Bool, fail: (String) -> BinaryLoadError
    ) throws {
        let name = segmentName(at: offset, prefix: prefix) ?? "\(index)"
        let fileoff: Int
        let filesize: Int
        let nsects: UInt32
        // The segment's memory range, which every section must lie inside.
        let vmStart: UInt64
        let vmEnd: UInt64
        if is64 {
            guard let off = prefix.u64(at: offset + 40, bigEndian: bigEndian),
                  let size = prefix.u64(at: offset + 48, bigEndian: bigEndian),
                  let count = prefix.u32(at: offset + 64, bigEndian: bigEndian),
                  let vmaddr = prefix.u64(at: offset + 24, bigEndian: bigEndian),
                  let vmsize = prefix.u64(at: offset + 32, bigEndian: bigEndian)
            else { return }   // beyond the prefix — our limit, not a bad file
            (vmStart, vmEnd) = (vmaddr, vmaddr.addingReportingOverflow(vmsize).partialValue)
            // Clamp rather than convert: `Int(_:)` traps above `Int.max`, which is
            // exactly the input this validator exists to survive. A clamped value
            // still fails the bounds check below.
            (fileoff, filesize, nsects) = (Int(clamping: off), Int(clamping: size), count)
        } else {
            guard let off = prefix.u32(at: offset + 32, bigEndian: bigEndian),
                  let size = prefix.u32(at: offset + 36, bigEndian: bigEndian),
                  let count = prefix.u32(at: offset + 48, bigEndian: bigEndian),
                  let vmaddr = prefix.u32(at: offset + 24, bigEndian: bigEndian),
                  let vmsize = prefix.u32(at: offset + 28, bigEndian: bigEndian)
            else { return }
            (fileoff, filesize, nsects) = (Int(off), Int(size), count)
            (vmStart, vmEnd) = (UInt64(vmaddr), UInt64(vmaddr) + UInt64(vmsize))
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
            // `section.segname` (bytes 16..<32 of both layouts) must name the
            // segment it sits in; `segmentName(at: base - 8)` reads that field.
            if loadable {
                let owner = segmentName(at: offset, prefix: prefix) ?? ""
                let declared = segmentName(at: base + 8, prefix: prefix) ?? ""
                guard declared == owner else {
                    throw fail(
                        "section \(section) of segment '\(owner)' names segment '\(declared)'; dyld refuses to load such an image"
                    )
                }
                // dyld: "section '…' end address … is beyond containing
                // segment's end address …". A section addressed outside its
                // segment points every metadata read through it at unmapped
                // memory (SIGSEGV in `dump`, SIGTRAP in `objc`, measured).
                let addr: UInt64?
                let size: UInt64?
                if is64 {
                    (addr, size) = (prefix.u64(at: base + 32, bigEndian: bigEndian),
                                    prefix.u64(at: base + 40, bigEndian: bigEndian))
                } else {
                    (addr, size) = (prefix.u32(at: base + 32, bigEndian: bigEndian).map(UInt64.init),
                                    prefix.u32(at: base + 36, bigEndian: bigEndian).map(UInt64.init))
                }
                // An unmapped segment (`vmsize` 0) and a debug section
                // (`S_ATTR_DEBUG`) are never read through memory. A Go binary's
                // `__DWARF` is both, with sections sized past its empty range,
                // and dyld loads it (`com.docker.build`, measured).
                let mapped = vmEnd > vmStart && flags & SectionAttribute.debug == 0
                if mapped, let addr, let size {
                    let (end, overflow) = addr.addingReportingOverflow(size)
                    guard addr >= vmStart, !overflow, end <= vmEnd else {
                        throw fail(
                            "section \(section) of segment '\(owner)' spans 0x\(String(addr, radix: 16))..<0x\(String(end, radix: 16)), outside the segment's 0x\(String(vmStart, radix: 16))..<0x\(String(vmEnd, radix: 16)); dyld refuses to load such an image"
                        )
                    }
                }
            }
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
