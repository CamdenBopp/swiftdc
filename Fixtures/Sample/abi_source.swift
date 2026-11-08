// Native arm64 ABI probes for result and value-self register placement.
// Build with build-abi-source.sh; keep these bodies visible at -O.

public struct ABIOneDouble {
    public var value: Double
    public init(_ value: Double) { self.value = value }
}

@inline(never)
public func abiAddOne(_ value: Int) -> Int { value &+ 1 }

@inline(never)
public func abiOneDoubleFromInt(_ value: Int) -> ABIOneDouble {
    ABIOneDouble(Double(abiAddOne(value)) + 0.5)
}

public struct ABIVec2 {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    @inline(never)
    public func scaled(_ factor: Double) -> Double { x * factor + y }

    @inline(never)
    public func dot(_ other: ABIVec2) -> Double { x * other.x + y * other.y }
}

// An ordinary five-word value uses x8 for its result. Under library
// evolution, even the one- and two-word public values below use x8.
public struct ABIOneWord {
    public let a: Int
    public init(_ a: Int) { self.a = a }
}

public struct ABITwoWords {
    public let a: Int
    public let b: Int
    public init(_ a: Int, _ b: Int) { self.a = a; self.b = b }
}

public struct ABIFiveWords {
    public let a: Int
    public let b: Int
    public let c: Int
    public let d: Int
    public let e: Int
    public init(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e
    }
}

public final class ABIRef {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

@inline(never)
public func abiMakeOne(_ seed: Int) -> ABIOneWord { ABIOneWord(seed &+ 17) }

@inline(never)
public func abiMakeTwo(_ seed: Int) -> ABITwoWords { ABITwoWords(seed &+ 1, seed &+ 2) }

@inline(never)
public func abiMakeFive(_ seed: Int) -> ABIFiveWords {
    ABIFiveWords(seed &+ 1, seed &+ 2, seed &+ 3, seed &+ 4, seed &+ 5)
}

@inline(never)
public func abiMaybeFive(_ seed: Int, _ yes: Bool) -> ABIFiveWords? {
    yes ? abiMakeFive(seed) : nil
}

@inline(never)
public func abiMakeRef(_ seed: Int) -> ABIRef { ABIRef(seed &+ 1) }

@inline(never)
public func abiEraseInt(_ value: Int) -> Any { value }

@inline(never)
public func abiMakeSubstring(_ value: String) -> Substring { value.dropFirst() }
