import Foundation
import Demangling
import MachOKit
import MachOSwiftSection
// `SymbolicDemangler` is SPI, as in FieldMap and MetadataSymbolizer.
@_spi(Internals) import SwiftInspection

/// The type a call to `__swift_instantiateConcreteTypeFromMangledNameV2`
/// fetches, read from its second argument: a `{relative offset, length}`
/// pair whose offset, from the pair's own address, leads to the type's
/// mangled name (lib/IRGen/MetadataRequest.cpp; the helper computes the
/// name as `x1 + sext(low word)` and the length as the high word).
enum MangledNamePair {
    /// The demangled type, or nil when the pair or the name cannot be read,
    /// the name's length disagrees with the pair's, or it does not demangle
    /// to a type.
    /// The type a `__swift_instantiateConcreteTypeFromMangledName` demangling
    /// cache variable fetches. Until its first use the variable holds the
    /// relative address of the mangled name and the name's length negated, a
    /// negative 64-bit value marking it uninitialized
    /// (swift/lib/IRGen/MetadataRequest.cpp); the runtime then stores the
    /// metadata there, of the same type.
    static func typeName(
        atCacheVariable address: UInt64, in machO: MachOFile, fixups: Disassembler.ChainedFixupTable = .init()
    ) -> String? {
        guard machO.cache == nil, let fileOffset = machO.fileOffset(of: address),
              let negated = UnrecordedTypes.read(Int(fileOffset) + 4, as: Int32.self, in: machO)
        else { return nil }
        // An initialized (positive) word negates to no length and declines.
        return typeName(at: address, in: machO, length: Int(-Int64(negated)), fixups: fixups)
    }

    static func typeName(
        at address: UInt64, in machO: MachOFile, fixups: Disassembler.ChainedFixupTable = .init()
    ) -> String? {
        typeName(at: address, in: machO, length: nil, fixups: fixups)
    }

    /// `length` is the name's length when the pair's second word is not it.
    private static func typeName(
        at address: UInt64, in machO: MachOFile, length knownLength: Int?, fixups: Disassembler.ChainedFixupTable
    ) -> String? {
        let offset: Int
        if let cache = machO.cache {
            offset = Int(address) - Int(cache.mainCacheHeader.sharedRegionStart)
        } else {
            guard let fileOffset = machO.fileOffset(of: address) else { return nil }
            offset = Int(fileOffset)
        }
        guard let relative = UnrecordedTypes.read(offset, as: Int32.self, in: machO),
              let length = knownLength.map({ Int32(clamping: $0) }) ?? UnrecordedTypes.read(offset + 4, as: Int32.self, in: machO),
              length > 0,
              byteLength(at: offset + Int(relative), in: machO) == Int(length),
              machO.cache == nil,
              referencesAreSound(
                  nameAddress: UInt64(Int64(address) + Int64(relative)), length: Int(length), in: machO, fixups: fixups),
              let name = try? MangledName.resolve(at: offset + Int(relative), in: machO.context),
              let node = try? SymbolicDemangler.demangleType(for: name, in: machO.context)
        else { return nil }
        let printed = node.print(using: .default)
        guard !printed.isEmpty, !printed.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        return printed
    }

    /// Whether every symbolic reference in the name at `nameAddress` leads
    /// where the demangler can follow it without reading outside the file,
    /// which traps in MachOKit (`Negative value is not representable`). The
    /// name must lie in `__swift5_typeref`, where IRGen puts them; its
    /// direct references must pass the preflight check every
    /// record-reached name passes (a mapped target that is a context
    /// descriptor); and each indirect reference's slot must be a bind or a
    /// rebase onto such a descriptor. A fuzzed pair offset moved a name so
    /// its `\x02` reference read the wrong slot, and its `\x01` one a
    /// "module" whose name lay at -2063597537 (`Tools/fuzz.swift metadata`
    /// on libMangledTypes.stripped and libSample.stripped with `__const`
    /// in reach, seed 777: mutants 56 and 11).
    ///
    /// `fixups` is the image's chained-fixup table. It is built by walking
    /// every chain of the image, so a run passes the one its resolver holds:
    /// a fresh table per name was 89% of a GoodLinks `xrefs` sample.
    static func referencesAreSound(
        nameAddress: UInt64, length: Int, in machO: MachOFile, fixups: Disassembler.ChainedFixupTable = .init()
    ) -> Bool {
        guard let typeref = machO.sections.first(where: { $0.segmentName == "__TEXT" && $0.sectionName == "__swift5_typeref" }),
              nameAddress >= UInt64(typeref.address),
              nameAddress + UInt64(length) < UInt64(typeref.address + typeref.size),
              let sectionOffset = machO.fileOffset(of: UInt64(typeref.address))
        else { return false }
        let segments: [Range<UInt64>] = machO.segments.map {
            UInt64($0.virtualMemoryAddress) ..< UInt64($0.virtualMemoryAddress + $0.virtualMemorySize)
        }
        func read(_ address: UInt64, _ count: Int) -> Data? {
            guard segments.contains(where: { $0.contains(address) && $0.contains(address + UInt64(max(count, 1)) - 1) }),
                  let start = machO.fileOffset(of: address)
            else { return nil }
            var bytes = Data()
            for index in 0 ..< count {
                guard let byte = UnrecordedTypes.read(Int(start) + index, as: UInt8.self, in: machO) else { return nil }
                bytes.append(byte)
            }
            return bytes
        }
        guard let bytes = read(nameAddress, length + 1) else { return false }
        do {
            try MachOPreflight.validateMangledNames(
                at: [Int(sectionOffset) + Int(nameAddress - UInt64(typeref.address))], in: bytes,
                sectionOffset: Int(sectionOffset) + Int(nameAddress - UInt64(typeref.address)),
                sectionAddress: nameAddress, segments: segments, name: "__swift5_typeref", read: read)
        } catch {
            return false
        }
        // Indirect references: the slot is a bind (another image's
        // descriptor, which the demangler names from the symbol) or a
        // rebase onto a context descriptor of this file.
        let base = machO.segments.first(where: { $0.segmentName == "__TEXT" }).map { UInt64($0.virtualMemoryAddress) } ?? 0
        var cursor = 0
        while cursor < length {
            let byte = bytes[cursor]
            switch byte {
            case 0x01 ... 0x17:
                guard let raw = bytes.u32(at: cursor + 1) else { return false }
                if byte == 0x02 {
                    let slot = (nameAddress &+ UInt64(cursor + 1)) &+ UInt64(bitPattern: Int64(Int32(bitPattern: raw)))
                    guard let slotOffset = machO.fileOffset(of: slot) else { return false }
                    if fixups.symbol(at: UInt64(slotOffset), in: machO) == nil {
                        guard let target = fixups.rebaseTarget(at: UInt64(slotOffset), in: machO),
                              (try? MachOPreflight.validateContextDescriptor(
                                  at: base &+ target, read: read, segments: segments, path: "<image>",
                                  what: "indirect reference")) != nil
                        else { return false }
                    }
                }
                cursor += 5
            case 0x18 ... 0x1F:
                // An absolute reference names an address in process.
                return false
            default:
                cursor += 1
            }
        }
        return true
    }

    /// The bytes of the mangled name at `offset` before its terminator, a
    /// symbolic reference counted as its marker and its 4-byte (0x01-0x17)
    /// or 8-byte (0x18-0x1F) operand, as `MangledName.resolve` reads it.
    /// Nil past 4 KB or on an unreadable byte.
    static func byteLength(at offset: Int, in machO: MachOFile) -> Int? {
        var length = 0
        while length < 4096 {
            guard let byte = UnrecordedTypes.read(offset + length, as: UInt8.self, in: machO) else { return nil }
            switch byte {
            case 0: return length
            case 0x01 ... 0x17: length += 5
            case 0x18 ... 0x1F: length += 9
            default: length += 1
            }
        }
        return nil
    }
}
