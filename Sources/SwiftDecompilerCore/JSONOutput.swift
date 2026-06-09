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
}

private struct FunctionDTO: Encodable {
    let name: String
    let symbol: String
    let address: String
    /// How the name/boundary was recovered: "symbol", "metadata", or "address".
    let source: String
    let instructions: [InstructionDTO]
}

private struct ReportDTO: Encodable {
    let declarations: [String]
    let objc: [String]
    let functions: [FunctionDTO]
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
            instructions: instructions.map {
                InstructionDTO(address: hex($0.address), text: $0.text, annotation: $0.annotation)
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

/// JSON array of declaration blocks parsed from a declarations dump.
public func declarationsJSON(_ dump: String) -> String {
    jsonEncode(declarationBlocks(dump))
}

/// JSON array of pre-split string blocks (e.g. ObjC headers).
public func jsonStrings(_ strings: [String]) -> String {
    jsonEncode(strings)
}
