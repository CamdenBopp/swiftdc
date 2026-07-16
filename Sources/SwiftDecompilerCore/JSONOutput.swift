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

private struct FunctionDTO: Encodable {
    let name: String
    let symbol: String
    let address: String
    /// How the name/boundary was recovered: "symbol", "metadata",
    /// "objc-metadata", or "address".
    let source: String
    /// Runtime method identity/signature when this function is an ObjC IMP.
    let objectiveC: ObjCMethodDTO?
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
            instructions: instructions.map {
                InstructionDTO(
                    address: hex($0.address),
                    text: $0.text,
                    annotation: $0.annotation,
                    controlFlow: ($0.controlFlow == nil || $0.controlFlow == .sequential)
                        ? nil : $0.controlFlow?.rawValue,
                    branchTarget: $0.branchTarget.map(hex),
                    arguments: $0.callArguments
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
