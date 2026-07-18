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

    public init(methods: [String: [Int: UInt64]] = [:]) { self.methods = methods }

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

        var methods: [String: [Int: UInt64]] = [:]
        for type in (try? machO.swift.types) ?? [] {
            guard case .class(let model) = type,
                  let header = model.vTableDescriptorHeader,
                  let typeName = try? model.descriptor.name(in: machO)
            else { continue }

            let base = Int(header.layout.vTableOffset)
            for (slot, method) in model.methodDescriptors.enumerated() {
                let relative = Int(method.layout.implementation.relativeOffset)
                // A null relative pointer is a resilient / externally-defined slot.
                guard relative != 0 else { continue }
                let fieldOffset = method.offset + implementationDelta
                let address = machO.address(forOffset: fieldOffset + relative)
                guard address != 0 else { continue }
                let byteOffset = (base + slot) * pointerSize
                if methods[typeName] == nil { methods[typeName] = [:] }
                // First writer wins, mirroring the address→name indexes.
                if methods[typeName]?[byteOffset] == nil {
                    methods[typeName]?[byteOffset] = address
                }
            }
        }
        return VTableIndex(methods: methods)
    }
}
