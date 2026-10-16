import Foundation

/// A first-cut pseudocode view: each function rendered as its sequence of
/// recovered calls and named field writes, with low-level ARC/runtime
/// bookkeeping hidden. Not a structured decompiler — it surfaces the useful
/// statements that the CFG + value-tracking already recover.
public extension DisassembledFunction {
    /// A throwing function's exit not proven to be a return or a throw.
    static let unresolvedSwiftExitNote = "swift-exit=unknown"
    static let unresolvedSwiftExitStatement = "machine_return() /* unresolved Swift success/error exit */"
    /// A throwing function's exit proven normal that has no value to print.
    static let normalSwiftExitNote = "swift-exit=normal"

    func renderPseudo(hideRuntime: Bool = true) -> String {
        Probe.inFunction(startAddress, displayName) {
            Probe.timed(.renderTime) {
                let output = renderPseudoBody(hideRuntime: hideRuntime)
                Probe.rendered(output, of: self, view: "pseudo")
                return output
            }
        }
    }

    private func renderPseudoBody(hideRuntime: Bool) -> String {
        var lines = ["\(displayName) {"]
        if let objcMethod { lines.append("    // \(objcMethod.signature)") }
        if let asyncLine = asyncHeaderLine() { lines.append("    \(asyncLine)") }
        var statements: [String] = []
        for insn in instructions {
            let recovered = Self.pseudoStatement(of: insn, hideRuntime: hideRuntime)
            let fallback: String? = if insn.controlFlow != .return { nil }
                else if Self.splitSignature(analysisDisplayName)?.isThrowing == true { Self.unresolvedSwiftExitStatement }
                else if hasProvenMachineValueReturn { "return ?" }
                else { nil }
            guard let statement = recovered ?? fallback else { continue }
            statements += statement.components(separatedBy: "\n")
        }
        if hideRuntime { statements = Self.foldSwiftIdioms(statements) }
        if statements.isEmpty {
            lines.append("    // no non-runtime calls (leaf / pure computation)")
        } else {
            for statement in statements { lines.append("    \(statement)") }
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// A source-level statement recovered from an instruction. Calls retain
    /// their richer message-send rendering; direct stores to a known Swift
    /// field or Objective-C ivar reuse the field annotation from disassembly.
    static func pseudoStatement(of insn: Instruction, hideRuntime: Bool) -> String? {
        // A path that throws after this instruction (a throw merged into the
        // shared epilogue): its own statement, then the throw.
        if let annotation = insn.annotation, annotation.contains(Self.thenThrowNote) {
            let rest = annotation.replacingOccurrences(of: "  " + Self.thenThrowNote, with: "")
                .replacingOccurrences(of: Self.thenThrowNote, with: "")
            let base = Instruction(
                address: insn.address, text: insn.text, annotation: rest.isEmpty ? nil : rest,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: insn.callArguments, callSelf: insn.callSelf,
                resultConsumed: insn.resultConsumed, sourceType: insn.sourceType, detail: insn.detail,
                calleeDisplayName: insn.calleeDisplayName)
            return pseudoStatement(of: base, hideRuntime: hideRuntime).map { "\($0)\nthrow ?" } ?? "throw ?"
        }
        if insn.isTrap { return "trap()" }
        if let notes = insn.annotation?.components(separatedBy: "  ") {
            if notes.contains(Self.unresolvedSwiftExitNote) { return Self.unresolvedSwiftExitStatement }
            if notes.contains(Self.normalSwiftExitNote) { return "return" }
        }
        if let annotation = insn.annotation {
            let semantic = annotation.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { note in
                    if note.hasPrefix("return ") || note.hasPrefix("throw ") { return true }
                    // `let r0 = call(...)`: a call whose indirect result is read
                    // back field by field later, bound once so the call is not
                    // spelled out (executed) at every use.
                    if note.hasPrefix("let r") { return true }
                    if note.hasPrefix("yield ") { return true }
                    if note.hasPrefix("await hop_to_executor(") { return true }
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
        guard insn.controlFlow == .call || insn.controlFlow == .branch else { return nil }
        guard let callee = calleeName(of: insn) else {
            // An unknown target does not make the call pure: it is an effect,
            // and its arguments may be the only rendering of earlier calls'
            // results. The observed register values are not a claimed
            // signature, so they are listed as recovered values, not arguments.
            if insn.controlFlow == .branch, let target = indirectJumpTarget(of: insn) {
                // A suspension is a call; any other indirect `br` may be a
                // tail call or an unrecovered jump table, so it is a jump.
                if let binding = awaitBinding(of: insn) {
                    let call = "indirect_call(\(target))"
                    return binding.isEmpty ? "await \(call)" : "let \(binding) = await \(call)"
                }
                let comment = target == "?" ? "/* unresolved indirect branch @ 0x\(String(insn.address, radix: 16)) */ " : ""
                return "\(comment)indirect_jump(\(target))"
            }
            guard insn.controlFlow == .call else { return nil }
            let arguments = (insn.callArguments ?? []).joined(separator: ", ")
            return "/* unresolved call @ 0x\(String(insn.address, radix: 16)) */ indirect_call(?, recovered_args: [\(arguments)])"
        }
        guard !insn.resultConsumed else { return nil }
        let rawArguments = insn.callArguments ?? []
        // A dynamic cast reads its target type from the metadata argument that the
        // plumbing strip below would remove, so recognize it on the raw arguments
        // first.
        if hideRuntime, let cast = swiftCastIdiom(callee: callee, arguments: rawArguments) { return cast }
        if hideRuntime, let literal = arrayLiteralPlaceholder(callee: callee) { return literal }
        if hideRuntime, isRuntimeNoise(callee) || isGenericPlumbingCallee(callee) { return nil }
        let arguments = hideRuntime ? strippingGenericPlumbing(rawArguments) : rawArguments
        if let send = MessageSend(callee: callee, arguments: arguments) { return send.rendered }
        if let idiom = objcRuntimeIdiom(callee: callee, arguments: arguments) { return idiom }
        // A Swift method's receiver arrives in x20, not x0, so show it as an
        // explicit `self:` rather than letting it vanish from the call.
        if isSelfDispatch(insn) {
            let call = "\(selfDispatchCall(insn.calleeDisplayName ?? callee))(\(arguments.joined(separator: ", ")))"
            guard let binding = awaitBinding(of: insn) else { return call }
            return binding.isEmpty ? "await \(call)" : "let \(binding) = await \(call)"
        }
        let parts = insn.callSelf.map { ["self: \($0)"] + arguments } ?? arguments
        let call = "\(strippedCallee(insn.calleeDisplayName ?? callee))(\(parts.joined(separator: ", ")))"
        // A suspension point: the tail call is an `await`, and its result is
        // bound to the name the resume funclet reads it under, when proven.
        guard let binding = awaitBinding(of: insn) else { return call }
        return binding.isEmpty ? "await \(call)" : "let \(binding) = await \(call)"
    }

    /// The `await=<name>` note the analysis attaches to a suspension's tail call:
    /// nil when the call is not a suspension, empty when it is one whose result
    /// is not provable.
    static func awaitBinding(of insn: Instruction) -> String? {
        guard let annotation = insn.annotation else { return nil }
        for note in annotation.components(separatedBy: "  ") where note.hasPrefix("await=") {
            return String(note.dropFirst("await=".count))
        }
        return nil
    }

    /// The note on a `br` through a register to no known function, followed
    /// by the rendered register value or `?` (see `enrichCallArguments`).
    static let indirectJumpNote = "jump="

    /// The rendered target of an indirect `br` the analysis marked, if any.
    static func indirectJumpTarget(of insn: Instruction) -> String? {
        guard let annotation = insn.annotation else { return nil }
        for note in annotation.components(separatedBy: "  ") where note.hasPrefix(indirectJumpNote) {
            return String(note.dropFirst(indirectJumpNote.count))
        }
        return nil
    }

    /// The note on the last instruction of a path that throws into a shared
    /// epilogue.
    static let thenThrowNote = "then throw ?"

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

    /// A Swift dynamic cast (`x as? T` / `x as! T`) recovered from the runtime
    /// call the compiler lowers it to. Read from the *raw* arguments, before
    /// `strippingGenericPlumbing` removes the target-type metadata — for a cast
    /// that metadata IS the source-level type, not scaffolding.
    ///
    /// The conditional/unconditional split is exact: the class/metatype helpers
    /// spell `Unconditional` in their name (`as!`), and the general
    /// `swift_dynamicCast` carries it in `DynamicCastFlags.Unconditional` (bit 0)
    /// of its flags operand. Returns nil — leaving the raw call — when the target
    /// type is an unrecoverable mangled-name instantiation or the flags are
    /// unknown, so the cast is never rendered with a guessed type or direction.
    static func swiftCastIdiom(callee: String, arguments: [String]) -> String? {
        func cast(object: String, targetArgument: String, forced: Bool) -> String? {
            guard let type = swiftTypeName(fromMetadata: targetArgument) else { return nil }
            return "(\(object) \(forced ? "as!" : "as?") \(type))"
        }
        switch callee {
        case "swift_dynamicCastClass", "swift_dynamicCastObjCClass",
             "swift_dynamicCastUnknownClass", "swift_dynamicCastMetatype":
            guard arguments.count >= 2 else { return nil }
            return cast(object: arguments[0], targetArgument: arguments[1], forced: false)
        case "swift_dynamicCastClassUnconditional", "swift_dynamicCastObjCClassUnconditional",
             "swift_dynamicCastUnknownClassUnconditional", "swift_dynamicCastMetatypeUnconditional":
            guard arguments.count >= 2 else { return nil }
            return cast(object: arguments[0], targetArgument: arguments[1], forced: true)
        case "swift_dynamicCast":
            // (dest, src, srcType, targetType, flags): the value is `src`, the
            // type is `targetType`, and `dest` is the out-parameter it's written
            // through — not a source expression, so it isn't shown.
            guard arguments.count >= 5, let forced = castFlagsUnconditional(arguments[4]) else { return nil }
            return cast(object: arguments[1], targetArgument: arguments[3], forced: forced)
        default:
            return nil
        }
    }

    /// The Swift type named by a metadata argument — `type metadata accessor for
    /// Foo.Bar(0)` / `type metadata for Swift.String` → `Foo.Bar` / `Swift.String`
    /// — or nil when the argument is not a nameable metadata reference (e.g. a
    /// mangled-name instantiation we can't resolve to a spelling here).
    static func swiftTypeName(fromMetadata argument: String) -> String? {
        let prefixes = ["type metadata accessor for ", "type metadata for ", "type metadata pattern for "]
        guard let prefix = prefixes.first(where: argument.hasPrefix) else { return nil }
        var name = String(argument.dropFirst(prefix.count))
        // An accessor is a call — drop its "(metadataRequest)" argument group,
        // which a nominal or generic type name (using `<>`, not `()`) never has.
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Whether a `swift_dynamicCast` flags operand has `DynamicCastFlags`'
    /// `Unconditional` bit (0x1) set — i.e. the cast is `as!`. Nil when the
    /// operand isn't a recovered immediate, so the caller can decline to guess.
    static func castFlagsUnconditional(_ argument: String) -> Bool? {
        let value = argument.hasPrefix("0x")
            ? UInt64(argument.dropFirst(2), radix: 16)
            : UInt64(argument)
        return value.map { $0 & 0x1 != 0 }
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
            let selector: String
            if callee.hasPrefix("objc_msgSend") {
                if let marker = callee.firstIndex(of: "$") {
                    selector = String(callee[callee.index(after: marker)...])
                } else if arguments.count >= 2, let literal = Self.selectorLiteral(arguments[1]) {
                    selector = literal
                } else {
                    return nil
                }
            } else if let direct = Self.directMethodSelector(callee) {
                selector = direct
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

        /// The selector of a statically-dispatched call whose callee is spelled
        /// `-[Class selector]` / `+[Class selector]` (a direct IMP call the
        /// compiler emitted instead of a msgSend). It takes the same
        /// `(self, _cmd, args…)` ABI as a message send, so x0 is the receiver and
        /// the selector's arguments still begin at x2 — rendering identically as
        /// `[receiver selector]` rather than the raw `-[Class sel](self, …)`.
        private static func directMethodSelector(_ callee: String) -> String? {
            guard callee.hasPrefix("-[") || callee.hasPrefix("+["), callee.hasSuffix("]") else { return nil }
            let inner = callee.dropFirst(2).dropLast()
            guard let space = inner.firstIndex(of: " ") else { return nil }
            let selector = inner[inner.index(after: space)...]
            guard !selector.isEmpty, !selector.contains(" ") else { return nil }
            return String(selector)
        }

        /// Foundation selector families whose final source arguments continue
        /// after the colon-delimited fixed parameters.
        /// How many variadic arguments a printf-style format consumes, from its
        /// rendered literal (`@"%ld %@"`), or nil when that is not provable: a
        /// truncated literal, a `*` width or precision (an extra argument), a
        /// positional `%1$d`, or any specifier this parser does not know. On
        /// Apple arm64 each variadic argument is one 8-byte stack slot.
        static func formatArgumentCount(_ literal: String) -> Int? {
            var text = Substring(literal)
            if text.hasPrefix("@") { text = text.dropFirst() }
            guard text.hasPrefix("\""), text.hasSuffix("\""), !text.hasSuffix("…\""), text.count >= 2
            else { return nil }
            let characters = Array(text.dropFirst().dropLast())
            var count = 0, index = 0
            while index < characters.count {
                guard characters[index] == "%" else { index += 1; continue }
                index += 1
                guard index < characters.count else { return nil }
                if characters[index] == "%" { index += 1; continue }
                while index < characters.count, "-+ #0'".contains(characters[index]) { index += 1 }
                while index < characters.count, characters[index].isNumber { index += 1 }
                if index < characters.count, characters[index] == "." {
                    index += 1
                    while index < characters.count, characters[index].isNumber { index += 1 }
                }
                // `*` takes an argument; `$` reorders them. Neither is counted soundly.
                guard index < characters.count, characters[index] != "*", characters[index] != "$"
                else { return nil }
                while index < characters.count, "hlqLjzt".contains(characters[index]) { index += 1 }
                guard index < characters.count, "diouxXfFeEgGaAcsSpn@C".contains(characters[index])
                else { return nil }
                count += 1
                index += 1
            }
            return count
        }

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
        if base.isEmpty || base.hasPrefix("args(") || base.hasPrefix("self=") || base.hasPrefix("→")
            || base.hasPrefix("await=") || base.hasPrefix(indirectJumpNote) || base.hasPrefix("swift-exit=") {
            return nil
        }
        return base
    }

    /// Whether `callee` is a static member of a struct or enum the index
    /// proves one. Such a member's `self` is a thin metatype, which no
    /// register carries, so x20 at the call is the caller's, not `self`. The
    /// owner is the member's own context: the name without the member (and
    /// an accessor keyword), so a class nested in a struct is the class
    /// (`static BoxA.Holder.shared.getter` is `BoxA.Holder`'s, not `BoxA`'s).
    static func isStaticValueTypeMember(_ callee: String, classTypeIndex: ClassTypeIndex) -> Bool {
        guard callee.hasPrefix("static ") else { return false }
        var name = callee.dropFirst("static ".count)
        // A type declared in an extension prints with its context,
        // `(extension in Foundation):Swift.String.Encoding`; so does the
        // evidence for it.
        var context = ""
        if name.hasPrefix("(extension in "), let colon = name.firstIndex(of: ":") {
            context = String(name[...colon])
            name = name[name.index(after: colon)...]
        }
        if let end = name.firstIndex(where: { $0 == "(" || $0 == "<" || $0 == " " }) { name = name[..<end] }
        guard var dot = name.lastIndex(of: ".") else { return false }
        if accessorKeywords.contains(String(name[name.index(after: dot)...])) {
            guard let property = name[..<dot].lastIndex(of: ".") else { return false }
            dot = property
        }
        let owner = String(name[..<dot])
        return classTypeIndex.isValueType(context + owner) || classTypeIndex.isValueType(owner)
    }

    /// Marks a call reached through `self`'s own vtable slot. The named
    /// implementation is self's class's; an override in a subclass runs
    /// instead when self is one, so the call is `self.member(…)`, not a static
    /// call to that implementation, and its call-graph edge is not proven.
    static let selfDispatchMarker = "  dispatch=self"

    static func isSelfDispatch(_ insn: Instruction) -> Bool {
        insn.annotation?.contains(selfDispatchMarker) == true
    }

    /// `self.member` for a self dispatch to `callee`.
    static func selfDispatchCall(_ callee: String) -> String {
        let stripped = strippedCallee(callee)
        let parts = stripped.split(separator: ".").map(String.init)
        // An accessor keeps its property: `self.value.getter`, never the
        // accessor keyword alone.
        if parts.count >= 2, accessorKeywords.contains(parts[parts.count - 1]) {
            return "self.\(parts[parts.count - 2]).\(parts[parts.count - 1])"
        }
        return "self.\(parts.last ?? stripped)"
    }

    private static let accessorKeywords: Set<String> = [
        "getter", "setter", "modify", "read", "unsafeAddressor", "unsafeMutableAddressor", "willset", "didset",
    ]

    /// Drop the notes value-tracking appends to an annotation (`self=…`,
    /// `args(…)`, `await=…`, `let r0 = …`, `return …`), leaving just the
    /// resolved name. Every note follows two spaces, which no name contains;
    /// cutting at four known markers let the semantic ones through, and the
    /// call graph named `swift_dynamicCastClass` as
    /// `swift_dynamicCastClass  let r0 = (? as? Reconstruction.Dog)`.
    private static func stripNotes(_ text: String) -> String {
        let cut = text.range(of: "  ")?.lowerBound ?? text.endIndex
        return String(text[..<cut]).trimmingCharacters(in: .whitespaces)
    }

    /// The C name of a Mach-O symbol: one leading underscore is the linker's
    /// prefix; any more belong to the name (`___stack_chk_fail` is
    /// `__stack_chk_fail`, as the in-process paths spell it).
    private static func stripUnderscores(_ symbol: String) -> String {
        symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
    }

    /// Drop a demangled name's trailing return clause and argument-label
    /// signature so the recovered `(args)` reads cleanly:
    /// `String.append(_:)` → `String.append`, `Tree.sum()` → `Tree.sum`.
    static func strippedCallee(_ name: String) -> String {
        var s = mergedCallName(name)
        // The signature's own arrow, not one inside a function-typed
        // parameter: `init(_:transform: (A.Element) async -> B?) -> Iterator`
        // cut at the first arrow rendered `init(_: A.AsyncIterator, transform: ()`.
        if let arrow = topLevelRange(of: " -> ", in: s) { s = String(s[..<arrow.lowerBound]) }
        // A property accessor's ` : Type` is the property's type, not part of
        // the call: `Foo.value.getter : Swift.Int()` read as a call through a
        // type, and a self dispatch to it was named `self.Int`. A protocol
        // witness keeps its `in conformance … : P` clause.
        if !s.contains(" in conformance "), let colon = topLevelRange(of: " : ", in: s),
           let keyword = s[..<colon.lowerBound].split(separator: ".").last,
           accessorKeywords.contains(String(keyword)) {
            // Keep a suffix that names a different function: the `.resume.0`
            // half of a `modify` coroutine is not its ramp.
            let suffix = s[colon.upperBound...].range(of: " with unmangled suffix ").map { String(s[$0.lowerBound...]) } ?? ""
            s = String(s[..<colon.lowerBound]) + suffix
        }
        // Effect specifiers follow the parameter list (`f(Swift.Int) async
        // throws`); they are not part of the callee's name, and left in place
        // they kept the parameter list from being recognised and stripped, so
        // such a call rendered `f(Swift.Int) async(arg0)`.
        while let effect = s.range(of: #" (async|throws|rethrows)(\([^()]*\))?$"#, options: .regularExpression) {
            s = String(s[..<effect.lowerBound])
        }
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

    /// A call to a merged (`Tm`) function, without the type its symbol happens
    /// to name.
    ///
    /// LLVM's function merging keeps one body for functions that differ only
    /// in constants, which it now takes as arguments, and names it after
    /// whichever it kept: `storeEnumTagSinglePayload value witness for
    /// Reconstruction.OuterX.Wide` tail-called `merged
    /// storeEnumTagSinglePayload value witness for Reconstruction.IntQuad`, a
    /// type it has nothing to do with. The kind of function is shared by every
    /// caller; the type is not, so it reads `…`:
    ///
    ///     merged storeEnumTagSinglePayload value witness for …
    ///     merged protocol witness for Swift.Hashable.hashValue.getter : Swift.Int in conformance … : Swift.Hashable in M
    ///     merged ….hashValue.getter : Swift.Int
    ///
    /// The merged function's own header keeps its real symbol.
    static func mergedCallName(_ name: String) -> String {
        let prefix = "merged "
        guard name.hasPrefix(prefix) else { return name }
        var body = String(name.dropFirst(prefix.count))
        if let conformance = body.range(of: " in conformance "),
           let colon = body.range(of: " : ", range: conformance.upperBound..<body.endIndex) {
            body.replaceSubrange(conformance.upperBound..<colon.lowerBound, with: "…")
            return prefix + body
        }
        // `… value witness for T`, `outlined copy of T`: the type ends the name.
        if let subject = body.range(of: " for ", options: .backwards) ?? body.range(of: " of ", options: .backwards),
           !body[subject.upperBound...].contains("(") {
            body.replaceSubrange(subject.upperBound..., with: "…")
            return prefix + body
        }
        // `Context.member[.accessor][(parameters)][ : Type]`.
        let headEnd = [body.firstIndex(of: "("), body.range(of: " : ")?.lowerBound]
            .compactMap { $0 }.min() ?? body.endIndex
        let head = body[..<headEnd]
        guard var dot = head.lastIndex(of: ".") else { return name }
        let accessors: Set<Substring> = [
            "getter", "setter", "modify", "read", "willset", "didset", "unsafeAddressor", "unsafeMutableAddressor",
        ]
        if accessors.contains(head[head.index(after: dot)...]) {
            guard let memberDot = head[..<dot].lastIndex(of: ".") else { return name }
            dot = memberDot
        }
        let member = head[head.index(after: dot)...]
        guard !member.isEmpty, member.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
        else { return name }
        body.replaceSubrange(body.startIndex..<dot, with: "…")
        return prefix + body
    }

    /// Fixed-ABI runtime/libc entry points whose argument count is publicly
    /// stable, so a stale live register past the real parameter list is trimmed
    /// rather than printed as a fabricated argument (`abort([? x])` → `abort()`).
    ///
    /// Membership is deliberately conservative and asymmetric, matching the
    /// tracer's "never invent" rule: clamping only ever DROPS trailing values, so
    /// a wrong entry costs at most a missed argument — never a fabricated one. An
    /// unknown callee returns nil and keeps every recovered value. Message sends
    /// are intentionally absent: their arity comes from the selector's colons, and
    /// `MessageSend` already pairs those.
    static func knownCArity(of callee: String) -> Int? {
        switch callee {
        case "abort", "__stack_chk_fail", "objc_autoreleasePoolPush",
             "swift_unexpectedError", "objc_exception_rethrow", "exit":
            return 0
        case "objc_opt_class", "objc_opt_self", "objc_alloc", "objc_allocWithZone",
             "objc_alloc_init", "objc_opt_new", "objc_retain", "objc_release",
             "objc_autorelease", "objc_retainAutorelease",
             "objc_retainAutoreleasedReturnValue", "objc_claimAutoreleasedReturnValue",
             "objc_autoreleaseReturnValue", "objc_autoreleasePoolPop",
             "objc_sync_enter", "objc_sync_exit", "objc_begin_catch",
             "objc_retainBlock", "_Block_copy", "free",
             // swift/include/swift/Runtime/Concurrency.h: `void *(size_t)`
             // and `void (void *)`.
             "swift_task_alloc", "swift_task_dealloc",
             // swift/include/swift/Runtime/HeapObject.h: one object each.
             "swift_retain", "swift_release", "swift_bridgeObjectRetain", "swift_bridgeObjectRelease",
             "swift_unknownObjectRetain", "swift_unknownObjectRelease", "swift_errorRetain", "swift_errorRelease",
             "swift_unknownObjectWeakLoadStrong":
            return 1
        case "objc_opt_isKindOfClass", "objc_opt_respondsToSelector",
             "objc_storeStrong", "objc_storeWeak", "objc_initWeak",
             "objc_loadWeakRetained", "os_log_type_enabled", "objc_sync_wait":
            return 2
        case "objc_copyWeak", "objc_moveWeak", "memcpy", "memmove", "memset",
             // swift/include/swift/Runtime/RuntimeFunctions.def
             "swift_arrayDestroy":
            return 3
        case "swift_arrayInitWithCopy", "swift_arrayInitWithTakeFrontToBack", "swift_arrayInitWithTakeBackToFront":
            return 4
        default:
            // The formatted-emit os_log helpers: (dso, log, type, format, buf, size).
            if callee.hasPrefix("_os_log"), callee.hasSuffix("_impl") { return 6 }
            // `() -> WitnessTable` (swift/lib/IRGen/GenDecl.cpp:6384,
            // `FunctionType::get(WitnessTablePtrTy, false)`). A stale x0 used
            // to print as its argument, often a whole unrelated call.
            if callee.hasPrefix("lazy protocol witness table accessor for ") { return 0 }
            // Historical prefix match: some selectors resolve as
            // `objc_opt_isKindOfClass` with a trailing disambiguator.
            if callee.hasPrefix("objc_opt_isKindOfClass") { return 2 }
            return nil
        }
    }

    /// Checked-cast / safe-category helpers whose result IS one of their
    /// arguments — the object being cast — by that argument's index. Unwrapping
    /// them is faithful (the helper returns its operand unchanged) and mirrors the
    /// ARC identity unwrap, so a checked cast doesn't bury the value it wraps.
    /// These are pervasive in Apple's accessibility bundles, where nearly every
    /// cross-type access goes through one.
    static func castPassthroughIndex(of callee: String) -> Int? {
        switch callee {
        // (targetClass, value, shouldAssert, outError) — the value is argument 1.
        case "__UIAccessibilityCastAsClass", "__UIAccessibilityCastAsSafeCategory":
            return 1
        default:
            return nil
        }
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
            // Async context bookkeeping: every await allocates the callee's
            // context before the call and frees it in the resume funclet. It is
            // the lowering of the call, not a statement of the source.
            "swift_task_alloc", "swift_task_dealloc",
        ]
        return prefixes.contains { callee.hasPrefix($0) }
    }

    /// Runtime calls that return their (first) argument unchanged: the retain
    /// and autorelease family. Only these may be read through as their
    /// argument. The rest of `isRuntimeNoise` returns nothing (`swift_release`,
    /// `swift_beginAccess`) or something else entirely: `swift_task_alloc`
    /// returns fresh memory, and `swift_isUniquelyReferenced*` a Bool (the
    /// object's strong refcount is exactly one). Read through, the uniqueness
    /// check rendered `return self.storage` for a `-> Bool` CoW method.
    static func returnsItsArgument(_ callee: String) -> Bool {
        let name = callee.hasPrefix("_") ? String(callee.dropFirst()) : callee
        let identities: Set<String> = [
            "swift_retain", "swift_retain_n", "swift_nonatomic_retain",
            "swift_bridgeObjectRetain", "swift_bridgeObjectRetain_n",
            "swift_unknownObjectRetain", "swift_unknownObjectRetain_n",
            "objc_retain", "objc_autorelease", "objc_retainAutorelease",
            "objc_retainAutoreleasedReturnValue", "objc_claimAutoreleasedReturnValue",
            "objc_unsafeClaimAutoreleasedReturnValue", "objc_retainAutoreleaseReturnValue",
            "objc_autoreleaseReturnValue",
        ]
        return identities.contains(name)
    }

    /// `swift_isUniquelyReferenced*`: the lowering of `isKnownUniquelyReferenced`
    /// (`Builtin.isUnique`), a Bool over its object argument.
    static func isUniquenessCheck(_ callee: String) -> Bool {
        let name = callee.hasPrefix("_") ? String(callee.dropFirst()) : callee
        return name.hasPrefix("swift_isUniquelyReferenced")
    }

    // MARK: - Implicit generic plumbing

    /// A call whose *entire* purpose is the compiler's generic machinery — type
    /// metadata, protocol witness tables, mangled-name instantiation, and the
    /// `outlined` value-witness helpers. None of these appear in Swift source;
    /// the compiler inserts them to carry `<T>`/conformances across a call. When
    /// one surfaces as its own statement (its result unconsumed), hide it — it is
    /// scaffolding, not logic.
    ///
    /// Deliberately kept OUT of `isRuntimeNoise`: that predicate also drives the
    /// value tracer's "a call that returns its argument" unwrap in `Disassembler`,
    /// and a metadata accessor does not return its argument. This one is
    /// presentation-only.
    static func isGenericPlumbingCallee(_ callee: String) -> Bool {
        let prefixes = [
            "outlined ",
            "type metadata accessor for ",
            "type metadata completion function for ",
            "type metadata instantiation function for ",
            "lazy protocol witness table accessor ",
            "lazy protocol witness table cache variable ",
            "protocol witness table accessor ",
            "associated type descriptor for ",
            "associated conformance descriptor for ",
            "demangling cache variable for ",
            "__swift_instantiateConcreteTypeFromMangledName",
            // A defaulted parameter is lowered to a call to its generator; the
            // source didn't write it, so as a statement it's scaffolding.
            "default argument ",
        ]
        if prefixes.contains(where: callee.hasPrefix) { return true }
        // The outlined `Any`/existential box ARC helpers (`__swift_project_/
        // destroy_/allocate_boxed_opaque_existential…`) are bookkeeping around a
        // boxed value, with no source-level statement of their own.
        if callee.contains("boxed_opaque_existential") { return true }
        return genericPlumbingRuntimeNames.contains(where: callee.hasPrefix)
    }

    /// A rendered argument that is implicit generic plumbing rather than a source
    /// value: a type-metadata reference, a witness table, or a mangled-name type
    /// instantiation. In the Swift calling convention these are passed *after* the
    /// formal value arguments, so `strippingGenericPlumbing` only drops a trailing
    /// run of them — a metadata argument with real values after it (e.g. the type
    /// operand of `swift_allocObject`) is left untouched.
    static func isGenericPlumbingArgument(_ argument: String) -> Bool {
        let prefixes = [
            "type metadata accessor for ",
            "type metadata for ",
            "type metadata pattern for ",
            "protocol witness table for ",
            "protocol witness table accessor ",
            "lazy protocol witness table accessor ",
            "lazy protocol witness table cache variable ",
            "associated type witness table accessor ",
            "demangling cache variable for ",
            "__swift_instantiateConcreteTypeFromMangledName",
            "default argument ",
        ]
        if prefixes.contains(where: argument.hasPrefix) { return true }
        return genericPlumbingRuntimeNames.contains(where: argument.hasPrefix)
    }

    /// Runtime entry points (from the compiler's `RuntimeFunctions.def`) that
    /// only fetch or instantiate metadata / witness tables — implicit plumbing
    /// whether they appear as a statement or an argument.
    private static let genericPlumbingRuntimeNames = [
        "swift_getWitnessTable", "swift_getWitnessTableRelative",
        "swift_getAssociatedTypeWitness", "swift_getAssociatedTypeWitnessRelative",
        "swift_getAssociatedConformanceWitness",
        "swift_getGenericMetadata", "swift_getSingletonMetadata",
        "swift_getTypeByMangledNameInContext", "swift_getTypeByMangledNameInContextInMetadataState",
        "swift_getOpaqueTypeMetadata", "swift_getOpaqueTypeConformance",
        "swift_getMetatypeMetadata", "swift_getExistentialTypeMetadata",
        "swift_instantiateConcreteTypeFromMangledName",
        "__swift_instantiateConcreteTypeFromMangledName",
    ]

    /// Drop implicit-plumbing arguments, leaving the source-level values.
    ///
    /// Two removal rules, matched to how each kind sits in the Swift calling
    /// convention: a default-argument generator is never a source argument, so it
    /// is dropped wherever it appears (they interleave with unrecovered `?`
    /// slots); metadata / witness tables are passed *after* the formal arguments,
    /// so only a trailing run of them is removed — a metadata operand that
    /// precedes real arguments (e.g. the type operand of `swift_allocObject`) is
    /// preserved.
    static func strippingGenericPlumbing(_ arguments: [String]) -> [String] {
        var kept = arguments.filter { !$0.hasPrefix("default argument ") }
        while let last = kept.last, isGenericPlumbingArgument(last) { kept.removeLast() }
        return kept
    }

    /// The compact rendering of a Swift array-literal / varargs construction — a
    /// call to `_allocateUninitializedArray` (which returns an (array, buffer)
    /// pair the caller fills) or its `_finalizeUninitializedArray` handback. The
    /// elements box into the array's existential slots at ABI-specific offsets,
    /// too fragile to recover faithfully, so `[…]` shows the literal's presence
    /// without inventing its contents. Nil for any other callee.
    static func arrayLiteralPlaceholder(callee: String) -> String? {
        callee.contains("_allocateUninitializedArray")
            || callee.contains("_finalizeUninitializedArray")
            ? "[…]" : nil
    }

    /// Parse a Swift accessor's demangled name — `Module.Type.property.getter :
    /// ReturnType`, or the `.setter` form — into its property name and kind. Nil
    /// for any non-accessor name. Used to render a class's own vtable-dispatched
    /// getter/setter as `self.property` rather than a raw method call.
    static func swiftAccessorProperty(_ name: String) -> (property: String, isGetter: Bool)? {
        var base = name
        if let range = base.range(of: " : ") { base = String(base[..<range.lowerBound]) }
        if let range = base.range(of: " -> ") { base = String(base[..<range.lowerBound]) }
        let isGetter: Bool
        if base.hasSuffix(".getter") { isGetter = true; base = String(base.dropLast(7)) }
        else if base.hasSuffix(".setter") { isGetter = false; base = String(base.dropLast(7)) }
        else { return nil }
        guard let dot = base.lastIndex(of: ".") else { return nil }
        let property = String(base[base.index(after: dot)...])
        return property.isEmpty ? nil : (property, isGetter)
    }
}
