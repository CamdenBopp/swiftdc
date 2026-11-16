import Foundation
import MachOKit

/// Checks every `// Address: 0x…` comment `interface --member-addresses`
/// prints, and declines the ones that are not a function.
///
/// The interface printer (MachOSwiftSection) prints a member's address from
/// the symbol it attributed the member to. In a stripped image a witness of
/// a conformance to another image's protocol has no symbol of its own, so
/// the indexer names it from its requirement: the symbol is the requirement's
/// bind, and its "address" is the slot that bind fills, in
/// `__DATA_CONST,__const`. `sample.stripped` printed `0x1000084B0` for both
/// `Point: Equatable` and `Direction: Equatable` `==`, the one slot bound to
/// `$sSQ2eeoiySbx_xtFZTq`, where the true witnesses are `0x100001164` and
/// `0x100001508`.
///
/// Rules, in order, for each address comment:
/// 1. An address in a code section at a function start (`LC_FUNCTION_STARTS`;
///    a defined symbol when the image has no such list) is kept.
/// 2. An address a `…Tu` symbol names is an async function pointer record,
///    whose first word is a relative pointer to the function: the function
///    it leads to is printed, if that passes rule 1.
/// 3. Inside `extension T: P`, an address that is the requirement slot of a
///    witness of the one conformance of `T` to `P`
///    (`ResilientWitnessIndex`) is replaced by that witness's
///    implementation, if that passes rule 1.
/// 4. In a `protocol` body the address is a requirement's method
///    descriptor, and a requirement has no code: the comment is dropped.
/// 5. Anything else prints `?`: an address that cannot be shown to be the
///    member's code is declined rather than shown.
struct MemberAddressAudit {
    /// What the audit did, for tests and diagnostics.
    struct Counts: Equatable {
        var kept = 0
        var recovered = 0
        var declined = 0
        /// Requirement descriptors in a protocol body, dropped.
        var requirements = 0
    }

    private let codeRanges: MethodImplementation
    private let functionStarts: Set<UInt64>
    private let witnesses: ResilientWitnessIndex
    /// Defined symbols outside code, by address, the first name kept.
    private let dataSymbols: [UInt64: String]

    init(_ machO: MachOFile) {
        codeRanges = MethodImplementation(machO)
        var starts = Set(Disassembler.linkerFunctionStarts(of: machO))
        let declaresStarts = !starts.isEmpty
        var data: [UInt64: String] = [:]
        for symbol in machO.symbols where !symbol.name.isEmpty {
            guard let address = Disassembler.sectionAddress(of: symbol) else { continue }
            if codeRanges.isCode(address) {
                // No LC_FUNCTION_STARTS: a defined symbol is the only
                // evidence that an address begins a function.
                if !declaresStarts { starts.insert(address) }
            } else if data[address] == nil {
                data[address] = symbol.name
            }
        }
        functionStarts = starts
        dataSymbols = data
        witnesses = ResilientWitnessIndex(machO)
    }

    func isFunctionStart(_ address: UInt64) -> Bool {
        codeRanges.isCode(address) && functionStarts.contains(address)
    }

    /// The function an async function pointer record at `address` leads
    /// to, when a `…Tu` symbol names the record and the function is a
    /// function start.
    func asyncFunction(at address: UInt64) -> UInt64? {
        guard let name = dataSymbols[address], Self.namesAsyncFunctionPointer(name),
              let function = codeRanges.code(at: address, isData: true), isFunctionStart(function)
        else { return nil }
        return function
    }

    /// Whether `symbol` is a Swift async function pointer record (`…Tu`).
    /// Any other data's first word is not a relative pointer to code.
    static func namesAsyncFunctionPointer(_ symbol: String) -> Bool {
        (symbol.hasPrefix("_$s") || symbol.hasPrefix("$s")) && symbol.hasSuffix("Tu")
    }

    /// `text` with every address comment checked.
    func audit(_ text: String) -> (text: String, counts: Counts) {
        var counts = Counts()
        var header: (type: String, protocol: String)?
        var inProtocol = false
        var lines: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if !line.isEmpty, !line.hasPrefix(" ") {
                // A top-level line opens or closes a block; only an
                // `extension T: P` block has witnesses. A blank line
                // separates members inside a block.
                header = Self.extensionHeader(line)
                inProtocol = line.hasPrefix("protocol ")
            }
            guard let comment = Self.addressComment(line) else {
                lines.append(line)
                continue
            }
            let address = comment.address
            if isFunctionStart(address) {
                counts.kept += 1
                lines.append(line)
            } else if let function = asyncFunction(at: address) {
                counts.recovered += 1
                lines.append(comment.prefix + "0x" + String(function, radix: 16, uppercase: true))
            } else if inProtocol {
                // A requirement has no code: the printer's address is its
                // method descriptor (`…Tq`). Nothing is printed, which is
                // not the same as a `?` for code that exists but was not
                // found.
                counts.requirements += 1
            } else if let header, let witness = witness(at: address, type: header.type, protocol: header.protocol) {
                counts.recovered += 1
                lines.append(comment.prefix + "0x" + String(witness, radix: 16, uppercase: true))
            } else {
                counts.declined += 1
                lines.append(comment.prefix + "?")
            }
        }
        return (lines.joined(separator: "\n"), counts)
    }

    /// The implementation of the witness whose requirement slot is
    /// `address`, in the one conformance of `type` to `protocol`. Nil when
    /// the conformance or the witness is not unique, or the implementation
    /// is not a function start.
    ///
    /// Every conformance to a protocol shares its requirement slots, so the
    /// conformance is chosen by its type's name alone. The qualified name
    /// decides when one conformance has it. A private type's name cannot be
    /// qualified (its parent is an anonymous context), so it is matched by
    /// its own name, the header's last component, but only when that is the
    /// one conformance to the protocol with that name, no other conformance
    /// to it has a type whose name is unknown, and the match has no
    /// qualified name of its own (one would have had to equal `type`).
    func witness(at address: UInt64, type: String, protocol name: String) -> UInt64? {
        guard let conformance = Self.conformance(of: type, to: name, among: witnesses.conformances) else { return nil }
        let candidates = conformance.witnesses.filter { $0.requirementSlot == address }
        guard candidates.count == 1, let implementation = candidates[0].implementation,
              isFunctionStart(implementation)
        else { return nil }
        return implementation
    }

    /// The one conformance of `type` to `protocol`, by the rules above.
    static func conformance(
        of type: String, to name: String, among conformances: [ResilientWitnessIndex.Conformance]
    ) -> ResilientWitnessIndex.Conformance? {
        let toProtocol = conformances.filter { $0.protocolName == name || $0.protocolName == nil }
        var matching = toProtocol.filter { $0.typeName == type }
        if matching.isEmpty, let simple = type.split(separator: ".").last.map(String.init),
           simple.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
           !toProtocol.contains(where: { $0.simpleName == nil }) {
            matching = toProtocol.filter { $0.simpleName == simple && $0.typeName == nil }
        }
        return matching.count == 1 ? matching[0] : nil
    }

    /// `(T, P)` from `extension T: P {`, `extension T: P where … {` or
    /// `extension T: P {}`, `P` without a leading `@retroactive`; nil for
    /// any other line, including an extension that lists no protocol or
    /// more than one.
    static func extensionHeader(_ line: Substring) -> (type: String, protocol: String)? {
        guard line.hasPrefix("extension ") else { return nil }
        var rest = line.dropFirst("extension ".count)
        guard let colon = rest.range(of: ": ") else { return nil }
        let type = rest[..<colon.lowerBound]
        rest = rest[colon.upperBound...]
        let end = rest.range(of: " where ")?.lowerBound ?? rest.range(of: " {")?.lowerBound
        guard let end else { return nil }
        var proto = rest[..<end]
        if proto.hasPrefix("@retroactive ") { proto = proto.dropFirst("@retroactive ".count) }
        guard !type.isEmpty, !proto.isEmpty, !proto.contains(","), !proto.contains(" ") else { return nil }
        return (String(type), String(proto))
    }

    /// `(prefix, address)` for `<indent>// Address: 0x<hex>` or
    /// `<indent>// Address (<label>): 0x<hex>`, where `prefix` is the line up
    /// to the `0x`.
    static func addressComment(_ line: Substring) -> (prefix: String, address: UInt64)? {
        let trimmed = line.drop { $0 == " " }
        guard trimmed.hasPrefix("// Address"), let marker = line.range(of: ": 0x", options: .backwards) else { return nil }
        let hex = line[marker.upperBound...]
        guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit), let address = UInt64(hex, radix: 16) else { return nil }
        let label = line[line.index(trimmed.startIndex, offsetBy: "// Address".count) ..< marker.lowerBound]
        guard label.isEmpty || label.hasPrefix(" (") && label.hasSuffix(")") else { return nil }
        return (String(line[..<marker.lowerBound]) + ": ", address)
    }
}
