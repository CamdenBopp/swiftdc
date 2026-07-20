import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A **differential oracle** for recovered semantics.
///
/// Every other soundness test in this suite asserts that recovered pseudocode
/// matches a string someone wrote down. That catches regressions against what we
/// already believed, but it cannot catch a *plausible-but-wrong* render, because
/// the expected string was written by the same reasoning that produced the bug.
/// Defect U1 survived exactly that way: `(arg0 < 10)` looked right, matched its
/// test, and disagreed with the machine at every negative input.
///
/// This harness compares against the binary instead of against an expectation:
///
///   1. recover the expression swiftdc renders for a function,
///   2. parse it and evaluate it over a set of inputs,
///   3. call the **real compiled function** with the same inputs via `dlsym`,
///   4. assert the two agree.
///
/// A disagreement is a fabrication — an expression the binary does not support.
/// The ground-truth address comes from swiftdc's own reported symbol, so the
/// oracle cannot drift onto a different function than the one it analysed.
///
/// Deliberately narrow: pure integer/boolean functions with scalar arguments.
/// That is the domain where "semantically equal" is decidable by sampling, and
/// it is where the fabrications found so far have lived.

// MARK: - Expression AST

private indirect enum Expr {
    case literal(Int)
    case arg(Int)
    case binary(String, Expr, Expr)
    case ternary(Expr, Expr, Expr)
    case not(Expr)
    case negate(Expr)
    case bitNot(Expr)
}

private enum EvalValue: Equatable {
    case int(Int)
    case bool(Bool)

    /// Swift `Bool` and a 0/1 `Int` are the same fact here: the machine returns
    /// a register, and whether we call it Bool depends on the declared type.
    func matches(_ other: EvalValue) -> Bool {
        switch (self, other) {
        case let (.int(a), .int(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case let (.int(a), .bool(b)), let (.bool(b), .int(a)): return (a != 0) == b
        }
    }
}

private struct Unsupported: Error { let reason: String }

// MARK: - Parser
//
// swiftdc renders fully-parenthesized expressions, so no precedence table is
// needed — the parentheses already encode the tree. Anything outside the
// supported grammar throws `Unsupported` and the function is SKIPPED, never
// silently passed.

private struct ExpressionParser {
    private let tokens: [String]
    private var position = 0

    init(_ text: String) {
        var tokens: [String] = []
        var current = ""
        // Longest-first so `<=` and `&&` win over `<` and `&`. The unsigned
        // markers carry U+1D41 and must be matched before their bare forms.
        let operators = [
            "<=\u{1D41}", ">=\u{1D41}", "<\u{1D41}", ">\u{1D41}",
            "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
            "+", "-", "*", "/", "%", "&", "|", "^", "<", ">", "!", "~", "?", ":", "(", ")",
        ]
        let characters = Array(text)
        var index = 0
        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        outer: while index < characters.count {
            if characters[index] == " " { flush(); index += 1; continue }
            for op in operators {
                if characters[index...].starts(with: Array(op)) {
                    flush()
                    tokens.append(op)
                    index += op.count
                    continue outer
                }
            }
            current.append(characters[index])
            index += 1
        }
        flush()
        self.tokens = tokens
    }

    private var peek: String? { position < tokens.count ? tokens[position] : nil }

    private mutating func advance() -> String? {
        guard position < tokens.count else { return nil }
        defer { position += 1 }
        return tokens[position]
    }

    private mutating func expect(_ token: String) throws {
        guard advance() == token else { throw Unsupported(reason: "expected \(token)") }
    }

    mutating func parseAll() throws -> Expr {
        let expr = try parse()
        guard position == tokens.count else {
            throw Unsupported(reason: "trailing tokens at \(position)")
        }
        return expr
    }

    mutating func parse() throws -> Expr {
        guard let token = peek else { throw Unsupported(reason: "empty expression") }

        switch token {
        case "(":
            position += 1
            let lhs = try parse()
            guard let next = peek else { throw Unsupported(reason: "unterminated group") }
            if next == ")" { position += 1; return lhs }
            if next == "?" {
                position += 1
                let whenTrue = try parse()
                try expect(":")
                let whenFalse = try parse()
                try expect(")")
                return .ternary(lhs, whenTrue, whenFalse)
            }
            guard let op = advance() else { throw Unsupported(reason: "missing operator") }
            let rhs = try parse()
            try expect(")")
            return .binary(op, lhs, rhs)

        case "!":
            position += 1
            return .not(try parse())
        case "-":
            position += 1
            return .negate(try parse())
        case "~":
            position += 1
            return .bitNot(try parse())

        default:
            position += 1
            if token.hasPrefix("arg"), let index = Int(token.dropFirst(3)) {
                return .arg(index)
            }
            if let value = Int(token) { return .literal(value) }
            if token.hasPrefix("0x"), let value = Int(token.dropFirst(2), radix: 16) {
                return .literal(value)
            }
            throw Unsupported(reason: "token '\(token)'")
        }
    }
}

// MARK: - Evaluator
//
// Arithmetic uses the wrapping operators so the ORACLE can never trap. Inputs
// are chosen per function to stay inside the real function's non-trapping
// domain; if that choice were ever wrong, the compiled side would trap and the
// failure would be loud rather than a silently wrong comparison.

private func evaluate(_ expr: Expr, args: [Int]) throws -> EvalValue {
    func int(_ e: Expr) throws -> Int {
        guard case let .int(value) = try evaluate(e, args: args) else {
            throw Unsupported(reason: "expected integer operand")
        }
        return value
    }
    func bool(_ e: Expr) throws -> Bool {
        switch try evaluate(e, args: args) {
        case let .bool(value): return value
        case let .int(value): return value != 0
        }
    }

    switch expr {
    case let .literal(value): return .int(value)
    case let .arg(index):
        guard index < args.count else { throw Unsupported(reason: "arg\(index) out of range") }
        return .int(args[index])
    case let .not(e): return .bool(!(try bool(e)))
    case let .negate(e): return .int(0 &- (try int(e)))
    case let .bitNot(e): return .int(~(try int(e)))
    case let .ternary(condition, whenTrue, whenFalse):
        return try bool(condition) ? try evaluate(whenTrue, args: args)
                                   : try evaluate(whenFalse, args: args)
    case let .binary(op, lhs, rhs):
        switch op {
        case "&&": return .bool(try bool(lhs) && (try bool(rhs)))
        case "||": return .bool(try bool(lhs) || (try bool(rhs)))
        default: break
        }
        let a = try int(lhs), b = try int(rhs)
        switch op {
        case "+": return .int(a &+ b)
        case "-": return .int(a &- b)
        case "*": return .int(a &* b)
        case "/": return b == 0 ? .int(0) : .int(a == Int.min && b == -1 ? Int.min : a / b)
        case "%": return b == 0 ? .int(0) : .int(a == Int.min && b == -1 ? 0 : a % b)
        case "&": return .int(a & b)
        case "|": return .int(a | b)
        case "^": return .int(a ^ b)
        case "<<": return .int(a << b)
        case ">>": return .int(a >> b)
        case "==": return .bool(a == b)
        case "!=": return .bool(a != b)
        case "<": return .bool(a < b)
        case "<=": return .bool(a <= b)
        case ">": return .bool(a > b)
        case ">=": return .bool(a >= b)
        // Unsigned comparisons compare the raw bit patterns — the whole point of
        // the U1 fix is that these are NOT the signed ones.
        case "<\u{1D41}": return .bool(UInt(bitPattern: a) < UInt(bitPattern: b))
        case "<=\u{1D41}": return .bool(UInt(bitPattern: a) <= UInt(bitPattern: b))
        case ">\u{1D41}": return .bool(UInt(bitPattern: a) > UInt(bitPattern: b))
        case ">=\u{1D41}": return .bool(UInt(bitPattern: a) >= UInt(bitPattern: b))
        default: throw Unsupported(reason: "operator '\(op)'")
        }
    }
}

// MARK: - Ground truth

/// The compiled fixture, opened once. Ground truth is the machine code itself.
private final class FixtureImage {
    let handle: UnsafeMutableRawPointer
    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path),
              let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
        else { return nil }
        self.handle = handle
    }
    deinit { dlclose(handle) }

    /// Resolve by the RAW symbol swiftdc reported, so the oracle is guaranteed to
    /// be calling the same function it analysed.
    func function(symbol: String) -> UnsafeMutableRawPointer? {
        dlsym(handle, symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol)
    }
}

private func callInt(_ pointer: UnsafeMutableRawPointer, _ args: [Int]) -> Int {
    switch args.count {
    case 0: return unsafeBitCast(pointer, to: (@convention(c) () -> Int).self)()
    case 1: return unsafeBitCast(pointer, to: (@convention(c) (Int) -> Int).self)(args[0])
    case 2: return unsafeBitCast(pointer, to: (@convention(c) (Int, Int) -> Int).self)(args[0], args[1])
    case 3: return unsafeBitCast(pointer, to: (@convention(c) (Int, Int, Int) -> Int).self)(
        args[0], args[1], args[2])
    default: return unsafeBitCast(pointer, to: (@convention(c) (Int, Int, Int, Int) -> Int).self)(
        args[0], args[1], args[2], args[3])
    }
}

// MARK: - Cases

private struct OracleCase {
    let name: String
    let arity: Int
    /// Returns Bool — compare the low bit only, since the ABI leaves the rest of
    /// the register undefined for a Bool return.
    let returnsBool: Bool
    /// Inputs chosen to stay inside this function's non-trapping domain.
    let inputs: [[Int]]
}

private let edgeInts = [Int.min, -1_000, -1, 0, 1, 99, 100, 1_000, Int.max]
private let smallInts = [-1_000, -7, -1, 0, 1, 7, 1_000]

private func pairs(_ values: [Int]) -> [[Int]] {
    values.flatMap { a in values.map { b in [a, b] } }
}

private let oracleCases: [OracleCase] = [
    // Comparisons: no arithmetic, so the full edge set including Int.min/max is
    // safe — and it is exactly where a signed/unsigned confusion shows up.
    .init(name: "isPositive", arity: 1, returnsBool: true, inputs: edgeInts.map { [$0] }),
    .init(name: "signedLess", arity: 1, returnsBool: true, inputs: edgeInts.map { [$0] }),
    .init(name: "rangeCheck", arity: 1, returnsBool: true, inputs: edgeInts.map { [$0] }),
    .init(name: "isEqual", arity: 2, returnsBool: true, inputs: pairs(edgeInts)),
    .init(name: "atLeast", arity: 2, returnsBool: true, inputs: pairs(edgeInts)),
    // `computedRange` evaluates x + 1, which traps at Int.max — excluded.
    .init(
        name: "computedRange", arity: 1, returnsBool: true,
        inputs: edgeInts.filter { $0 != Int.max }.map { [$0] }
    ),
    // Arithmetic: small magnitudes only, so the compiled side cannot trap on
    // overflow. The oracle is about semantics, not about overflow behaviour.
    .init(name: "addThree", arity: 3, returnsBool: false,
          inputs: [[1, 2, 3], [-1, -2, -3], [0, 0, 0], [1000, -500, 7], [-7, 7, 0]]),
    .init(name: "fusedMultiplyAdd", arity: 3, returnsBool: false,
          inputs: [[1, 2, 3], [-1, 2, -3], [0, 5, 5], [10, 10, 10]]),
    .init(name: "bitOps", arity: 2, returnsBool: false, inputs: pairs(smallInts)),
    .init(name: "maxOf", arity: 2, returnsBool: false, inputs: pairs(smallInts)),
    .init(name: "clampLow", arity: 1, returnsBool: false, inputs: edgeInts.map { [$0] }),
    .init(name: "threeWay", arity: 1, returnsBool: false, inputs: edgeInts.map { [$0] }),
    .init(name: "constant", arity: 0, returnsBool: false, inputs: [[]]),
    .init(name: "deepNest", arity: 4, returnsBool: false,
          inputs: [[1, 2, 3, 4], [-1, -2, -3, -4], [0, 0, 0, 0], [7, -7, 7, -7]]),
]

// MARK: - The test

private let fixture = "Fixtures/Sample/libReconstruction.dylib"

/// Recover the rendered `return <expr>` and the raw symbol for `name`.
private func recovered(_ name: String) async throws -> (expression: String, symbol: String)? {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: fixture, functionFilter: name)
    }
    // Demangled names are `Reconstruction.name(...)`; match the callable exactly
    // so a substring hit on another function cannot be compared by mistake.
    guard let function = functions.first(where: {
        ($0.demangledName ?? "").contains(".\(name)(")
            || ($0.demangledName ?? "").hasSuffix(".\(name)")
    }) else { return nil }

    for line in function.renderPseudo().split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("return ") else { continue }
        return (String(trimmed.dropFirst("return ".count)), function.symbol)
    }
    return nil
}

@Test func recoveredExpressionsAgreeWithTheCompiledCode() async throws {
    guard let image = FixtureImage(path: fixture) else { return }  // fixture not built

    var compared = 0
    var skipped: [String] = []

    for testCase in oracleCases {
        guard let (expression, symbol) = try await recovered(testCase.name) else {
            skipped.append("\(testCase.name): not recovered")
            continue
        }
        var parser = ExpressionParser(expression)
        guard let tree = try? parser.parseAll() else {
            skipped.append("\(testCase.name): unparsed '\(expression)'")
            continue
        }
        guard let pointer = image.function(symbol: symbol) else {
            skipped.append("\(testCase.name): symbol \(symbol) not found")
            continue
        }

        for args in testCase.inputs {
            guard let predicted = try? evaluate(tree, args: args) else {
                skipped.append("\(testCase.name): uneval '\(expression)'")
                break
            }
            let raw = callInt(pointer, args)
            let actual: EvalValue = testCase.returnsBool ? .bool((raw & 1) != 0) : .int(raw)

            #expect(
                predicted.matches(actual),
                """
                \(testCase.name)(\(args.map(String.init).joined(separator: ", "))): \
                swiftdc renders `\(expression)` → \(predicted), \
                but the compiled function returns \(actual). \
                The recovered expression is not supported by the binary.
                """
            )
            compared += 1
        }
    }

    // The empty-result rule applies to the oracle itself: a harness that silently
    // compares nothing is worse than no harness, because it reports success. If a
    // parser or naming change stops these from being recovered, this fails.
    #expect(
        compared >= 200,
        "differential oracle compared only \(compared) input(s); skipped: \(skipped)"
    )
    #expect(
        skipped.count <= oracleCases.count / 2,
        "over half the oracle cases were skipped: \(skipped)"
    )
}
