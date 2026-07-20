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
    case doubleLiteral(Double)
    case call(String, Expr)
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
    case double(Double)

    /// Swift `Bool` and a 0/1 `Int` are the same fact here: the machine returns
    /// a register, and whether we call it Bool depends on the declared type.
    ///
    /// Doubles compare **bit-exactly**, not approximately. That is the whole
    /// point for floating point: a rendered constant like `3.14` is a claim about
    /// which of ~2^64 doubles the binary actually holds, and an approximate
    /// comparison would accept a rounded or truncated decimal — precisely the
    /// fabrication this is meant to detect. NaN is the one exception: it is never
    /// bit-stable across a computation, so any-NaN vs any-NaN counts as agreement.
    func matches(_ other: EvalValue) -> Bool {
        switch (self, other) {
        case let (.int(a), .int(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case let (.int(a), .bool(b)), let (.bool(b), .int(a)): return (a != 0) == b
        case let (.double(a), .double(b)):
            if a.isNaN && b.isNaN { return true }
            return a.bitPattern == b.bitPattern
        case let (.double(a), .int(b)), let (.int(b), .double(a)):
            return a == Double(b)
        default: return false
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
            // `sqrt(...)` and friends: an identifier immediately followed by a
            // group. Rendered by swiftdc for intrinsics it recognises.
            if peek == "(" {
                position += 1
                let argument = try parse()
                try expect(")")
                return .call(token, argument)
            }
            // A decimal point or exponent means this is a floating-point literal.
            // Swift's Double(String) is correctly rounded, so parsing the rendered
            // text reproduces exactly the double that text denotes — which is what
            // makes a bit-exact comparison against the binary meaningful.
            if token.contains(".") || token.lowercased().contains("e"),
               let value = Double(token) {
                return .doubleLiteral(value)
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
        case let .double(value): return value != 0
        }
    }
    /// A value usable as a Double, whether it arrived as one or as an integer
    /// literal in a floating-point expression (`(arg0 * 2)`).
    func asDouble(_ e: Expr) throws -> Double? {
        switch try evaluate(e, args: args) {
        case let .double(value): return value
        case let .int(value): return Double(value)
        case .bool: return nil
        }
    }

    switch expr {
    case let .literal(value): return .int(value)
    case let .doubleLiteral(value): return .double(value)
    case let .call(name, argument):
        guard let operand = try asDouble(argument) else {
            throw Unsupported(reason: "non-numeric argument to \(name)")
        }
        switch name {
        // `squareRoot()` lowers to the fsqrt instruction, which is
        // correctly-rounded per IEEE 754 — so Swift's own squareRoot() is
        // bit-identical, not merely close.
        case "sqrt": return .double(operand.squareRoot())
        case "abs", "fabs": return .double(Swift.abs(operand))
        default: throw Unsupported(reason: "call to \(name)")
        }
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
        // Promote to floating point only when an operand genuinely IS floating
        // point. The integer path is unchanged, so its wrapping semantics and
        // its existing verified results are untouched.
        let lhsValue = try evaluate(lhs, args: args)
        let rhsValue = try evaluate(rhs, args: args)
        if case .double = lhsValue {} else if case .double = rhsValue {} else {
            return try integerBinary(op, try int(lhs), try int(rhs))
        }
        guard let x = try asDouble(lhs), let y = try asDouble(rhs) else {
            throw Unsupported(reason: "mixed operands for '\(op)'")
        }
        switch op {
        case "+": return .double(x + y)
        case "-": return .double(x - y)
        case "*": return .double(x * y)
        case "/": return .double(x / y)
        case "==": return .bool(x == y)
        case "!=": return .bool(x != y)
        case "<": return .bool(x < y)
        case "<=": return .bool(x <= y)
        case ">": return .bool(x > y)
        case ">=": return .bool(x >= y)
        default: throw Unsupported(reason: "float operator '\(op)'")
        }
    }
}

/// The integer arithmetic path, unchanged and factored out so the float branch
/// above cannot perturb it.
private func integerBinary(_ op: String, _ a: Int, _ b: Int) throws -> EvalValue {
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

// MARK: - Ground truth

/// The compiled fixture, opened once. Ground truth is the machine code itself.
private final class FixtureImage {
    let handle: UnsafeMutableRawPointer
    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path),
              let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
        else { return nil }
        self.handle = handle
        self.path = path
    }
    deinit { dlclose(handle) }

    let path: String

    /// Resolve by the RAW symbol swiftdc reported, so the oracle is guaranteed to
    /// be calling the same function it analysed.
    ///
    /// Then verify, via `dladdr`, that the address actually lies in THIS image.
    /// The `-Onone` and `-O` fixtures are two builds of the same source, so they
    /// export byte-identical mangled symbols — the objc runtime says so out loud
    /// ("Class ... is implemented in both ..."). If `dlsym` resolved to the
    /// first-loaded image, the `-O` half of this oracle would be silently
    /// re-testing `-Onone` code while reporting optimized coverage. That is the
    /// no-op-that-passes failure this harness exists to prevent, so it is
    /// checked rather than assumed.
    func function(symbol: String) -> UnsafeMutableRawPointer? {
        let name = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        guard let pointer = dlsym(handle, name) else { return nil }
        var info = Dl_info()
        guard dladdr(pointer, &info) != 0, let owner = info.dli_fname else { return nil }
        let resolved = URL(fileURLWithPath: String(cString: owner)).resolvingSymlinksInPath().path
        let expected = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolved == expected else { return nil }
        return pointer
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

/// Both optimization levels are oracles in their own right.
///
/// `-O` is not a nice-to-have here: it lowers differently, and it is where U1
/// actually lived. A signed range check becomes a single UNSIGNED compare
/// (`cmp x0, #100; cset w0, lo`), which swiftdc renders as the source-level
/// idiom `((0 <= arg0) && (arg0 < 100))`. Whether that idiom is genuinely
/// equivalent to the machine's unsigned test has, until now, only ever been
/// reasoned about — never executed. `csel` ternaries, commuted operands, and
/// functions recovered at one level but not the other are all in the same
/// position.
private struct Fixture {
    let path: String
    let label: String
    /// Cases that MUST be compared at this level. A skip here is a regression,
    /// not a limitation — see the no-op injection lesson in the test below.
    let required: Set<String>
    /// Floor on comparisons for this level alone, so losing a whole fixture
    /// cannot hide behind the other one's total.
    let minimumComparisons: Int
}

private let fixtures = [
    Fixture(
        path: "Fixtures/Sample/libReconstruction.dylib", label: "-Onone",
        required: ["isPositive", "isEqual", "atLeast", "rangeCheck", "addThree", "maxOf"],
        minimumComparisons: 200
    ),
    Fixture(
        path: "Fixtures/Sample/libReconstruction.opt.dylib", label: "-O",
        // `rangeCheck` and `computedRange` are the U1 idiom itself; `threeWay`
        // is a csel cascade that only survives at -O. If any stops being
        // compared, the oracle has lost the coverage it exists for.
        required: ["rangeCheck", "computedRange", "threeWay", "maxOf", "isPositive"],
        minimumComparisons: 200
    ),
]

/// Recover the rendered `return <expr>` and the raw symbol for `name`.
private func recovered(
    _ name: String, in fixture: String
) async throws -> (expression: String, symbol: String)? {
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
    for fixture in fixtures {
        guard let image = FixtureImage(path: fixture.path) else { continue }  // not built

        var compared = 0
        var skipped: [String] = []
        var comparedNames: Set<String> = []

        for testCase in oracleCases {
            guard let (expression, symbol) = try await recovered(
                testCase.name, in: fixture.path
            ) else {
                // Legitimate at -O: inlining and ICF can remove a function
                // entirely. `required` below is what separates "optimized away"
                // from "we stopped recovering it".
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
                    [\(fixture.label)] \
                    \(testCase.name)(\(args.map(String.init).joined(separator: ", "))): \
                    swiftdc renders `\(expression)` → \(predicted), \
                    but the compiled function returns \(actual). \
                    The recovered expression is not supported by the binary.
                    """
                )
                compared += 1
                comparedNames.insert(testCase.name)
            }
        }

        // The empty-result rule applies to the oracle itself: a harness that
        // silently compares nothing is worse than no harness, because it reports
        // success. Checked PER FIXTURE so an empty -O run cannot hide inside the
        // -Onone total.
        #expect(
            compared >= fixture.minimumComparisons,
            "[\(fixture.label)] compared only \(compared) input(s); skipped: \(skipped)"
        )

        // Named cases, not just a count. A count floor is satisfiable by the easy
        // cases while the interesting ones quietly stop being recovered — which is
        // exactly how the first sensitivity injection for this harness passed as a
        // no-op. These are the cases the oracle exists for.
        let missing = fixture.required.subtracting(comparedNames)
        #expect(
            missing.isEmpty,
            "[\(fixture.label)] required cases were not compared: \(missing.sorted()); skipped: \(skipped)"
        )
    }
}

// MARK: - Floating point
//
// A separate case list, because floating point asks a different question than
// integers do. `polynomial` renders as `((arg0 * arg0) + 3.14)`: that decimal is
// a claim about WHICH of ~2^64 doubles the binary holds. swiftdc decodes it from
// the machine encoding (fmov-encodable constants) or from a literal pool, then
// prints a decimal — and printing loses information unless it round-trips. Only
// executing both sides bit-exactly can confirm it.
//
// The edge inputs are chosen for the ways float breaks and integers do not:
// signed zero, subnormals, infinities, and NaN.

private enum FloatSignature {
    case d_d          // (Double) -> Double
    case dd_d         // (Double, Double) -> Double
    case ff_f         // (Float, Float) -> Float
    case idid_d       // (Int, Double, Int, Double) -> Double
    case void_d       // () -> Double
}

private struct FloatCase {
    let name: String
    let signature: FloatSignature
    let inputs: [[Double]]
}

private let edgeDoubles: [Double] = [
    0.0, -0.0, 1.0, -1.0, 0.5, -2.5, 3.14, 1e308, -1e308,
    .leastNonzeroMagnitude, .infinity, -.infinity, .nan,
]

private let floatCases: [FloatCase] = [
    .init(name: "scaled", signature: .d_d, inputs: edgeDoubles.map { [$0] }),
    .init(name: "polynomial", signature: .d_d, inputs: edgeDoubles.map { [$0] }),
    .init(
        name: "hypotenuse", signature: .dd_d,
        inputs: edgeDoubles.flatMap { a in edgeDoubles.map { b in [a, b] } }
    ),
    .init(
        name: "floatMath", signature: .ff_f,
        // Float, not Double: a narrower type whose rounding differs. Values are
        // kept inside Float's range so the comparison tests arithmetic rather
        // than overflow-to-infinity.
        inputs: [0.0, -0.0, 1.0, -1.0, 0.5, -2.5, 3.5, 1e30, -1e30, .infinity, .nan]
            .flatMap { a in [0.0, 1.0, -1.0, 2.0, 0.5, .nan].map { b in [a, b] } }
    ),
    .init(
        name: "interleaved", signature: .idid_d,
        // (Int, Double, Int, Double) -> Double. swiftdc renders `(arg1 + arg3)`,
        // an ABI claim: integers occupy x0/x1 while doubles occupy d0/d1, and the
        // rendered argN indices refer to SOURCE positions, not register order. If
        // that mapping were wrong the sum would pick up the wrong operands.
        inputs: edgeDoubles.flatMap { a in [0.0, 1.0, -2.5, .infinity].map { b in [a, b] } }
    ),
    .init(name: "piValue", signature: .void_d, inputs: [[]]),
]

private func callFloat(
    _ pointer: UnsafeMutableRawPointer, _ signature: FloatSignature, _ args: [Double]
) -> EvalValue {
    switch signature {
    case .d_d:
        return .double(unsafeBitCast(pointer, to: (@convention(c) (Double) -> Double).self)(args[0]))
    case .dd_d:
        return .double(unsafeBitCast(
            pointer, to: (@convention(c) (Double, Double) -> Double).self)(args[0], args[1]))
    case .ff_f:
        let result = unsafeBitCast(pointer, to: (@convention(c) (Float, Float) -> Float).self)(
            Float(args[0]), Float(args[1]))
        return .double(Double(result))
    case .idid_d:
        return .double(unsafeBitCast(
            pointer, to: (@convention(c) (Int, Double, Int, Double) -> Double).self)(
                0, args[0], 0, args[1]))
    case .void_d:
        return .double(unsafeBitCast(pointer, to: (@convention(c) () -> Double).self)())
    }
}

/// Arguments as the RENDERED expression indexes them (by source position).
private func floatArgs(_ signature: FloatSignature, _ inputs: [Double]) -> [Double] {
    switch signature {
    case .d_d, .void_d: return inputs
    case .dd_d, .ff_f: return inputs
    // arg0/arg2 are the integers (always 0 here); arg1/arg3 are the doubles.
    case .idid_d: return [0, inputs[0], 0, inputs[1]]
    }
}

/// `floatMath` is Float-typed, so the oracle must round each intermediate to
/// Float precision to match the machine. Evaluating in Double would silently
/// disagree wherever Float rounding differs — and would look like a swiftdc bug.
private func evaluateFloat(
    _ tree: Expr, args: [Double], asFloat: Bool
) throws -> EvalValue {
    if !asFloat {
        return try evaluateDouble(tree, args: args)
    }
    let result = try evaluateFloat32(tree, args: args.map { Float($0) })
    return .double(Double(result))
}

private func evaluateDouble(_ tree: Expr, args: [Double]) throws -> EvalValue {
    switch tree {
    case let .doubleLiteral(value): return .double(value)
    case let .literal(value): return .double(Double(value))
    case let .arg(index):
        guard index < args.count else { throw Unsupported(reason: "arg\(index)") }
        return .double(args[index])
    case let .negate(e):
        guard case let .double(v) = try evaluateDouble(e, args: args) else {
            throw Unsupported(reason: "negate")
        }
        return .double(-v)
    case let .call(name, argument):
        guard case let .double(v) = try evaluateDouble(argument, args: args) else {
            throw Unsupported(reason: "call arg")
        }
        switch name {
        case "sqrt": return .double(v.squareRoot())
        case "abs", "fabs": return .double(Swift.abs(v))
        default: throw Unsupported(reason: "call \(name)")
        }
    case let .binary(op, lhs, rhs):
        guard case let .double(x) = try evaluateDouble(lhs, args: args),
              case let .double(y) = try evaluateDouble(rhs, args: args)
        else { throw Unsupported(reason: "operand") }
        switch op {
        case "+": return .double(x + y)
        case "-": return .double(x - y)
        case "*": return .double(x * y)
        case "/": return .double(x / y)
        default: throw Unsupported(reason: "float op '\(op)'")
        }
    default: throw Unsupported(reason: "unsupported float node")
    }
}

private func evaluateFloat32(_ tree: Expr, args: [Float]) throws -> Float {
    switch tree {
    case let .doubleLiteral(value): return Float(value)
    case let .literal(value): return Float(value)
    case let .arg(index):
        guard index < args.count else { throw Unsupported(reason: "arg\(index)") }
        return args[index]
    case let .negate(e): return -(try evaluateFloat32(e, args: args))
    case let .call(name, argument):
        let v = try evaluateFloat32(argument, args: args)
        switch name {
        case "sqrt": return v.squareRoot()
        case "abs", "fabs": return Swift.abs(v)
        default: throw Unsupported(reason: "call \(name)")
        }
    case let .binary(op, lhs, rhs):
        let x = try evaluateFloat32(lhs, args: args)
        let y = try evaluateFloat32(rhs, args: args)
        switch op {
        case "+": return x + y
        case "-": return x - y
        case "*": return x * y
        case "/": return x / y
        default: throw Unsupported(reason: "float op '\(op)'")
        }
    default: throw Unsupported(reason: "unsupported float node")
    }
}

/// Cases that must be compared at each level. `polynomial` and `scaled` carry the
/// constant-decoding claim; `hypotenuse` covers an intrinsic; `interleaved`
/// covers the mixed-register ABI. Losing any of them silently would remove the
/// reason this test exists — a comparison count alone would not notice.
private let requiredFloatCases: Set<String> = [
    "scaled", "polynomial", "hypotenuse", "interleaved",
]

@Test func recoveredFloatExpressionsAgreeWithTheCompiledCode() async throws {
    for fixture in fixtures {
        guard let image = FixtureImage(path: fixture.path) else { continue }

        var compared = 0
        var skipped: [String] = []
        var comparedNames: Set<String> = []

        for testCase in floatCases {
            guard let (expression, symbol) = try await recovered(
                testCase.name, in: fixture.path
            ) else {
                skipped.append("\(testCase.name): not recovered")
                continue
            }
            var parser = ExpressionParser(expression)
            guard let tree = try? parser.parseAll() else {
                skipped.append("\(testCase.name): unparsed '\(expression)'")
                continue
            }
            guard let pointer = image.function(symbol: symbol) else {
                skipped.append("\(testCase.name): symbol not in this image")
                continue
            }

            let isFloat32 = testCase.signature == .ff_f
            for inputs in testCase.inputs {
                let indexed = floatArgs(testCase.signature, inputs)
                guard let predicted = try? evaluateFloat(
                    tree, args: indexed, asFloat: isFloat32
                ) else {
                    skipped.append("\(testCase.name): uneval '\(expression)'")
                    break
                }
                let actual = callFloat(pointer, testCase.signature, inputs)

                #expect(
                    predicted.matches(actual),
                    """
                    [\(fixture.label)] \
                    \(testCase.name)(\(inputs.map { "\($0)" }.joined(separator: ", "))): \
                    swiftdc renders `\(expression)` → \(predicted), \
                    but the compiled function returns \(actual). \
                    Bit-exact comparison: the rendered expression is not supported by the binary.
                    """
                )
                compared += 1
                comparedNames.insert(testCase.name)
            }
        }

        #expect(
            compared >= 150,
            "[\(fixture.label)] float oracle compared only \(compared); skipped: \(skipped)"
        )
        let missing = requiredFloatCases.subtracting(comparedNames)
        #expect(
            missing.isEmpty,
            "[\(fixture.label)] required float cases not compared: \(missing.sorted()); skipped: \(skipped)"
        )
    }
}
