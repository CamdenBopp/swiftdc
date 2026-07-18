import Foundation

/// Post-pass peephole folders that turn recovered call sequences back into the
/// Swift idioms they were lowered from. Each fold is *faithful*: it only rewrites
/// a run of statements when the run unambiguously reconstructs to source, and
/// bails (leaving the raw statements) the moment a piece is missing. Nothing is
/// invented — a value we cannot name stays as the frame slot the tracer recovered.
extension DisassembledFunction {
    /// Run every idiom folder over a function's rendered statements, in order.
    static func foldSwiftIdioms(_ rawStatements: [String]) -> [String] {
        let statements = rawStatements.map { strippingNestedPlumbing($0) }
        var out: [String] = []
        var index = 0
        while index < statements.count {
            if let (literal, consumed) = matchStringInterpolation(statements, at: index) {
                out.append(literal)
                index += consumed
                continue
            }
            if let literal = standaloneStringLiteral(statements[index]) {
                out.append(literal)
                index += 1
                continue
            }
            out.append(statements[index])
            index += 1
        }
        return out
    }

    // MARK: - String interpolation

    /// Match a run of `DefaultStringInterpolation.appendLiteral` /
    /// `appendInterpolation` statements (as the compiler lowers `"a\(x)b"`) and
    /// rebuild the interpolated literal. Returns the rebuilt literal and the
    /// number of statements consumed, or nil if `at` does not begin such a run or
    /// a literal segment can't be recovered.
    static func matchStringInterpolation(_ statements: [String], at start: Int) -> (String, Int)? {
        var components = ""
        var index = start
        var sawInterpolation = false
        while index < statements.count {
            let statement = statements[index]
            if statement.contains("DefaultStringInterpolation.appendLiteral") {
                guard let inner = firstArgument(of: statement),
                      let literal = stringLiteralValue(ofInit: inner)
                else { return nil }
                components += escapeForInterpolation(literal)
                index += 1
            } else if statement.contains("DefaultStringInterpolation.appendInterpolation") {
                let value = firstArgument(of: statement) ?? "?"
                components += "\\(\(value))"
                sawInterpolation = true
                index += 1
            } else {
                break
            }
        }
        // The `let s = "…"` that consumes the builder into a String — part of the
        // same lowering, so fold it away if it trails the run.
        if index < statements.count,
           statements[index].contains("String.init"),
           statements[index].contains("DefaultStringInterpolation.init") {
            index += 1
        }
        // A run with no interpolation is just a literal; leave that to the
        // standalone folder so this only claims genuine interpolations.
        guard sawInterpolation, index > start else { return nil }
        return ("\"\(components)\"", index - start)
    }

    /// A bare Swift string-literal construction — `String.init("hi", 2, 1)`,
    /// the `(contents, utf8Count, isASCII)` literal initializer — rendered as the
    /// literal itself. Returns nil for any other `String.init`.
    static func standaloneStringLiteral(_ statement: String) -> String? {
        guard statement.hasPrefix("Swift.String.init(") || statement.hasPrefix("String.init("),
              let literal = stringLiteralValue(ofInit: statement)
        else { return nil }
        return "\"\(escapeForInterpolation(literal))\""
    }

    /// The literal text of a `String.init(contents, count, isASCII)` expression:
    /// the quoted contents when present, or `""` when the count operand is `0`
    /// (an empty segment, common as an interpolation's trailing piece). Nil when
    /// the contents are only a pointer we could not decode, so a fold that needs
    /// this can bail rather than print a wrong literal.
    static func stringLiteralValue(ofInit expression: String) -> String? {
        guard expression.contains("String.init"),
              let arguments = outermostArgumentList(of: expression)
        else { return nil }
        let parts = splitTopLevelArguments(arguments)
        guard parts.count == 3 else { return nil }
        if parts[0].hasPrefix("\""), parts[0].hasSuffix("\""), parts[0].count >= 2 {
            return String(parts[0].dropFirst().dropLast())
        }
        if parts[1] == "0" { return "" }
        return nil
    }

    // MARK: - Expression parsing

    /// The first top-level argument of a rendered call expression, or nil when it
    /// takes none. Handles a callee that itself contains parentheses (e.g.
    /// `(extension in Swift):…`) by taking the *last* top-level `(...)` group.
    static func firstArgument(of expression: String) -> String? {
        guard let arguments = outermostArgumentList(of: expression) else { return nil }
        return splitTopLevelArguments(arguments).first
    }

    /// The contents of the call's argument list: the last parenthesized group at
    /// bracket depth zero, skipping any parentheses inside string literals.
    static func outermostArgumentList(of expression: String) -> Substring? {
        outermostArgumentListRange(of: expression).map { expression[$0] }
    }

    /// The index range of the argument list's *contents* (between, not including,
    /// the outermost `(` and `)`), so callers can rebuild `prefix(newArgs)suffix`.
    static func outermostArgumentListRange(of expression: String) -> Range<String.Index>? {
        var depth = 0
        var inQuote = false
        var groupStart: String.Index?
        var lastGroup: Range<String.Index>?
        var index = expression.startIndex
        while index < expression.endIndex {
            let character = expression[index]
            if character == "\"" {
                inQuote.toggle()
            } else if !inQuote {
                if character == "(" {
                    if depth == 0 { groupStart = expression.index(after: index) }
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0, let groupStart { lastGroup = groupStart..<index }
                }
            }
            index = expression.index(after: index)
        }
        return lastGroup
    }

    /// Recursively drop trailing generic-plumbing arguments from every call group
    /// in a rendered expression, not just the outermost one — so nested builders
    /// like `Point.init(_allocateUninitializedArray(2, <mangled-name>))` lose the
    /// implicit metadata argument too. Message sends, arithmetic, and literals
    /// pass through unchanged (they have no call-argument group to prune).
    static func strippingNestedPlumbing(_ expression: String) -> String {
        guard let range = outermostArgumentListRange(of: expression) else { return expression }
        let prefix = expression[expression.startIndex..<range.lowerBound]
        let suffix = expression[range.upperBound...]
        let arguments = splitTopLevelArguments(expression[range])
            .map { strippingNestedPlumbing($0) }
        let kept = strippingGenericPlumbing(arguments)
        return prefix + kept.joined(separator: ", ") + suffix
    }

    /// Split an argument list on commas that sit at bracket/paren/angle depth zero
    /// and outside string literals, so nested calls and generic clauses stay whole.
    ///
    /// The `>` of a function-type arrow (`(String) -> Bool`) is NOT a closing
    /// angle bracket; counting it as one desynchronises the depth and merges the
    /// arguments that follow — which used to hide the trailing plumbing after a
    /// closure argument. It is recognised by its preceding `-` and skipped.
    static func splitTopLevelArguments(_ arguments: Substring) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        var previous: Character = " "
        for character in arguments {
            if character == "\"" {
                inQuote.toggle()
                current.append(character)
            } else if inQuote {
                current.append(character)
            } else if character == "(" || character == "[" || character == "<" {
                depth += 1
                current.append(character)
            } else if character == ">" && previous == "-" {
                current.append(character) // the arrow `->`, not a closing angle
            } else if character == ")" || character == "]" || character == ">" {
                depth -= 1
                current.append(character)
            } else if character == "," && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    /// Escape a recovered literal for embedding in a rendered `"…"` so the output
    /// stays a single well-formed string.
    private static func escapeForInterpolation(_ literal: String) -> String {
        literal
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
