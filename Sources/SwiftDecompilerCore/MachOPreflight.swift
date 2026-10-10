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
                selrefs: (selrefs.addr, selrefs.size), path: url.path,
                sectionOffset: methlist.offset, fileSize: fileSize
            )
        }

        // The Objective-C pointer arrays, decoded per their segment's
        // chained-fixup pointer format (or as plain addresses without one).
        if let table = sectionTable(prefix: prefix) {
            var formats: [Int: UInt16] = [:]
            var imports: UInt32 = 0
            var chained = false
            if let fixups = chainedFixups(prefix: prefix),
               (try? handle.seek(toOffset: UInt64(fixups.dataoff))) != nil,
               let blob = try? handle.read(upToCount: fixups.datasize), blob.count == fixups.datasize,
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
                      (try? handle.seek(toOffset: UInt64(section.offset))) != nil,
                      let bytes = try? handle.read(upToCount: section.size), bytes.count == section.size
                else { continue }
                try validateObjCPointerArray(
                    bytes: bytes, name: section.name, encoding: encoding, allowed: allowed, path: url.path
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
            let loaded: Set<String> = ["__objc_data", "__data", "__objc_const", "__objc_classlist", "__objc_nlclslist"]
            // (Other sections are named, not read: a field's target only has to
            // land in them.)
            var reader = PointerReader(sections: [], encodings: encodings)
            for section in table.sections {
                var bytes: Data?
                if loaded.contains(section.name), section.size > 0, section.size <= 64 << 20,
                   section.offset <= fileSize, section.size <= fileSize - section.offset,
                   (try? handle.seek(toOffset: UInt64(section.offset))) != nil,
                   let read = try? handle.read(upToCount: section.size), read.count == section.size {
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
            try validateObjCClasses(classes, reader: reader, path: url.path)
        }

        for table in relativePointerTables(prefix: prefix, fileSize: fileSize) {
            guard table.size > 0, let _ = try? handle.seek(toOffset: UInt64(table.offset)),
                  let bytes = try? handle.read(upToCount: table.size), bytes.count == table.size
            else { continue }
            if table.name == "__swift5_assocty" {
                try validateAssociatedTypeTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: url.path
                )
            } else if table.name == "__swift5_fieldmd" {
                try validateFieldDescriptorTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: url.path
                )
            } else if table.name == "__swift5_mpenum" {
                try validateMultiPayloadEnumTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize, path: url.path
                )
            } else {
                try validateRelativePointerTable(
                    bytes: bytes, sectionOffset: table.offset, fileSize: fileSize,
                    name: table.name, path: url.path, code: codeRanges(prefix: prefix)
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
    enum PointerTarget: Equatable { case address(UInt64), bind, badBind(UInt32), undecoded }

    static func decodePointer(_ raw: UInt64, _ encoding: PointerEncoding) -> PointerTarget {
        switch encoding {
        case .plain:
            return .address(raw)
        case .chained(let format, let imageBase, let imports):
            guard format == 2 || format == 6 else { return .undecoded }
            if raw >> 63 != 0 {
                let ordinal = UInt32(raw & 0xff_ffff)
                return ordinal < imports ? .bind : .badBind(ordinal)
            }
            let target = raw & 0xf_ffff_ffff
            return .address(format == 2 ? target | ((raw >> 36) & 0xff) << 56 : imageBase &+ target)
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
    static func validateObjCPointerArray(
        bytes: Data, name: String, encoding: PointerEncoding,
        allowed: [(name: String, addr: UInt64, size: Int)], path: String = "<data>"
    ) throws {
        for index in stride(from: 0, to: bytes.count - bytes.count % 8, by: 8) {
            guard let raw = bytes.u64(at: index) else { break }
            switch decodePointer(raw, encoding) {
            case .undecoded, .bind:
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
            return raw == 0 ? .some(nil) : .some(MachOPreflight.decodePointer(raw, encoding))
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
    static func validateObjCClasses(_ classes: [UInt64], reader: PointerReader, path: String = "<data>") throws {
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
        let names: Set<String> = ["__objc_methname", "__cstring"]
        for cls in classes {
            let isa = try check(cls, "class isa", in: classSections, null: false)
            try check(cls + 8, "superclass", in: classSections)
            // `cache` is always bound to `_objc_empty_cache` or null, `vtable`
            // always null, in every measured class and metaclass.
            try check(cls + 16, "class cache", in: [])
            try check(cls + 24, "class vtable", in: [], bind: false)
            let data = try check(cls + 32, "class data", in: ["__objc_const", "__objc_data"], null: false, mask: 7)
            if let isa {
                try check(isa, "metaclass isa", in: ["__objc_data"])
                try check(isa + 8, "metaclass superclass", in: classSections)
                try check(isa + 16, "metaclass cache", in: [])
                try check(isa + 24, "metaclass vtable", in: [], bind: false)
                try check(isa + 32, "metaclass data", in: ["__objc_const"], null: false, mask: 7)
            }
            guard let ro = data else { continue }
            try check(ro + 16, "ivar layout", in: ["__cstring", "__objc_classname"], aligned: false)
            try check(ro + 24, "class name", in: strings, null: false, aligned: false)
            try check(ro + 32, "method list", in: ["__objc_methlist", "__objc_const", "__objc_methname"], mask: 7)
            try check(ro + 40, "protocol list", in: ["__objc_const"])
            let ivars = try check(ro + 48, "ivar list", in: ["__objc_const"])
            try check(ro + 56, "weak ivar layout", in: ["__cstring", "__objc_classname"], aligned: false)
            let properties = try check(ro + 64, "property list", in: ["__objc_const"])
            // `ivar_t`: the offset variable, name, type (then alignment, size).
            if let ivars {
                for ivar in try listEntries(ivars, "ivar list", entsize: 32) {
                    try check(ivar, "ivar offset", in: ["__objc_ivar", "__const", "__data", "__common", "__bss"],
                              aligned: false)
                    try check(ivar + 8, "ivar name", in: names, null: false, aligned: false)
                    try check(ivar + 16, "ivar type", in: ["__objc_methtype", "__cstring"], aligned: false)
                }
            }
            // `property_t`: name, attributes.
            if let properties {
                for property in try listEntries(properties, "property list", entsize: 16) {
                    try check(property, "property name", in: names, null: false, aligned: false)
                    try check(property + 8, "property attributes", in: names, aligned: false)
                }
            }
        }
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

    /// `__swift5_fieldmd`, walked by its record layout. Each `FieldDescriptor`
    /// (swift/include/swift/RemoteInspection/Records.h:206) is relative
    /// `MangledTypeName` and `Superclass` pointers, `Kind` (u16),
    /// `FieldRecordSize` (u16, emitted as 12), `NumFields` (u32), then that
    /// many `FieldRecord`s: `Flags`, relative `MangledTypeName` and
    /// `FieldName`. A pointer resolving outside the file trapped `objc`,
    /// `layout`, `disasm`, `xrefs` and `analyze` with `Negative value is not
    /// representable` (`metadata-fuzz.py sample.release 150 4242`, mutant 5).
    static func validateFieldDescriptorTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws {
        func fail(_ why: String) -> BinaryLoadError {
            BinaryLoadError("Malformed Mach-O: \(path) — __swift5_fieldmd \(why)")
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
            try checkPointer(at: cursor, "descriptor \(descriptor)'s type name")
            try checkPointer(at: cursor + 4, "descriptor \(descriptor)'s superclass")
            for field in 0..<Int(count) {
                let base = cursor + 16 + field * 12
                try checkPointer(at: base + 4, "descriptor \(descriptor) field \(field)'s type")
                try checkPointer(at: base + 8, "descriptor \(descriptor) field \(field)'s name")
            }
            cursor += 16 + body
            descriptor += 1
        }
    }

    /// `__swift5_mpenum`, walked by its record layout. Each
    /// `MultiPayloadEnumDescriptor` (swift/include/swift/RemoteInspection/
    /// Records.h:427) is a relative `TypeName` pointer, then
    /// `contents[0] >> 16` 32-bit words (the runtime asserts that is
    /// non-zero), so a descriptor is `4 + 4 * words` bytes. A `TypeName`
    /// resolving outside the file trapped `objc`, `disasm` and `analyze` with
    /// `Negative value is not representable` in `MangledName.resolve`
    /// (fuzz mutant 19).
    static func validateMultiPayloadEnumTable(
        bytes: Data, sectionOffset: Int, fileSize: Int, path: String = "<data>"
    ) throws {
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
            cursor += 4 + 4 * words
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
            // Each entry names a descriptor, which is data. One aimed into an
            // instruction section is parsed out of machine code, and the
            // pointers read from it trap (`resolveBind(fileOffset:)` on a
            // negative offset; `metadata-fuzz.py sample.release 150 4242`).
            if let range = code.first(where: { $0.contains(target) }) {
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
