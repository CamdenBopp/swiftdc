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
        let objc = machO.objc
        var out: [String] = []

        if machO.is64Bit {
            for cls in objc.classes64 ?? [] {
                if let info = cls.info(in: machO) { out.append(info.headerString) }
            }
            for proto in objc.protocols64 ?? [] {
                if let info = proto.info(in: machO) { out.append(info.headerString) }
            }
            for category in objc.categories64 ?? [] {
                if let info = category.info(in: machO) { out.append(info.headerString) }
            }
        } else {
            for cls in objc.classes32 ?? [] {
                if let info = cls.info(in: machO) { out.append(info.headerString) }
            }
            for proto in objc.protocols32 ?? [] {
                if let info = proto.info(in: machO) { out.append(info.headerString) }
            }
            for category in objc.categories32 ?? [] {
                if let info = category.info(in: machO) { out.append(info.headerString) }
            }
        }
        return out
    }

    /// All ObjC headers joined into a single document.
    public func dump(_ machO: MachOFile) -> String {
        blocks(machO).joined(separator: "\n\n")
    }
}
