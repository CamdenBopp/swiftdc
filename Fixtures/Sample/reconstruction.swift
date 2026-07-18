// Fixture exercising swiftdc's Swift-body reconstruction features, one
// construct per function so the pseudocode assertions in
// `ReconstructionTests.swift` stay legible. Built by `build.sh` into
// `libReconstruction.dylib` (-Onone -g, where the recovery is richest).
//
// Keep the shapes below stable: the tests assert the exact recovered
// pseudocode, so renaming a property or reordering a computation changes the
// expected output.

// MARK: - Comparisons (NZCV + cset)

public func isPositive(_ x: Int) -> Bool { x > 0 }
public func isEqual(_ a: Int, _ b: Int) -> Bool { a == b }
public func atLeast(_ a: Int, _ b: Int) -> Bool { a >= b }

// MARK: - Integer + floating-point argument seeding

public func addThree(_ a: Int, _ b: Int, _ c: Int) -> Int { a + b + c }
public func hypotenuse(_ a: Double, _ b: Double) -> Double { (a * a + b * b).squareRoot() }
public func scaleInt(_ n: Int, by f: Double) -> Double { Double(n) * f }

// MARK: - HFA struct decomposition (self + by-value struct params)

public struct Vec2 {
    var x: Double
    var y: Double
    public var magnitudeSquared: Double { x * x + y * y }
    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    public mutating func scale(_ k: Double) { x = x * k; y = y * k }
}

// MARK: - Class vtable getters/setters (self.property)

public class Counter {
    var value: Int
    var step: Int
    public init(value: Int, step: Int) { self.value = value; self.step = step }
    public var doubled: Int { value + value }
    public func advance() { value = value + step }
    public func reset() { value = 0 }
}

// MARK: - Dynamic casts

public protocol Shape {}
public class Animal {}
public class Dog: Animal {}

public func castOptional(_ a: Animal) -> Dog? { a as? Dog }
public func castForced(_ a: Animal) -> Dog { a as! Dog }
public func castToString(_ x: Any) -> String? { x as? String }

// MARK: - Homogeneous array literals

public func triple() -> [Int] { [10, 20, 30] }
public func pairOf(_ a: Int, _ b: Int) -> [Int] { [a, b] }
public func doublesOf(_ a: Double, _ b: Double) -> [Double] { [a, b] }

// MARK: - Wider constructs (edge cases)

public func bitOps(_ a: Int, _ b: Int) -> Int { (a & b) | (a << 2) }
public func floatMath(_ a: Float, _ b: Float) -> Float { a * b + a }
public func intDivide(_ a: Int, _ b: Int) -> Int { a / b }
public func remainder(_ a: Int, _ b: Int) -> Int { a % b }
public func fusedMultiplyAdd(_ a: Int, _ b: Int, _ c: Int) -> Int { a + b * c }

// A 3-field HFA struct: self decomposes across d0, d1, d2.
public struct RGB {
    var r: Double
    var g: Double
    var b: Double
    public var luminance: Double { r + g + b }
}

// MARK: - Robustness edge cases (deep nesting, many args, mixed, constants)

public func constant() -> Int { 42 }

public func deepNest(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Int {
    ((a + b) * (c - d)) + ((a - c) * (b + d))
}

// All eight integer argument registers x0…x7.
public func eightArgs(_ a: Int, _ b: Int, _ c: Int, _ d: Int,
                      _ e: Int, _ f: Int, _ g: Int, _ h: Int) -> Int {
    a + b + c + d + e + f + g + h
}

// Interleaved integer (x0, x1) and floating-point (v0, v1) parameters.
public func interleaved(_ i: Int, _ d: Double, _ j: Int, _ e: Double) -> Double { d + e }

// MARK: - Ternary / select reconstruction (control-flow value merge)

public func clampLow(_ x: Int) -> Int { x < 0 ? 0 : x }
public func maxOf(_ a: Int, _ b: Int) -> Int { a > b ? a : b }
public func pickInc(_ c: Bool, _ a: Int) -> Int { c ? a + 1 : a - 1 }

// Negative: a THREE-way merge is not a clean 2-arm diamond, so the tool must
// decline to reconstruct a select rather than guess one.
public func threeWay(_ x: Int) -> Int {
    let r: Int
    if x < 0 { r = -10 } else if x == 0 { r = 0 } else { r = 10 }
    return r
}

// Pointer-optional nil-coalescing: a pointer optional is one register (nil == 0),
// so `x ?? f` reconstructs at -O via csel as `(arg0 == 0) ? arg1 : arg0`. The
// -Onone lowering's redundant double nil-check is a three-way merge that declines.
public func ptrOrElse(_ x: UnsafeRawPointer?, _ f: UnsafeRawPointer) -> UnsafeRawPointer { x ?? f }

// Negative: a TAGGED optional (`Int?`) is multi-register (payload + tag byte);
// its nil check isn't a single-register diamond, so it declines to guess.
public func intOrDefault(_ x: Int?) -> Int { x ?? -1 }

// MARK: - No-payload enum case naming (immediate tag → .case)

// A no-payload enum: the returned tag is the declaration index, so it names
// the case (`.south` is tag 2) — recovered from `__swift5_fieldmd`, which
// survives stripping.
public enum Direction { case north, east, south, west }
public func heading() -> Direction { .south }

// A raw-value enum names by DECLARATION INDEX, not the raw value: `.high` is
// tag 2 even though its `rawValue` is 12. Proves the tag, not the literal, is
// what indexes the case list.
public enum Priority: Int { case low = 10, medium, high }
public func urgency() -> Priority { .high }

// Negative: a PAYLOAD enum's tag does not index its cases in declaration order
// (payload cases and the spare-bit-encoded empty case interleave), so a
// returned immediate must stay a raw value — never a fabricated `.eof`.
public enum Token { case eof; case number(Int); case ident(Int) }
public func endToken() -> Token { .eof }

// MARK: - Enum equality against a case literal (no-payload)

// A no-payload enum parameter is seeded as a scalar tag, then a comparison to a
// case literal names the case. Both lowerings — the `__derived_enum_equals`
// call (-Onone) and the masked-tag compare (-O) — reconstruct identically.
// `!=` is recovered from the compiler's `^ 1` logical-negation.
public func isNorth(_ d: Direction) -> Bool { d == .north }
public func notWest(_ d: Direction) -> Bool { d != .west }
public func sameHeading(_ a: Direction, _ b: Direction) -> Bool { a == b }

// Negative: a PAYLOAD enum's `==` (indirect args, spare-bit tags) can name no
// case, so it must not fabricate `.ping`.
public enum Msg: Equatable { case ping; case data(Int) }
public func isPing(_ m: Msg) -> Bool { m == .ping }

// An `if` over a no-payload enum: the compiler lowers the guard as a falsity
// test (`(d == .north) == 0 ? else : then`); the reconstruction peels that
// double-negation so the ternary reads cleanly (no leftover `== 0`).
public func northScore(_ d: Direction) -> Int {
    if d == .north { return 100 }
    return 0
}

// MARK: - Switch over a tag → nested ternary (N-way value merge)

// A switch over a no-payload enum: the tag-comparison cascade reconstructs as a
// nested ternary with every case named and the fall-through as the final else.
public func rank(_ d: Direction) -> Int {
    switch d {
    case .north: return 1
    case .east: return 2
    case .south: return 3
    case .west: return 4
    }
}

// A switch over an Int (a different lowering: `n != k` fall-through arms) with
// an explicit default — same nested-ternary reconstruction, raw constants.
public func gradeOf(_ n: Int) -> Int {
    switch n {
    case 0: return 10
    case 1: return 20
    case 2: return 30
    default: return 99
    }
}

// Negative integer constants render as signed decimals (`-1`), not the
// two's-complement hex the immediate is stored as — exercised through a switch.
public func polarity(_ n: Int) -> Int {
    switch n {
    case 0: return -1
    case 1: return -2
    default: return -3
    }
}

// Adversarial: a genuine large unsigned mask is NOT within the small-negative
// window, so it must stay hex — never relabelled as a negative.
public func highMask() -> UInt64 { 0xFF00_0000_0000_0000 }

// A Bool literal result reads as `true`/`false`, not the raw `1`/`0` the
// register holds — the return type drives the reading.
public func alwaysTrue() -> Bool { true }

// A floating-point constant reads as its decimal, not the raw IEEE-754 bit
// pattern the immediate stores (loaded from the literal pool; not fmov-encodable).
public func piValue() -> Double { 3.14159 }

// A Bool parameter is recognized as a boolean, so `!b` (lowered `(b ^ 1) & 1`)
// folds to `!arg0` rather than a masked xor.
public func negateFlag(_ b: Bool) -> Bool { !b }

// Unary negation is emitted as `0 - x`; it folds back to `-x`. `absValue`
// exercises it in a ternary (`x < 0 ? -x : x` → abs), while a genuine
// subtraction from a constant (`100 - x`) is left alone.
public func absValue(_ x: Int) -> Int { x < 0 ? -x : x }
public func fromHundred(_ x: Int) -> Int { 100 - x }
