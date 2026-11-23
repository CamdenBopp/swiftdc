import Foundation

// A call promises only its declared scalar result bits. RET and outgoing
// arguments read physical views, not numeric conversions. Dirty producers
// leave nonzero upper bits and increment a counter to expose dropped calls.
struct Function { let name: String; let argument: String?; let result: String; let code: [String] }
func type(_ width: Int) -> String { width == 16 ? "Float16" : width == 32 ? "Float" : "Double" }
var functions: [Function] = []
let countCall = ["adrp x8, _fp_return_counter@PAGE", "ldr x9, [x8, _fp_return_counter@PAGEOFF]",
                 "add x9, x9, #1", "str x9, [x8, _fp_return_counter@PAGEOFF]"]
for (label, width, raw) in [("16",16,UInt64(0x3c00)), ("32",32,UInt64(0x3f800000)),
                           ("64",64,UInt64(0x3ff0000000000000)),
                           ("Dirty16",16,UInt64(0x123456783f803c00)), ("Dirty32",32,UInt64(0x123456783f800000))] {
    let register = width == 16 ? "h0" : width == 32 ? "s0" : "d0"
    let value: [String]
    if label.hasPrefix("Dirty") {
        value = ["mov x8, #\(raw & 0xffff)"] + [16,32,48].map { "movk x8, #\((raw >> $0) & 0xffff), lsl #\($0)" } + ["fmov d0, x8"]
    } else { value = ["fmov \(register), #1.0"] }
    functions.append(Function(name: "produce\(label)", argument: nil, result: type(width), code: countCall + value + ["ret"]))
    for result in [16, 32, 64] {
        functions.append(Function(name: "call\(label)to\(result)", argument: nil, result: type(result),
            code: ["stp x29, x30, [sp, #-16]!", "bl PRODUCE\(label)", "ldp x29, x30, [sp], #16", "ret"]))
        functions.append(Function(name: "forward\(label)to\(result)", argument: nil, result: type(result),
            code: ["stp x29, x30, [sp, #-16]!", "bl PRODUCE\(label)", "bl SINK\(result)", "ldp x29, x30, [sp], #16", "ret"]))
    }
}
for width in [16, 32, 64] {
    functions.append(Function(name: "sink\(width)", argument: type(width), result: type(width), code: ["ret"]))
}
for width in [32, 64] {
    for result in [16, 32, 64] {
        functions.append(Function(name: "c\(width)to\(result)", argument: nil, result: type(result),
            code: ["stp x29, x30, [sp, #-16]!", width == 32 ? "fmov s0, wzr" : "fmov d0, xzr",
                   width == 32 ? "bl _cosf" : "bl _cos", "ldp x29, x30, [sp], #16", "ret"]))
    }
}
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("fp-returns-\(UUID().uuidString)")
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
let declarations = functions.map {
    "public func \($0.name)(\($0.argument.map { "_ value: " + $0 } ?? "")) -> \($0.result) { 0 }"
}.joined(separator: "\n")
try declarations.write(to: scratch.appendingPathComponent("abi.swift"), atomically: true, encoding: .utf8)
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "FPReturns",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
let types = ["UInt32": "i32", "UInt64": "i64", "Float16": "half", "Float": "float", "Double": "double"]
var symbols: [String: String] = [:]
var definitions: [String] = []
for function in functions {
    let prefix = "$s9FPReturns\(function.name.count)\(function.name)"
    let matches = ir.split(separator: "\n").filter { $0.hasPrefix("define ") && $0.contains("@\"" + prefix) }
    precondition(matches.count == 1, "Missing/ambiguous ABI: " + function.name)
    let line = String(matches[0]).replacingOccurrences(of: "noundef ", with: "")
    let start = line.range(of: "@\"")!.upperBound
    let end = line[start...].firstIndex(of: "\"")!
    precondition(line[..<start].contains("swiftcc \(types[function.result]!) @\""))
    let parameters = line[line.index(after: end)...]
    if let argument = function.argument {
        precondition(parameters.hasPrefix("(\(types[argument]!) %0)"), "Unexpected parameters: " + line)
    } else { precondition(parameters.hasPrefix("()"), "Unexpected hidden arguments: " + line) }
    symbols[function.name] = String(line[start..<end])
    definitions.append(String(matches[0]))
}
// Name padding locally so the ABI fixture remains fully symbolized.
var assembly = [".data", ".p2align 3", ".globl _fp_return_counter", "_fp_return_counter:", ".quad 0", ".text", "_fp_returns_fixture_start:", "nop"]
for function in functions {
    assembly += [".p2align 2", ".globl _\(symbols[function.name]!)", "_\(symbols[function.name]!):"]
        + function.code.map { line in
            let resolved = [16, 32, 64].reduce(line) {
                $0.replacingOccurrences(of: "SINK\($1)", with: "_" + symbols["sink\($1)"]!)
            }
            return "    " + ["16", "32", "64", "Dirty16", "Dirty32"].reduce(resolved) {
                $0.replacingOccurrences(of: "PRODUCE\($1)", with: "_" + symbols["produce\($1)"]!)
            }
        }
}
try assembly.joined(separator: "\n").appending("\n").write(to: scratch.appendingPathComponent("case.s"), atomically: true, encoding: .utf8)
try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib", scratch.appendingPathComponent("case.s").path,
         "-o", "libFPReturns.dylib"])
try JSONSerialization.data(withJSONObject: ["definitions": definitions, "symbols": symbols], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("fpreturns.abi.json"))
print("Checked \(functions.count) LLVM signatures and built scalar FP call-return views")
