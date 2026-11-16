import Foundation

// Identical symbols can have two hidden isolation words or none. Preserve
// compiler frames/calls at -O, -Onone and -Osize; native drivers check values
// and one evaluation per effectful leaf. A pure constant separately proves
// GP-independent returns. Class self and the FP bank stay
// independent. Machine outlining is disabled to isolate argument placement;
// outlined-helper return modelling is a separate limitation. No code or
// metadata is patched.
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("async-isolation-" + UUID().uuidString)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
func run(_ args: [String]) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.currentDirectoryURL = directory; p.arguments = args
    try p.run(); p.waitUntilExit(); precondition(p.terminationStatus == 0, args.joined(separator: " "))
}

let fixture = #"""
nonisolated(unsafe) public var effectCount = 0
public func resetEffects() { effectCount = 0 }
public func readEffects() -> Int { effectCount }
@inline(never) nonisolated(nonsending) public func single(_ a: Int) async -> Int { effectCount &+= 1; return a &+ 7 }
@inline(never) nonisolated(nonsending) public func constant() async -> Int { 17 }
@inline(never) nonisolated(nonsending) func hidden(_ a: Int, _ b: Int) async -> Int { effectCount &+= 1; return a &* 101 &+ b }
@inline(never) nonisolated(nonsending) public func hiddenCaller(_ a: Int, _ b: Int) async -> Int { await hidden(b,a) }
@inline(never) nonisolated(nonsending) public func inner(_ a: Int, _ b: Int) async -> Int {
    effectCount &+= 1
    await Task.yield()
    return a &* 101 &+ b
}
@inline(never) nonisolated(nonsending) public func outer(_ a: Int, _ b: Int) async -> Int {
    await inner(b, a)
}
@inline(never) nonisolated(nonsending) public func mix(_ a: Int, _ f: Double, _ b: Int) async -> Double { effectCount &+= 1; return Double(a &* 101 &+ b) + f }
@inline(never) nonisolated(nonsending) public func mixOuter(_ a: Int, _ f: Double, _ b: Int) async -> Double {
    await mix(b, f, a)
}
@inline(never) nonisolated(nonsending) public func floatOnly(_ f: Double) async -> Double { effectCount &+= 1; return f + 2 }
@inline(never) nonisolated(nonsending) public func literalCaller() async -> Int { await inner(7,-3) }
public struct Pair { public var x: Int; public var f: Double; public init(_ x: Int, _ f: Double) { self.x=x; self.f=f } }
@inline(never) nonisolated(nonsending) public func pair(_ p: Pair) async -> Double { effectCount &+= 1; return Double(p.x) + p.f }
@inline(never) nonisolated(nonsending) public func pairOuter(_ p: Pair) async -> Double { await pair(p) }
@inline(never) nonisolated(nonsending) public func long(_ a0:Int,_ a1:Int,_ a2:Int,_ a3:Int,_ a4:Int,_ a5:Int,_ a6:Int,_ a7:Int,_ a8:Int) async -> Int { effectCount &+= 1; return a0 &* 3 &+ a1 &* 7 &+ a2 &* 11 &+ a3 &* 13 &+ a4 &* 17 &+ a5 &* 19 &+ a6 &* 23 &+ a7 &* 29 &+ a8 &* 31 }
@inline(never) nonisolated(nonsending) public func longOuter(_ a0:Int,_ a1:Int,_ a2:Int,_ a3:Int,_ a4:Int,_ a5:Int,_ a6:Int,_ a7:Int,_ a8:Int) async -> Int { await long(a8,a7,a6,a5,a4,a3,a2,a1,a0) }
@inline(never) nonisolated(nonsending) public func longLiteral() async -> Int { await long(1,2,3,4,5,6,7,8,9) }
@inline(never) public func sync(_ a:Int,_ b:Int) -> Int { effectCount &+= 1; return a &* 101 &+ b }
public final class Box: @unchecked Sendable {
    public let base: Int
    public init(_ base: Int) { self.base=base }
    @inline(never) nonisolated(nonsending) public func add(_ x:Int) async -> Int { effectCount &+= 1; return base &+ x }
}
@inline(never) nonisolated(nonsending) public func boxOuter(_ box:Box,_ x:Int) async -> Int { await box.add(x) }
"""#

let driver = #"""
import AsyncIsolation
@main struct Oracle { static func main() async {
    resetEffects()
    var n = 0
    for (a,b) in [(0,0),(1,2),(7,-3),(-9,4),(Int.max,Int.min)] {
        let direct = await inner(a,b)
        let swapped = await outer(a,b)
        let mixed = await mix(a,0.25,b)
        let mixedSwapped = await mixOuter(a,0.25,b)
        precondition(direct == a &* 101 &+ b)
        precondition(swapped == b &* 101 &+ a)
        precondition(mixed.bitPattern == (Double(direct)+0.25).bitPattern)
        precondition(mixedSwapped.bitPattern == (Double(swapped)+0.25).bitPattern)
        let p = Pair(a,0.25)
        let pr = await pair(p)
        let po = await pairOuter(p)
        precondition(pr.bitPattern == (Double(a)+0.25).bitPattern && po.bitPattern == pr.bitPattern)
        let lr = await long(a,b,2,3,4,5,6,7,8)
        let lo = await longOuter(a,b,2,3,4,5,6,7,8)
        precondition(lr == a &* 3 &+ b &* 7 &+ 813 && lo == a &* 31 &+ b &* 29 &+ 375)
        precondition(sync(a,b) == direct)
        let box = Box(5)
        let br = await box.add(a)
        let bo = await boxOuter(box,b)
        precondition(br == 5 &+ a && bo == 5 &+ b)
        let one = await single(a); precondition(one == a &+ 7)
        let hiddenResult = await hiddenCaller(a,b); precondition(hiddenResult == swapped)
        n += 13
    }
    for f in [0.0,1.25,-3.5] { let result = await floatOnly(f); precondition(result == f+2); n += 1 }
    let literal = await literalCaller(); precondition(literal == 704); n += 1
    let longLit = await longLiteral(); precondition(longLit == 973); n += 1
    let fixed = await constant(); precondition(fixed == 17); n += 1
    precondition(n == 71)
    precondition(readEffects() == n - 1, "One evaluation per effectful leaf")
    print("PASS",n,"native async isolation observations")
} }
"""#

var proofs: [[String: Any]] = []
for level in ["O", "Onone", "Osize"] {
    for mode in ["nonsending", "concurrent"] {
        let work = scratch.appendingPathComponent(level + "-" + mode)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let source = mode == "nonsending" ? fixture : fixture.replacingOccurrences(of: "nonisolated(nonsending)", with: "@concurrent")
        let input = work.appendingPathComponent("fixture.swift")
        let oracle = work.appendingPathComponent("native.swift")
        try source.write(to: input, atomically: true, encoding: .utf8)
        try driver.write(to: oracle, atomically: true, encoding: .utf8)
        let common = ["swiftc", "-parse-as-library", "-" + level, "-module-name", "AsyncIsolation", "-Xfrontend", "-disable-llvm-merge-functions-pass", "-Xllvm", "-enable-machine-outliner=never"]
        let library = "AsyncIsolation." + level + "." + mode
        try run(common + ["-emit-library", "-emit-module", "-emit-module-path", work.appendingPathComponent("AsyncIsolation.swiftmodule").path,
            input.path, "-Xlinker", "-install_name", "-Xlinker", "@rpath/lib" + library + ".dylib", "-o", "lib" + library + ".dylib"])
        try run(common + ["-emit-ir", input.path, "-o", work.appendingPathComponent("abi.ll").path])
        let ir = try String(contentsOf: work.appendingPathComponent("abi.ll"), encoding: .utf8)
        var definitions: [String] = []
        let shapes = [("5inner",2,0), ("5outer",2,0), ("3mix",2,1), ("8mixOuter",2,1), ("9floatOnly",0,1),
            ("13literalCaller",0,0), ("4pair",1,1), ("9pairOuter",1,1), ("4long",9,0), ("9longOuter",9,0),
            ("11longLiteral",0,0), ("8boxOuter",1,0), ("3BoxC3add",1,0), ("6single",1,0), ("8constant",0,0),
            ("6hidden",2,0), ("12hiddenCaller",2,0)]
        for (name, integers, floats) in shapes {
            let lines = ir.split(separator: "\n").filter { line in
                guard line.hasPrefix("define "), line.contains("@\"$s14AsyncIsolation" + name), line.contains("swiftasync"),
                    let rest = line.components(separatedBy: "@\"").dropFirst().first else { return false }
                return rest.components(separatedBy: "\"")[0].hasSuffix("YaF")
            }
            precondition(lines.count == 1, name)
            let line = String(lines[0])
            let hidden = mode == "nonsending" ? 2 : 0
            precondition(line.components(separatedBy: "i64 %").count - 1 == integers + hidden, line)
            precondition(line.components(separatedBy: "double %").count - 1 == floats, line)
            if name == "3BoxC3add" { precondition(line.contains("swiftself"), line) }
            if name == "8boxOuter" { precondition(line.components(separatedBy: "ptr ").count - 1 == 2, line) }
            definitions.append(line)
        }
        let sync = ir.split(separator: "\n").filter { $0.hasPrefix("define swiftcc i64 @\"$s14AsyncIsolation4sync") }
        precondition(sync.count == 1 && sync[0].components(separatedBy: "i64 %").count - 1 == 2)
        definitions.append(String(sync[0]))
        let executable = "async-isolation-" + level + "-" + mode + "-oracle"
        try run(["swiftc", "-parse-as-library", "-" + level, "-I", work.path, "-L", directory.path, "-l" + library,
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path", oracle.path, "-o", executable])
        let native = Process(); native.executableURL = directory.appendingPathComponent(executable)
        try native.run(); native.waitUntilExit(); precondition(native.terminationStatus == 0)
        precondition(definitions.count == 18)
        proofs.append(["optimization":level, "mode":mode, "definitions":definitions,
            "nativeObservations":71, "effectfulLeafEvaluations":70])
    }
}
precondition(proofs.count == 6)
let stripped = directory.appendingPathComponent("libAsyncIsolation.O.nonsending.stripped.dylib")
if FileManager.default.fileExists(atPath: stripped.path) { try FileManager.default.removeItem(at: stripped) }
try FileManager.default.copyItem(at: directory.appendingPathComponent("libAsyncIsolation.O.nonsending.dylib"), to: stripped)
try run(["strip", "-x", stripped.path])
try JSONSerialization.data(withJSONObject: ["builds":proofs, "checkedSignatures":108, "nativeObservations":426], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("asyncisolation.abi.json"))
print("Checked 108 compiler ABI signatures and 426 native async isolation observations")
