import Foundation
import MachOKit
import MachOSwiftSection

/// How a function receives `self`, and what type that `self` is.
public struct SelfBinding: Sendable, Equatable {
    /// The nominal type whose instance arrives in x20. Naming a field requires
    /// this, so a binding without it is useless — hence non-optional.
    public let selfTypeName: String
    /// What the function is: a method, a property accessor, an initializer.
    public let kind: String
    /// False for static/class methods, where x20 holds the *metatype* and the
    /// instance field map does not apply.
    public let isInstance: Bool
    /// Where this binding came from — the basis for trusting it.
    public let source: Source

    public enum Source: Sendable, Equatable {
        /// A class vtable slot. Survives stripping: `MethodDescriptor` is
        /// `{flags, implementation}` in metadata, not a symbol-table entry.
        case vtableSlot(type: String, slot: Int)
    }
}

/// Maps a function's implementation address to the type of its `self`.
///
/// This is what makes field naming work on a **stripped** binary, and it is the
/// reason the field map is worth having at all: `FieldMap` can say what lives at
/// `+0x20` of a `Dog`, but only this can say that the pointer in x20 *is* a Dog.
///
/// Sourced from class vtables rather than from symbols, deliberately. A method's
/// mangled symbol carries its signature and its type, but `strip -x -S` deletes
/// every internal and private one. The vtable is metadata: the slot still says
/// "this address is class C's slot 3, a getter", which yields C — and therefore
/// C's entire field map — with no symbol at all.
///
/// A lookup **miss** is the honest answer, and is the structural reason this is
/// safe. x20 is not `self` in a reabstraction thunk, a closure invocation
/// function (where it holds a heap-boxed capture context whose layout is nothing
/// like the nominal type's), or a static method (where it holds a metatype).
/// None of those appear in an instance vtable slot, so none of them get a
/// binding, so none of them get a field name. That is a table enforcing the
/// "never invent" rule rather than vigilance enforcing it.
public struct SelfTypeIndex: Sendable {
    private let bindings: [UInt64: SelfBinding]

    public init(bindings: [UInt64: SelfBinding]) { self.bindings = bindings }

    /// The `self` binding for a function's entry address, if it has one.
    public func binding(for implementationAddress: UInt64) -> SelfBinding? {
        bindings[implementationAddress]
    }

    public var count: Int { bindings.count }

    /// Every binding, for `swiftdc layout --self-index`.
    public var all: [(address: UInt64, binding: SelfBinding)] {
        bindings.map { ($0.key, $0.value) }.sorted { $0.address < $1.address }
    }

    /// Build from a binary's Swift class metadata.
    public static func build(in machO: MachOFile) -> SelfTypeIndex {
        // `MethodDescriptor.Layout` is `{ flags, implementation }`; the
        // implementation is a RelativeDirectPointer stored relative to its own
        // location. MachOSwiftSection's own `offset(of:)` helper is `package`,
        // but its body is just this, over public types.
        let implementationDelta = MemoryLayout<MethodDescriptor.Layout>.offset(of: \.implementation) ?? 4

        var bindings: [UInt64: SelfBinding] = [:]
        for type in (try? machO.swift.types) ?? [] {
            guard case .class(let model) = type,
                  let typeName = try? model.descriptor.name(in: machO)
            else { continue }

            for (slot, method) in model.methodDescriptors.enumerated() {
                let fieldOffset = method.offset + implementationDelta
                let relative = Int(method.layout.implementation.relativeOffset)
                // A null relative pointer means the slot has no implementation
                // in this image (a resilient or externally-defined method).
                guard relative != 0 else { continue }
                let address = machO.address(forOffset: fieldOffset + relative)
                guard address != 0, bindings[address] == nil else { continue }

                bindings[address] = SelfBinding(
                    selfTypeName: typeName,
                    kind: Self.describe(method.layout.flags.kind),
                    isInstance: method.layout.flags.isInstance,
                    source: .vtableSlot(type: typeName, slot: slot)
                )
            }
        }
        return SelfTypeIndex(bindings: bindings)
    }

    private static func describe(_ kind: MethodDescriptorKind) -> String {
        switch kind {
        case .method: return "method"
        case .`init`: return "init"
        case .getter: return "getter"
        case .setter: return "setter"
        case .modifyCoroutine: return "modify"
        case .readCoroutine: return "read"
        default: return "\(kind)"
        }
    }
}
