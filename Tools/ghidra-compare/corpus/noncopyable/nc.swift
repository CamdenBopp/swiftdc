// Noncopyable / ownership probe fixture. True behaviour stated per function.
@inline(never) public func sink(_ x: Int) { print(x) }

public struct FileDesc: ~Copyable {
    public var fd: Int32
    public init(fd: Int32) { self.fd = fd }
    // deinit: calls sink(Int(fd))
    deinit { sink(Int(fd)) }
    // consuming: returns fd + 1, and runs deinit (sink(fd)) at end
    public consuming func close() -> Int32 { return fd &+ 1 }
    // discard self: returns fd, deinit NOT run
    public consuming func take() -> Int32 { let v = fd; discard self; return v }
    // borrowing: returns fd * 2, no deinit
    public borrowing func peek() -> Int32 { return fd &* 2 }
    public mutating func bump() { fd &+= 3 }
}

// borrowing param: returns d.fd &+ 7
@inline(never) public func borrowFD(_ d: borrowing FileDesc) -> Int32 { d.fd &+ 7 }
// consuming param: returns d.fd, then deinit runs sink(fd)
@inline(never) public func consumeFD(_ d: consuming FileDesc) -> Int32 { d.fd }
// inout noncopyable: d.fd += 3
@inline(never) public func inoutFD(_ d: inout FileDesc) { d.bump() }
// makes a FileDesc(fd: x), consumes it via close(): returns x+1 (sink(x) by deinit)
@inline(never) public func makeAndClose(_ x: Int32) -> Int32 { let f = FileDesc(fd: x); return f.close() }
// consume operator: moves a into b, returns b.fd via consumeFD
@inline(never) public func moveIt(_ x: Int32) -> Int32 { let a = FileDesc(fd: x); let b = consume a; return consumeFD(b) }

public enum Token: ~Copyable {
    case none
    case num(Int)
    case pair(Int, Int)
    // consuming switch: none->0, num(n)->n, pair(a,b)->a&+b
    public consuming func value() -> Int {
        switch consume self {
        case .none: return 0
        case .num(let n): return n
        case .pair(let a, let b): return a &+ b
        }
    }
}
// borrowing switch: none -> -1, num -> 1, pair -> 2
@inline(never) public func tokenKind(_ t: borrowing Token) -> Int {
    switch t { case .none: return -1; case .num: return 1; case .pair: return 2 }
}

// generic noncopyable
public struct Box<T: ~Copyable>: ~Copyable {
    public var item: T
    public init(_ i: consuming T) { item = i }
    public consuming func unwrap() -> T { item }
}
// returns x via Box<Int>
@inline(never) public func boxInt(_ x: Int) -> Int { Box(x).unwrap() }
@inline(never) public func genericConsume<T: ~Copyable>(_ t: consuming T) -> T { t }

// optional noncopyable: nil -> -1, some(f) -> f.fd (and deinit)
@inline(never) public func optFD(_ o: consuming FileDesc?) -> Int32 {
    switch consume o { case .none: return -1; case .some(let f): return f.take() }
}

// sending param: returns the array count
@inline(never) public func sendIt(_ a: sending [Int]) -> Int { a.count }

public struct View: ~Escapable {
    public let p: UnsafeRawPointer
    @_lifetime(immortal) public init(p: UnsafeRawPointer) { self.p = p }
}
// returns first byte of v.p
@inline(never) public func readView(_ v: View) -> UInt8 { v.p.load(as: UInt8.self) }
