import Foundation

/// Name and ABI assertions can compare expressions regardless of whether a
/// call must be materialized. This helper does not check evaluation order or
/// count; AuditSemanticTests and the reused-result tests check those directly.
func expandingResultBindingsForAssertions(_ text: String) -> String {
    var bindings: [String: String] = [:]
    let names = try! NSRegularExpression(pattern: #"\br[0-9]+\b"#)
    func expand(_ line: String) -> String {
        var result = line
        for match in names.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
            guard let range = Range(match.range, in: result), let expression = bindings[String(result[range])] else { continue }
            result.replaceSubrange(range, with: expression)
        }
        return result
    }
    return text.components(separatedBy: "\n").map { line in
        if !line.hasPrefix(" "), line.hasSuffix(" {") { bindings.removeAll() }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("let r"), let split = trimmed.range(of: " = ") {
            let name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<split.lowerBound])
            bindings[name] = expand(String(trimmed[split.upperBound...]))
            return ""
        }
        return expand(line)
    }.joined(separator: "\n")
}
