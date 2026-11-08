import Foundation
import MachOKit

/// The classes whose stored fields a free function may name through a
/// parameter: `h.v` in `func read(_ h: Holder)`, where `h` is one pointer
/// register and `v` sits at a constant offset from it.
///
/// An entry is a claim that the demangled name in a signature IS this class,
/// and that its `FieldMap` offsets are what the code uses. So it is keyed by
/// the exact qualified name (never a last-component match, which would hand
/// `Other.Holder` this module's `Holder`). That key is what makes a shared
/// simple name harmless: `A.Shared` and `B.Shared` are different keys, whatever
/// `FieldMapBuilder` did with the simple one, and a private class has no
/// qualified key at all. A class goes in unless its layout is in doubt:
///
/// - a class published with a class metadata base offset (`…CMo`, what library
///   evolution emits, and any class over a resilient base) is out: its offsets
///   are the runtime's to give, through `Wvd` globals.
///
/// A generic class has no entry to find: a bound parameter prints with its
/// arguments (`F.Box<Swift.Int>`), which no key has.
///
/// Field-level declines stay with `FieldMap`: an ObjC or cross-module ancestor
/// leaves no trusted prefix, and an inherited field is not in the map.
struct ClassParameterFieldIndex: Sendable {
    private let maps: [String: FieldMap]

    init(
        fieldMaps: [String: FieldMap] = [:], classTypeIndex: ClassTypeIndex = ClassTypeIndex(),
        runtimeLaidOut: Set<String> = []
    ) {
        var maps: [String: FieldMap] = [:]
        for (name, map) in fieldMaps where name.contains(".") {
            guard classTypeIndex.isClass(name), !classTypeIndex.isValueType(name),
                  !runtimeLaidOut.contains(name)
            else { continue }
            maps[name] = map
        }
        self.maps = maps
    }

    /// The field map of a parameter whose whole type is `typeName`, as the
    /// signature prints it. Anything but a bare class name (`inout F.Holder`,
    /// `Swift.Optional<F.Holder>`, `F.Holder.Type`, `F.Box<Swift.Int>`) is a
    /// different value and has no entry.
    func fieldMap(ofParameterType typeName: String) -> FieldMap? { maps[typeName] }

    static func build(
        in machO: MachOFile, fieldMaps: [String: FieldMap], classTypeIndex: ClassTypeIndex,
        demangle: (String) -> String?
    ) -> ClassParameterFieldIndex {
        var runtimeLaidOut: Set<String> = []
        let basePrefix = "class metadata base offset for "
        for symbol in machO.symbols where symbol.name.hasSuffix("CMo") {
            guard let printed = demangle(symbol.name), printed.hasPrefix(basePrefix) else { continue }
            runtimeLaidOut.insert(String(printed.dropFirst(basePrefix.count)))
        }
        return ClassParameterFieldIndex(fieldMaps: fieldMaps, classTypeIndex: classTypeIndex,
                                        runtimeLaidOut: runtimeLaidOut)
    }
}

extension Disassembler {
    /// The field maps of a free function's class parameters, by argument
    /// index. `scalarArguments` is the register each parameter arrived in, so
    /// only a parameter whose one register is proven gets a map.
    ///
    /// Free functions only: a method's or closure's name has no one reading
    /// here, and neither do specializations, which may have changed what is
    /// passed. An async function's parameters do not stay in registers past
    /// its first suspension.
    static func classArgumentFieldMaps(
        of function: DisassembledFunction, scalarArguments: [String: Int], index: ClassParameterFieldIndex
    ) -> [Int: FieldMap] {
        guard let name = function.analysisName, let signature = DisassembledFunction.splitSignature(name),
              !signature.isAsync,
              let range = DisassembledFunction.outermostArgumentListRange(of: signature.head)
        else { return [:] }
        var head = signature.head[..<range.lowerBound].dropLast()
        if let open = head.firstIndex(of: "<") {
            guard head.hasSuffix(">") else { return [:] }
            head = head[..<open]
        }
        guard head.filter({ $0 == "." }).count == 1,
              head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
        else { return [:] }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature.head[range])
        var maps: [Int: FieldMap] = [:]
        for argument in scalarArguments.values where parameters.indices.contains(argument) {
            maps[argument] = index.fieldMap(ofParameterType: parameterType(parameters[argument]))
        }
        return maps
    }

    /// `arg<n>.field` when a store of `write.bytes` at `offset` from the
    /// write's base is exactly one field of a class argument. The base must be
    /// that argument at this store: a parameter reassigned in the body is not
    /// `.argument` any more, so its stores keep their raw address.
    static func classArgumentFieldTarget(of write: MemoryWrite, offset: Int64, maps: [Int: FieldMap]) -> String? {
        guard !maps.isEmpty, write.kind == "address", write.bytes <= 8,
              write.indexRegister == nil, !write.indexed
        else { return nil }
        let argument: Int, delta: Int64
        switch write.base {
        case .argument(let index):
            (argument, delta) = (index, 0)
        case .binary(.add, .argument(let index), .immediate(let constant)) where constant < 1 << 32:
            (argument, delta) = (index, Int64(constant))
        default:
            return nil
        }
        guard let map = maps[argument], case .success(.whole(let name, _)) =
            map.lookup(offset: Int(delta + offset), bytes: write.bytes)
        else { return nil }
        return "arg\(argument).\(name)"
    }

    /// Per field, the width a load must have to read that field and nothing
    /// else: offset to bytes, for each field one register can hold.
    static func wholeWordFieldWidths(of map: FieldMap) -> [Int: Int] {
        var widths: [Int: Int] = [:]
        for field in map.fields where field.bytes <= 8 {
            if case .success(.whole) = map.lookup(offset: field.offset, bytes: field.bytes) {
                widths[field.offset] = field.bytes
            }
        }
        return widths
    }
}
