import Foundation

// Author all four scalar half/GPR moves after proving the public Swift ABI.
// H->W/X zero-extends sixteen bits; W/X->H discards every upper bit.
struct Function {
    let name: String
    let argument: String?
    let result: String
    let code: [String]
}
var functions: [Function] = []
for wide in [false, true] {
    let suffix = wide ? "X" : "W"
    let register = wide ? "x0" : "w0"
    let scratch = wide ? "x8" : "w8"
    let integer = wide ? "UInt64" : "UInt32"
    functions += [
        Function(name: "neg" + suffix, argument: nil, result: integer,
                 code: ["fmov h0, #1.0", "fneg h0, h0", "fmov \(register), h0", "ret"]),
        Function(name: "arg" + suffix, argument: "Float16", result: integer,
                 code: ["fmov \(register), h0", "ret"]),
        Function(name: "narrow" + suffix, argument: "Float16", result: integer,
                 code: ["fneg h0, h0", "fmov \(register), h0", "ret"]),
        Function(name: "from" + suffix, argument: integer, result: "Float16",
                 code: ["fmov h0, \(register)", "ret"]),
        Function(name: "view" + suffix, argument: integer, result: "Double",
                 code: ["fmov h0, \(register)", "ret"]),
        Function(name: "single" + suffix, argument: integer, result: "Float",
                 code: ["fmov h0, \(register)", "ret"]),
        Function(name: "viewConst" + suffix, argument: nil, result: "Double",
                 code: ["mov \(scratch), #0x7e01", "movk \(scratch), #0xabcd, lsl #16"]
                    + (wide ? ["movk x8, #0x1234, lsl #48"] : [])
                    + ["fmov h0, \(scratch)", "ret"]),
        Function(name: "add" + suffix, argument: integer, result: "Float16",
                 code: ["fmov h0, \(register)", "fadd h0, h0, h0", "ret"]),
        Function(name: "round" + suffix, argument: integer, result: integer,
                 code: ["fmov h0, \(register)", "fmov \(register), h0", "ret"]),
        Function(name: "back" + suffix, argument: "Float16", result: "Float16",
                 code: ["fmov \(scratch), h0", "fmov h0, \(scratch)", "ret"]),
        Function(name: "raw" + suffix, argument: nil, result: integer,
                 code: ["mov \(scratch), #0x7e01", "movk \(scratch), #0xabcd, lsl #16"]
                    + (wide ? ["movk x8, #0x1234, lsl #48"] : [])
                    + ["fmov h0, \(scratch)", "fmov \(register), h0", "ret"]),
        Function(name: "low" + suffix, argument: nil, result: integer,
                 code: ["mov x8, #0x7e01", "movk x8, #0xabcd, lsl #16", "movk x8, #0x1234, lsl #48",
                        "fmov d0, x8", "fmov \(register), h0", "ret"]),
        Function(name: "call" + suffix, argument: nil, result: integer,
                 code: ["stp x29, x30, [sp, #-16]!", "bl PRODUCER", "fmov \(register), h0",
                        "ldp x29, x30, [sp], #16", "ret"]),
    ]
}
functions.append(Function(name: "producer", argument: nil, result: "Float16", code: ["fmov h0, #2.5", "ret"]))
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("half-moves-\(UUID().uuidString)")
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
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "HalfMoves",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
let types = ["UInt32": "i32", "UInt64": "i64", "Float16": "half", "Float": "float", "Double": "double"]
var symbols: [String: String] = [:]
var definitions: [String] = []
for function in functions {
    let prefix = "$s9HalfMoves\(function.name.count)\(function.name)"
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
// Keep the padding's local symbol: this is a fully named ABI fixture, not
// a partially stripped image whose trivial callee names must be declined.
var assembly = [".text", "_half_moves_fixture_start:", "nop"]
for function in functions {
    assembly += [".p2align 2", ".globl _\(symbols[function.name]!)", "_\(symbols[function.name]!):"]
        + function.code.map { "    " + $0.replacingOccurrences(of: "PRODUCER", with: "_" + symbols["producer"]!) }
}
try assembly.joined(separator: "\n").appending("\n").write(to: scratch.appendingPathComponent("case.s"), atomically: true, encoding: .utf8)
try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib", scratch.appendingPathComponent("case.s").path,
         "-o", "libHalfMoves.dylib"])
try JSONSerialization.data(withJSONObject: ["definitions": definitions, "symbols": symbols], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("halfmoves.abi.json"))
print("Checked \(functions.count) LLVM signatures and built all four half/GPR move forms")
