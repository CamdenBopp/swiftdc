import Foundation

/// Output format for CLI commands.
public enum OutputFormat: String, Sendable, CaseIterable {
    case text
    case json
}

// MARK: - JSON DTOs (addresses rendered as hex strings for readability)

private struct InstructionDTO: Encodable {
    let address: String
    let text: String
    let annotation: String?
    /// Control-flow class ("branch"/"call"/"return"/…); omitted when sequential.
    let controlFlow: String?
    let branchTarget: String?
    /// Recovered call arguments (x0…), when value-tracking inferred them.
    let arguments: [String]?
    /// Source-like statement recovered for this instruction, when any.
    let statement: String?
}

private struct BlockDTO: Encodable {
    let address: String
    let successors: [String]
}

private struct ObjCMethodDTO: Encodable {
    let owner: String
    let `class`: String
    let category: String?
    let selector: String
    let kind: String
    let typeEncoding: String
    let signature: String
}

private struct AsyncFuncletDTO: Encodable {
    /// Entry funclet address; absent when no parent was recovered.
    let parent: String?
    /// 0 for the entry funclet, 1… for resume funclets in chain order.
    let ordinal: Int
    /// "await-return", "continuation", or "unknown"; absent for the entry.
    let kind: String?
    /// The funclet whose suspension this one continues; absent when several
    /// suspensions of the chain continue into it.
    let predecessor: String?
    /// Every funclet of the chain, entry first.
    let chain: [String]
    /// The runtime wait that resumes this continuation, when not a hop.
    let resumedBy: String?
    /// Entries of every chain that resumes into this funclet, when more than
    /// one does (identical code folding) and so none owns it.
    let sharedBy: [String]?
}

private struct FunctionDTO: Encodable {
    let name: String
    let symbol: String
    let address: String
    /// How the name/boundary was recovered: "symbol", "metadata",
    /// "objc-metadata", "address", "folded-symbols", or "async-funclet".
    let source: String
    /// Runtime method identity/signature when this function is an ObjC IMP.
    let objectiveC: ObjCMethodDTO?
    /// Place in an async function's funclet chain, when this is one.
    let async: AsyncFuncletDTO?
    let instructions: [InstructionDTO]
    /// Basic blocks (control-flow graph) recovered via Capstone.
    let blocks: [BlockDTO]
}

private struct ReportDTO: Encodable {
    let declarations: [String]
    let objc: [String]
    let functions: [FunctionDTO]
}

private struct ObjCReportDTO: Encodable {
    let headers: [String]
    let methods: [FunctionDTO]
}

private func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

private func jsonEncode<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return string
}

private extension DisassembledFunction {
    var dto: FunctionDTO {
        FunctionDTO(
            name: displayName,
            symbol: symbol,
            address: hex(startAddress),
            source: source.rawValue,
            objectiveC: objcMethod.map {
                ObjCMethodDTO(
                    owner: $0.ownerName,
                    class: $0.className,
                    category: $0.categoryName,
                    selector: $0.selector,
                    kind: $0.isClassMethod ? "class" : "instance",
                    typeEncoding: $0.typeEncoding,
                    signature: $0.signature
                )
            },
            async: asyncFunclet.map {
                AsyncFuncletDTO(
                    parent: $0.parent.map(hex), ordinal: $0.ordinal, kind: $0.kind?.rawValue,
                    predecessor: $0.predecessor.map(hex), chain: $0.chain.map(hex),
                    resumedBy: $0.resumedBy, sharedBy: $0.sharedBy.isEmpty ? nil : $0.sharedBy.map(hex)
                )
            },
            instructions: instructions.map {
                InstructionDTO(
                    address: hex($0.address),
                    text: $0.text,
                    annotation: $0.annotation,
                    controlFlow: ($0.controlFlow == nil || $0.controlFlow == .sequential)
                        ? nil : $0.controlFlow?.rawValue,
                    branchTarget: $0.branchTarget.map(hex),
                    arguments: $0.callArguments,
                    statement: DisassembledFunction.pseudoStatement(of: $0, hideRuntime: true)
                )
            },
            blocks: basicBlocks().map {
                BlockDTO(address: hex($0.startAddress), successors: $0.successors.map(hex))
            }
        )
    }
}

public extension Array where Element == DisassembledFunction {
    /// JSON array of the disassembled functions.
    func jsonString() -> String { jsonEncode(map(\.dto)) }
}

/// Split a reconstructed-declarations dump into individual declaration blocks
/// (separated by blank lines), for structured output.
public func declarationBlocks(_ dump: String) -> [String] {
    dump.components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

/// JSON object combining Swift declarations, ObjC headers, and functions.
public func reportJSON(declarations: String, objc: [String], functions: [DisassembledFunction]) -> String {
    jsonEncode(ReportDTO(declarations: declarationBlocks(declarations), objc: objc, functions: functions.map(\.dto)))
}

/// Objective-C headers plus their recovered IMP implementations.
public func objcReportJSON(headers: [String], methods: [DisassembledFunction]) -> String {
    jsonEncode(ObjCReportDTO(headers: headers, methods: methods.map(\.dto)))
}

/// JSON array of declaration blocks parsed from a declarations dump.
public func declarationsJSON(_ dump: String) -> String {
    jsonEncode(declarationBlocks(dump))
}

/// JSON array of pre-split string blocks (e.g. ObjC headers).
public func jsonStrings(_ strings: [String]) -> String {
    jsonEncode(strings)
}
