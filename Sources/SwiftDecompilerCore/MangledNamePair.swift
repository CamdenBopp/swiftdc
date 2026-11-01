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
    static func typeName(at address: UInt64, in machO: MachOFile) -> String? {
        let offset: Int
        if let cache = machO.cache {
            offset = Int(address) - Int(cache.mainCacheHeader.sharedRegionStart)
        } else {
            guard let fileOffset = machO.fileOffset(of: address) else { return nil }
            offset = Int(fileOffset)
        }
        guard let relative = UnrecordedTypes.read(offset, as: Int32.self, in: machO),
              let length = UnrecordedTypes.read(offset + 4, as: Int32.self, in: machO), length > 0,
              byteLength(at: offset + Int(relative), in: machO) == Int(length),
              let name = try? MangledName.resolve(at: offset + Int(relative), in: machO.context),
              let node = try? SymbolicDemangler.demangleType(for: name, in: machO.context)
        else { return nil }
        let printed = node.print(using: .default)
        guard !printed.isEmpty, !printed.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        return printed
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
