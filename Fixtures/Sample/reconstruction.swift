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
