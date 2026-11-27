// Swift error handling at the machine level (-Onone, -O, -Osize).
//
// Conventions used below. Untyped `throws`: the callee returns with x21
// holding the boxed error (x21 is zero on success; a function zeroes it
// once at entry, not before each call). Typed `throws(E)`: the callee sets
// x21 non-zero and the error value overlays the integer result registers
// (x0…), or is written through a caller-supplied buffer when it does not
// fit. Every thrower throws on a condition of x and otherwise returns a
// value weighted from x. Every caller returns one integer that separates
// the success path, each error case and each payload. All arithmetic
// wraps (&+ &* &-), so only `try!` and `Never` can trap.

// MARK: error types

public enum Plain: Error { case low, mid, high }              // no payload: one byte
public enum Coded: Error { case small(Int), big(Int), none }  // Int payload + tag byte
public struct One: Error {                                    // one word
    public var code: Int
    public init(code: Int) { self.code = code }
}
public struct Wide: Error { public var a: Int, b: Int, c: Int } // three words, direct
public final class Boxed: Error {                             // a reference
    public let code: Int
    init(code: Int) { self.code = code }
}
public struct Huge: Error {                                   // six words: through a buffer
    public var a: Int, b: Int, c: Int, d: Int, e: Int, f: Int
}

// MARK: result types

public struct Pair { public var p: Int, q: Int }
public struct Quad { public var a: Int, b: Int, c: Int, d: Int }
public struct Five { public var a: Int, b: Int, c: Int, d: Int, e: Int }  // indirect (x8)
public final class Node {
    public let value: Int
    init(_ value: Int) { self.value = value }
}
public final class Ledger {
    public var count = 0
    public init() {}
}

// MARK: untyped throwers (error boxed in x21)

// Void result. x<0 throws Plain.low, x>1000 Plain.high, x==5 Plain.mid, else returns.
@inline(never) public func uVoid(_ x: Int) throws {
    if x < 0 { throw Plain.low }
    if x > 1000 { throw Plain.high }
    if x == 5 { throw Plain.mid }
}

// Int result in x0. x<0 throws Coded.small(x-3), x>1000 Coded.big(x*2),
// x==5 Coded.none, else returns x*3+1.
@inline(never) public func uInt(_ x: Int) throws -> Int {
    if x < 0 { throw Coded.small(x &- 3) }
    if x > 1000 { throw Coded.big(x &* 2) }
    if x == 5 { throw Coded.none }
    return x &* 3 &+ 1
}

// Two-register result x0,x1. x<0 throws One(code: x+7), x>1000 Plain.high,
// else Pair(p: x+11, q: x*5).
@inline(never) public func uPair(_ x: Int) throws -> Pair {
    if x < 0 { throw One(code: x &+ 7) }
    if x > 1000 { throw Plain.high }
    return Pair(p: x &+ 11, q: x &* 5)
}

// Four-register result x0…x3. x<0 throws Wide(x, x+1, x*3), else
// Quad(x+2, x*7, x^0x55, x-9).
@inline(never) public func uQuad(_ x: Int) throws -> Quad {
    if x < 0 { throw Wide(a: x, b: x &+ 1, c: x &* 3) }
    return Quad(a: x &+ 2, b: x &* 7, c: x ^ 0x55, d: x &- 9)
}

// Five-word result through x8. x<0 throws Boxed(code: x*9), else
// Five(x+1, x+20, x+300, x+4000, x*6).
@inline(never) public func uFive(_ x: Int) throws -> Five {
    if x < 0 { throw Boxed(code: x &* 9) }
    return Five(a: x &+ 1, b: x &+ 20, c: x &+ 300, d: x &+ 4000, e: x &* 6)
}

// Optional<Int> result (x0 payload, x1 tag). x<0 throws
// Huge(x, x+1, x+2, x+3, x+4, x*5), x==0 returns nil, else x*11.
@inline(never) public func uOpt(_ x: Int) throws -> Int? {
    if x < 0 { throw Huge(a: x, b: x &+ 1, c: x &+ 2, d: x &+ 3, e: x &+ 4, f: x &* 5) }
    if x == 0 { return nil }
    return x &* 11
}

// Class reference result. x<0 throws Plain.mid, x>1000 One(code: x),
// else Node(x+41).
@inline(never) public func uNode(_ x: Int) throws -> Node {
    if x < 0 { throw Plain.mid }
    if x > 1000 { throw One(code: x) }
    return Node(x &+ 41)
}

// Never result. x<0 throws One(code: x-100), else traps.
@inline(never) public func uNever(_ x: Int) throws -> Never {
    if x < 0 { throw One(code: x &- 100) }
    fatalError()
}

// MARK: typed throwers (x21 non-zero, error in the result registers or a buffer)

// Void result, one-byte error in x0. x<0 .low, x>1000 .high, x==5 .mid.
@inline(never) public func tPlainVoid(_ x: Int) throws(Plain) {
    if x < 0 { throw .low }
    if x > 1000 { throw .high }
    if x == 5 { throw .mid }
}

// Int result; x0 is the result or the case byte. x<0 .high, x>1000 .low,
// else x*17+2.
@inline(never) public func tPlainInt(_ x: Int) throws(Plain) -> Int {
    if x < 0 { throw .high }
    if x > 1000 { throw .low }
    return x &* 17 &+ 2
}

// Int result; error is payload x0 + tag x1. x<0 .small(x+19),
// x>1000 .big(x-23), x==5 .none, else x*29.
@inline(never) public func tCodedInt(_ x: Int) throws(Coded) -> Int {
    if x < 0 { throw .small(x &+ 19) }
    if x > 1000 { throw .big(x &- 23) }
    if x == 5 { throw .none }
    return x &* 29
}

// Pair result and a two-register error share x0,x1. x<0 .big(x^0x31),
// x==5 .none, else Pair(x+37, x*41).
@inline(never) public func tCodedPair(_ x: Int) throws(Coded) -> Pair {
    if x < 0 { throw .big(x ^ 0x31) }
    if x == 5 { throw .none }
    return Pair(p: x &+ 37, q: x &* 41)
}

// Int result or One.code, both in x0. x<0 One(x*43), else x+47.
@inline(never) public func tOneInt(_ x: Int) throws(One) -> Int {
    if x < 0 { throw One(code: x &* 43) }
    return x &+ 47
}

// Quad result x0…x3, error in x0 only. x<0 One(x-53), else
// Quad(x+59, x+61, x*67, x^71).
@inline(never) public func tOneQuad(_ x: Int) throws(One) -> Quad {
    if x < 0 { throw One(code: x &- 53) }
    return Quad(a: x &+ 59, b: x &+ 61, c: x &* 67, d: x ^ 71)
}

// Int result x0, three-word error x0…x2 (wider than the result).
// x<0 Wide(x+73, x*79, x^83), else x*89.
@inline(never) public func tWideInt(_ x: Int) throws(Wide) -> Int {
    if x < 0 { throw Wide(a: x &+ 73, b: x &* 79, c: x ^ 83) }
    return x &* 89
}

// Quad result x0…x3, error x0…x2. x<0 Wide(x-97, x+101, x*103), else
// Quad(x+107, x*109, x-113, x^127).
@inline(never) public func tWideQuad(_ x: Int) throws(Wide) -> Quad {
    if x < 0 { throw Wide(a: x &- 97, b: x &+ 101, c: x &* 103) }
    return Quad(a: x &+ 107, b: x &* 109, c: x &- 113, d: x ^ 127)
}

// Indirect result (x8): the error then goes indirect too (buffer in x1).
// x<0 Wide(x+131, x+137, x+139), else Five(x+149, x+151, x+157, x+163, x*167).
@inline(never) public func tWideFive(_ x: Int) throws(Wide) -> Five {
    if x < 0 { throw Wide(a: x &+ 131, b: x &+ 137, c: x &+ 139) }
    return Five(a: x &+ 149, b: x &+ 151, c: x &+ 157, d: x &+ 163, e: x &* 167)
}

// Int result or a class reference, both in x0. x<0 Boxed(x*173), else x+179.
@inline(never) public func tBoxedInt(_ x: Int) throws(Boxed) -> Int {
    if x < 0 { throw Boxed(code: x &* 173) }
    return x &+ 179
}

// Two different references in x0. x<0 Boxed(x+181), else Node(x*191).
@inline(never) public func tBoxedNode(_ x: Int) throws(Boxed) -> Node {
    if x < 0 { throw Boxed(code: x &+ 181) }
    return Node(x &* 191)
}

// Int result x0, six-word error through the caller's error buffer.
// x<0 Huge(x, x+193, x+197, x+199, x+211, x*223), else x*227.
@inline(never) public func tHugeInt(_ x: Int) throws(Huge) -> Int {
    if x < 0 { throw Huge(a: x, b: x &+ 193, c: x &+ 197, d: x &+ 199, e: x &+ 211, f: x &* 223) }
    return x &* 227
}

// Indirect result and indirect error. x<0 Huge(x+229, x+233, x+239, x+241,
// x+251, x+257), else Five(x+263, x+269, x+271, x+277, x+281).
@inline(never) public func tHugeFive(_ x: Int) throws(Huge) -> Five {
    if x < 0 {
        throw Huge(a: x &+ 229, b: x &+ 233, c: x &+ 239, d: x &+ 241, e: x &+ 251, f: x &+ 257)
    }
    return Five(a: x &+ 263, b: x &+ 269, c: x &+ 271, d: x &+ 277, e: x &+ 281)
}

// Optional<Int> result and a Coded error, each a word plus a tag.
// x<0 .small(x*283), x==0 nil, else x+293.
@inline(never) public func tCodedOpt(_ x: Int) throws(Coded) -> Int? {
    if x < 0 { throw .small(x &* 283) }
    if x == 0 { return nil }
    return x &+ 293
}

// Never result. x<0 One(x+307), else traps.
@inline(never) public func tOneNever(_ x: Int) throws(One) -> Never {
    if x < 0 { throw One(code: x &+ 307) }
    fatalError()
}

// Generic typed throw: the error goes out indirectly whatever E is.
// x<0 throws e, else x*311.
@inline(never) public func tGen<E: Error>(_ x: Int, _ e: E) throws(E) -> Int {
    if x < 0 { throw e }
    return x &* 311
}

// MARK: controls (must render exactly)

// x*313 + y. No error handling at all.
@inline(never) public func ctlInt(_ x: Int, _ y: Int) -> Int { x &* 313 &+ y }

// throws(Never) cannot throw: an ordinary Int in x0. x*317.
@inline(never) public func ctlNoThrow(_ x: Int) throws(Never) -> Int { x &* 317 }

// ctlNoThrow(x) + y = x*317 + y.
@inline(never) public func ctlUseNoThrow(_ x: Int, _ y: Int) -> Int { ctlNoThrow(x) &+ y }

// Declared `throws`, never throws. (x ^ y) + 331.
@inline(never) public func ctlNeverThrows(_ x: Int, _ y: Int) throws -> Int { (x ^ y) &+ 331 }

// try? of a function that never throws: always (x ^ y) + 331 + 337.
@inline(never) public func ctlOptNeverThrows(_ x: Int, _ y: Int) -> Int {
    ((try? ctlNeverThrows(x, y)) ?? 9999) &+ 337
}

// A non-throwing Pair producer and its reader: (x+347)*2 + (y*349)*3.
@inline(never) public func ctlMakePair(_ x: Int, _ y: Int) -> Pair { Pair(p: x &+ 347, q: y &* 349) }
@inline(never) public func ctlPair(_ x: Int, _ y: Int) -> Int {
    let p = ctlMakePair(x, y)
    return p.p &* 2 &+ p.q &* 3
}

// MARK: `try` propagating

// uInt(x) + y*13, or uInt's error passed on in x21 untouched.
@inline(never) public func propUInt(_ x: Int, _ y: Int) throws -> Int {
    let v = try uInt(x)
    return v &+ y &* 13
}

// (tCodedInt(x) ^ y) + 353, or the same Coded error rethrown in x0,x1.
@inline(never) public func propTCoded(_ x: Int, _ y: Int) throws(Coded) -> Int {
    let v = try tCodedInt(x)
    return (v ^ y) &+ 353
}

// q.a + q.b*3 + q.c*5 + q.d*7 + y over tWideQuad(x), or its Wide error.
@inline(never) public func propTWideQuad(_ x: Int, _ y: Int) throws(Wide) -> Int {
    let q = try tWideQuad(x)
    return q.a &+ q.b &* 3 &+ q.c &* 5 &+ q.d &* 7 &+ y
}

// p*2 + q*3 - y over uPair(x), or its error.
@inline(never) public func propUPair(_ x: Int, _ y: Int) throws -> Int {
    let p = try uPair(x)
    return p.p &* 2 &+ p.q &* 3 &- y
}

// a + b*2 + c*3 + d*4 + e*5 + y*6 over tHugeFive(x), or its Huge error
// forwarded through this function's own error buffer.
@inline(never) public func propTHugeFive(_ x: Int, _ y: Int) throws(Huge) -> Int {
    let f = try tHugeFive(x)
    return f.a &+ f.b &* 2 &+ f.c &* 3 &+ f.d &* 4 &+ f.e &* 5 &+ y &* 6
}

// A typed error widened to untyped: tOneInt(x)*y + 359, or One boxed
// (swift_allocError) and thrown in x21.
@inline(never) public func propWiden(_ x: Int, _ y: Int) throws -> Int {
    let v = try tOneInt(x)
    return v &* y &+ 359
}

// MARK: `try?` with a fallback

// (uInt(x) or y+900) + 367. The boxed error is released.
@inline(never) public func optUInt(_ x: Int, _ y: Int) -> Int {
    ((try? uInt(x)) ?? (y &+ 900)) &+ 367
}

// (tOneInt(x) or y*373) - 379.
@inline(never) public func optTOne(_ x: Int, _ y: Int) -> Int {
    ((try? tOneInt(x)) ?? (y &* 373)) &- 379
}

// a + b*2 + c*3 + d*4 over tOneQuad(x), or y+383 when it threw.
@inline(never) public func optTOneQuad(_ x: Int, _ y: Int) -> Int {
    if let q = try? tOneQuad(x) { return q.a &+ q.b &* 2 &+ q.c &* 3 &+ q.d &* 4 }
    return y &+ 383
}

// try? flattens: tCodedOpt(x)'s value, or y+389 for nil and for a throw.
@inline(never) public func optTCodedOpt(_ x: Int, _ y: Int) -> Int {
    (try? tCodedOpt(x)) ?? (y &+ 389)
}

// y+397 when tPlainVoid(x) threw, y+401 when it returned.
@inline(never) public func optTPlainVoid(_ x: Int, _ y: Int) -> Int {
    (try? tPlainVoid(x)) == nil ? y &+ 397 : y &+ 401
}

// uNode(x).value (x+41), or y*409 when it threw.
@inline(never) public func optUNode(_ x: Int, _ y: Int) -> Int {
    (try? uNode(x))?.value ?? (y &* 409)
}

// a + e*419 over tWideFive(x), or y-421 when it threw.
@inline(never) public func optTWideFive(_ x: Int, _ y: Int) -> Int {
    guard let f = try? tWideFive(x) else { return y &- 421 }
    return f.a &+ f.e &* 419
}

// MARK: `try!` (traps when the callee throws)

// uInt(x) + y + 431; traps for x<0, x>1000, x==5.
@inline(never) public func bangUInt(_ x: Int, _ y: Int) -> Int {
    (try! uInt(x)) &+ y &+ 431
}

// tOneInt(x)*3 + y; traps for x<0.
@inline(never) public func bangTOne(_ x: Int, _ y: Int) -> Int {
    (try! tOneInt(x)) &* 3 &+ y
}

// a + e + y over tHugeFive(x); traps for x<0.
@inline(never) public func bangTHugeFive(_ x: Int, _ y: Int) -> Int {
    let f = try! tHugeFive(x)
    return f.a &+ f.e &+ y
}

// y + 433 when tPlainVoid(x) returns; traps for x<0, x>1000, x==5.
@inline(never) public func bangTPlainVoid(_ x: Int, _ y: Int) -> Int {
    try! tPlainVoid(x)
    return y &+ 433
}

// MARK: do/catch mapping the error to an integer

// uInt(x)+y; .small(n) -> 1000+n; .big(n) -> 2000+n; .none -> 3000+y; other -> -1.
@inline(never) public func catchUCoded(_ x: Int, _ y: Int) -> Int {
    do { return try uInt(x) &+ y } catch let e as Coded {
        switch e {
        case .small(let n): return 1000 &+ n
        case .big(let n): return 2000 &+ n
        case .none: return 3000 &+ y
        }
    } catch { return -1 }
}

// tPlainInt(x) + y*439; .low -> 4001; .mid -> 4002; .high -> 4003+y.
@inline(never) public func catchTPlain(_ x: Int, _ y: Int) -> Int {
    do throws(Plain) { return try tPlainInt(x) &+ y &* 439 } catch {
        switch error {
        case .low: return 4001
        case .mid: return 4002
        case .high: return 4003 &+ y
        }
    }
}

// y+443 on return; catch clauses by case: .low -> 5001, .mid -> 5002, else 5003.
@inline(never) public func catchTPlainVoid(_ x: Int, _ y: Int) -> Int {
    do throws(Plain) { try tPlainVoid(x); return y &+ 443 }
    catch .low { return 5001 } catch .mid { return 5002 } catch { return 5003 }
}

// tCodedInt(x)+y; .small(n) -> n*449; .big(n) -> n+457; .none -> 461-y.
@inline(never) public func catchTCoded(_ x: Int, _ y: Int) -> Int {
    do throws(Coded) { return try tCodedInt(x) &+ y } catch {
        switch error {
        case .small(let n): return n &* 449
        case .big(let n): return n &+ 457
        case .none: return 461 &- y
        }
    }
}

// p + q*y over tCodedPair(x); .small(n) -> n-463; .big(n) -> n*467; .none -> 479.
@inline(never) public func catchTCodedPair(_ x: Int, _ y: Int) -> Int {
    do throws(Coded) { let p = try tCodedPair(x); return p.p &+ p.q &* y } catch {
        switch error {
        case .small(let n): return n &- 463
        case .big(let n): return n &* 467
        case .none: return 479
        }
    }
}

// tOneInt(x) - y, or error.code*487 + y. x0 after the call is either.
@inline(never) public func catchTOne(_ x: Int, _ y: Int) -> Int {
    do throws(One) { return try tOneInt(x) &- y } catch { return error.code &* 487 &+ y }
}

// a + b*491 + c + d*y over tOneQuad(x), or error.code ^ 499.
@inline(never) public func catchTOneQuad(_ x: Int, _ y: Int) -> Int {
    do throws(One) { let q = try tOneQuad(x); return q.a &+ q.b &* 491 &+ q.c &+ q.d &* y }
    catch { return error.code ^ 499 }
}

// tWideInt(x) + y*503, or a + b*509 + c*521 of the error (x1, x2 exist
// only on the error path).
@inline(never) public func catchTWideInt(_ x: Int, _ y: Int) -> Int {
    do throws(Wide) { return try tWideInt(x) &+ y &* 503 }
    catch { return error.a &+ error.b &* 509 &+ error.c &* 521 }
}

// a*523 + b + c + d + y over tWideQuad(x), or a - b*541 + c of the error.
@inline(never) public func catchTWideQuad(_ x: Int, _ y: Int) -> Int {
    do throws(Wide) { let q = try tWideQuad(x); return q.a &* 523 &+ q.b &+ q.c &+ q.d &+ y }
    catch { return error.a &- error.b &* 541 &+ error.c }
}

// b + d*547 over tWideFive(x) (from the result buffer), or a*557 + b + c*y
// of the error (from the error buffer: an indirect result makes it indirect).
@inline(never) public func catchTWideFive(_ x: Int, _ y: Int) -> Int {
    do throws(Wide) { let f = try tWideFive(x); return f.b &+ f.d &* 547 }
    catch { return error.a &* 557 &+ error.b &+ error.c &* y }
}

// tBoxedInt(x)*563 + y, or error.code + 569 (x0 is a reference there).
@inline(never) public func catchTBoxedInt(_ x: Int, _ y: Int) -> Int {
    do throws(Boxed) { return try tBoxedInt(x) &* 563 &+ y } catch { return error.code &+ 569 }
}

// node.value + y, or error.code ^ 571.
@inline(never) public func catchTBoxedNode(_ x: Int, _ y: Int) -> Int {
    do throws(Boxed) { return try tBoxedNode(x).value &+ y } catch { return error.code ^ 571 }
}

// tHugeInt(x) - y, or a + b*2 + c*3 + d*5 + e*7 + f*11 read from the
// error buffer.
@inline(never) public func catchTHugeInt(_ x: Int, _ y: Int) -> Int {
    do throws(Huge) { return try tHugeInt(x) &- y } catch {
        return error.a &+ error.b &* 2 &+ error.c &* 3 &+ error.d &* 5 &+ error.e &* 7 &+ error.f &* 11
    }
}

// c*577 + e + y from the result buffer, or a + f*587 from the error buffer.
@inline(never) public func catchTHugeFive(_ x: Int, _ y: Int) -> Int {
    do throws(Huge) { let f = try tHugeFive(x); return f.c &* 577 &+ f.e &+ y }
    catch { return error.a &+ error.f &* 587 }
}

// (value or 593) + y on return; .small(n) -> n+599; else 601.
@inline(never) public func catchTCodedOpt(_ x: Int, _ y: Int) -> Int {
    do throws(Coded) { return (try tCodedOpt(x) ?? 593) &+ y } catch {
        if case .small(let n) = error { return n &+ 599 }
        return 601
    }
}

// Two untyped throwers and casts by pattern: uVoid(x) then uNode(y).value;
// Plain.low -> 6001, Plain.mid -> 6002, One -> code+6100, else 6003.
@inline(never) public func catchUPattern(_ x: Int, _ y: Int) -> Int {
    do { try uVoid(x); let n = try uNode(y); return n.value }
    catch Plain.low { return 6001 } catch Plain.mid { return 6002 }
    catch let e as One { return e.code &+ 6100 } catch { return 6003 }
}

// a + b + c*607 + d + y over uQuad(x), or a*613 + b + c of a Wide cast
// out of the box; anything else -7.
@inline(never) public func catchUWide(_ x: Int, _ y: Int) -> Int {
    do { let q = try uQuad(x); return q.a &+ q.b &+ q.c &* 607 &+ q.d &+ y }
    catch let e as Wide { return e.a &* 613 &+ e.b &+ e.c } catch { return -7 }
}

// a + c + e*617 + y over uFive(x), or Boxed.code - 619; else -8.
@inline(never) public func catchUBoxed(_ x: Int, _ y: Int) -> Int {
    do { let f = try uFive(x); return f.a &+ f.c &+ f.e &* 617 &+ y }
    catch let e as Boxed { return e.code &- 619 } catch { return -8 }
}

// (uOpt(x) or 631) + y, or a + f*641 of a Huge; else -9.
@inline(never) public func catchUHuge(_ x: Int, _ y: Int) -> Int {
    do { return (try uOpt(x) ?? 631) &+ y }
    catch let e as Huge { return e.a &+ e.f &* 641 } catch { return -9 }
}

// error.code + y (= x+307+y) for x<0; traps otherwise. No success path.
@inline(never) public func catchTNever(_ x: Int, _ y: Int) -> Int {
    do throws(One) { try tOneNever(x) } catch { return error.code &+ y }
}

// One.code*643 (= (x-100)*643) for x<0; traps otherwise; other errors -10.
@inline(never) public func catchUNever(_ x: Int, _ y: Int) -> Int {
    do { try uNever(x) } catch let e as One { return e.code &* 643 } catch { return -10 }
}

// tGen(x, One(code: y+647)) = x*311, or (y+647)*2 for x<0.
@inline(never) public func catchTGen(_ x: Int, _ y: Int) -> Int {
    do throws(One) { return try tGen(x, One(code: y &+ 647)) } catch { return error.code &* 2 }
}

// MARK: rethrowing a different error

// uInt(x)+y; .small(n) rethrown as One(code: n+653); any other Coded as
// Plain.mid; a non-Coded error unchanged.
@inline(never) public func rethrowU(_ x: Int, _ y: Int) throws -> Int {
    do { return try uInt(x) &+ y } catch let e as Coded {
        if case .small(let n) = e { throw One(code: n &+ 653) }
        throw Plain.mid
    }
}

// tPlainInt(x) ^ y; .low -> One(659), .mid -> One(661), .high -> One(y+673).
@inline(never) public func rethrowT(_ x: Int, _ y: Int) throws(One) -> Int {
    do throws(Plain) { return try tPlainInt(x) ^ y } catch {
        switch error {
        case .low: throw One(code: 659)
        case .mid: throw One(code: 661)
        case .high: throw One(code: y &+ 673)
        }
    }
}

// tWideInt(x) + y, or Coded.big(a + b + c) of the Wide error.
@inline(never) public func rethrowTWide(_ x: Int, _ y: Int) throws(Coded) -> Int {
    do throws(Wide) { return try tWideInt(x) &+ y } catch {
        throw Coded.big(error.a &+ error.b &+ error.c)
    }
}

// tCodedInt(x) - y; .small(n) -> untyped Boxed(n+677); .big(n) -> One(n);
// .none -> Plain.low.
@inline(never) public func rethrowTToU(_ x: Int, _ y: Int) throws -> Int {
    do throws(Coded) { return try tCodedInt(x) &- y } catch {
        switch error {
        case .small(let n): throw Boxed(code: n &+ 677)
        case .big(let n): throw One(code: n)
        case .none: throw Plain.low
        }
    }
}

// MARK: defer on both paths

// count += 683 on both paths, then uInt(x)+691 or uInt's error.
@inline(never) public func deferUInner(_ l: Ledger, _ x: Int) throws -> Int {
    defer { l.count &+= 683 }
    return try uInt(x) &+ 691
}

// Ledger starts at y. Returned: v + count*2 = uInt(x)+691 + (y+683)*2; or
// on a throw count*3 + 1 = (y+683)*3 + 1.
@inline(never) public func deferU(_ x: Int, _ y: Int) -> Int {
    let l = Ledger(); l.count = y
    do { let v = try deferUInner(l, x); return v &+ l.count &* 2 }
    catch { return l.count &* 3 &+ 1 }
}

// count ^= 701 on both paths, after `count += v` on the success path only.
// Returns tOneInt(x)*2.
@inline(never) public func deferTInner(_ l: Ledger, _ x: Int) throws(One) -> Int {
    defer { l.count ^= 701 }
    let v = try tOneInt(x)
    l.count &+= v
    return v &* 2
}

// Success: v*2 + ((y+v) ^ 701) with v = x+47. Throw: code + (y ^ 701)*709
// with code = x*43.
@inline(never) public func deferT(_ x: Int, _ y: Int) -> Int {
    let l = Ledger(); l.count = y
    do throws(One) { let v = try deferTInner(l, x); return v &+ l.count }
    catch { return error.code &+ l.count &* 709 }
}

// MARK: nested do/catch

// acc = uInt(x), or 719 when it threw Coded.none (inner catch; others go
// out). Then acc + uPair(y).q. Outer: .small(n) -> n-7000, .big(n) ->
// n+7000, .none -> -7001 (unreachable), One -> code+7100, else -3.
@inline(never) public func nestedU(_ x: Int, _ y: Int) -> Int {
    do {
        var acc = 0
        do { acc = try uInt(x) } catch Coded.none { acc = 719 }
        return acc &+ (try uPair(y)).q
    } catch let e as Coded {
        switch e {
        case .small(let n): return n &- 7000
        case .big(let n): return n &+ 7000
        case .none: return -7001
        }
    } catch let e as One { return e.code &+ 7100 } catch { return -3 }
}

// acc = tOneInt(x), or code+727 when it threw. Then acc + tCodedInt(y).
// Outer: .small(n) -> acc*0 + n*733, .big(n) -> n-739, .none -> 743.
@inline(never) public func nestedT(_ x: Int, _ y: Int) -> Int {
    do throws(Coded) {
        var acc: Int
        do throws(One) { acc = try tOneInt(x) } catch { acc = error.code &+ 727 }
        return acc &+ (try tCodedInt(y))
    } catch {
        switch error {
        case .small(let n): return n &* 733
        case .big(let n): return n &- 739
        case .none: return 743
        }
    }
}

// MARK: throwing closures and rethrowing functions

// f(x) + 751, or f's error.
@inline(never) public func applyRe(_ f: (Int) throws -> Int, _ x: Int) rethrows -> Int {
    try f(x) &+ 751
}

// f(x) + 757, or f's typed error (generic: indirect).
@inline(never) public func applyTyped<E: Error>(_ f: (Int) throws(E) -> Int, _ x: Int) throws(E) -> Int {
    try f(x) &+ 757
}

// uInt(x+y) + 751 through a closure capturing y; .small(n) -> n+761,
// .big(n) -> n+769, .none -> 773; else -4.
@inline(never) public func closU(_ x: Int, _ y: Int) -> Int {
    do { return try applyRe({ try uInt($0 &+ y) }, x) } catch let e as Coded {
        switch e {
        case .small(let n): return n &+ 761
        case .big(let n): return n &+ 769
        case .none: return 773
        }
    } catch { return -4 }
}

// A non-throwing closure through the rethrowing function: x*y + 787 + 751.
@inline(never) public func closNoThrow(_ x: Int, _ y: Int) -> Int {
    applyRe({ $0 &* y &+ 787 }, x)
}

// tOneInt(x ^ y) + 757 through a typed-throwing closure, or code + 797.
@inline(never) public func closT(_ x: Int, _ y: Int) -> Int {
    do throws(One) {
        return try applyTyped({ (v: Int) throws(One) -> Int in try tOneInt(v ^ y) }, x)
    } catch { return error.code &+ 797 }
}

// MARK: a loop that throws from the middle

// acc = 809; for i in 0..<6: acc = acc*3 + uInt(x - i*y). On a throw the
// partial acc survives: .small(n) -> acc + n, .big(n) -> acc - n,
// .none -> acc ^ 811; else -5.
@inline(never) public func loopU(_ x: Int, _ y: Int) -> Int {
    var acc = 809
    do {
        for i in 0..<6 { acc = acc &* 3 &+ (try uInt(x &- i &* y)) }
        return acc
    } catch let e as Coded {
        switch e {
        case .small(let n): return acc &+ n
        case .big(let n): return acc &- n
        case .none: return acc ^ 811
        }
    } catch { return -5 }
}

// acc = 821; for i in 0..<5: acc += tOneInt(x + i*y). On a throw:
// acc*1000 + code + i, where i is the iteration that threw.
@inline(never) public func loopT(_ x: Int, _ y: Int) -> Int {
    var acc = 821
    var i = 0
    do throws(One) {
        while i < 5 { acc &+= try tOneInt(x &+ i &* y); i &+= 1 }
        return acc
    } catch { return acc &* 1000 &+ error.code &+ i }
}

// MARK: two throwers in sequence

// uInt(x)*823 + uInt(y); the first error wins.
@inline(never) public func seqU(_ x: Int, _ y: Int) throws -> Int {
    let a = try uInt(x)
    let b = try uInt(y)
    return a &* 823 &+ b
}

// a = tOneInt(x), or code-827 when it threw (x21 is left non-zero by that
// call; the second call's callee must zero or set it itself). Then
// a + tPlainInt(y); .low -> a+8001, .mid -> a+8002, .high -> a^8003.
@inline(never) public func seqT(_ x: Int, _ y: Int) -> Int {
    var a = 0
    do throws(One) { a = try tOneInt(x) } catch { a = error.code &- 827 }
    do throws(Plain) { return a &+ (try tPlainInt(y)) } catch {
        switch error {
        case .low: return a &+ 8001
        case .mid: return a &+ 8002
        case .high: return a ^ 8003
        }
    }
}

// a = tWideInt(x), or a+b+c of its error. Then a*829 + uPair(y).p; One ->
// a + code*839; else a - 853.
@inline(never) public func seqMixed(_ x: Int, _ y: Int) -> Int {
    var a = 0
    do throws(Wide) { a = try tWideInt(x) } catch { a = error.a &+ error.b &+ error.c }
    do { return a &* 829 &+ (try uPair(y)).p }
    catch let e as One { return a &+ e.code &* 839 } catch { return a &- 853 }
}

// tCodedInt(x)*857 + tCodedInt(y), same error type from both calls; the
// first error wins.
@inline(never) public func seqTwoTyped(_ x: Int, _ y: Int) throws(Coded) -> Int {
    let a = try tCodedInt(x)
    let b = try tCodedInt(y)
    return a &* 857 &+ b
}

// a = tOneInt(x) or 859 (try?), then a + uInt(y) propagating.
@inline(never) public func seqOptThenTry(_ x: Int, _ y: Int) throws -> Int {
    let a = (try? tOneInt(x)) ?? 859
    return a &+ (try uInt(y))
}
