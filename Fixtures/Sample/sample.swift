// A small but metadata-rich Swift program used as a decompiler test fixture.
// Compile with: swiftc -O sample.swift -o sample
// (also build a -g and a stripped variant — see build.sh)

import Foundation

// MARK: - Protocols

public protocol Shape {
    var area: Double { get }
    func describe() -> String
}

public protocol Named {
    var name: String { get }
}

// MARK: - Structs

public struct Point: Equatable {
    public var x: Double
    public var y: Double

    public func distance(to other: Point) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

public struct Circle: Shape, Named {
    public var center: Point
    public var radius: Double
    public var name: String

    public init(center: Point, radius: Double, name: String) {
        self.center = center; self.radius = radius; self.name = name
    }

    public var area: Double { Double.pi * radius * radius }
    public func describe() -> String { "Circle(\(name)) r=\(radius)" }
}

public struct Rectangle: Shape {
    public var origin: Point
    public var width: Double
    public var height: Double

    public init(origin: Point, width: Double, height: Double) {
        self.origin = origin; self.width = width; self.height = height
    }

    public var area: Double { width * height }
    public func describe() -> String { "Rect \(width)x\(height)" }
}

// MARK: - Enums

enum Direction: Int {
    case north, east, south, west
}

enum Tree {
    case leaf(Int)
    indirect case node(Tree, Tree)

    func sum() -> Int {
        switch self {
        case .leaf(let v): return v
        case .node(let l, let r): return l.sum() + r.sum()
        }
    }
}

enum NetworkResult {
    case success(payload: Data, code: Int)
    case failure(message: String)
    case pending
}

// MARK: - Classes

class Animal: Named {
    let name: String
    init(name: String) { self.name = name }
    func speak() -> String { "..." }
}

final class Dog: Animal {
    var breed: String
    init(name: String, breed: String) {
        self.breed = breed
        super.init(name: name)
    }
    override func speak() -> String { "Woof, I am \(name) the \(breed)" }
}

// MARK: - Objective-C interop (emits ObjC runtime metadata)

@objc(SDWidget)
public class Widget: NSObject {
    @objc public var label: String
    @objc public init(label: String) {
        self.label = label
        super.init()
    }
    @objc public func ping() -> Int { label.count }
    @objc public func reset() { label = "" }
}

// MARK: - Generics

struct Stack<Element> {
    private var items: [Element] = []
    mutating func push(_ x: Element) { items.append(x) }
    mutating func pop() -> Element? { items.popLast() }
    var count: Int { items.count }
}

func maxElement<T: Comparable>(_ xs: [T]) -> T? {
    xs.max()
}

// MARK: - Loop (exercises while-structuring)

@inline(never)
public func countMatches(_ items: [Int], _ target: Int) -> Int {
    var count = 0
    for x in items {
        if x == target { count += 1 }
    }
    return count
}

// MARK: - Driver (keep symbols alive under -O)

@inline(never)
func run() {
    let shapes: [Shape] = [
        Circle(center: Point(x: 0, y: 0), radius: 2, name: "c1"),
        Rectangle(origin: Point(x: 1, y: 1), width: 3, height: 4),
    ]
    for s in shapes { print(s.describe(), s.area) }

    let tree = Tree.node(.leaf(1), .node(.leaf(2), .leaf(3)))
    print("tree sum", tree.sum())

    var stack = Stack<Int>()
    stack.push(10); stack.push(20)
    print("stack", stack.count, stack.pop() ?? -1)

    let dog = Dog(name: "Rex", breed: "Lab")
    print(dog.speak())

    print("max", maxElement([3, 1, 4, 1, 5, 9, 2, 6]) ?? -1)
    print("matches", countMatches([1, 2, 1, 3, 1], 1))
    print("dir", Direction.east.rawValue)

    switch (NetworkResult.success(payload: Data([1, 2, 3]), code: 200)) {
    case .success(_, let code): print("ok", code)
    case .failure(let m): print("err", m)
    case .pending: print("pending")
    }
}

// Driver runs only in the executable build (-DSAMPLE_MAIN). Expressed as an
// `@main` declaration (not a top-level statement) so the same file also
// compiles as a library with `-parse-as-library`.
#if SAMPLE_MAIN
@main
struct SampleMain {
    static func main() { run() }
}
#endif
