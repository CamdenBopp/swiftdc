// A real compiler declaration still has operands when every value loaded
// through an opaque imported pointer is unknown to the tracer. Keep the
// formal ABI intact at all three optimization levels.
@frozen public struct Token {
    public var a: Int
    public var b: Double
    public var c: Int
    @_optimize(none) @inline(never)
    public static func == (_ lhs: Token, _ rhs: Token) -> Bool { true }
}

@_silgen_name("operator_arity_source")
func source() -> UnsafePointer<Token>

@_optimize(none) @inline(never)
public prefix func ! (_ value: Token) -> Bool { false }

postfix operator ^^^
@_optimize(none) @inline(never)
public postfix func ^^^ (_ value: Token) -> Int { 42 }

@_cdecl("operator_arity_equal") @inline(never)
public func equalOpaque() -> Int {
    let p = source()
    return p[0] == p[1] ? 1 : 0
}

@_cdecl("operator_arity_prefix") @inline(never)
public func prefixOpaque() -> Int { !source()[0] ? 1 : 0 }

@_cdecl("operator_arity_postfix") @inline(never)
public func postfixOpaque() -> Int { source()[0]^^^ }
