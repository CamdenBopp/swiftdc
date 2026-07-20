import Testing
import Foundation

/// An Objective-C method whose return value was not recovered must render
/// `return ?`, never a bare `return` — the same contract as Swift functions
/// (see `ValuelessReturnTests`). The readiness doc recorded the ObjC branch of
/// that classifier as "unit-tested only"; this closes it end-to-end, and closing
/// it surfaced a real integration bug.
///
/// The bug: the structurer's `usesSwiftError` heuristic treats a function that
/// clears x21 (`mov x21, #0`) as threading the Swift error register, which
/// suppresses `return ?` on the unrecovered path. But ObjC does not use that ABI
/// — its errors bridge through an `NSError**` out-parameter — so an ObjC method
/// that merely zeroes x21 while computing a `BOOL` (routine in `isEqual:`) was
/// misclassified, and rendered a bare `return` that reads as "returns nothing".
///
/// The oracle is a **real system framework**, not a hand-built fixture, and the
/// assertion is a population property (no non-void ObjC method may render a bare
/// `return`) rather than one method by name — so it holds across OS versions.
/// Host-gated: skips cleanly where the dyld cache image is unavailable.

private let cli = URL(fileURLWithPath: ".build/debug/swiftdc")

private func run(_ args: [String]) -> String? {
    guard FileManager.default.fileExists(atPath: cli.path) else { return nil }
    let out = Pipe()
    let process = Process()
    process.executableURL = cli
    process.arguments = args
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let text = String(decoding: data, as: UTF8.self)
    return text.isEmpty ? nil : text
}

/// Walk the `objc --methods --structured` output, pairing each method's declared
/// return type (from its `// - (Type)selector;` comment) with the `return`
/// statements in its body.
private func returnAudit(_ text: String) -> (bareUnderNonVoid: [String], questionMarks: Int) {
    var returnType: String?
    var method: String?
    var bare: [String] = []
    var questionMarks = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let l = String(line)
        let trimmed = l.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("-[") || trimmed.hasPrefix("+[") { method = trimmed }
        // The signature comment inside a rendered body, e.g. "// - (BOOL)isEqual:(id)arg0;"
        if let open = trimmed.range(of: ") ("), trimmed.hasPrefix("// ") {
            _ = open  // (unused shape guard)
        }
        if trimmed.hasPrefix("// -") || trimmed.hasPrefix("// +"),
           let lp = trimmed.firstIndex(of: "("), let rp = trimmed[lp...].firstIndex(of: ")") {
            returnType = String(trimmed[trimmed.index(after: lp)..<rp]).trimmingCharacters(in: .whitespaces)
        }
        if l.range(of: #"^\s+return\s*$"#, options: .regularExpression) != nil,
           let rt = returnType, rt != "void", rt != "IBAction" {
            bare.append("\(method ?? "?") -> \(rt)")
        }
        if l.range(of: #"^\s+return \?\s*$"#, options: .regularExpression) != nil {
            questionMarks += 1
        }
    }
    return (bare, questionMarks)
}

@Test func objectiveCMethodsNeverRenderABareReturnUnderANonVoidSignatureIfPresent() throws {
    // A real system framework with many `isEqual:`-style BOOL methods — exactly
    // the shape that clears x21 while computing a Bool. Skips without the cache.
    guard let text = run(["objc", "--image", "UserNotifications", "--methods", "--structured"])
    else { return }

    let audit = returnAudit(text)

    // Not vacuous: the framework must actually contain unrecovered ObjC returns,
    // or the test proves nothing. Before the fix this was 27; the 7 bugged
    // methods now bring it higher. A zero here means the audit matched nothing
    // and the assertion below is empty.
    #expect(
        audit.questionMarks >= 10,
        "audit found only \(audit.questionMarks) `return ?` — the ObjC render path was not exercised"
    )
    #expect(
        audit.bareUnderNonVoid.isEmpty,
        """
        \(audit.bareUnderNonVoid.count) Objective-C method(s) render a bare `return` under a \
        non-void signature, which reads as "returns nothing" for a value that was merely \
        unrecovered. Most likely the `usesSwiftError` heuristic misfiring on a method that \
        zeroes x21 while computing a BOOL. Examples: \(audit.bareUnderNonVoid.prefix(4).joined(separator: "; "))
        """
    )
}
