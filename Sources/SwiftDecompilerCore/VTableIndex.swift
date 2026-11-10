import Foundation
import MachOKit
import MachOSwiftSection

/// Maps a class vtable dispatch offset to the method it calls.
///
/// A Swift class instance method dispatches as `ldr x8, [x20]; ldr x8, [x8, #off];
/// blr x8` — load the instance's metadata (its isa at offset 0), load the vtable
/// slot at byte offset `off`, and call it. This resolves `(self's type, off)` to
/// the method's implementation address so the dispatch can be named `Type.method`
/// instead of an unresolved indirect call.
///
/// Only a class's OWN methods are indexed. An inherited method sits at a
/// superclass's vtable offset that this class's descriptor doesn't list, so it is
/// left unresolved — an honest miss, never a wrong name, in keeping with the
/// "never invent" rule the rest of the recovery follows.
///
/// The offset formula is `(vTableDescriptorHeader.vTableOffset + slot) * 8`,
/// verified against a real dispatch: `Vec.x.getter` is slot 0 of a class whose
/// vtable begins at word 12, giving byte `0x60` — exactly the `ldr x8, [x8, #0x60]`
/// the compiler emits.
public struct VTableIndex: Sendable {
    /// typeName → (dispatch byte offset → method implementation address).
    private let methods: [String: [Int: UInt64]]
    /// typeName → where a top-level generic class's generic arguments start
    /// in its metadata (bytes) and how many there are.
    private let genericArguments: [String: (offset: Int, count: Int)]
    /// typeName → the witness tables that follow its parameters' metadata
    /// among its generic arguments, one per key conformance requirement in
    /// generic-signature order: the parameter it is for, and the address of
    /// the protocol's descriptor in this image. Nil for a table whose
    /// protocol or subject is not proven (another image's protocol, an
    /// associated type's conformance).
    private let witnessTables: [String: [WitnessTableArgument?]]

    /// A key witness-table argument: the index of the parameter that
    /// conforms, and the protocol descriptor's address.
    public struct WitnessTableArgument: Sendable, Equatable {
        public let parameter: Int
        public let protocolDescriptor: UInt64
    }

    public init(
        methods: [String: [Int: UInt64]] = [:], genericArguments: [String: (offset: Int, count: Int)] = [:],
        witnessTables: [String: [WitnessTableArgument?]] = [:]
    ) {
        self.methods = methods
        self.genericArguments = genericArguments
        self.witnessTables = witnessTables
    }

    /// The witness table at byte `offset` of a generic class's metadata:
    /// the parameter it is for, as its members' signatures print it, and
    /// the in-image protocol descriptor. A class's key arguments are each
    /// parameter's metadata, then one witness table per key conformance
    /// requirement in generic-signature order
    /// (swift/stdlib/public/runtime/ProtocolConformance.cpp:
    /// `checkGenericRequirement` appends a table for each protocol
    /// requirement that needs one).
    public func witnessTable(type: String, offset: Int) -> (parameter: String, protocolDescriptor: UInt64)? {
        guard let arguments = genericArguments[type], let tables = witnessTables[type],
              offset >= arguments.offset, (offset - arguments.offset) % 8 == 0
        else { return nil }
        let index = (offset - arguments.offset) / 8 - arguments.count
        guard index >= 0, index < tables.count, let table = tables[index],
              table.parameter < arguments.count, table.parameter < 26,
              let scalar = Unicode.Scalar(65 + table.parameter)
        else { return nil }
        return (String(Character(scalar)), table.protocolDescriptor)
    }

    /// The name a class's generic parameter prints as in its members'
    /// demangled signatures (`A`, `B`, …) when byte `offset` of its metadata
    /// is that parameter's metadata. The arguments start at the descriptor's
    /// immediate-members offset for a class without a resilient superclass
    /// (`TargetClassDescriptor::getGenericArgumentOffset`), one word per key
    /// parameter in order.
    public func genericParameter(type: String, offset: Int) -> String? {
        guard let arguments = genericArguments[type], offset >= arguments.offset, (offset - arguments.offset) % 8 == 0
        else { return nil }
        let index = (offset - arguments.offset) / 8
        guard index < arguments.count, index < 26, let scalar = Unicode.Scalar(65 + index) else { return nil }
        return String(Character(scalar))
    }

    public var isEmpty: Bool { methods.isEmpty }

    /// The implementation address a class dispatches to at a vtable byte offset.
    public func methodAddress(type: String, offset: Int) -> UInt64? {
        methods[type]?[offset]
    }

    /// Every implementation address in a class's own vtable — used to build the
    /// set of `self`'s accessors so a dispatch to one renders as `self.property`.
    public func methodAddresses(type: String) -> [UInt64] {
        methods[type].map { Array($0.values) } ?? []
    }

    public static func build(in machO: MachOFile) -> VTableIndex {
        // `MethodDescriptor.Layout` is `{ flags, implementation }`; the
        // implementation is a RelativeDirectPointer stored relative to its own
        // location — the same computation `SelfTypeIndex` uses.
        let implementationDelta = MemoryLayout<MethodDescriptor.Layout>.offset(of: \.implementation) ?? 4
        let pointerSize = MemoryLayout<UInt64>.size

        let implementations = MethodImplementation(machO)
        var methods: [String: [Int: UInt64]] = [:]
        var genericArguments: [String: (offset: Int, count: Int)] = [:]
        var witnessTables: [String: [WitnessTableArgument?]] = [:]
        // Keyed by simple name, so two classes that share one (`Alpha.Node`,
        // `Beta.Node`) would share a slot table: first writer won, and a dispatch
        // in `Beta.Node.work()` rendered `Alpha.Node.launchMissiles()`. A
        // colliding name is dropped instead, so its dispatches decline, as the
        // field-map collision guard does for layouts.
        var descriptorsByName: [String: Set<Int>] = [:]
        for type in UnrecordedTypes.all(in: machO) {
            guard case .class(let model) = type,
                  let typeName = try? model.descriptor.name(in: machO)
            else { continue }
            descriptorsByName[typeName, default: []].insert(model.descriptor.offset)
        }
        for type in UnrecordedTypes.all(in: machO) {
            guard case .class(let model) = type,
                  let typeName = try? model.descriptor.name(in: machO),
                  descriptorsByName[typeName, default: []].count == 1
            else { continue }
            // A top-level generic class (a nested one's parameters include its
            // parent's, which print at another depth), every parameter a key
            // argument, and no resilient superclass, whose bounds only the
            // runtime knows.
            if let generic = model.genericContext, !generic.parameters.isEmpty,
               generic.currentParameters.count == generic.parameters.count,
               generic.parameters.allSatisfy(\.hasKeyArgument), !model.descriptor.hasResilientSuperclass {
                genericArguments[typeName] = (Int(model.descriptor.nonResilientImmediateMembersOffset) * pointerSize,
                                              generic.parameters.count)
                if let tables = keyWitnessTables(of: generic, in: machO) { witnessTables[typeName] = tables }
            }
            guard let header = model.vTableDescriptorHeader else { continue }

            let base = Int(header.layout.vTableOffset)
            for (slot, method) in model.methodDescriptors.enumerated() {
                let relative = Int(method.layout.implementation.relativeOffset)
                // A null relative pointer is a resilient / externally-defined slot.
                guard relative != 0 else { continue }
                let fieldOffset = method.offset + implementationDelta
                // An async (or callee-allocated coroutine) slot holds a
                // function pointer record, which a dispatch loads and then
                // reads the function from (`MethodImplementation`). A `blr`
                // straight to the slot's value calls nothing this table can
                // name, so the field is read as code, which the record is not,
                // and the slot is left out.
                guard let target = machO.relativeAddress(fromOffset: fieldOffset, displacement: relative),
                      let address = implementations.code(at: target, isData: false)
                else { continue }
                let byteOffset = (base + slot) * pointerSize
                if methods[typeName] == nil { methods[typeName] = [:] }
                if methods[typeName]?[byteOffset] == nil {
                    methods[typeName]?[byteOffset] = address
                }
            }
        }
        return VTableIndex(methods: methods, genericArguments: genericArguments, witnessTables: witnessTables)
    }

    /// The key witness tables of a top-level generic context whose
    /// parameters are all plain type parameters with key arguments, or nil
    /// when that layout is not proven: a pack or value parameter (pack
    /// lengths and values change it), a key requirement that is not a
    /// protocol conformance, or a count that disagrees with the header's
    /// key-argument count. Read in a standalone file only.
    static func keyWitnessTables(of generic: TypeGenericContext, in machO: MachOFile) -> [WitnessTableArgument?]? {
        guard machO.cache == nil, generic.typePackHeader == nil, generic.valueHeader == nil,
              generic.parameters.allSatisfy({ $0.kind == .type && $0.hasKeyArgument })
        else { return nil }
        var tables: [WitnessTableArgument?] = []
        for requirement in generic.requirements where requirement.layout.flags.contains(.hasKeyArgument) {
            // GenericRequirementKind::Protocol is 0 (MetadataValues.h). A
            // pack requirement's argument is a pack of tables.
            guard requirement.layout.flags.rawValue & 0x1F == 0,
                  !requirement.layout.flags.contains(.isPackRequirement)
            else { return nil }
            tables.append(protocolTable(requirement, in: machO))
        }
        guard generic.parameters.count + tables.count == Int(generic.header.layout.numKeyArguments) else { return nil }
        return tables
    }

    /// One key conformance requirement's subject parameter and in-image
    /// protocol descriptor. The requirement is `{flags, param, protocol}`,
    /// four bytes each (swift/include/swift/ABI/GenericContext.h). Its
    /// subject must be a depth-0 parameter spelled `x` (0), `q_` (1) or
    /// `q<n-2>_` (n): anything else, `A.Element: P` say, is a table for
    /// another type. The protocol is a relative pointer whose bit 0 marks an
    /// indirect reference (a protocol in another image, reached through a
    /// bind) and bit 1 an Objective-C protocol; either declines.
    private static func protocolTable(_ requirement: GenericRequirementDescriptor, in machO: MachOFile) -> WitnessTableArgument? {
        let base = requirement.offset
        guard let paramRelative = UnrecordedTypes.read(base + 4, as: Int32.self, in: machO),
              let protocolRelative = UnrecordedTypes.read(base + 8, as: Int32.self, in: machO),
              protocolRelative & 3 == 0, protocolRelative != 0
        else { return nil }
        var spelling: [UInt8] = []
        guard let nameOffset = machO.relativeOffset(fromOffset: base + 4, displacement: Int(paramRelative)) else { return nil }
        while spelling.count < 8 {
            guard let byte = UnrecordedTypes.read(nameOffset + spelling.count, as: UInt8.self, in: machO) else { return nil }
            if byte == 0 { break }
            spelling.append(byte)
        }
        guard spelling.count < 8, let text = String(bytes: spelling, encoding: .ascii) else { return nil }
        let parameter: Int
        if text == "x" {
            parameter = 0
        } else if text == "q_" {
            parameter = 1
        } else if text.count > 2, text.hasPrefix("q"), text.hasSuffix("_"),
                  let n = Int(text.dropFirst().dropLast()), n >= 0, String(n) == String(text.dropFirst().dropLast()) {
            parameter = n + 2
        } else {
            return nil
        }
        guard let field = machO.imageAddress(ofOffset: base + 8) else { return nil }
        return WitnessTableArgument(parameter: parameter, protocolDescriptor: UInt64(Int64(field) + Int64(protocolRelative)))
    }
}
