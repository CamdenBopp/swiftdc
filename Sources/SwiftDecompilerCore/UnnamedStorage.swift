import MachOKit
import MachOSwiftSection

/// Cases or stored fields a descriptor counts and no field record names.
///
/// An `@objc` enum has no field descriptor, and neither has anything built
/// with `-disable-reflection-metadata`. Printing what the records say read as
/// a type with nothing in it: `enum OE {}` for a two-case enum, whose
/// descriptor holds `NumEmptyCases`. The count is the fact; the names are not
/// in the binary.
public enum UnnamedStorage {
    /// What the descriptor counts, or `nil` when it counts nothing or a
    /// record names it.
    static func comment(of type: TypeContextWrapper, in machO: MachOFile) -> String? {
        switch type {
        case .enum(let model):
            let cases = model.descriptor.numberOfCases
            guard cases > 0, hasNoRecords(model.descriptor, in: machO) else { return nil }
            let payloads = model.descriptor.numberOfPayloadCases
            let detail = payloads > 0 ? " (\(payloads) with a payload)" : ""
            return "\(counted(cases, "case"))\(detail): the binary has no field records, so no names"
        case .struct(let model):
            return fieldsComment(Int(model.descriptor.layout.numFields), hasNoRecords(model.descriptor, in: machO))
        case .class(let model):
            return fieldsComment(Int(model.descriptor.layout.numFields), hasNoRecords(model.descriptor, in: machO))
        }
    }

    /// Every type in the image with storage no record names, by display name.
    public static func comments(in machO: MachOFile) -> [(type: String, comment: String)] {
        ((try? machO.swift.types) ?? []).compactMap { type in
            comment(of: type, in: machO).map { (SwiftDeclarationDumper.displayName(of: type, in: machO), $0) }
        }
    }

    /// `text`, a type's `dump`, with the comment first in its body.
    static func placing(_ comment: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let header = lines.first else { return text }
        if header.hasSuffix("{}") {
            lines[0] = String(header.dropLast()) // leaves `… {`
            lines.insert(contentsOf: ["    // \(comment)", "}"], at: 1)
        } else {
            lines.insert(contentsOf: ["    // \(comment)", ""], at: 1)
        }
        return lines.joined(separator: "\n")
    }

    private static func fieldsComment(_ fields: Int, _ hasNoRecords: Bool) -> String? {
        guard fields > 0, hasNoRecords else { return nil }
        return "\(counted(fields, "stored field")): the binary has no field records, so no names"
    }

    private static func hasNoRecords(_ descriptor: some TypeContextDescriptorProtocol, in machO: MachOFile) -> Bool {
        ((try? descriptor.fieldDescriptor(in: machO).records(in: machO)) ?? []).isEmpty
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
