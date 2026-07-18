import Foundation
import MachOKit
import MachOObjCSection
import ObjCDump

/// Reconstructs Objective-C declarations (`@interface` / `@protocol` headers)
/// from a Mach-O's ObjC runtime metadata, using MachOObjCSection + ObjCDump.
///
/// Real iOS/macOS apps and frameworks mix Swift and Objective-C; this covers the
/// ObjC half (NSObject-derived and `@objc` classes, protocols, categories) that
/// the Swift metadata dumper does not.
public struct ObjCDumper: Sendable {
    public init() {}

    /// One ObjC header string per class/protocol/category, in that order.
    /// Property-backed accessors are suppressed metadata-only (every one treated
    /// as synthesized); `blocks(_:disassembler:)` refines that with the body.
    public func blocks(_ machO: MachOFile) -> [String] {
        Self.render(ObjCMetadataSnapshot.build(in: machO), isSynthesized: { _ in nil })
    }

    /// Header blocks with disassembly-backed accessor classification: on arm64,
    /// each property-backed accessor's body is disassembled — synthesized ones
    /// (a trivial ivar load/store the `@property` already implies) are dropped,
    /// custom ones are kept and typed from the property. Off arm64 (no disasm)
    /// this is the metadata-only behaviour of `blocks(_:)`.
    public func blocks(_ machO: MachOFile, disassembler: Disassembler) async -> [String] {
        let snapshot = ObjCMetadataSnapshot.build(in: machO)
        guard BinaryLoader.archName(machO).hasPrefix("arm64") else {
            return Self.render(snapshot, isSynthesized: { _ in nil })
        }
        let classification = await Self.classifyAccessors(snapshot, in: machO, disassembler: disassembler)
        return Self.render(snapshot, isSynthesized: { classification[$0] })
    }

    private static func render(
        _ snapshot: ObjCMetadataSnapshot,
        isSynthesized: (UInt64) -> Bool?
    ) -> [String] {
        let classes = snapshot.classes.map { info -> String in
            let withSuper = injectingSuperclass(
                info.headerString, class: info.name,
                superclass: snapshot.superclassBinds[info.name]
            )
            return rewritingPropertyAccessors(withSuper, class: info, isSynthesized: isSynthesized)
        }
        return (classes
            + snapshot.protocols.map(\.headerString)
            + snapshot.categories.map(\.headerString))
            .map(fixingArrayFields)
    }

    /// Move an array dimension the type printer emitted *before* the field name
    /// back to after it: `unsigned long long[5] x3` (invalid C, seen in the
    /// `NSFastEnumerationState` parameter of `countByEnumeratingWithState:`) →
    /// `unsigned long long x3[5]`. Anchored to `[count] identifier`, which a
    /// correctly-placed dimension (`name[5];`) never is, so it only rewrites the
    /// malformed case.
    static func fixingArrayFields(_ header: String) -> String {
        header.replacing(/([A-Za-z_][A-Za-z0-9_ ]*?)\[([0-9]+)\] ([A-Za-z_][A-Za-z0-9_]*)/) { match in
            "\(match.1) \(match.3)[\(match.2)]"
        }
    }

    /// Insert `: Super` into an `@interface` line whose superclass the metadata
    /// left unnamed. `@interface AWEzv {` → `@interface AWEzv : NSObject {`,
    /// `@interface X <P>` → `@interface X : NSObject <P>`. A no-op when there is
    /// no recovered superclass or one is already present.
    static func injectingSuperclass(_ header: String, class name: String, superclass: String?) -> String {
        guard let superclass, !superclass.isEmpty else { return header }
        let prefix = "@interface \(name)"
        guard header.hasPrefix(prefix) else { return header }
        let afterName = header.index(header.startIndex, offsetBy: prefix.count)
        let rest = header[afterName...]
        // The character after the name must be a declaration boundary, so a class
        // name that is a prefix of another (`AWEzv` vs `AWEzvContact`) can't match.
        guard let boundary = rest.first, " <{:\n".contains(boundary) else { return header }
        // Already has a superclass (`@interface X : Super`)? Leave it untouched.
        if rest.drop(while: { $0 == " " }).first == ":" { return header }
        return "\(prefix) : \(superclass)\(rest)"
    }

    /// All ObjC headers joined into a single document.
    public func dump(_ machO: MachOFile) -> String {
        blocks(machO).joined(separator: "\n\n")
    }
}
