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
        /// Every command whose payload is a `struct dylib` (a name as an
        /// `lc_str` offset into the command, then three version words).
        static let dylibCommands: Set<UInt32> = [
            0xc,            // LC_LOAD_DYLIB
            0xd,            // LC_ID_DYLIB
            0x20,           // LC_LAZY_LOAD_DYLIB
            0x8000_0018,    // LC_LOAD_WEAK_DYLIB
            0x8000_001f,    // LC_REEXPORT_DYLIB
            0x8000_0023,    // LC_LOAD_UPWARD_DYLIB
        ]
        /// `sizeof(struct dylib_command)`: `cmd`, `cmdsize`, then `struct dylib`
        /// (name offset, timestamp, current_version, compatibility_version).
        /// The name string starts at or after this.
        static let dylibCommandHeader = 24
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
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw BinaryLoadError("Cannot open \(url.path)")
        }
        defer { try? handle.close() }
        // The size of what the handle reads. `attributesOfItem` describes a
        // symlink itself, so `/usr/bin/ex` (a link to `vim`) measured 3 bytes.
        guard let end = try? handle.seekToEnd(), let fileSize = Int(exactly: end),
              (try? handle.seek(toOffset: 0)) != nil
        else {
            throw BinaryLoadError("Cannot determine size of \(url.path)")
        }
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
            // And its contents, exactly as a thin file's: MachOKit parses the
            // chosen slice's metadata just as it would a thin image, so without
            // this every universal binary reached it unchecked (the
            // `sample.release 150 99` selref mutant, wrapped by `lipo -create`,
            // still trapped in `objc --arch arm64`).
            let image = ImageReader(handle: handle, base: extent.offset, size: extent.size)
            if let slicePrefix = image.read(offset: 0, count: min(extent.size, 1 << 20)) {
                try validateImageContents(prefix: slicePrefix, image: image, path: "\(url.path) (slice \(index))")
            }
        }

        try validateImageContents(
            prefix: prefix, image: ImageReader(handle: handle, base: 0, size: fileSize), path: url.path
        )
    }

    /// One image's bytes: the whole file for a thin image, or one fat slice.
    /// Offsets are relative to the image, as its load commands give them, and
    /// a read that would leave the image returns nil.
    struct ImageReader {
        let handle: FileHandle
        let base: Int
        let size: Int

        func read(offset: Int, count: Int) -> Data? {
            guard offset >= 0, count >= 0, offset <= size, count <= size - offset,
                  (try? handle.seek(toOffset: UInt64(base + offset))) != nil,
                  let data = try? handle.read(upToCount: count), data.count == count
            else { return nil }
            return data
        }
    }

    /// Section contents of one thin image, whose header and load commands
    /// start `prefix`.
    static func validateImageContents(prefix: Data, image: ImageReader, path: String) throws {
        let fileSize = image.size
        // Section CONTENTS, for a thin little-endian image. A fat file's
        // slices come through here one at a time from `validate(url:)`.
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
           let header = image.read(offset: fixups.dataoff, count: 8),
           let startsOffset = header.u32(at: 4),
           UInt64(startsOffset) + 4 <= UInt64(fixups.datasize),
           let starts = image.read(offset: fixups.dataoff + Int(startsOffset), count: 4), let segCount = starts.u32(at: 0),
           Int(segCount) > fixups.segments {
            throw BinaryLoadError(
                "Malformed Mach-O: \(path) — chained fixups describe \(segCount) segment(s) but the image has \(fixups.segments); dyld refuses to load such an image"
            )
        }

        let objc = sectionExtents(named: ["__objc_methlist", "__objc_selrefs"], prefix: prefix)
        if let methlist = objc["__objc_methlist"], let selrefs = objc["__objc_selrefs"],
           methlist.size > 0, methlist.offset <= fileSize, methlist.size <= fileSize - methlist.offset,
           let bytes = image.read(offset: methlist.offset, count: methlist.size) {
            try validateObjCMethodLists(
                bytes: bytes, sectionAddress: methlist.addr,
                selrefs: (selrefs.addr, selrefs.size), path: path,
                sectionOffset: methlist.offset, fileSize: fileSize
            )
        }

        // Every fixup chain stays inside its page, and the slots the chains
        // reach are what the pointer checks below decode.
        var chainEntries: ChainEntries?
        if let fixups = chainedFixups(prefix: prefix),
           let blob = image.read(offset: fixups.dataoff, count: fixups.datasize),
           let startsOffset = blob.u32(at: 4), let segmentCount = blob.u32(at: Int(startsOffset)) {
            let segments = segmentRanges(prefix: prefix)
            chainEntries = try validateFixupChains(
                blob: blob, startsOffset: Int(startsOffset), segmentCount: Int(segmentCount),
                readSegment: { index in
                    guard index < segments.count else { return nil }
                    let segment = segments[index]
                    guard segment.size > 0, segment.size <= 512 << 20,
                          let data = image.read(offset: segment.offset, count: segment.size)
                    else { return nil }
                    return (segment.vmaddr, data)
                },
                path: path
            )
        }

        // The Objective-C pointer arrays, decoded per their segment's
        // chained-fixup pointer format (or as plain addresses without one).
        if let table = sectionTable(prefix: prefix) {
            var formats: [Int: UInt16] = [:]
            var imports: UInt32 = 0
            var chained = false
            if let fixups = chainedFixups(prefix: prefix),
               let blob = image.read(offset: fixups.dataoff, count: fixups.datasize),
               let startsOffset = blob.u32(at: 4), let importCount = blob.u32(at: 16),
               let segCount = blob.u32(at: Int(startsOffset)) {
                chained = true
                imports = importCount
                let starts = Int(startsOffset)
                for index in 0..<Int(segCount) {
                    let entry: Int = starts + 4 + 4 * index
                    guard let start = blob.u32(at: entry), start != 0 else { continue }
                    let formatOffset: Int = starts + Int(start) + 6
                    if let format = blob.u16(at: formatOffset) { formats[index] = format }
                }
            }
            let targets: [String: [String]] = [
                "__objc_selrefs": ["__objc_methname"],
                "__objc_classlist": ["__objc_data", "__data"],
                "__objc_nlclslist": ["__objc_data", "__data"],
                "__objc_catlist": ["__objc_const"],
                "__objc_nlcatlist": ["__objc_const"],
                "__objc_protolist": ["__data", "__objc_const"],
                "__objc_protorefs": ["__data", "__objc_const"],
                "__objc_classrefs": ["__objc_data"],
                "__objc_superrefs": ["__objc_data", "__data"],
            ]
            for section in table.sections {
                guard let names = targets[section.name], section.size > 0,
                      section.offset <= fileSize, section.size <= fileSize - section.offset
                else { continue }
                let encoding: PointerEncoding
                if chained {
                    // A segment with no fixups has no pointers to decode.
                    guard let format = formats[section.segment] else { continue }
                    encoding = .chained(format: format, imageBase: table.textBase, imports: imports)
                } else {
                    encoding = .plain
                }
                let allowed = table.sections.filter { names.contains($0.name) }
                    .map { (name: $0.name, addr: $0.addr, size: $0.size) }
                guard !allowed.isEmpty,
                      let bytes = image.read(offset: section.offset, count: section.size)
                else { continue }
                try validateObjCPointerArray(
                    bytes: bytes, name: section.name, encoding: encoding, allowed: allowed, path: path,
                    nullable: section.name == "__objc_classrefs" || section.name == "__objc_superrefs",
                    address: section.addr, chainEntries: chainEntries
                )
            }

            // The classes those lists name, through their pointer fields.
            var encodings: [Int: PointerEncoding] = [:]
            let segments = Set(table.sections.map(\.segment))
            for segment in segments {
                if !chained { encodings[segment] = .plain }
                else if let format = formats[segment] {
                    encodings[segment] = .chained(format: format, imageBase: table.textBase, imports: imports)
                }
            }
            let loaded: Set<String> = [
                "__objc_data", "__data", "__objc_const", "__objc_classlist", "__objc_nlclslist", "__objc_protolist",
            ]
            // (Other sections are named, not read: a field's target only has to
            // land in them.)
            var reader = PointerReader(sections: [], encodings: encodings, chainEntries: chainEntries)
            for section in table.sections {
                var bytes: Data?
                if loaded.contains(section.name), section.size > 0, section.size <= 64 << 20,
                   section.offset <= fileSize, section.size <= fileSize - section.offset,
                   let read = image.read(offset: section.offset, count: section.size) {
                    bytes = read
                }
                reader.sections.append((section.name, section.addr, section.size, section.segment, bytes))
            }
            var classes: [UInt64] = []
            for list in reader.sections where list.name == "__objc_classlist" || list.name == "__objc_nlclslist" {
                for slot in stride(from: list.addr, to: list.addr &+ UInt64(list.size), by: 8) {
                    if case .address(let cls)?? = reader.field(at: slot) { classes.append(cls) }
                }
            }
            var protocols: [UInt64] = []
            for list in reader.sections where list.name == "__objc_protolist" {
                for slot in stride(from: list.addr, to: list.addr &+ UInt64(list.size), by: 8) {
                    if case .address(let proto)?? = reader.field(at: slot) { protocols.append(proto) }
                }
            }
            try validateObjCClasses(classes, protocols: protocols, reader: reader, path: path)
        }

        var mangledNames: [Int] = []
        for table in relativePointerTables(prefix: prefix, fileSize: fileSize) {
            guard table.size > 0, let bytes = image.read(offset: table.offset, count: table.size)
            else { continue }
            if table.name == "__swift5_assocty" {
                mangledNames += try validateAssociatedTypeTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: path
                )
            } else if table.name == "__swift5_builtin" {
                mangledNames += try validateBuiltinTypeTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: path
                )

            } else if table.name == "__swift5_fieldmd" {
                mangledNames += try validateFieldDescriptorTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: path
                )
            } else if table.name == "__swift5_mpenum" {
                mangledNames += try validateMultiPayloadEnumTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: path
                )
            } else {
                try validateRelativePointerTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize,
                    name: table.name, path: path, code: codeRanges(prefix: prefix)
                )
            }
        }

        // The mangled type names those records point at, parsed from there.
        if !mangledNames.isEmpty,
           let typeref = sectionTable(prefix: prefix)?.sections.first(where: { $0.name == "__swift5_typeref" }),
           typeref.size > 0, typeref.offset <= fileSize, typeref.size <= fileSize - typeref.offset,
           let bytes = image.read(offset: typeref.offset, count: typeref.size) {
            try validateMangledNames(
                at: mangledNames, in: bytes, sectionOffset: typeref.offset, sectionAddress: typeref.addr,
                segments: mappedSegments(prefix: prefix), name: "__swift5_typeref", path: path
            )
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
    /// How a pointer slot in one of the Objective-C pointer arrays is stored.
    enum PointerEncoding: Equatable {
        /// No chained fixups: the slot holds the unslid target address.
        case plain
        /// `DYLD_CHAINED_PTR_64` (2) or `DYLD_CHAINED_PTR_64_OFFSET` (6).
        case chained(format: UInt16, imageBase: UInt64, imports: UInt32)
    }

    /// Where an Objective-C pointer-array slot points: the unslid address of
    /// a rebase, `bind` for a bind within the import table, or nil when the
    /// encoding is one this check does not decode (it then declines).
    enum PointerTarget: Equatable { case address(UInt64), bind, badBind(UInt32), undecoded, unchained(UInt64) }

    static func decodePointer(_ raw: UInt64, _ encoding: PointerEncoding) -> PointerTarget {
        switch encoding {
        case .plain:
            return .address(raw)
        case .chained(let format, let imageBase, let imports):
            switch format {
            case 2, 6:
                if raw >> 63 != 0 {
                    let ordinal = UInt32(raw & 0xff_ffff)
                    return ordinal < imports ? .bind : .badBind(ordinal)
                }
                let target = raw & 0xf_ffff_ffff
                return .address(format == 2 ? target | ((raw >> 36) & 0xff) << 56 : imageBase &+ target)
            case 1, 9, 12:
                // arm64e (`fixup-chains.h`): bit 63 auth, bit 62 bind. A bind's
                // ordinal is 16 bits, 24 in USERLAND24. An authenticated rebase
                // holds a 32-bit offset from the image base; a plain one a
                // 43-bit target (a vmaddr in DYLD_CHAINED_PTR_ARM64E, an offset
                // in the USERLAND formats) with the top byte at bits 43-50.
                let auth = raw >> 63 != 0
                if (raw >> 62) & 1 != 0 {
                    let ordinal = UInt32(raw & (format == 12 ? 0xff_ffff : 0xffff))
                    return ordinal < imports ? .bind : .badBind(ordinal)
                }
                if auth { return .address(imageBase &+ (raw & 0xffff_ffff)) }
                let target = raw & 0x7ff_ffff_ffff
                let high8 = ((raw >> 43) & 0xff) << 56
                return .address((format == 1 ? target : imageBase &+ target) | high8)
            default:
                return .undecoded
            }
        }
    }

    /// The Objective-C pointer arrays: `__objc_selrefs`, `__objc_classlist`,
    /// `__objc_nlclslist` and `__objc_catlist`. Every slot is a pointer, so
    /// unlike `__objc_const`/`__objc_data` (which interleave flags, sizes and
    /// offsets) each can be checked without a struct walk. A rebase must land
    /// in the section that kind of slot always names, and a bind's ordinal
    /// must be inside the import table. Measured on 571 real thin binaries:
    /// every selref lands in `__objc_methname` (453k slots), every class-list
    /// entry in `__objc_data` or `__data`, every category in `__objc_const`.
    /// A corrupt slot sent MachOObjCSection to parse a class or category out of
    /// arbitrary memory (SIGSEGV/SIGTRAP in `objc`, `layout`, `disasm`,
    /// `analyze`; `metadata-fuzz.py sample.release 150 4242`).
    /// The protocol, class-reference and non-lazy category arrays follow the
    /// same rule, measured over 4,101 binaries including fat slices (objcsweep,
    /// the 1,609 universal binaries under /Applications, the 1,434 arm64e
    /// system binaries): protocols in `__data` or `__objc_const`, class and
    /// superclass references in `__objc_data` (superclass refs also `__data`),
    /// each 8-aligned. Only the two reference arrays hold nulls (`nullable`).
    /// A corrupt `__objc_protolist` slot trapped MachOObjCSection's file
    /// reader (`metadata-fuzz.py` on the arm64e slice of Stickies, 60 11).
    static func validateObjCPointerArray(
        bytes: Data, name: String, encoding: PointerEncoding,
        allowed: [(name: String, addr: UInt64, size: Int)], path: String = "<data>",
        nullable: Bool = false, address: UInt64 = 0, chainEntries: ChainEntries? = nil
    ) throws {
        for index in stride(from: 0, to: bytes.count - bytes.count % 8, by: 8) {
            guard let raw = bytes.u64(at: index) else { break }
            if raw == 0, nullable { continue }
            // In a chained image a pointer slot holds a fixup only if a chain
            // reaches it; otherwise MachOKit reads its bits as a plain address.
            if raw != 0, let chainEntries, !chainEntries.contains(address &+ UInt64(index)) {
                throw BinaryLoadError(
                    "Malformed Mach-O: \(path) — \(name)[\(index / 8)] holds 0x\(String(raw, radix: 16)) outside every fixup chain"
                )
            }
            switch decodePointer(raw, encoding) {
            case .undecoded, .bind, .unchained:
                continue
            case .badBind(let ordinal):
                throw BinaryLoadError(
                    "Malformed Mach-O: \(path) — \(name)[\(index / 8)] binds import \(ordinal), past the import table"
                )
            case .address(let target):
                // Classes and categories are pointer-aligned objects; a
                // misaligned target is the middle of one (fuzz mutants 19, 47).
                // Selector strings carry no alignment.
                if name != "__objc_selrefs", target % 8 != 0 {
                    throw BinaryLoadError(
                        "Malformed Mach-O: \(path) — \(name)[\(index / 8)] points at 0x\(String(target, radix: 16)), not pointer-aligned"
                    )
                }
                guard allowed.contains(where: { target >= $0.addr && target < $0.addr &+ UInt64($0.size) }) else {
                    let names = allowed.map(\.name).joined(separator: " or ")
                    throw BinaryLoadError(
                        "Malformed Mach-O: \(path) — \(name)[\(index / 8)] points at 0x\(String(target, radix: 16)), outside \(names)"
                    )
                }
            }
        }
    }

    /// Reads 8-byte pointer fields out of loaded sections by unslid address,
    /// decoding them with the encoding of the segment each one sits in.
    struct PointerReader {
        var sections: [(name: String, addr: UInt64, size: Int, segment: Int, bytes: Data?)]
        var encodings: [Int: PointerEncoding]
        var chainEntries: ChainEntries? = nil

        func section(containing address: UInt64) -> Int? {
            sections.firstIndex { address >= $0.addr && address < $0.addr &+ UInt64($0.size) }
        }

        /// The decoded field at `address`, nil when it is not in a loaded
        /// section or its segment's encoding is unknown. A raw zero is null: a
        /// field outside every fixup chain.
        func field(at address: UInt64) -> PointerTarget?? {
            guard let index = section(containing: address), let bytes = sections[index].bytes,
                  let encoding = encodings[sections[index].segment],
                  let raw = bytes.u64(at: Int(address - sections[index].addr))
            else { return nil }
            if raw == 0 { return .some(nil) }
            if let chainEntries, !chainEntries.contains(address) { return .some(.unchained(raw)) }
            return .some(MachOPreflight.decodePointer(raw, encoding))
        }

        /// A raw 32-bit word at `address` with the section it lies in, nil when
        /// outside the loaded sections.
        func word(at address: UInt64) -> (value: UInt32, section: Int)? {
            guard let index = section(containing: address), let bytes = sections[index].bytes,
                  let value = bytes.u32(at: Int(address - sections[index].addr))
            else { return nil }
            return (value, index)
        }
    }

    /// The Objective-C classes the class lists name, with their metaclasses
    /// and read-only data, walked through the fields that are always pointers.
    /// `__objc_const` and `__objc_data` interleave those with flags, sizes and
    /// offsets, so only these fields are checked, each against the sections it
    /// lands in across 44,323 classes in 1,058 real thin binaries (see the
    /// table in docs/PRODUCTION-READINESS.md). A corrupt one sent
    /// MachOObjCSection to parse a class, its data, or a name out of
    /// arbitrary memory (`metadata-fuzz.py sample.release 150 4242`).
    static func validateObjCClasses(
        _ classes: [UInt64], protocols: [UInt64] = [], reader: PointerReader, path: String = "<data>"
    ) throws {
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — Objective-C \(why)")
        }
        /// Checks the pointer field at `address`; returns its (masked) target
        /// when it is a rebase, nil for null, a bind, or an undecoded field.
        @discardableResult
        func check(
            _ address: UInt64, _ what: String, in names: Set<String>,
            null: Bool = true, bind: Bool = true, mask: UInt64 = 0, aligned: Bool = true
        ) throws -> UInt64? {
            guard let decoded = reader.field(at: address) else { return nil }
            guard let target = decoded else {
                if null { return nil }
                throw fail("\(what) at 0x\(String(address, radix: 16)) is null")
            }
            switch target {
            case .undecoded: return nil
            case .unchained(let raw):
                throw fail("\(what) at 0x\(String(address, radix: 16)) holds 0x\(String(raw, radix: 16)) outside every fixup chain")
            case .bind: if bind { return nil }; throw fail("\(what) at 0x\(String(address, radix: 16)) is a bind")
            case .badBind(let ordinal): throw fail("\(what) at 0x\(String(address, radix: 16)) binds import \(ordinal), past the import table")
            case .address(let raw):
                let value = raw & ~mask
                guard let index = reader.section(containing: value), names.contains(reader.sections[index].name),
                      !aligned || value % 8 == 0
                else {
                    throw fail("\(what) at 0x\(String(address, radix: 16)) points at 0x\(String(value, radix: 16)), not into \(names.sorted().joined(separator: " or "))")
                }
                return value
            }
        }
        /// A list's header (`entsizeAndFlags`, `count`): the entry size this
        /// kind of list always has, and every entry inside the list's section.
        func listEntries(_ list: UInt64, _ what: String, entsize expected: Int) throws -> [UInt64] {
            guard let header = reader.word(at: list), let count = reader.word(at: list + 4) else { return [] }
            let entsize = Int(header.value & 0xfffc)
            guard entsize == expected else {
                throw fail("\(what) at 0x\(String(list, radix: 16)) declares \(entsize)-byte entries, not \(expected)")
            }
            let section = reader.sections[header.section]
            let end = section.addr &+ UInt64(section.size)
            let (span, overflow) = UInt64(count.value).multipliedReportingOverflow(by: UInt64(entsize))
            guard !overflow, list + 8 <= end, span <= end - list - 8 else {
                throw fail("\(what) at 0x\(String(list, radix: 16)) declares \(count.value) entries, past its section's end")
            }
            return (0..<UInt64(count.value)).map { list + 8 + $0 * UInt64(entsize) }
        }
        let classSections: Set<String> = ["__objc_data", "__data"]
        let strings: Set<String> = ["__objc_classname", "__cstring", "__const"]
        // x86_64 slices also keep ivar and property names in `__TEXT,__const`
        // (7 in the 1,609 universal binaries under /Applications).
        let names: Set<String> = ["__objc_methname", "__cstring", "__const"]
        /// A `class_ro_t`, of a class or a metaclass. No field of one, and no
        /// list entry it reaches, is ever a bind in the measured binaries.
        func walkReadOnlyData(_ ro: UInt64) throws {
            try check(ro + 16, "ivar layout", in: ["__cstring", "__objc_classname"], bind: false, aligned: false)
            try check(ro + 24, "class name", in: strings, null: false, bind: false, aligned: false)
            // x86_64 slices keep pointer-based method lists in `__objc_data`
            // (all 86 such lists in the arm64e sweep's fat system binaries).
            try check(ro + 32, "method list", in: ["__objc_methlist", "__objc_const", "__objc_methname", "__objc_data"],
                      bind: false, mask: 7)
            let protocols = try check(ro + 40, "protocol list", in: ["__objc_const"], bind: false)
            let ivars = try check(ro + 48, "ivar list", in: ["__objc_const"], bind: false)
            try check(ro + 56, "weak ivar layout", in: ["__cstring", "__objc_classname"], bind: false, aligned: false)
            let properties = try check(ro + 64, "property list", in: ["__objc_const"], bind: false)
            // `protocol_list_t`: a 64-bit count, then that many protocol
            // pointers (into `__data` or `__objc_const` in all 8,684 measured
            // lists). A corrupt count had MachOObjCSection read 7e16 entries
            // (`try!` in its file reader; fuzz libReconstruction.opt 777, mutant 44).
            if let protocols, let low = reader.word(at: protocols), let high = reader.word(at: protocols + 4) {
                let count = UInt64(high.value) << 32 | UInt64(low.value)
                let section = reader.sections[low.section]
                let end = section.addr &+ UInt64(section.size)
                let (span, overflow) = count.multipliedReportingOverflow(by: 8)
                guard !overflow, protocols + 8 <= end, span <= end - protocols - 8 else {
                    throw fail("protocol list at 0x\(String(protocols, radix: 16)) declares \(count) protocols, past its section's end")
                }
                for entry in 0..<count {
                    try check(protocols + 8 + 8 * entry, "protocol", in: ["__data", "__objc_const"], bind: false)
                }
            }
            // `ivar_t`: the offset variable, name, type (then alignment, size).
            if let ivars {
                for ivar in try listEntries(ivars, "ivar list", entsize: 32) {
                    try check(ivar, "ivar offset", in: ["__objc_ivar", "__const", "__data", "__common", "__bss"],
                              bind: false, aligned: false)
                    try check(ivar + 8, "ivar name", in: names, null: false, bind: false, aligned: false)
                    try check(ivar + 16, "ivar type", in: ["__objc_methtype", "__cstring"], bind: false, aligned: false)
                }
            }
            // `property_t`: name, attributes.
            if let properties {
                for property in try listEntries(properties, "property list", entsize: 16) {
                    try check(property, "property name", in: names, null: false, bind: false, aligned: false)
                    try check(property + 8, "property attributes", in: names, bind: false, aligned: false)
                }
            }
        }
        for cls in classes {
            let isa = try check(cls, "class isa", in: classSections, null: false, bind: false)
            try check(cls + 8, "superclass", in: classSections)
            // `cache` is always bound to `_objc_empty_cache` or null, `vtable`
            // always null, in every measured class and metaclass.
            try check(cls + 16, "class cache", in: [])
            try check(cls + 24, "class vtable", in: [], bind: false)
            let data = try check(cls + 32, "class data", in: ["__objc_const", "__objc_data"], null: false,
                                 bind: false, mask: 7)
            if let isa {
                try check(isa, "metaclass isa", in: ["__objc_data"])
                try check(isa + 8, "metaclass superclass", in: classSections)
                try check(isa + 16, "metaclass cache", in: [])
                try check(isa + 24, "metaclass vtable", in: [], bind: false)
                if let metaRO = try check(isa + 32, "metaclass data", in: ["__objc_const"], null: false,
                                          bind: false, mask: 7) {
                    try walkReadOnlyData(metaRO)
                }
            }
            if let ro = data { try walkReadOnlyData(ro) }
        }
        // `protocol_t`: isa, name, protocols, four method lists, instance
        // properties, then `size` and `flags`, then (when `size` reaches them)
        // extended method types, demangled name, class properties. Measured
        // over every protocol the 4,101 binaries' protocol lists name: isa
        // always null, no field ever a bind, `size` 80, 88 or 96. A list slot
        // aimed into the middle of a protocol had MachOObjCSection read its
        // fields out of whatever lay there (`try!` in its file reader;
        // `metadata-fuzz.py` on the arm64e slice of Stickies, 60 11, mutant 38).
        let methodLists: Set<String> = ["__objc_methlist", "__objc_const", "__objc_data"]
        for proto in protocols {
            guard let size = reader.word(at: proto + 64) else { continue }
            let section = reader.sections[size.section]
            let end = section.addr &+ UInt64(section.size)
            guard size.value >= 72, size.value <= 4096, proto + UInt64(size.value) <= end else {
                throw fail("protocol at 0x\(String(proto, radix: 16)) declares \(size.value) bytes, not a protocol in its section")
            }
            try check(proto, "protocol isa", in: [])
            try check(proto + 8, "protocol name", in: strings, null: false, bind: false, aligned: false)
            try check(proto + 16, "protocol's protocol list", in: ["__objc_const"], bind: false)
            for (offset, what) in [(24, "instance"), (32, "class"), (40, "optional instance"), (48, "optional class")] {
                try check(proto + UInt64(offset), "protocol \(what) method list", in: methodLists, bind: false)
            }
            try check(proto + 56, "protocol instance properties", in: ["__objc_const"], bind: false)
            if size.value >= 80 {
                try check(proto + 72, "protocol extended method types", in: ["__objc_const"], bind: false)
            }
            if size.value >= 88 {
                try check(proto + 80, "protocol demangled name", in: strings, bind: false, aligned: false)
            }
            if size.value >= 96 {
                try check(proto + 88, "protocol class properties", in: ["__objc_const"], bind: false)
            }
        }
    }

    /// The VM ranges of every mapped segment (`vmsize > 0`) of a thin
    /// little-endian image.
    static func mappedSegments(prefix: Data) -> [Range<UInt64>] {
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE,
              let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20)
        else { return [] }
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        var cursor = Layout.machHeader64
        var ranges: [Range<UInt64>] = []
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { break }
            if cmd == Command.segment64, let vmaddr = prefix.u64(at: cursor + 24),
               let vmsize = prefix.u64(at: cursor + 32), vmsize > 0 {
                let (end, overflow) = vmaddr.addingReportingOverflow(vmsize)
                if !overflow { ranges.append(vmaddr..<end) }
            }
            cursor += Int(cmdsize)
        }
        return ranges
    }

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
        selrefs: (addr: UInt64, size: Int), path: String = "<data>",
        sectionOffset: Int? = nil, fileSize: Int? = nil
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
                    // The type encoding (a string in `__objc_methtype`) and the
                    // IMP sit in `__TEXT` beside the list, so their offsets
                    // resolve in file space. A types offset flipped out of the
                    // file sent `strlen` off the mapping (`metadata-fuzz.py
                    // sample.release 150 4242`, mutant 105).
                    if let sectionOffset, let fileSize {
                        for (slot, what) in [(4, "type encoding"), (8, "implementation")] {
                            guard let delta = bytes.u32(at: field + slot) else { break }
                            let resolved = sectionOffset + field + slot + Int(Int32(bitPattern: delta))
                            guard resolved >= 0, resolved < fileSize else {
                                throw fail(
                                    "list at +\(cursor) method \(method)'s \(what) is a relative pointer to offset \(resolved), outside the \(fileSize)-byte file"
                                )
                            }
                        }
                    }
                }
            }
            cursor += 8 + span
        }
    }

    /// File ranges of every section that holds instructions
    /// (`S_ATTR_PURE_INSTRUCTIONS` or `S_ATTR_SOME_INSTRUCTIONS`) in a thin
    /// little-endian image.
    static func codeRanges(prefix: Data) -> [Range<Int>] {
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE,
              let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20)
        else { return [] }
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        var cursor = Layout.machHeader64
        var ranges: [Range<Int>] = []
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { break }
            if cmd == Command.segment64, let nsects = prefix.u32(at: cursor + 64) {
                for section in 0..<Int(nsects) {
                    let base = cursor + 72 + section * 80
                    guard base + 80 <= limit, let size = prefix.u64(at: base + 40),
                          let offset = prefix.u32(at: base + 48), let flags = prefix.u32(at: base + 64)
                    else { break }
                    if flags & 0x8000_0400 != 0, size > 0, size < UInt64(Int.max) - UInt64(offset) {
                        ranges.append(Int(offset)..<(Int(offset) + Int(size)))
                    }
                }
            }
            cursor += Int(cmdsize)
        }
        return ranges
    }

    /// Every section's `(segment index, name, vmaddr, file offset, size)`,
    /// and the `__TEXT` vmaddr, of a thin little-endian image.
    static func sectionTable(prefix: Data) -> (sections: [(segment: Int, name: String, addr: UInt64, offset: Int, size: Int)], textBase: UInt64)? {
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE,
              let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20)
        else { return nil }
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        var cursor = Layout.machHeader64
        var sections: [(segment: Int, name: String, addr: UInt64, offset: Int, size: Int)] = []
        var segment = 0
        var textBase: UInt64 = 0
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { return nil }
            if cmd == Command.segment64, let nsects = prefix.u32(at: cursor + 64) {
                if segmentName(at: cursor, prefix: prefix) == "__TEXT", let vmaddr = prefix.u64(at: cursor + 24) {
                    textBase = vmaddr
                }
                for section in 0..<Int(nsects) {
                    let base = cursor + 72 + section * 80
                    guard base + 80 <= limit,
                          let addr = prefix.u64(at: base + 32), let size = prefix.u64(at: base + 40),
                          let offset = prefix.u32(at: base + 48)
                    else { return nil }
                    let raw = prefix[(prefix.startIndex + base)..<(prefix.startIndex + base + 16)]
                    let name = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                    sections.append((segment, name, addr, Int(offset), Int(clamping: size)))
                }
                segment += 1
            }
            cursor += Int(cmdsize)
        }
        return (sections, textBase)
    }

    /// Each segment command's `(vmaddr, fileoff, filesize)`, in command
    /// order: the order chained fixups index segments by.
    static func segmentRanges(prefix: Data) -> [(vmaddr: UInt64, offset: Int, size: Int)] {
        guard let magic = prefix.u32(at: 0), magic == Magic.machO64LE,
              let ncmds = prefix.u32(at: 16), let sizeofcmds = prefix.u32(at: 20)
        else { return [] }
        let limit = min(Layout.machHeader64 + Int(sizeofcmds), prefix.count)
        var cursor = Layout.machHeader64
        var ranges: [(vmaddr: UInt64, offset: Int, size: Int)] = []
        for _ in 0..<Int(ncmds) {
            guard cursor + Layout.minLoadCommand <= limit,
                  let cmd = prefix.u32(at: cursor), let cmdsize = prefix.u32(at: cursor + 4),
                  cmdsize >= UInt32(Layout.minLoadCommand)
            else { break }
            if cmd == Command.segment64, let vmaddr = prefix.u64(at: cursor + 24),
               let offset = prefix.u64(at: cursor + 40), let size = prefix.u64(at: cursor + 48) {
                ranges.append((vmaddr, Int(clamping: offset), Int(clamping: size)))
            }
            cursor += Int(cmdsize)
        }
        return ranges
    }

    /// The slots fixup chains reach, by unslid address: a bit per 4-byte
    /// word of each segment that has chains.
    struct ChainEntries {
        var segments: [(vmaddr: UInt64, size: Int, bits: [UInt64])] = []

        func contains(_ address: UInt64) -> Bool {
            for segment in segments where address >= segment.vmaddr && address - segment.vmaddr < UInt64(segment.size) {
                let word = Int((address - segment.vmaddr) / 4)
                return segment.bits[word / 64] & (1 << UInt64(word % 64)) != 0
            }
            return false
        }

        mutating func insert(segment: Int, offset: Int) {
            let word = offset / 4
            segments[segment].bits[word / 64] |= 1 << UInt64(word % 64)
        }
    }

    /// Every fixup chain, walked the way dyld walks it: from each page's
    /// `page_start`, following `next` (12 bits, 4-byte stride, for
    /// `DYLD_CHAINED_PTR_64`/`_64_OFFSET`; 11 bits, 8-byte stride, for the
    /// arm64e formats) until it is zero. A chain must end inside its page,
    /// reach only 4-byte-aligned slots, and bind only imports the table has.
    /// Returns the slots it reached, which are the only ones dyld rewrites:
    /// a nonzero pointer slot outside them is read by MachOKit as a plain
    /// address. That is what the `metadata-fuzz.py sample.release 150 99`
    /// mutants (3 and 131) do: a flipped `next` bit skips slots, and a
    /// MachOObjCSection `try!` traps on the raw chained value in one.
    static func validateFixupChains(
        blob: Data, startsOffset: Int, segmentCount: Int,
        readSegment: (Int) -> (vmaddr: UInt64, data: Data)?, path: String = "<data>"
    ) throws -> ChainEntries {
        let imports = blob.u32(at: 16) ?? 0
        var entries = ChainEntries()
        for segment in 0..<segmentCount {
            guard let start = blob.u32(at: startsOffset + 4 + 4 * segment), start != 0 else { continue }
            let base = startsOffset + Int(start)
            guard let pageSize = blob.u16(at: base + 4), let format = blob.u16(at: base + 6),
                  let pageCount = blob.u16(at: base + 20), pageSize >= 8
            else { continue }
            let stride: Int
            let nextMask: UInt64
            switch format {
            case 2, 6: (stride, nextMask) = (4, 0xfff)
            case 1, 9, 12: (stride, nextMask) = (8, 0x7ff)
            default: continue                       // a format this check does not walk
            }
            guard let (vmaddr, data) = readSegment(segment) else { continue }
            entries.segments.append((vmaddr, data.count, Array(repeating: 0, count: data.count / 256 + 1)))
            let index = entries.segments.count - 1
            for page in 0..<Int(pageCount) {
                guard let first = blob.u16(at: base + 22 + 2 * page) else { break }
                if first == 0xffff || first & 0x8000 != 0 { continue }   // none, or 32-bit multi-starts
                var offset = Int(first)
                while true {
                    let slot = page * Int(pageSize) + offset
                    guard offset % 4 == 0 else {
                        throw BinaryLoadError(
                            "Malformed Mach-O: \(path) — fixup chain in segment \(segment), page \(page) lands on misaligned +\(offset)"
                        )
                    }
                    guard offset + 8 <= Int(pageSize), let raw = data.u64(at: slot) else {
                        throw BinaryLoadError(
                            "Malformed Mach-O: \(path) — fixup chain in segment \(segment), page \(page) runs past its page at +\(offset)"
                        )
                    }
                    entries.insert(segment: index, offset: slot)
                    if case .badBind(let ordinal) = decodePointer(raw, .chained(format: format, imageBase: 0, imports: imports)) {
                        throw BinaryLoadError(
                            "Malformed Mach-O: \(path) — fixup in segment \(segment), page \(page) at +\(offset) binds import \(ordinal), past the import table"
                        )
                    }
                    let next = Int((raw >> 51) & nextMask)
                    if next == 0 { break }
                    offset += next * stride
                }
            }
        }
        return entries
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
            // Not flat, but walked by their own record layouts; see
            // `validateAssociatedTypeTable` and `validateMultiPayloadEnumTable`.
            "__swift5_assocty", "__swift5_mpenum", "__swift5_fieldmd",
            "__swift5_builtin",
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
    @discardableResult
    static func validateAssociatedTypeTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws -> [Int] {
        var names: [Int] = []
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — __swift5_assocty \(why)")
        }
        @discardableResult
        func checkPointer(at offset: Int, _ what: String) throws -> Int {
            guard let raw = bytes.u32(at: offset) else { throw fail("\(what) is truncated") }
            let target = sectionOffset + offset + Int(Int32(bitPattern: raw))
            guard target >= 0, target < fileSize else {
                throw fail("\(what) is a relative pointer to offset \(target), outside the \(fileSize)-byte file")
            }
            return target
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
            names.append(try checkPointer(at: cursor, "descriptor \(descriptor)'s conforming type name"))
            names.append(try checkPointer(at: cursor + 4, "descriptor \(descriptor)'s protocol name"))
            for record in 0..<Int(count) {
                let base = cursor + 16 + record * 8
                try checkPointer(at: base, "descriptor \(descriptor) record \(record)'s name")
                names.append(try checkPointer(at: base + 4, "descriptor \(descriptor) record \(record)'s type"))
            }
            cursor += 16 + body
            descriptor += 1
        }
        return names
    }

    /// `__swift5_builtin`: 20-byte `BuiltinTypeDescriptor`s (swift/include/
    /// swift/RemoteInspection/Records.h:396), a relative `TypeName` then four
    /// 32-bit layout numbers. A `TypeName` resolving outside the file trapped
    /// `dump`, `interface`, `objc` and `layout` (`metadata-fuzz.py
    /// libReconstruction.opt.dylib 150 777`).
    @discardableResult
    static func validateBuiltinTypeTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws -> [Int] {
        var names: [Int] = []
        guard bytes.count % 20 == 0 else {
            throw BinaryLoadError(
                "Malformed Mach-O: \(path) — __swift5_builtin is \(bytes.count) bytes, not a whole number of 20-byte descriptors"
            )
        }
        for record in stride(from: 0, to: bytes.count, by: 20) {
            guard let raw = bytes.u32(at: record) else { break }
            let target = sectionOffset + record + Int(Int32(bitPattern: raw))
            guard target >= 0, target < fileSize else {
                throw BinaryLoadError(
                    "Malformed Mach-O: \(path) — __swift5_builtin descriptor \(record / 20)'s type name is a relative pointer to offset \(target), outside the \(fileSize)-byte file"
                )
            }
            names.append(target)
        }
        return names
    }

    /// Mangled names, each parsed from a start the metadata records point
    /// at, by the symbolic-reference grammar (swift/docs/ABI/Mangling.rst:76):
    /// `\x01`-`\x17` is followed by a 4-byte relative offset (which may
    /// contain NULs), `\x18`-`\x1F` by an 8-byte absolute pointer, `\xFF` is
    /// padding, and a NUL ends the name. A corrupt relative reference trapped
    /// `dump` and `interface` with `Negative value is not representable`
    /// (`metadata-fuzz.py libReconstruction.opt.dylib 150 777`).
    ///
    /// Only from those starts: `__swift5_typeref` is not a plain string table
    /// (current toolchains place 16-byte-aligned binary records between the
    /// names), and walking it front to back misread record bytes as
    /// references, falsely rejecting 130 of 832 real binaries.
    ///
    /// References resolve in VM space: an indirect one (`\x02`) names a GOT
    /// slot in `__DATA_CONST`, whose VM address need not track its file
    /// offset. Each must land in a mapped segment.
    static func validateMangledNames(
        at starts: [Int], in bytes: Data, sectionOffset: Int, sectionAddress: UInt64,
        segments: [Range<UInt64>], name: String, path: String = "<data>"
    ) throws {
        for start in Set(starts) {
            var cursor = start - sectionOffset
            guard cursor >= 0, cursor < bytes.count else { continue }   // not a name in this section
            while cursor < bytes.count {
                let byte = bytes[bytes.startIndex + cursor]
                if byte == 0 { break }
                switch byte {
                case 0x01...0x17:
                    guard let raw = bytes.u32(at: cursor + 1) else {
                        throw BinaryLoadError(
                            "Malformed Mach-O: \(path) — \(name) symbolic reference at +\(cursor) is cut off by the section's end"
                        )
                    }
                    let target = (sectionAddress &+ UInt64(cursor + 1)) &+ UInt64(bitPattern: Int64(Int32(bitPattern: raw)))
                    guard segments.contains(where: { $0.contains(target) }) else {
                        throw BinaryLoadError(
                            "Malformed Mach-O: \(path) — \(name) symbolic reference at +\(cursor) points to 0x\(String(target, radix: 16)), outside every mapped segment"
                        )
                    }
                    cursor += 5
                case 0x18...0x1F:
                    cursor += 9
                default:
                    cursor += 1
                }
            }
        }
    }

    /// `__swift5_fieldmd`, walked by its record layout. Each `FieldDescriptor`
    /// (swift/include/swift/RemoteInspection/Records.h:206) is relative
    /// `MangledTypeName` and `Superclass` pointers, `Kind` (u16),
    /// `FieldRecordSize` (u16, emitted as 12), `NumFields` (u32), then that
    /// many `FieldRecord`s: `Flags`, relative `MangledTypeName` and
    /// `FieldName`. A pointer resolving outside the file trapped `objc`,
    /// `layout`, `disasm`, `xrefs` and `analyze` with `Negative value is not
    /// representable` (`metadata-fuzz.py sample.release 150 4242`, mutant 5).
    @discardableResult
    static func validateFieldDescriptorTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws -> [Int] {
        var names: [Int] = []
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — __swift5_fieldmd \(why)")
        }
        @discardableResult
        func checkPointer(at offset: Int, _ what: String) throws -> Int {
            guard let raw = bytes.u32(at: offset) else { throw fail("\(what) is truncated") }
            let target = sectionOffset + offset + Int(Int32(bitPattern: raw))
            guard target >= 0, target < fileSize else {
                throw fail("\(what) is a relative pointer to offset \(target), outside the \(fileSize)-byte file")
            }
            return target
        }
        var cursor = 0
        var descriptor = 0
        while cursor < bytes.count {
            guard cursor + 16 <= bytes.count, let sizes = bytes.u32(at: cursor + 8),
                  let count = bytes.u32(at: cursor + 12)
            else { throw fail("descriptor \(descriptor) is truncated") }
            let recordSize = Int(sizes >> 16)
            guard recordSize == 12 else {
                throw fail("descriptor \(descriptor) declares \(recordSize)-byte records, not 12")
            }
            let (body, overflow) = Int(count).multipliedReportingOverflow(by: 12)
            guard !overflow, body <= bytes.count - cursor - 16 else {
                throw fail("descriptor \(descriptor) declares \(count) field(s), past the section's end")
            }
            names.append(try checkPointer(at: cursor, "descriptor \(descriptor)'s type name"))
            names.append(try checkPointer(at: cursor + 4, "descriptor \(descriptor)'s superclass"))
            for field in 0..<Int(count) {
                let base = cursor + 16 + field * 12
                names.append(try checkPointer(at: base + 4, "descriptor \(descriptor) field \(field)'s type"))
                try checkPointer(at: base + 8, "descriptor \(descriptor) field \(field)'s name")
            }
            cursor += 16 + body
            descriptor += 1
        }
        return names
    }

    /// `__swift5_mpenum`, walked by its record layout. Each
    /// `MultiPayloadEnumDescriptor` (swift/include/swift/RemoteInspection/
    /// Records.h:427) is a relative `TypeName` pointer, then
    /// `contents[0] >> 16` 32-bit words (the runtime asserts that is
    /// non-zero), so a descriptor is `4 + 4 * words` bytes. A `TypeName`
    /// resolving outside the file trapped `objc`, `disasm` and `analyze` with
    /// `Negative value is not representable` in `MangledName.resolve`
    /// (fuzz mutant 19).
    @discardableResult
    static func validateMultiPayloadEnumTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws -> [Int] {
        var names: [Int] = []
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — __swift5_mpenum \(why)")
        }
        var cursor = 0
        var descriptor = 0
        while cursor < bytes.count {
            guard cursor + 8 <= bytes.count, let typeName = bytes.u32(at: cursor),
                  let sizeFlags = bytes.u32(at: cursor + 4)
            else { throw fail("descriptor \(descriptor) is truncated") }
            let words = Int(sizeFlags >> 16)
            guard words > 0, 4 + 4 * words <= bytes.count - cursor else {
                throw fail("descriptor \(descriptor) declares \(words) content word(s), not fitting the section")
            }
            let target = sectionOffset + cursor + Int(Int32(bitPattern: typeName))
            guard target >= 0, target < fileSize else {
                throw fail(
                    "descriptor \(descriptor)'s type name is a relative pointer to offset \(target), outside the \(fileSize)-byte file"
                )
            }
            // With the spare-bits flag set, the mask's byte count is the next
            // word and the mask must fit the record; the runtime asserts
            // `byteCount <= (words - 2) * 4` (Records.h, getPayloadSpareBitMaskByteCount).
            // MachOSwiftSection indexes it unchecked: "Index out of range" in
            // `analyze` (metadata-fuzz libReconstruction.opt.dylib 150 777, mutant 88).
            if sizeFlags & 1 != 0 {
                guard words >= 2, let maskWord = bytes.u32(at: cursor + 8) else {
                    throw fail("descriptor \(descriptor) uses payload spare bits but has no mask-size word")
                }
                let maskBytes = Int(maskWord & 0xffff)
                guard maskBytes <= (words - 2) * 4 else {
                    throw fail("descriptor \(descriptor)'s \(maskBytes)-byte spare-bit mask does not fit its \(words - 2) remaining word(s)")
                }
            }
            names.append(target)
            cursor += 4 + 4 * words
            descriptor += 1
        }
        return names
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
        bytes: Data, sectionOffset: Int, fileSize: Int, name: String, path: String = "<data>",
        code: [Range<Int>] = []
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
            // Descriptors are 4-byte-aligned records. A conformance record is
            // a plain relative pointer, so a misaligned one is the middle of a
            // descriptor (`metadata-fuzz.py libReconstruction.resilient.dylib
            // 150 31`, mutants 64 and 124). Type and protocol records carry
            // tag bits in the low two (`TargetTypeMetadataRecord`'s
            // TypeReferenceKind; `TargetProtocolRecord`'s indirect and
            // reserved bits, ABI/Metadata.h), set in system binaries such as
            // Music.app, so only the bits above them are checked there.
            let tagBits = name == "__swift5_proto" ? 0 : 3
            let descriptor = target & ~tagBits
            guard descriptor % 4 == 0 else {
                throw BinaryLoadError(
                    """
                    Malformed Mach-O: \(path) — \(name)[\(index / 4)] points at offset \(target), \
                    not a 4-byte-aligned descriptor
                    """
                )
            }
            // Each entry names a descriptor, which is data. One aimed into an
            // instruction section is parsed out of machine code, and the
            // pointers read from it trap (`resolveBind(fileOffset:)` on a
            // negative offset; `metadata-fuzz.py sample.release 150 4242`).
            if let range = code.first(where: { $0.contains(descriptor) }) {
                throw BinaryLoadError(
                    """
                    Malformed Mach-O: \(path) — \(name)[\(index / 4)] points at offset \(target), \
                    inside instructions (\(range.lowerBound)..<\(range.upperBound)), not a descriptor
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
        case let cmd where Command.dylibCommands.contains(cmd):
            try validateDylib(at: offset, prefix: prefix, bigEndian: bigEndian, index: index, fail: fail)
        default:
            break
        }
    }

    /// A dylib command's name must lie inside the command itself.
    ///
    /// `struct dylib.name` is an `lc_str`: an offset from the start of the
    /// command to a NUL-terminated path that the command's own `cmdsize`
    /// covers. MachOKit's `DylibCommand.dylib(in:)` reads that string with
    /// `try! readString(offset: commandOffset + name.offset, size: cmdsize -
    /// name.offset)`, so an offset past `cmdsize` is an uncatchable trap
    /// (`FileIOBinary/_FileIOProtocol+.swift:242`, `offsetOutOfBounds`).
    /// Confirmed live at the MachOSwiftSection 0.22.0 pin: its class dumper
    /// walks the ObjC ancestor chain, which reads `MachOFile.dependencies`,
    /// which decodes every dylib command. `container-fuzz.py libSample.dylib
    /// 150 7` mutant 63 (LC_LOAD_WEAK_DYLIB name offset's top byte) and
    /// `sample.release 150 7` mutant 104 (LC_LOAD_DYLIB name offset's third
    /// byte) each killed `dump` and `interface` by SIGTRAP; 0.19.0 never read
    /// dependencies on that path, so the same mutants only failed cleanly there.
    private static func validateDylib(
        at offset: Int, prefix: Data, bigEndian: Bool, index: Int, fail: (String) -> BinaryLoadError
    ) throws {
        guard let cmdsize = prefix.u32(at: offset + 4, bigEndian: bigEndian),
              let nameOffset = prefix.u32(at: offset + 8, bigEndian: bigEndian)
        else { return }   // beyond the prefix: our limit, not a bad file
        guard nameOffset >= UInt32(Command.dylibCommandHeader), nameOffset < cmdsize else {
            throw fail(
                "load command \(index) puts its dylib name at offset \(nameOffset) of a \(cmdsize)-byte command"
            )
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
    func u16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

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
