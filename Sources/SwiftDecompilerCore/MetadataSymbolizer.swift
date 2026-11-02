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
        for claim in classMethodClaims(in: machO) + witnessClaims(in: machO) + accessorClaims(in: machO)
            + valueWitnessClaims(in: machO) {
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

    // MARK: - Type metadata accessors

    /// Each type's metadata accessor, which its descriptor points at
    /// (`TypeContextDescriptor.accessFunctionPtr`), named as its symbol
    /// demangles: `type metadata accessor for Sample.Dog`. A local type's
    /// accessor loses its symbol under `strip -x`; libSample.stripped named
    /// 4 of its 11.
    private func accessorClaims(in machO: MachOFile) -> [Claim] {
        var claims: [Claim] = []
        for type in UnrecordedTypes.all(in: machO) {
            let wrapper: TypeContextDescriptorWrapper
            let target: Int?
            switch type {
            case .struct(let m): wrapper = .struct(m.descriptor); target = Self.accessorOffset(of: m.descriptor)
            case .enum(let m): wrapper = .enum(m.descriptor); target = Self.accessorOffset(of: m.descriptor)
            case .class(let m): wrapper = .class(m.descriptor); target = Self.accessorOffset(of: m.descriptor)
            }
            // A local type's demangled context drops the function it is in:
            // `LocalTypes.Outer.LocalDouble` for `LocalDouble #1 in
            // LocalTypes.Outer.makeCounter()`. As in `contextName`, the
            // dropped context is marked, and a name it cannot be placed in
            // is declined.
            guard let target, let typeName = accessorTypeName(of: type, wrapper: wrapper, in: machO) else { continue }
            claims.append(Claim(address: machO.address(forOffset: target), name: "type metadata accessor for \(typeName)",
                                owner: typeName))
        }
        return claims
    }

    // MARK: - Value witnesses

    /// The value witness table's functions in order
    /// (swift/include/swift/ABI/ValueWitness.def), then, for an enum, the
    /// three enum witnesses after the size, stride, flags and extra
    /// inhabitant count.
    static let valueWitnessNames = [
        "initializeBufferWithCopyOfBuffer", "destroy", "initializeWithCopy", "assignWithCopy",
        "initializeWithTake", "assignWithTake", "getEnumTagSinglePayload", "storeEnumTagSinglePayload",
    ]
    static let enumValueWitnessNames = ["getEnumTag", "destructiveProjectEnumData", "destructiveInjectEnumTag"]

    /// Each struct's and enum's value witness functions, named as their
    /// symbols demangle: `destroy value witness for Sample.Tree`. A type's
    /// metadata record is its value witness table pointer, its kind (0x200
    /// a struct, 0x201 an enum) and its descriptor (swift/include/swift/ABI/
    /// Metadata.h), so the record is found by the rebase that points at
    /// the descriptor, and each witness by the rebase in the table's slot.
    /// One function serving several types (a shared `destroy`, a
    /// `__swift_memcpy`) is claimed by each and so declined as a fold.
    /// Standalone images with chained fixups only.
    private func valueWitnessClaims(in machO: MachOFile) -> [Claim] {
        guard machO.cache == nil, machO.dyldChainedFixups != nil,
              let base = machO.segments.first(where: { $0.segmentName == "__TEXT" })?.virtualMemoryAddress
        else { return [] }
        var types: [UInt64: (name: String, isEnum: Bool)] = [:]
        for type in UnrecordedTypes.all(in: machO) {
            let wrapper: TypeContextDescriptorWrapper
            let isEnum: Bool
            switch type {
            case .struct(let m): wrapper = .struct(m.descriptor); isEnum = false
            case .enum(let m): wrapper = .enum(m.descriptor); isEnum = true
            case .class: continue
            }
            guard let name = accessorTypeName(of: type, wrapper: wrapper, in: machO) else { continue }
            let runtime = machO.address(forOffset: SwiftDeclarationDumper.descriptorOffset(of: type)) - UInt64(base)
            types[runtime] = (name, isEnum)
        }
        guard !types.isEmpty else { return [] }
        let table = Disassembler.ChainedFixupTable()
        let rebases = table.allRebases(in: machO)
        func fileOffset(ofRuntime runtime: UInt64) -> UInt64? {
            machO.fileOffset(of: UInt64(base) + runtime).map { UInt64($0) }
        }
        guard let engine = CapstoneEngine() else { return [] }
        var claims: [Claim] = []
        var seenTables: Set<UInt64> = []
        for (slot, target) in rebases.sorted(by: { $0.key < $1.key }) {
            guard let type = types[target], slot >= 16,
                  let kind = UnrecordedTypes.read(Int(slot) - 8, as: UInt64.self, in: machO),
                  kind == (type.isEnum ? 0x201 : 0x200),
                  let tableRuntime = rebases[slot - 16], let tableOffset = fileOffset(ofRuntime: tableRuntime),
                  seenTables.insert(tableOffset).inserted
            else { continue }
            var entries = Self.valueWitnessNames.enumerated().map { (UInt64($0.offset * 8), $0.element) }
            if type.isEnum {
                // After 8 functions: size, stride, flags (4) and extra
                // inhabitants (4).
                entries += Self.enumValueWitnessNames.enumerated().map { (UInt64(88 + $0.offset * 8), $0.element) }
            }
            for (delta, witness) in entries {
                guard let function = rebases[tableOffset + delta],
                      let functionOffset = fileOffset(ofRuntime: function),
                      !Self.isSharedCopyHelper(at: Int(functionOffset), address: UInt64(base) + function,
                                               in: machO, engine: engine),
                      // The copy, destroy, assign and take witnesses are
                      // where IRGen's shared helpers go.
                      delta >= 48 || !Self.isSharedHelperShape(at: Int(functionOffset), address: UInt64(base) + function,
                                                               in: machO, engine: engine)
                else { continue }
                claims.append(Claim(address: UInt64(base) + function,
                                    name: "\(witness) value witness for \(type.name)", owner: type.name))
            }
        }
        return claims
    }

    /// Whether the function at `offset` only copies from x1 to x0, or only
    /// returns: the shape of IRGen's shared `__swift_memcpyN_M` and
    /// `__swift_noop_void_return` helpers, which serve as the copy, take and
    /// destroy witnesses of trivial types. Its witness role is real, but
    /// its identity is the helper (libSample.stripped's `initializeWithTake
    /// value witness for Sample.Circle` is `__swift_memcpy40_8`), so it is
    /// not named for one type.
    static func isSharedCopyHelper(at offset: Int, address: UInt64, in machO: MachOFile,
                                   engine: CapstoneEngine) -> Bool {
        // An unrolled copy of a large type runs long (`__swift_memcpy225_8`).
        var bytes = Data()
        for index in 0 ..< 128 {
            guard let word = UnrecordedTypes.read(offset + index * 4, as: UInt32.self, in: machO) else { break }
            withUnsafeBytes(of: word.littleEndian) { bytes.append(contentsOf: $0) }
        }
        let loads: Set<String> = ["ldr", "ldp", "ldur", "ldrb", "ldrh", "ldurb", "ldurh"]
        let stores: Set<String> = ["str", "stp", "stur", "strb", "strh", "sturb", "sturh"]
        for insn in engine.disassemble(bytes, address: address) {
            if insn.mnemonic == "ret" { return true }
            let base = insn.operands.range(of: "[").map { insn.operands[$0.upperBound...].prefix(2) }
            if loads.contains(insn.mnemonic), base == "x1" { continue }
            if stores.contains(insn.mnemonic), base == "x0" { continue }
            return false
        }
        return false
    }

    /// Whether the function at `offset` has the shape of IRGen's shared
    /// value witness helpers: at most 14 instructions in a straight line (no
    /// conditional branch), its memory reached only through x0, x1, sp, x29
    /// and registers copied from x0 or x1, ending in `ret` or a tail branch. `__swift_memcpy41_8` sets up a
    /// frame and calls `memcpy`; `__swift_destroy_strong` loads x0's word
    /// and branches to `swift_release`; the `assignWith…_strong` helpers
    /// swap one reference. Each served one type in an image as its
    /// initializeWithTake, destroy or assign witness, and was named for it
    /// (358 conflicts in the stripped-name oracle). A type's own copy,
    /// destroy or assign reaches its fields through another register or
    /// branches on them.
    static func isSharedHelperShape(at offset: Int, address: UInt64, in machO: MachOFile,
                                    engine: CapstoneEngine) -> Bool {
        var bytes = Data()
        for index in 0 ..< 14 {
            guard let word = UnrecordedTypes.read(offset + index * 4, as: UInt32.self, in: machO) else { break }
            withUnsafeBytes(of: word.littleEndian) { bytes.append(contentsOf: $0) }
        }
        // A register copied from x0 or x1 is the same base:
        // `__swift_assignWithCopy_strong` keeps x0 in x19 across its calls.
        var bases: Set<Substring> = ["x0", "x1", "sp", "x29"]
        for insn in engine.disassemble(bytes, address: address) {
            if insn.mnemonic == "ret" { return true }
            if insn.mnemonic == "b" { return true }
            if insn.controlFlow == .conditionalBranch { return false }
            if insn.mnemonic == "mov" {
                let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[1] == "x0" || parts[1] == "x1" { bases.insert(Substring(parts[0])) }
            }
            if let open = insn.operands.range(of: "[") {
                let base = insn.operands[open.upperBound...].prefix(while: { $0 != "," && $0 != "]" })
                guard bases.contains(base) else { return false }
            }
        }
        return false
    }

    /// `text` without its `< where …>` groups.
    static func withoutWhereClauses(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "< where ") {
            var depth = 0
            var index = open.lowerBound
            while index < result.endIndex {
                if result[index] == "<" { depth += 1 } else if result[index] == ">" {
                    depth -= 1
                    if depth == 0 { break }
                }
                index = result.index(after: index)
            }
            guard index < result.endIndex else { return result }
            result.removeSubrange(open.lowerBound ... index)
        }
        return result
    }

    /// A type as its accessor's and value witnesses' symbols spell it, or
    /// nil when that cannot be proven.
    private func accessorTypeName(
        of type: TypeContextWrapper, wrapper: TypeContextDescriptorWrapper, in machO: MachOFile
    ) -> String? {
        guard let (own, contexts) = SwiftDeclarationDumper.anonymousAncestors(of: type, in: machO),
              let node = try? SymbolicDemangler.demangleContext(for: .type(wrapper), in: machO.context)
        else { return nil }
        var typeName = node.print(using: .default)
        // An imported type's descriptor does not carry the name its
        // symbol uses (`__C.Options` for `__C.NSRegularExpressionOptions`).
        guard !typeName.isEmpty, !typeName.hasPrefix("__C") else { return nil }
        // An extension's where-clause prints its requirements as the
        // descriptor lists them, which the symbol minimises (`B:
        // Swift.Error` on `Swift.Result`); it is not part of the type's
        // identity, so it is left out.
        typeName = Self.withoutWhereClauses(typeName)
        guard let unwrapped = SwiftDeclarationDumper.withoutPositionName(
            typeName, contexts: contexts, from: typeName.startIndex
        ) else { return nil }
        typeName = unwrapped
        // A name that spells each context by its function reads as a
        // prefix's object (`type metadata accessor for Result #1 in
        // M.T.f()`); a vtable label appends `.kind` to its owner, which on
        // such a name reads as a member of the function's result type, so
        // `contextName` does not take this path.
        if SwiftDeclarationDumper.namesEveryAnonymousContext(node, contexts: contexts) { return typeName }
        if !contexts.isEmpty, !typeName.contains("(unknown context at "), !typeName.contains("(\(own) in _"),
           !SwiftDeclarationDumper.markingUnknownContexts(contexts, in: &typeName, from: typeName.startIndex) {
            return nil
        }
        return typeName
    }

    /// The offset the descriptor's relative accessor pointer leads to, or
    /// nil when it is null.
    private static func accessorOffset(of descriptor: some TypeContextDescriptorProtocol) -> Int? {
        let relative = descriptor.layout.accessFunctionPtr
        guard relative.isValid else { return nil }
        return relative.resolveDirectOffset(from: descriptor.offset + descriptor.layout.offset(of: .accessFunctionPtr))
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
        for type in UnrecordedTypes.all(in: machO) {
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
                record(address, Self.label(typeName, methodKindLabel(method.layout.flags.kind),
                                           isInstance: method.layout.flags.isInstance))
            }
            for override in model.methodOverrideDescriptors {
                guard let offset = override.implementationOffset else { continue }
                // The overridden method's kind is known when its descriptor is
                // in this image; across images it is a symbol, and the slot is
                // labelled only as the override it is.
                if case .element(let base)? = try? override.methodDescriptor(in: machO.context) {
                    record(machO.address(forOffset: offset), Self.label(typeName, methodKindLabel(base.layout.flags.kind),
                                                                        isInstance: base.layout.flags.isInstance))
                } else {
                    record(machO.address(forOffset: offset), "\(typeName).override")
                }
            }
        }
        return claims
    }

    private func contextName(of model: Class, type: TypeContextWrapper, in machO: MachOFile) -> String? {
        // A class declared in a function sits under an anonymous context,
        // which the demangled context drops: LLDB's `OperatorAndGroupVisitor`,
        // local to `OperatorTable.addSourceFile(…)`, named its methods
        // `CompilerSwiftOperators.OperatorTable.OperatorAndGroupVisitor.override`,
        // a member class that does not exist. The context is marked where it
        // was dropped, as `dump` marks it, and a name it cannot be placed in
        // is declined. So is the bare simple name: it reads as top level.
        guard let (own, contexts) = SwiftDeclarationDumper.anonymousAncestors(of: type, in: machO) else { return nil }
        if let node = try? SymbolicDemangler.demangleContext(for: .type(.class(model.descriptor)), in: machO.context) {
            var printed = node.print(using: .default)
            guard let unwrapped = SwiftDeclarationDumper.withoutPositionName(
                printed, contexts: contexts, from: printed.startIndex
            ) else { return nil }
            printed = unwrapped
            if !printed.isEmpty {
                // A private class's context is its file, which the private
                // discriminator already names: `M.(Bundle in _A1B2)`.
                if contexts.isEmpty || printed.contains("(unknown context at ") || printed.contains("(\(own) in _") {
                    return printed
                }
                return SwiftDeclarationDumper.markingUnknownContexts(contexts, in: &printed, from: printed.startIndex)
                    ? printed : nil
            }
        }
        guard contexts.isEmpty else { return nil }
        return FieldMapBuilder.qualifiedName(of: type, in: machO) ?? (try? model.descriptor.name(in: machO))
    }

    /// `T.kind`, or `static T.kind` for a class or static member, as
    /// swift-demangle spells one: `OESystemPlugin.getter` read as an
    /// instance getter for `static pluginExtension`. An initializer is never
    /// spelled static.
    static func label(_ owner: String, _ kind: String, isInstance: Bool) -> String {
        isInstance || kind == "init" ? "\(owner).\(kind)" : "static \(owner).\(kind)"
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
                slots.append((pattern.offset + pointerSize * (index + 1),
                              Self.label(label, kind, isInstance: requirement.layout.flags.isInstance), typeName ?? label))
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
