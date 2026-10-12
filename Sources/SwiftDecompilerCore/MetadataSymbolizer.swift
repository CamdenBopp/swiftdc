import Foundation
import MachOKit
import MachOSwiftSection
// `SymbolicDemangler` is SPI. Safe while MachOSwiftSection is exact-pinned;
// re-check it at each bump.
@_spi(Internals) import SwiftInspection
import Demangling

/// Derives function `address → name` mappings from Swift metadata that survives
/// stripping. Two sources:
///   - **Class methods**: each class's vtable entries and overrides, read from
///     its method descriptors and named `<Module.Type>.<kind>`.
///   - **Protocol-conformance witnesses** — read directly from each
///     conformance's witness table, named `<Type>: <Protocol>.<kind>`.
///
/// Struct/enum *non-protocol* methods are intentionally absent: with static
/// dispatch they have no metadata record, so they can't be named from a
/// stripped binary (only their boundaries are recovered, via function-starts).
struct MetadataSymbolizer: Sendable {
    /// Names for the addresses metadata attributes to exactly one owner, and the
    /// candidates for the addresses identical code folding gave several.
    struct Names {
        var unique: [UInt64: String] = [:]
        var folded: [UInt64: [String]] = [:]
    }

    /// One metadata record naming an implementation address. `owner` is the
    /// type's simple name, the one spelling a class method and a witness for
    /// that class share; `isWitness` tells the two sources apart.
    private struct Claim {
        let address: UInt64
        let name: String
        let owner: String
        var isWitness = false
    }

    /// Every address metadata names, classes before witnesses.
    ///
    /// At -O the linker folds identical bodies (`Counter.step.modify` and
    /// `BoxA.Holder.second.modify` share one address), and metadata then names
    /// that address once per owner. Crediting the first reader misnames the
    /// rest, so an address claimed by two owners is folded: no heading or call
    /// is named after either, and the candidates are carried instead. A class
    /// method that is also its own class's witness is one function with two
    /// descriptions, and keeps the class name.
    func functionNames(in machO: MachOFile) -> Names {
        var claims: [UInt64: [Claim]] = [:]
        for claim in classMethodClaims(in: machO) + witnessClaims(in: machO) {
            claims[claim.address, default: []].append(claim)
        }
        var names = Names()
        for (address, list) in claims {
            let methods = list.filter { !$0.isWitness }
            let witnesses = list.filter(\.isWitness)
            let methodNames = Set(methods.map(\.name))
            let attributable: String? = if let method = methods.first {
                // One class method name (two slots of one kind in one class
                // read the same), and every witness is that class's own.
                methodNames.count == 1 && witnesses.allSatisfy { $0.owner == method.owner }
                    ? method.name : nil
            } else {
                Set(witnesses.map(\.name)).count == 1 ? witnesses[0].name : nil
            }
            if let attributable {
                names.unique[address] = attributable
            } else {
                names.folded[address] = Array(Set(list.map(\.name))).sorted()
            }
        }
        return names
    }

    // MARK: - Class vtable methods (via method descriptors)

    /// Each class's own vtable entries and its overrides of a superclass's,
    /// named `Module.Type.<kind>`. Stripped metadata carries no method names,
    /// only kinds, so two methods of one class can share a name; the address
    /// still identifies which body it is.
    ///
    /// This reads the method descriptors directly. It used to scrape the
    /// `sub_<hex>` tokens out of a full SwiftDump of every type, which on
    /// MachOSwiftSection 0.22 walks each class's ObjC ancestry through the
    /// dyld cache: the step that made `xrefs` 6.3x slower on Fiery Feeds.
    private func classMethodClaims(in machO: MachOFile) -> [Claim] {
        let implementationDelta = MemoryLayout<MethodDescriptor.Layout>.offset(of: \.implementation) ?? 4

        // The demangled context spells a class nested in an extension through
        // the extended type (`HTTPTypes.HTTPFields._Storage`) and a private one
        // with its discriminator (`M.(Bundle in _A1B2)`), so two private classes
        // of one name stay apart. When it fails, the parent walk or the simple
        // name stands in, and a name two classes share is dropped rather than
        // credited to either.
        var classes: [(name: String, owner: String, model: Class)] = []
        for type in (try? machO.swift.types) ?? [] {
            guard case .class(let model) = type,
                  let name = contextName(of: model, type: type, in: machO),
                  let owner = try? model.descriptor.name(in: machO)
            else { continue }
            classes.append((name, owner, model))
        }
        var nameCounts: [String: Int] = [:]
        for entry in classes { nameCounts[entry.name, default: 0] += 1 }

        var claims: [Claim] = []
        for (typeName, owner, model) in classes where nameCounts[typeName] == 1 {
            func record(_ address: UInt64, _ name: String) {
                if address != 0 { claims.append(Claim(address: address, name: name, owner: owner)) }
            }
            for method in model.methodDescriptors {
                let relative = Int(method.layout.implementation.relativeOffset)
                // A null relative pointer is a resilient / externally-defined slot.
                guard relative != 0 else { continue }
                let address = machO.address(forOffset: method.offset + implementationDelta + relative)
                record(address, "\(typeName).\(methodKindLabel(method.layout.flags.kind))")
            }
            for override in model.methodOverrideDescriptors {
                guard let offset = override.implementationOffset else { continue }
                // The overridden method's kind is known when its descriptor is
                // in this image; across images it is a symbol, and the slot is
                // labelled only as the override it is.
                let kind: String
                if case .element(let base)? = try? override.methodDescriptor(in: machO.context) {
                    kind = methodKindLabel(base.layout.flags.kind)
                } else {
                    kind = "override"
                }
                record(machO.address(forOffset: offset), "\(typeName).\(kind)")
            }
        }
        return claims
    }

    private func contextName(of model: Class, type: TypeContextWrapper, in machO: MachOFile) -> String? {
        if let node = try? SymbolicDemangler.demangleContext(for: .type(.class(model.descriptor)), in: machO.context) {
            let printed = node.print(using: .default)
            if !printed.isEmpty { return printed }
        }
        return FieldMapBuilder.qualifiedName(of: type, in: machO) ?? (try? model.descriptor.name(in: machO))
    }

    private func methodKindLabel(_ kind: MethodDescriptorKind) -> String {
        switch kind {
        case .method: return "method"
        case .`init`: return "init"
        case .getter: return "getter"
        case .setter: return "setter"
        case .readCoroutine: return "read"
        case .modifyCoroutine: return "modify"
        }
    }

    // MARK: - Protocol-conformance witnesses (via the witness table)

    private func witnessClaims(in machO: MachOFile) -> [Claim] {
        guard let conformances = try? machO.swift.protocolConformances else { return [] }
        let imageBase = machO.address(forOffset: 0)
        let pointerSize = MemoryLayout<UInt64>.size

        // Witness table layout: slot 0 is the conformance descriptor; the
        // requirements' implementations follow at slot (index + 1).
        var slots: [(offset: Int, name: String, owner: String)] = []
        for conformance in conformances {
            guard let protocolDescriptor = conformance.protocol?.resolved,
                  let pattern = conformance.witnessTablePattern,
                  let proto = try? MachOSwiftSection.Protocol(descriptor: protocolDescriptor, in: machO)
            else { continue }
            let protocolName = proto.name
            let typeName = conformingTypeName(conformance, in: machO)
            let label = typeName.map { "\($0): \(protocolName)" } ?? protocolName
            for (index, requirement) in proto.requirements.enumerated() {
                guard let kind = functionKindLabel(requirement.layout.flags.kind) else { continue }
                slots.append((pattern.offset + pointerSize * (index + 1), "\(label).\(kind)", typeName ?? label))
            }
        }
        guard let lowest = slots.map(\.offset).min(), let highest = slots.map(\.offset).max() else { return [] }

        // One walk of the fixup chains for every slot, not one per slot.
        let rebases = ChainedRebases(fileOffsets: lowest ..< highest + pointerSize, in: machO)
        var claims: [Claim] = []
        for slot in slots {
            let runtimeOffset = rebases.map { $0.targets[slot.offset] }
                ?? machO.resolveRebase(at: UInt64(slot.offset))
            guard let runtimeOffset else { continue }
            claims.append(Claim(address: imageBase + runtimeOffset, name: slot.name, owner: slot.owner, isWitness: true))
        }
        return claims
    }

    /// Simple (unqualified) name of the type a conformance is declared on.
    private func conformingTypeName(
        _ conformance: ProtocolConformance,
        in machO: MachOFile
    ) -> String? {
        guard let resolved = try? conformance.descriptor.resolvedTypeReference(in: machO) else {
            return nil
        }
        switch resolved {
        case .directTypeDescriptor(let wrapper):
            return wrapper.flatMap { typeName(of: $0, in: machO) }
        case .directObjCClassName(let name):
            return name
        case .indirectTypeDescriptor, .indirectObjCClass:
            return nil // best-effort: skip indirected references
        }
    }

    private func typeName(of wrapper: ContextDescriptorWrapper, in machO: MachOFile) -> String? {
        guard case .type(let typeWrapper) = wrapper else { return nil }
        switch typeWrapper {
        case .enum(let descriptor): return try? descriptor.name(in: machO)
        case .struct(let descriptor): return try? descriptor.name(in: machO)
        case .class(let descriptor): return try? descriptor.name(in: machO)
        }
    }

    /// Maps a requirement kind to a short label, or nil for non-function
    /// requirements (base protocols, associated-type/conformance accessors).
    private func functionKindLabel(_ kind: ProtocolRequirementKind) -> String? {
        switch kind {
        case .method: return "method"
        case .`init`: return "init"
        case .getter: return "getter"
        case .setter: return "setter"
        case .readCoroutine: return "read"
        case .modifyCoroutine: return "modify"
        case .baseProtocol, .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
            return nil
        }
    }

}
