import Foundation

// FP stores contain encodings. memcpy/memmove preserve those bytes even
// when the argument has no computed-result tag. LLVM fixes each Swift ABI;
// authored instructions isolate the stack-bank and byte-copy boundaries.
struct Function {
    let name: String
    let argument: String?
    let result: String
    let code: [String]
}
var functions: [Function] = []
func add(_ name: String, _ result: String, _ code: [String], argument: String) {
    functions.append(Function(name: name, argument: argument, result: result, code: code))
}
for width in [16, 32, 64] {
    let type = width == 16 ? "Float16" : width == 32 ? "Float" : "Double"
    let fp = width == 16 ? "h0" : width == 32 ? "s0" : "d0"
    let load = width == 16 ? "ldrh w0" : width == 32 ? "ldr w0" : "ldr x0"
    add("direct\(width)", "UInt64", ["sub sp, sp, #16", "str \(fp), [sp]", "\(load), [sp]", "add sp, sp, #16", "ret"], argument: type)
    func copied(_ name: String, bytes: Int, helper: String = "memcpy", prefix: [String] = [], load: String, result: String = "UInt64") {
        add("\(name)\(width)", result,
            ["sub sp, sp, #48", "stp x29, x30, [sp, #32]", "str \(fp), [sp]"] + prefix
            + ["mov x1, sp", "add x0, sp, #16", "mov x2, #\(bytes)", "bl _\(helper)", "\(load), [sp, #16]", "ldp x29, x30, [sp, #32]", "add sp, sp, #48", "ret"], argument: type)
    }
    copied("copy", bytes: width / 8, load: load)
    copied("move", bytes: width / 8, helper: "memmove", load: load)
    copied("byte", bytes: 1, load: "ldrb w0")
    if width > 16 { copied("short", bytes: 2, load: "ldrh w0") }
    copied("fpCopy", bytes: width / 8, load: "ldr \(fp)", result: type)
    // A partial overwrite invalidates the old whole-word fact. The native
    // result still contains untouched argument bytes; analysis must decline.
    copied("overlap", bytes: width / 8, prefix: ["mov w8, #7", "strb w8, [sp]"], load: load)
    copied("cleared", bytes: 8, prefix: ["str xzr, [sp]"], load: "ldr x0")
}
// A GPR spill uses integer semantics across the same byte-copy boundary.
add("integerCopy", "UInt64", ["sub sp, sp, #48", "stp x29, x30, [sp, #32]", "str x0, [sp]", "mov x1, sp", "add x0, sp, #16", "mov x2, #8", "bl _memcpy", "ldr x0, [sp, #16]", "ldp x29, x30, [sp, #32]", "add sp, sp, #48", "ret"], argument: "UInt64")
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("fp-copies-\(UUID().uuidString)")
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
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "FPCopies",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
let types = ["UInt32": "i32", "UInt64": "i64", "Float16": "half", "Float": "float", "Double": "double"]
var symbols: [String: String] = [:]
var definitions: [String] = []
for function in functions {
    let prefix = "$s8FPCopies\(function.name.count)\(function.name)"
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
var assembly = [".text", "nop"]
for function in functions {
    assembly += [".p2align 2", ".globl _\(symbols[function.name]!)", "_\(symbols[function.name]!):"]
        + function.code.map { "    " + $0 }
}
try assembly.joined(separator: "\n").appending("\n").write(to: scratch.appendingPathComponent("case.s"), atomically: true, encoding: .utf8)
try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib", scratch.appendingPathComponent("case.s").path,
         "-o", "libFPCopies.dylib"])
try JSONSerialization.data(withJSONObject: ["definitions": definitions, "symbols": symbols], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("fpcopies.abi.json"))
print("Checked \(functions.count) LLVM signatures and built scalar FP byte copies")
