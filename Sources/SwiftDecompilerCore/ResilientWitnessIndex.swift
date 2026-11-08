import Foundation
import MachOKit
import MachOSwiftSection
import Demangling

/// The resilient witnesses of each conformance to another image's protocol,
/// read from the conformance descriptor.
///
/// A conformance to a protocol outside the image (`Point: Equatable`) lists
/// its witnesses after the descriptor as `ResilientWitness { requirement,
/// implementation }` pairs (swift/include/swift/ABI/Metadata.h,
/// `TargetResilientWitness`). `requirement` is a relative indirectable
/// pointer: for a requirement in another image it leads to a pointer-sized
/// slot that dyld binds to the requirement's method descriptor
/// (`$sSQ2eeoiySbx_xtFZTq`). `implementation` is a direct relative pointer
/// to the witness, the function the runtime installs in the witness table.
///
/// Only requirements reached through such a bound slot are listed: those
/// carry the requirement's name in their bind, and the witness tables of
/// in-image protocols are read from the pattern instead
/// (`MetadataSymbolizer.witnessClaims`), so no witness is claimed twice.
struct ResilientWitnessIndex {
    struct Witness: Equatable {
        /// Address of the slot the requirement pointer leads to. A printer
        /// that names a witness from its requirement alone reports this
        /// address, which is data, never the witness.
        let requirementSlot: UInt64
        /// The requirement as its method descriptor demangles, without the
        /// `method descriptor for ` prefix:
        /// `static Swift.Equatable.== infix(A, A) -> Swift.Bool`.
        let requirementName: String?
        /// The witness's code address, or nil when the implementation
        /// pointer is null or does not lead into a code section (an async
        /// or callee-allocated coroutine requirement's witness is a
        /// function pointer record, which this index does not follow,
        /// because the requirement's flags live in another image).
        let implementation: UInt64?
    }

    struct Conformance {
        /// `sample.Point`: an in-image type as `FieldMapBuilder.qualifiedName`
        /// spells it, or another image's type as its descriptor's bind
        /// demangles. Nil when neither can be built (a private or local
        /// type, whose parent is an anonymous context, or an ObjC class).
        let typeName: String?
        /// The type's own name, `Point`, or nil when even that is unknown.
        let simpleName: String?
        /// Whether the type and every type it is nested in are shown not to
        /// be generic. A generic type's symbols spell its parameters
        /// (`MoveNodesInFrontOfFixIt<A>`), which `typeName` does not.
        let isNonGeneric: Bool
        /// `Swift.Equatable`, from the protocol descriptor's bind.
        let protocolName: String?
        /// Whether the descriptor names a retroactive context: the
        /// conformance is declared in a module that owns neither side.
        let isRetroactive: Bool
        let witnesses: [Witness]
    }

    let conformances: [Conformance]

    init(_ machO: MachOFile) {
        guard let all = try? machO.swift.protocolConformances else {
            conformances = []
            return
        }
        let implementations = MethodImplementation(machO)
        var result: [Conformance] = []
        for conformance in all where !conformance.resilientWitnesses.isEmpty {
            var witnesses: [Witness] = []
            for witness in conformance.resilientWitnesses {
                guard case .symbol(let symbol)? = try? witness.requirement(in: machO.context) else { continue }
                let implementation = witness.implementationOffset
                    .map { machO.address(forOffset: $0) }
                    .flatMap { implementations.code(at: $0, isData: false) }
                witnesses.append(Witness(
                    requirementSlot: machO.address(forOffset: symbol.offset),
                    requirementName: Self.demangled(symbol.name, dropping: "method descriptor for "),
                    implementation: implementation
                ))
            }
            guard !witnesses.isEmpty else { continue }
            let names = Self.conformingTypeNames(conformance, in: machO)
            result.append(Conformance(
                typeName: names.0,
                simpleName: names.1,
                isNonGeneric: names.2,
                protocolName: Self.protocolName(conformance),
                isRetroactive: conformance.retroactiveContextDescriptor != nil,
                witnesses: witnesses
            ))
        }
        conformances = result
    }

    /// `prefix` stripped from the demangling of `symbol`, or nil when the
    /// symbol does not demangle to a name with that prefix.
    static func demangled(_ symbol: String, dropping prefix: String) -> String? {
        let mangled = symbol.hasPrefix("_$s") ? String(symbol.dropFirst()) : symbol
        guard mangled.hasPrefix("$s"), let node = try? demangleAsNode(mangled) else { return nil }
        let printed = node.print(using: .default)
        guard printed.hasPrefix(prefix), printed.count > prefix.count else { return nil }
        return String(printed.dropFirst(prefix.count))
    }

    private static func protocolName(_ conformance: ProtocolConformance) -> String? {
        guard case .symbol(let symbol)? = conformance.protocol else { return nil }
        return demangled(symbol.name, dropping: "protocol descriptor for ")
    }

    /// `(qualified, simple)` names of the conforming type, each nil when it
    /// cannot be read.
    private static func conformingTypeNames(_ conformance: ProtocolConformance, in machO: MachOFile) -> (String?, String?, Bool) {
        guard let resolved = try? conformance.descriptor.resolvedTypeReference(in: machO) else { return (nil, nil, false) }
        func lastComponent(_ name: String?) -> String? {
            guard let name, let last = name.split(separator: ".").last,
                  last.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { return nil }
            return String(last)
        }
        switch resolved {
        case .directTypeDescriptor(let wrapper?), .indirectTypeDescriptor(.element(let wrapper)?):
            guard case .type(let type) = wrapper else { return (nil, nil, false) }
            let simple: String? = switch type {
            case .struct(let descriptor): try? descriptor.name(in: machO)
            case .enum(let descriptor): try? descriptor.name(in: machO)
            case .class(let descriptor): try? descriptor.name(in: machO)
            }
            let context = try? TypeContextWrapper.forTypeContextDescriptorWrapper(type, in: machO.context)
            let qualified = context.flatMap { FieldMapBuilder.qualifiedName(of: $0, in: machO) }
            return (qualified, simple, context.map { isNonGeneric($0, in: machO) } ?? false)
        case .indirectTypeDescriptor(.symbol(let symbol)?):
            // Another image's type: whether it is generic is not read.
            let qualified = demangled(symbol.name, dropping: "nominal type descriptor for ")
            return (qualified, lastComponent(qualified), false)
        default:
            return (nil, nil, false)
        }
    }

    /// Whether `type` and each type it is nested in, up to its module, are
    /// not generic. False when the chain passes through anything else.
    private static func isNonGeneric(_ type: TypeContextWrapper, in machO: MachOFile) -> Bool {
        var current = type
        for _ in 0 ..< 16 {
            let isGeneric: Bool
            let parent: SymbolOrElement<ContextWrapper>?
            switch current {
            case .enum(let m): isGeneric = m.descriptor.layout.flags.isGeneric; parent = try? m.parent(in: machO)
            case .struct(let m): isGeneric = m.descriptor.layout.flags.isGeneric; parent = try? m.parent(in: machO)
            case .class(let m): isGeneric = m.descriptor.layout.flags.isGeneric; parent = try? m.parent(in: machO)
            }
            guard !isGeneric, case .element(let wrapper)? = parent else { return false }
            switch wrapper {
            case .module: return true
            case .type(let next): current = next
            default: return false
            }
        }
        return false
    }
}
