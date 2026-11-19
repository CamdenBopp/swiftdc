// Own source: extraction of an already placed value receiver must keep formal types aligned.
public struct GPReceiver {
 public let bias: Int64
 public init(_ bias: Int64) { self.bias = bias }
 @inline(never) public func consume(_ x: Int8) -> Int64 { bias &+ Int64(x) }
}
public struct FPReceiver {
 public let bias: Float
 public init(_ bias: Float) { self.bias = bias }
 @inline(never) public func consume(_ x: Int8) -> Int64 { Int64(bias) &+ Int64(x) }
}
@inline(never) public func gpCaller(_ x: UInt8, _ bias: Int64) -> Int64 { GPReceiver(bias).consume(Int8(bitPattern: x)) }
@inline(never) public func fpCaller(_ x: UInt8, _ bias: Float) -> Int64 { FPReceiver(bias).consume(Int8(bitPattern: x)) }

public struct GP2Receiver {
 public let first: Int64
 public let second: Int64
 public init(_ a: Int64, _ b: Int64) { first = a; second = b }
 @inline(never) public func consume(_ x: Int8) -> Int64 { first &+ second &+ Int64(x) }
}
extension GPReceiver {
 @inline(never) public func consumeFloat(_ x: Float) -> Float { Float(bias) + x }
 @inline(never) public func consumeBool(_ x: Bool) -> Int64 { bias &+ (x ? 17 : 31) }
}
@inline(never) public func gp2Caller(_ x: UInt8, _ a: Int64, _ b: Int64) -> Int64 { GP2Receiver(a, b).consume(Int8(bitPattern: x)) }
@inline(never) public func gpFloatCaller(_ bias: Int64) -> Float { GPReceiver(bias).consumeFloat(3.5) }
@inline(never) public func gpBoolCaller(_ bias: Int64) -> Int64 { GPReceiver(bias).consumeBool(true) }
