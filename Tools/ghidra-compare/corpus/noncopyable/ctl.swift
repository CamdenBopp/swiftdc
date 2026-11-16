// Control: copyable twin of FileDesc
public struct CD { public var fd: Int32; public init(fd: Int32){self.fd=fd}
  // returns fd*2
  public func peek() -> Int32 { fd &* 2 } }
// returns d.fd + 7
@inline(never) public func borrowCD(_ d: CD) -> Int32 { d.fd &+ 7 }
// returns d.fd + 7 (explicit borrowing on copyable)
@inline(never) public func borrowCD2(_ d: borrowing CD) -> Int32 { d.fd &+ 9 }
// returns x + 7
@inline(never) public func plainI(_ x: Int32) -> Int32 { x &+ 7 }
