import Foundation
import MachOKit

/// Whether an image was compiled with library evolution
/// (`-enable-library-evolution`, `BUILD_LIBRARY_FOR_DISTRIBUTION`).
///
/// In such a module every public struct and enum that is not `@frozen` is
/// resilient, and a resilient type is address-only at every function
/// boundary, inside its own module too (swift/lib/SIL/IR/TypeLowering.cpp,
/// `handleResilience`): it is passed and returned through a pointer, never
/// as its fields in registers. `f(_ s: RS, _ k: Int) { k &* 3 }` takes k in
/// x1, and read with `s` exploded it rendered `return (arg0.b + (arg0.b <<
/// 1))`.
///
/// A resilient build has the same symbol NAMES as a plain one for structs.
/// The evidence, among the symbols the image defines, is what only a
/// resilient build emits:
/// - an `enum case for …` descriptor (`WC`), for a public enum's cases;
/// - a method dispatch thunk (`Tj`), for a public class or protocol;
/// - a property descriptor (`MV`) holding a stored struct or class
///   component (kinds 1 and 3). Without library evolution a stored
///   property's descriptor is the trivial zero word; a nonzero descriptor
///   alone proves nothing, since a plain module gives `public private(set)
///   var` a computed component (swift/lib/SILGen/SILGen.cpp,
///   `canStorageUseTrivialDescriptor`).
///
/// Which types are resilient, as far as the binary says:
/// - an enum is resilient exactly when its cases have `WC` descriptors: a
///   `@frozen` or internal enum of the same module has none
///   (`resilientself.swift`: `Mode` has three, the frozen `Fixed` none);
/// - a struct has no such mark. One whose nominal type descriptor is not
///   exported is internal, and an internal type is never resilient. An
///   exported one may be `@frozen`, which nothing records, so every
///   exported struct of an image with evidence is treated as possibly
///   resilient and declined.
/// Without evidence the image may still be resilient (public types with
/// no public stored property, enum, class or protocol): that case is not
/// detectable and is recorded as an assumption in
/// docs/PRODUCTION-READINESS.md.
enum LibraryEvolutionEvidence {
    /// The enums with `enum case for …` descriptors, by qualified name.
    static func resilientEnums(in machO: MachOFile) -> Set<String> {
        var names: Set<String> = []
        for symbol in machO.symbols where symbol.offset > 0 && symbol.name.hasSuffix("WC") {
            // `enum case for M.E.c(M.E.Type) -> M.E`, or `… -> (Payload) -> M.E`.
            guard let printed = ResilientWitnessIndex.demangled(symbol.name, dropping: "enum case for "),
                  let close = printed.range(of: ".Type) -> "),
                  let open = printed[..<close.lowerBound].range(of: "(", options: .backwards)
            else { continue }
            names.insert(String(printed[open.upperBound..<close.lowerBound]))
        }
        return names
    }

    /// The nominal types whose descriptor the image exports, by qualified
    /// name. Empty when the image shows no library-evolution evidence.
    static func exportedTypes(in machO: MachOFile) -> Set<String> {
        guard isPresent(in: machO) else { return [] }
        var names: Set<String> = []
        for symbol in machO.symbols where symbol.offset > 0 && symbol.name.hasSuffix("Mn") {
            guard symbol.nlist.flags?.contains(.ext) == true,
                  let name = ResilientWitnessIndex.demangled(symbol.name, dropping: "nominal type descriptor for ")
            else { continue }
            names.insert(name)
        }
        return names
    }

    enum Kind: Hashable, Sendable { case enumCase, dispatchThunk, storedPropertyDescriptor }

    static func isPresent(in machO: MachOFile) -> Bool { !kinds(in: machO).isEmpty }

    /// Every kind of evidence the image shows.
    static func kinds(in machO: MachOFile) -> Set<Kind> {
        var found: Set<Kind> = []
        var propertyDescriptors: Set<UInt64> = []
        for symbol in machO.symbols {
            let name = symbol.name
            // Defined here: every image imports the standard library's own
            // dispatch thunks (`dispatch thunk of Swift.Collection.count.getter`).
            guard symbol.offset > 0, name.hasPrefix("_$s") || name.hasPrefix("$s") else { continue }
            if name.hasSuffix("WC") { found.insert(.enumCase) }
            if name.hasSuffix("Tj") { found.insert(.dispatchThunk) }
            if name.hasSuffix("MV") { propertyDescriptors.insert(UInt64(symbol.offset)) }
        }
        let disassembler = Disassembler()
        for address in propertyDescriptors.sorted() {
            guard let bytes = disassembler.sectionBytes(address: address, size: 4, in: machO), bytes.count == 4
            else { continue }
            let word = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
            if isStoredComponent(word) {
                found.insert(.storedPropertyDescriptor)
                break
            }
        }
        return found
    }

    /// A key path component header's kind is bits 24–30
    /// (swift/stdlib/public/SwiftShims/swift/shims/KeyPath.h): 1 is a
    /// stored struct field, 3 a stored class field.
    static func isStoredComponent(_ header: UInt32) -> Bool {
        let kind = (header >> 24) & 0x7f
        return kind == 1 || kind == 3
    }
}
