import Foundation

// Compiler-produced async frames, executor hops and parent continuations.
// Only the ten cross-width result conversions become physical D8 copies.
// Dirty producers alter unused result bits in both raw and numeric controls.
// Their counter increment is two to keep their bodies distinct and detect
// duplicated evaluation; clean producers increment once.
struct Producer { let label: String; let bits: Int; let effect: Int }
let producers = [Producer(label: "16", bits: 16, effect: 1), Producer(label: "32", bits: 32, effect: 1),
    Producer(label: "64", bits: 64, effect: 1), Producer(label: "Dirty16", bits: 16, effect: 2),
    Producer(label: "Dirty32", bits: 32, effect: 2)]
let types = [16: "Float16", 32: "Float", 64: "Double"]
let llvmTypes = [16: "half", 32: "float", 64: "double"]
let registers = [16: "h", 32: "s", 64: "d"]
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("async-fp-returns-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
func run(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.currentDirectoryURL = directory
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, arguments.joined(separator: " "))
}
var source = ["nonisolated(unsafe) public var effectCount: UInt64 = 0",
    "public func resetEffects() { effectCount = 0 }", "public func readEffects() -> UInt64 { effectCount }"]
for producer in producers {
    let type = types[producer.bits]!
    source.append("@inline(never) public func produce\(producer.label)(_ value: \(type)) async -> \(type) { effectCount &+= \(producer.effect); return value }")
    for result in [16, 32, 64] {
        source.append("@inline(never) public func view\(producer.label)to\(result)(_ value: \(type)) async -> \(types[result]!) { let result = await produce\(producer.label)(value); return \(types[result]!)(result) }")
    }
}
let sourcePath = scratch.appendingPathComponent("fixture.swift")
try source.joined(separator: "\n").appending("\n").write(to: sourcePath, atomically: true, encoding: .utf8)
// Keep each continuation's identity independent. Width handling is tested
// here; folded/shared async continuations have separate ambiguity tests.
let common = ["swiftc", "-parse-as-library", "-O", "-target", "arm64-apple-macos15", "-module-name", "AsyncFPReturns",
              "-Xfrontend", "-disable-llvm-merge-functions-pass"]
try run(common + ["-emit-assembly", "-emit-module", "-emit-module-path", scratch.appendingPathComponent("AsyncFPReturns.swiftmodule").path,
                  sourcePath.path, "-o", scratch.appendingPathComponent("original.s").path])
try run(common + ["-emit-ir", sourcePath.path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
var assembly = try String(contentsOf: scratch.appendingPathComponent("original.s"), encoding: .utf8)
var symbols: [String: String] = [:]
var definitions: [String] = []
func definition(_ prefix: String) -> String {
    let matches = ir.split(separator: "\n").filter { $0.hasPrefix(prefix) }
    precondition(matches.count == 1, "Missing or ambiguous ABI: " + prefix)
    return String(matches[0])
}
func body(of line: String) -> String {
    let start = ir.range(of: line)!.lowerBound
    return String(ir[start...].prefix(while: { $0 != "}" }))
}
func requireParent(_ body: String, bits: Int) {
    let tails = body.split(separator: "\n").filter { $0.contains("musttail call swifttailcc void") }
    precondition(tails.count == 1 && tails[0].contains("(ptr swiftasync ") && tails[0].contains(", \(llvmTypes[bits]!) "), "Wrong parent result ABI")
}
for producer in producers {
    for name in ["produce" + producer.label] + [16, 32, 64].map({ "view\(producer.label)to\($0)" }) {
        let prefix = "$s14AsyncFPReturns\(name.count)\(name)"
        let entry = definition("define swifttailcc void @\"" + prefix)
        let symbol = String(entry.components(separatedBy: "@\"")[1].prefix(while: { $0 != "\"" }))
        symbols[name] = symbol
        precondition(entry.contains("ptr swiftasync") && entry.contains(", \(llvmTypes[producer.bits]!) %1)"), entry)
        definitions.append(entry)
        let resume = definition("define internal swifttailcc void @\"" + symbol + (name.hasPrefix("view") ? "TQ0_\"" : "TY0_\""))
        if name.hasPrefix("view") {
            precondition(resume.contains(", \(llvmTypes[producer.bits]!) %1)"), resume)
            requireParent(body(of: resume), bits: Int(name.components(separatedBy: "to").last!)!)
        } else {
            requireParent(body(of: resume), bits: producer.bits)
        }
        definitions.append(resume)
    }
}
precondition(definitions.count == 40)
var poisonProof: [[String: Any]] = []
for producer in producers where producer.label.hasPrefix("Dirty") {
    let marker = "_" + symbols["produce" + producer.label]! + "TY0_:"
    precondition(assembly.components(separatedBy: marker).count == 2)
    let start = assembly.range(of: marker)!.lowerBound
    let end = assembly.range(of: "; -- End function", range: start..<assembly.endIndex)!.lowerBound
    let block = String(assembly[start..<end])
    let branches = block.split(separator: "\n").filter { $0.hasPrefix("\tbr\t") }
    precondition(branches.count == 1)
    let branch = String(branches[0])
    let target = branch.trimmingCharacters(in: .whitespaces).components(separatedBy: "\t").last!
    let temporary = target == "x9" ? "x10" : "x9"
    var instructions = ["\tfmov\t\(temporary), d0"]
    if producer.bits == 16 { instructions.append("\tmovk\t\(temporary), #0x3f80, lsl #16") }
    instructions += ["\tmovk\t\(temporary), #0x5678, lsl #32", "\tmovk\t\(temporary), #0x1234, lsl #48", "\tfmov\td0, \(temporary)"]
    let patched = block.replacingOccurrences(of: branch, with: instructions.joined(separator: "\n") + "\n" + branch)
    assembly.replaceSubrange(start..<end, with: patched)
    poisonProof.append(["producer": producer.label, "resultBits": producer.bits, "branchRegister": target, "scratchRegister": temporary])
}
let conversion = try NSRegularExpression(pattern: "^\\tfcvt\\t([hsd])0, ([hsd])8$", options: [.anchorsMatchLines])
let matches = conversion.matches(in: assembly, range: NSRange(assembly.startIndex..., in: assembly))
let actual = matches.map { match in
    String(assembly[Range(match.range(at: 1), in: assembly)!]) + "," + String(assembly[Range(match.range(at: 2), in: assembly)!])
}.sorted()
let expected = producers.flatMap { producer in
    [16, 32, 64].filter { $0 != producer.bits }.map { registers[$0]! + "," + registers[producer.bits]! }
}.sorted()
precondition(matches.count == 10 && actual == expected, "Unexpected physical conversion lowering")
let raw = conversion.stringByReplacingMatches(in: assembly, range: NSRange(assembly.startIndex..., in: assembly), withTemplate: "\tfmov\td0, d8")
for (mode, text, library) in [("raw", raw, "libAsyncFPReturns.dylib"), ("control", assembly, "libAsyncFPReturnsControl.dylib")] {
    let path = scratch.appendingPathComponent(mode + ".s")
    try text.write(to: path, atomically: true, encoding: .utf8)
    let object = scratch.appendingPathComponent(mode + ".o")
    try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-mmacosx-version-min=15", "-c", path.path, "-o", object.path])
    try run(["swiftc", "-emit-library", "-target", "arm64-apple-macos15", "-module-name", "AsyncFPReturns", object.path,
             "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + library, "-o", library])
}
let patterns: [Int: [UInt64]] = [
    16: [0, 1, 0x3c00, 0x8000, 0x7c00, 0x7e01, 0xffff],
    32: [0, 1, 0x3f800000, 0x80000000, 0x7f800000, 0x7fc00001, 0xffffffff],
    64: [0, 1, 0x3ff0000000000000, 0x8000000000000000, 0x7ff0000000000000, 0x7ff8000000000001, .max],
]
var driver = ["import AsyncFPReturns", "@main struct Oracle { static func main() async {",
              "let converted = CommandLine.arguments.contains(\"--converted\")", "var observations = 0"]
for producer in producers {
    driver.append("for raw: UInt\(producer.bits) in [\(patterns[producer.bits]!.map { "0x" + String($0, radix: 16) }.joined(separator: ", "))] {")
    driver.append("let input = \(types[producer.bits]!)(bitPattern: raw)")
    for result in [16, 32, 64] {
        let bits = producer.label == "Dirty16" ? "(UInt64(raw) | 0x123456783f800000)" : producer.label == "Dirty32" ? "(UInt64(raw) | 0x1234567800000000)" : "UInt64(raw)"
        let mask = result == 64 ? "" : " & 0x" + String((UInt64(1) << result) - 1, radix: 16)
        driver += ["resetEffects()", "let result\(result) = await view\(producer.label)to\(result)(input)",
            "let expected\(result): UInt64 = converted ? UInt64(\(types[result]!)(input).bitPattern) : (\(bits)\(mask))",
            "precondition(UInt64(result\(result).bitPattern) == expected\(result), \"view\(producer.label)to\(result)\")",
            "precondition(readEffects() == \(producer.effect), \"producer effect count\")",
            "print(\"view\(producer.label)to\(result)\", String(raw, radix: 16), String(result\(result).bitPattern, radix: 16), \"effects\", readEffects())",
            "observations += 1"]
    }
    driver.append("}")
}
driver += ["precondition(observations == 105)", "print(\"PASS\", observations, \"native async observations\")", "} }"]
let driverPath = scratch.appendingPathComponent("native.swift")
try driver.joined(separator: "\n").appending("\n").write(to: driverPath, atomically: true, encoding: .utf8)
for mode in ["raw", "control"] {
    let library = mode == "raw" ? "AsyncFPReturns" : "AsyncFPReturnsControl"
    try run(["swiftc", "-parse-as-library", "-O", "-target", "arm64-apple-macos15", "-I", scratch.path, "-L", directory.path,
             "-l" + library, "-Xlinker", "-rpath", "-Xlinker", "@executable_path", driverPath.path, "-o", "async-fp-\(mode)-oracle"])
}
try JSONSerialization.data(withJSONObject: ["definitions": definitions, "symbols": symbols, "poison": poisonProof,
    "rawConversionReplacements": matches.count, "nativeObservationsPerMode": 105], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("asyncfpreturns.abi.json"))
print("Checked 40 async entry/resume LLVM signatures and built ten raw views plus numeric/dirty controls")
