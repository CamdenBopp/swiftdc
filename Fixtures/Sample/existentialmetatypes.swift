// Existential metatypes as results: how many words, and where the fifth
// one sends them (-O and -Onone).
//
// `any (P1 & P2).Type` is a metadata pointer followed by one witness table
// for each protocol of the composition that has one. A result of at most
// four words is returned in x0 to x3; a fifth sends the whole value through
// the caller's buffer in x8. So one to three witness-bearing protocols stay
// in registers and four or more do not.
//
// `AnyObject` is a layout constraint, `Sendable` a marker protocol and
// `Ping` an @objc protocol: none has a witness table, so each adds a member
// to the composition's name and no word to its metatype.
//
// The demangled result type does not parenthesize the composition:
// `ExistentialMetatypes.P1 & ExistentialMetatypes.P2.Type`.
//
// Each maker compares `k` with a constant of its own, so no two bodies are
// the same code.

import Foundation

public protocol P1 { func one() -> Int }
public protocol P2 { func two() -> Int }
public protocol P3 { func three() -> Int }
public protocol P4 { func four() -> Int }
public protocol P5 { func five() -> Int }
@objc public protocol Ping { func ping() }

public struct A: P1, P2, P3, P4, P5, Sendable {
    public func one() -> Int { 11 }
    public func two() -> Int { 12 }
    public func three() -> Int { 13 }
    public func four() -> Int { 14 }
    public func five() -> Int { 15 }
}

public struct B: P1, P2, P3, P4, P5, Sendable {
    public func one() -> Int { 21 }
    public func two() -> Int { 22 }
    public func three() -> Int { 23 }
    public func four() -> Int { 24 }
    public func five() -> Int { 25 }
}

// Direct, two words: metadata in x0, the P1 table in x1.
@inline(never) public func makeOne(_ k: Int) -> any P1.Type {
    let a: any P1.Type = A.self, b: any P1.Type = B.self
    return k > 1 ? a : b
}

// Direct, three words: x0 to x2.
@inline(never) public func makeTwo(_ k: Int) -> any (P1 & P2).Type {
    let a: any (P1 & P2).Type = A.self, b: any (P1 & P2).Type = B.self
    return k > 2 ? a : b
}

// Direct, four words: x0 to x3. The widest metatype that stays in registers.
@inline(never) public func makeThree(_ k: Int) -> any (P1 & P2 & P3).Type {
    let a: any (P1 & P2 & P3).Type = A.self, b: any (P1 & P2 & P3).Type = B.self
    return k > 3 ? a : b
}

// Indirect, five words: written through x8.
@inline(never) public func makeFour(_ k: Int) -> any (P1 & P2 & P3 & P4).Type {
    let a: any (P1 & P2 & P3 & P4).Type = A.self, b: any (P1 & P2 & P3 & P4).Type = B.self
    return k > 4 ? a : b
}

// Indirect, six words: written through x8.
@inline(never) public func makeFive(_ k: Int) -> any (P1 & P2 & P3 & P4 & P5).Type {
    let a: any (P1 & P2 & P3 & P4 & P5).Type = A.self, b: any (P1 & P2 & P3 & P4 & P5).Type = B.self
    return k > 5 ? a : b
}

// Direct, four words: four members, and Sendable has no table.
@inline(never) public func makeThreeSendable(_ k: Int) -> any (P1 & P2 & P3 & Sendable).Type {
    let a: any (P1 & P2 & P3 & Sendable).Type = A.self, b: any (P1 & P2 & P3 & Sendable).Type = B.self
    return k > 6 ? a : b
}

// Indirect, five words: Sendable takes none of the four tables away.
@inline(never) public func makeFourSendable(_ k: Int) -> any (P1 & P2 & P3 & P4 & Sendable).Type {
    let a: any (P1 & P2 & P3 & P4 & Sendable).Type = A.self, b: any (P1 & P2 & P3 & P4 & Sendable).Type = B.self
    return k > 7 ? a : b
}

// Direct, four words: AnyObject has no table, and nil is a null metadata
// pointer, so the Optional adds nothing. `t` arrives in x1 to x4.
@inline(never) public func makeThreeObject(
    _ k: Int, _ t: any (P1 & P2 & P3 & AnyObject).Type
) -> (any (P1 & P2 & P3 & AnyObject).Type)? {
    k > 8 ? t : nil
}

// Indirect, five words: written through x8. `t` is five words too and
// arrives by address in x1.
@inline(never) public func makeFourObject(
    _ k: Int, _ t: any (P1 & P2 & P3 & P4 & AnyObject).Type
) -> (any (P1 & P2 & P3 & P4 & AnyObject).Type)? {
    k > 9 ? t : nil
}

// Direct, four words: Ping is @objc and has no table. Its name does not
// say so, so this result is one a reader of the name cannot place.
@inline(never) public func makeThreeObjC(
    _ k: Int, _ t: any (P1 & P2 & P3 & Ping).Type
) -> (any (P1 & P2 & P3 & Ping).Type)? {
    k > 10 ? t : nil
}

// Direct, one word: a class's own metatype is its metadata pointer.
public final class Leaf {}
@inline(never) public func makeConcrete(_ k: Int, _ t: Leaf.Type) -> Leaf.Type? {
    k > 12 ? t : nil
}
