import Foundation

/// A first-cut pseudocode view: each function rendered as its sequence of
/// recovered calls and named field writes, with low-level ARC/runtime
/// bookkeeping hidden. Not a structured decompiler — it surfaces the useful
/// statements that the CFG + value-tracking already recover.
public extension DisassembledFunction {
    func renderPseudo(hideRuntime: Bool = true) -> String {
        var lines = ["\(displayName) {"]
        if let objcMethod { lines.append("    // \(objcMethod.signature)") }
        var shown = 0
        for insn in instructions {
            guard let statement = Self.pseudoStatement(of: insn, hideRuntime: hideRuntime) else { continue }
            lines.append("    \(statement)")
            shown += 1
        }
        if shown == 0 {
            lines.append("    // no non-runtime calls (leaf / pure computation)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// A source-level statement recovered from an instruction. Calls retain
    /// their richer message-send rendering; direct stores to a known Swift
    /// field or Objective-C ivar reuse the field annotation from disassembly.
    static func pseudoStatement(of insn: Instruction, hideRuntime: Bool) -> String? {
        if let annotation = insn.annotation {
            let semantic = annotation.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { note in
                    if note.hasPrefix("return ") { return true }
                    if note.hasPrefix("self = ") { return true }
                    if note.hasPrefix("("), note.contains("self->"), note.contains(" = ") {
                        return true
                    }
                    guard note.hasPrefix("self.") || note.hasPrefix("self->") else { return false }
                    return [" = ", " += ", " -= "].contains(where: note.contains)
                }
            if let semantic { return semantic }
        }
        return callStatement(of: insn, hideRuntime: hideRuntime)
    }

    /// The pseudo statement for a call or resolved tail-call instruction
    /// (`callee(args)`, or `[receiver doThing:]` for a message send), or nil if
    /// `insn` is not a call boundary or is hidden runtime bookkeeping.
    static func callStatement(of insn: Instruction, hideRuntime: Bool) -> String? {
        guard !insn.resultConsumed,
              insn.controlFlow == .call || insn.controlFlow == .branch,
              let callee = calleeName(of: insn)
        else { return nil }
        if hideRuntime, isRuntimeNoise(callee) { return nil }
        let arguments = insn.callArguments ?? []
        if let send = MessageSend(callee: callee, arguments: arguments) { return send.rendered }
        if let idiom = objcRuntimeIdiom(callee: callee, arguments: arguments) { return idiom }
        // A Swift method's receiver arrives in x20, not x0, so show it as an
        // explicit `self:` rather than letting it vanish from the call.
        let parts = insn.callSelf.map { ["self: \($0)"] + arguments } ?? arguments
        return "\(strippedCallee(callee))(\(parts.joined(separator: ", ")))"
    }

    /// ARC runtime helpers that are exact lowerings of a source message send,
    /// rendered back as that send.
    ///
    /// Each is a *faithful* rewrite — helper and bracket form denote the same
    /// call — so composing them reproduces the source rather than approximating
    /// it: `objc_alloc(objc_opt_class(self))` becomes `[[self class] alloc]`,
    /// which is exactly what was written.
    ///
    /// That composition is the reason the inner call is rendered rather than
    /// re-attributed. The lowering is the reverse of what it looks like,
    /// measured against clang:
    ///
    ///     [self alloc]           (self is a Class)     -> objc_alloc(self)
    ///     [[self class] alloc]   (self is an instance)  -> objc_alloc(objc_opt_class(self))
    ///
    /// so collapsing the composed form to `[self alloc]` drops the `class` call —
    /// and on an instance receiver prints something that is not valid ObjC at
    /// all, since `alloc` is a class method.
    ///
    /// Operands are rendered, never dropped: `objc_alloc()` would claim the call
    /// takes no argument, which is false. The send is proven by the callee; only
    /// its receiver is unknown, so that is what `?` says.
    static func objcRuntimeIdiom(callee: String, arguments: [String]) -> String? {
        func operand(_ index: Int) -> String {
            index < arguments.count ? arguments[index] : "?"
        }
        switch callee {
        case "objc_opt_class":     return "[\(operand(0)) class]"
        case "objc_opt_self":      return operand(0)
        case "objc_alloc":         return "[\(operand(0)) alloc]"
        case "objc_allocWithZone": return "[\(operand(0)) allocWithZone:nil]"
        case "objc_alloc_init",
             "objc_opt_new":       return "[[\(operand(0)) alloc] init]"
        case "objc_opt_isKindOfClass":
            return "[\(operand(0)) isKindOfClass:\(operand(1))]"
        case "objc_opt_respondsToSelector":
            return "[\(operand(0)) respondsToSelector:\(operand(1))]"
        default:
            return nil
        }
    }

    /// An Objective-C message send recovered from a call, in either dispatch
    /// shape the compiler emits.
    struct MessageSend {
        var receiver: String
        var selector: String
        var arguments: [String]

        /// Recognise a message send.
        ///
        /// Two shapes exist. Since Xcode 14 the compiler emits a per-selector
        /// stub and the selector lands in the callee's name
        /// (`objc_msgSend$setBool:forKey:`). Older code (and
        /// `-fno-objc-msgsend-selector-stubs`) materialises the selector into x1
        /// at the call site instead, where value tracking recovers it as a
        /// `@selector(…)` literal.
        ///
        /// Either way `x0` is the receiver and `x1` is `_cmd`, so the selector's
        /// own arguments start at `x2`.
        init?(callee: String, arguments: [String]) {
            guard callee.hasPrefix("objc_msgSend") else { return nil }
            let selector: String
            if let marker = callee.firstIndex(of: "$") {
                selector = String(callee[callee.index(after: marker)...])
            } else if arguments.count >= 2, let literal = Self.selectorLiteral(arguments[1]) {
                selector = literal
            } else {
                return nil
            }
            guard !selector.isEmpty else { return nil }
            self.receiver = callee.hasPrefix("objc_msgSendSuper") ? "super" : (arguments.first ?? "?")
            self.selector = selector
            self.arguments = Array(arguments.dropFirst(2))
        }

        private static func selectorLiteral(_ text: String) -> String? {
            guard text.hasPrefix("@selector("), text.hasSuffix(")") else { return nil }
            return String(text.dropFirst("@selector(".count).dropLast())
        }

        /// Foundation selector families whose final source arguments continue
        /// after the colon-delimited fixed parameters.
        static func isVariadicSelector(_ selector: String) -> Bool {
            guard !selector.contains("arguments:") else { return false }
            return selector.hasSuffix("WithFormat:")
                || selector.hasSuffix("appendFormat:")
                || selector.hasSuffix("WithObjects:")
                || selector.hasSuffix("WithObjectsAndKeys:")
        }

        /// `[receiver setBool:1 forKey:@"k"]`, or `[receiver reload]` for a
        /// selector that takes none.
        var rendered: String {
            guard selector.contains(":") else { return "[\(receiver) \(selector)]" }
            // `setBool:forKey:` splits to ["setBool", "forKey", ""] — the trailing
            // empty piece is the final colon, so drop it, then pair each keyword
            // with its argument.
            let keywords = selector.split(separator: ":", omittingEmptySubsequences: false).dropLast()
            let pieces = keywords.enumerated().map { index, keyword in
                "\(keyword):\(index < arguments.count ? arguments[index] : "?")"
            }
            var body = pieces.joined(separator: " ")
            if Self.isVariadicSelector(selector), arguments.count > keywords.count {
                body += ", " + arguments.dropFirst(keywords.count).joined(separator: ", ")
            }
            return "[\(receiver) \(body)]"
        }
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
            let name = stripNotes(String(annotation[arrow.upperBound...]))
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
        let base = stripNotes(annotation)
        if base.isEmpty || base.hasPrefix("args(") || base.hasPrefix("self=") || base.hasPrefix("→") {
            return nil
        }
        return base
    }

    /// Drop the notes value-tracking appends to an annotation (`self=…`,
    /// `args(…)`), leaving just the resolved name.
    private static func stripNotes(_ text: String) -> String {
        var cut = text.endIndex
        for marker in ["  args(", "  self="] {
            if let range = text.range(of: marker), range.lowerBound < cut { cut = range.lowerBound }
        }
        return String(text[..<cut]).trimmingCharacters(in: .whitespaces)
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
            // The autorelease family brackets almost every ObjC call that
            // returns an object; left in, it drowns out the actual sends.
            "objc_autorelease", "objc_claimAutoreleasedReturnValue",
            "objc_retainAutorelease", "objc_retainAutoreleasedReturnValue",
        ]
        return prefixes.contains { callee.hasPrefix($0) }
    }
}
