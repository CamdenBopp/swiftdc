// LEVELS: O Osize Onone
// Class vtable dispatch, protocol witness calls and generic specialization.
// TRUE behaviour:
//   Animal.describe(k): self.legs() through Animal's vtable slot 0x58, times k.
//   countLegs(a): a.legs() (ldr x8, [x0]; ldr x8, [x8, #0x58]; blr x8 with
//   x20 = a) plus a.describe(10) (slot 0x60). a is statically an Animal, so
//   the slots name Animal.legs and Animal.describe; the dynamic class may be
//   Bird, so naming Bird.legs would be a guess.
//   viaExistential(s): projects the existential buffer and calls witness-table
//   word 1 (requirement 0, size) with x20 = the projected value. Which
//   conformance runs is unknown, so Rod.size would be a guess.
//   viaGeneric<T>(s): s.size() through the witness table argument, times 3.
//   specialized(): viaGeneric<Rod> specialized, called with len 21 in x0.
//   maxOf<T>: calls T's static > with self = T's metadata, then
//   initializeWithCopy into the indirect result. maxInts calls the Int
//   specialization with (13, 31).
// EXPECT structured * Animal.describe :: self.legs()
// FORBID structured * Animal.describe :: Bird.legs
// EXPECT structured * countLegs :: legs(
// EXPECT structured * countLegs :: describe(
// FORBID structured * countLegs :: Bird.legs
// EXPECT structured * viaExistential :: Sized requirement 0
// FORBID structured * viaExistential :: Rod.size
// FORBID structured * Dispatch.viaGeneric<A :: Rod.size
// EXPECT structured O,Osize Dispatch.specialized :: generic specialization <Dispatch.Rod> of Dispatch.viaGeneric
// EXPECT structured Onone Dispatch.specialized :: Dispatch.Rod.init(len:)(21)
// EXPECT structured * Dispatch.maxOf<A :: dispatch thunk of static Swift.Comparable.> infix(A, A) -> Swift.Bool(self: type metadata for A, arg0, arg1)
// EXPECT structured * Dispatch.maxOf<A :: initializeWithCopy value witness for A(&result,
// EXPECT structured O,Osize generic specialization <Swift.Int> of Dispatch.maxOf :: return ((arg1 > arg0) ? arg1 : arg0)
// EXPECT structured O,Osize maxInts :: maxOf<A where A: Swift.Comparable>(13, 31)
// FORBID structured * maxInts :: (31, 13)
open class Animal { public init() {}
  open func legs() -> Int { 4 }
  open func describe(_ k: Int) -> Int { legs() &* k } }
public final class Bird: Animal { override public func legs() -> Int { 2 } }
public func countLegs(_ a: Animal) -> Int { a.legs() &+ a.describe(10) }
public protocol Sized { func size() -> Int }
public struct Rod: Sized { public var len: Int; public init(len: Int) { self.len = len }
  public func size() -> Int { len &* 2 } }
public func viaExistential(_ s: any Sized) -> Int { s.size() &+ 1 }
@inline(never) public func viaGeneric<T: Sized>(_ s: T) -> Int { s.size() &* 3 }
public func specialized() -> Int { viaGeneric(Rod(len: 21)) }
@inline(never) public func maxOf<T: Comparable>(_ a: T, _ b: T) -> T { a > b ? a : b }
public func maxInts() -> Int { maxOf(13, 31) }
