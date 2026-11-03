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

    public init(methods: [String: [Int: UInt64]] = [:], genericArguments: [String: (offset: Int, count: Int)] = [:]) {
        self.methods = methods
        self.genericArguments = genericArguments
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
                guard let address = implementations.code(
                    at: machO.address(forOffset: fieldOffset + relative), isData: false
                ) else { continue }
                let byteOffset = (base + slot) * pointerSize
                if methods[typeName] == nil { methods[typeName] = [:] }
                if methods[typeName]?[byteOffset] == nil {
                    methods[typeName]?[byteOffset] = address
                }
            }
        }
        return VTableIndex(methods: methods, genericArguments: genericArguments)
    }
}
