import Foundation

/// A first-cut pseudocode view: each function rendered as its sequence of
/// recovered call statements (callee + arguments), with low-level ARC/runtime
/// bookkeeping hidden. Not a structured decompiler — it surfaces the call
/// skeleton that the CFG + value-tracking already recover.
public extension DisassembledFunction {
    func renderPseudo(hideRuntime: Bool = true) -> String {
        var lines = ["\(displayName) {"]
        var shown = 0
        for insn in instructions {
            guard let statement = Self.callStatement(of: insn, hideRuntime: hideRuntime) else { continue }
            lines.append("    \(statement)")
            shown += 1
        }
        if shown == 0 {
            lines.append("    // no non-runtime calls (leaf / pure computation)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The pseudo statement for a call instruction (`callee(args)`), or nil if
    /// `insn` is not a call or is hidden runtime bookkeeping.
    static func callStatement(of insn: Instruction, hideRuntime: Bool) -> String? {
        guard insn.controlFlow == .call, let callee = calleeName(of: insn) else { return nil }
        if hideRuntime, isRuntimeNoise(callee) { return nil }
        let arguments = insn.callArguments?.joined(separator: ", ") ?? ""
        return "\(strippedCallee(callee))(\(arguments))"
    }

    /// Best-effort callee name for a call instruction, from the demangled
    /// annotation or objdump's stub/operand text.
    static func calleeName(of insn: Instruction) -> String? {
        // objdump tells us the real callee behind a stub.
        if insn.text.contains("symbol stub for: ") {
            if let demangled = demangledName(from: insn.annotation) { return demangled }
            if let range = insn.text.range(of: "symbol stub for: ") {
                let raw = insn.text[range.upperBound...].prefix { !$0.isWhitespace && $0 != ";" }
                return stripUnderscores(String(raw))
            }
        }
        // Direct call: prefer the demangled annotation, else a resolved
        // `→ name` target (the in-process path), else the symbol operand.
        if let demangled = demangledName(from: insn.annotation) { return demangled }
        if let annotation = insn.annotation, let arrow = annotation.range(of: "→ ") {
            let name = annotation[arrow.upperBound...]
                .components(separatedBy: "  args(")[0]
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        let fields = insn.text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if fields.count >= 2 {
            let operand = String(fields[1])
            if operand.hasPrefix("_") { return stripUnderscores(operand) }
        }
        return nil
    }

    /// The demangled-name portion of an annotation (before the `  args(…)` we
    /// appended). Nil when the annotation is only arguments or a `→` reference.
    private static func demangledName(from annotation: String?) -> String? {
        guard let annotation else { return nil }
        let base = annotation.components(separatedBy: "  args(")[0]
            .trimmingCharacters(in: .whitespaces)
        if base.isEmpty || base.hasPrefix("args(") || base.hasPrefix("→") { return nil }
        return base
    }

    private static func stripUnderscores(_ symbol: String) -> String {
        var s = Substring(symbol)
        while s.hasPrefix("_") { s = s.dropFirst() }
        return String(s)
    }

    /// Drop a demangled name's trailing return clause and argument-label
    /// signature so the recovered `(args)` reads cleanly:
    /// `String.append(_:)` → `String.append`, `Tree.sum()` → `Tree.sum`.
    static func strippedCallee(_ name: String) -> String {
        var s = name
        if let arrow = s.range(of: " -> ") { s = String(s[..<arrow.lowerBound]) }
        guard s.hasSuffix(")") else { return s }
        var depth = 0
        for index in s.indices.reversed() {
            if s[index] == ")" { depth += 1 }
            else if s[index] == "(" {
                depth -= 1
                if depth == 0 { return String(s[..<index]) }
            }
        }
        return s
    }

    /// Low-level retain/release/exclusivity bookkeeping — hidden by default so
    /// the program logic stands out.
    static func isRuntimeNoise(_ callee: String) -> Bool {
        let prefixes = [
            "swift_retain", "swift_release", "swift_bridgeObjectRetain",
            "swift_bridgeObjectRelease", "swift_beginAccess", "swift_endAccess",
            "objc_retain", "objc_release", "swift_isUniquelyReferenced",
            "__chkstk", "swift_unknownObjectRetain", "swift_unknownObjectRelease",
        ]
        return prefixes.contains { callee.hasPrefix($0) }
    }
}
