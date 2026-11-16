import Foundation

// Known ABI argument precision defines only the low scalar bits. RET alone
// reads physical views; scalar FMOV controls clear other bits. Raw callers
// poison the unused bits to disprove any implicit zero-extension at entry.
struct Function { let name: String; let argument: String?; let result: String; let code: [String] }
func type(_ width: Int) -> String { width == 16 ? "Float16" : width == 32 ? "Float" : "Double" }
var functions: [Function] = []
for source in [16, 32, 64] {
    for result in [16, 32, 64] {
        functions.append(Function(name: "entry\(source)to\(result)", argument: type(source), result: type(result), code: ["ret"]))
    }
}
for width in [16, 32, 64] {
    functions.append(Function(name: "copy\(width)", argument: type(width), result: type(width),
        code: ["mov v1.16b, v0.16b", "mov v0.16b, v1.16b", "ret"]))
    functions.append(Function(name: "kept\(width)", argument: type(width), result: type(width),
        code: ["sub sp, sp, #32", "stp x29, x30, [sp, #16]", "str d8, [sp]",
               "mov v8.16b, v0.16b", "bl _getpid", "mov v0.16b, v8.16b",
               "ldr d8, [sp]", "ldp x29, x30, [sp, #16]", "add sp, sp, #32", "ret"]))
}
for (source, result) in [(16,32),(16,64),(32,64)] {
    let r = source == 16 ? "h0" : "s0"
    functions.append(Function(name: "clear\(source)to\(result)", argument: type(source), result: type(result), code: ["fmov \(r), \(r)", "ret"]))
}
for (source, via) in [(32,16),(64,16),(64,32)] {
    let r = via == 16 ? "h0" : "s0"
    functions.append(Function(name: "narrow\(source)via\(via)", argument: type(source), result: "Double", code: ["fmov \(r), \(r)", "ret"]))
}
for (source, result) in [(16,32),(16,64),(32,64)] {
    functions.append(Function(name: "poison\(source)to\(result)", argument: "UInt64", result: type(result),
        code: ["stp x29, x30, [sp, #-16]!", "fmov d0, x0", "bl ENTRY\(source)to\(result)", "ldp x29, x30, [sp], #16", "ret"]))
}
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("fp-entries-\(UUID().uuidString)")
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
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "FPEntries",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
let types = ["UInt32": "i32", "UInt64": "i64", "Float16": "half", "Float": "float", "Double": "double"]
var symbols: [String: String] = [:]
var definitions: [String] = []
for function in functions {
    let prefix = "$s9FPEntries\(function.name.count)\(function.name)"
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
var assembly = [".text", "_fp_entries_fixture_start:", "nop"]
for function in functions {
    assembly += [".p2align 2", ".globl _\(symbols[function.name]!)", "_\(symbols[function.name]!):"]
        + function.code.map { line in
            "    " + [(16,32),(16,64),(32,64)].reduce(line) {
                $0.replacingOccurrences(of: "ENTRY\($1.0)to\($1.1)", with: "_" + symbols["entry\($1.0)to\($1.1)"]!)
            }
        }
}
try assembly.joined(separator: "\n").appending("\n").write(to: scratch.appendingPathComponent("case.s"), atomically: true, encoding: .utf8)
try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib", scratch.appendingPathComponent("case.s").path,
         "-o", "libFPEntries.dylib"])
try JSONSerialization.data(withJSONObject: ["definitions": definitions, "symbols": symbols], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("fpentries.abi.json"))
print("Checked \(functions.count) LLVM signatures and built scalar FP argument entry views")
