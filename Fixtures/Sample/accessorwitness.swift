// Value-witness calls on a metadata accessor's result (-O). URL is a
// resilient Foundation struct, so copying, assigning or destroying a field
// of it goes through its value-witness table: `bl type metadata accessor
// for Foundation.URL; ldur x8, [x0, #-0x8]; ldr x9, [x8, #k]; blr x9`,
// slot k / 8 of ValueWitness.def (initializeWithCopy 2, assignWithCopy 3,
// destroy 1). The accessor returns URL's metadata in x0, so each call is
// that witness for Foundation.URL.
import Foundation
public struct HasURL { public var u: URL; public var k: Int }
@inline(never) public func copyIt(_ x: HasURL) -> HasURL { var y = x; y.k &+= 1; return y }
@inline(never) public func assignIt(_ x: inout HasURL, _ y: HasURL) { x = y }
