import Foundation

/// A first-cut pseudocode view: each function rendered as its sequence of
/// recovered calls and named field writes, with low-level ARC/runtime
/// bookkeeping hidden. Not a structured decompiler — it surfaces the useful
/// statements that the CFG + value-tracking already recover.
public extension DisassembledFunction {
    func renderPseudo(hideRuntime: Bool = true) -> String {
        var lines = ["\(displayName) {"]
        if let objcMethod { lines.append("    // \(objcMethod.signature)") }
        var statements: [String] = []
        for insn in instructions {
            guard let statement = Self.pseudoStatement(of: insn, hideRuntime: hideRuntime) else { continue }
            statements.append(statement)
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
        if let annotation = insn.annotation {
            let semantic = annotation.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { note in
                    if note.hasPrefix("return ") { return true }
                    if note.hasPrefix("yield ") { return true }
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
             "objc_retainBlock", "_Block_copy", "free":
            return 1
        case "objc_opt_isKindOfClass", "objc_opt_respondsToSelector",
             "objc_storeStrong", "objc_storeWeak", "objc_initWeak",
             "objc_loadWeakRetained", "os_log_type_enabled", "objc_sync_wait":
            return 2
        case "objc_copyWeak", "objc_moveWeak":
            return 3
        default:
            // The formatted-emit os_log helpers: (dso, log, type, format, buf, size).
            if callee.hasPrefix("_os_log"), callee.hasSuffix("_impl") { return 6 }
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
        ]
        return prefixes.contains { callee.hasPrefix($0) }
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
