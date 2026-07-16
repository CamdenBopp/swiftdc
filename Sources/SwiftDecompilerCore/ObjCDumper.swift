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
    public func blocks(_ machO: MachOFile) -> [String] {
        let snapshot = ObjCMetadataSnapshot.build(in: machO)
        return snapshot.classes.map(\.headerString)
            + snapshot.protocols.map(\.headerString)
            + snapshot.categories.map(\.headerString)
    }

    /// All ObjC headers joined into a single document.
    public func dump(_ machO: MachOFile) -> String {
        blocks(machO).joined(separator: "\n\n")
    }
}
