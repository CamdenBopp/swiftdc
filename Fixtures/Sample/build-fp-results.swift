import Foundation

// Scalar results retain their precision. Wider reads are raw reinterpretations;
// unknown FPCR.NEP merging must never be guessed to clear the other bits.
struct Function {
    let name: String
    let argument: String?
    let result: String
    let code: [String]
}
var functions: [Function] = []
func add(_ name: String, _ result: String, _ code: [String], argument: String? = nil) {
    functions.append(Function(name: name, argument: argument, result: result, code: code))
}
func type(_ bits: Int) -> String { bits == 64 ? "Double" : bits == 32 ? "Float" : "Float16" }
func reg(_ bits: Int, _ index: Int) -> String { "\(bits == 64 ? "d" : bits == 32 ? "s" : "h")\(index)" }
func pattern(_ bits: Int, _ value: Double) -> UInt64 {
    bits == 64 ? value.bitPattern : bits == 32 ? UInt64(Float(value).bitPattern) : UInt64(Float16(value).bitPattern)
}
func raw(_ bits: UInt64, to index: Int, width: Int) -> [String] {
    var code = ["mov x8, #\(bits & 0xffff)"]
    for shift in stride(from: 16, to: 64, by: 16) {
        let part = (bits >> shift) & 0xffff
        if part != 0 { code.append("movk x8, #\(part), lsl #\(shift)") }
    }
    code.append("fmov \(reg(width, index)), \(width == 64 ? "x8" : "w8")")
    return code
}
func value(_ number: Double, to index: Int, width: Int) -> [String] { raw(pattern(width, number), to: index, width: width) }
let operations = ["neg", "abs", "sqrt", "add", "sub", "mul", "div", "nmul", "scvt", "ucvt", "convert", "fixSigned", "fixUnsigned", "nan"]
func operation(_ op: String, width: Int, dirtyDest: Bool = false, dirtySource: Bool = false) -> [String] {
    let d = reg(width, 0), n = reg(width, 1), m = reg(width, 2)
    let poison: UInt64 = width == 16 ? 0xabcd3c00 : 0x123400003f800000
    var code = dirtyDest ? raw(poison, to: 0, width: 64) : value(1, to: 0, width: width)
    switch op {
    case "neg", "abs", "sqrt", "nan":
        if op == "nan" {
            code += raw(width == 64 ? 0x7ff8000000000001 : width == 32 ? 0x7fc00001 : 0x7e01, to: 1, width: width)
        } else { code += value(op == "abs" ? -1 : op == "sqrt" ? 4 : 1, to: 1, width: width) }
        code += ["\(op == "abs" ? "fabs" : op == "sqrt" ? "fsqrt" : "fneg") \(d), \(n)"]
    case "scvt", "ucvt", "fixSigned", "fixUnsigned":
        code += ["mov x8, #5", "\(op == "ucvt" || op == "fixUnsigned" ? "ucvtf" : "scvtf") \(d), x8\(op.hasPrefix("fix") ? ", #1" : "")"]
    case "convert":
        let source = width == 32 ? 64 : 32
        code += value(0.1, to: 1, width: source) + ["fcvt \(d), \(reg(source, 1))"]
    default:
        let a: Double = op == "add" ? 0.1 : op == "sub" ? 2.5 : op == "div" ? 4 : 2
        let b: Double = op == "add" ? 0.2 : op == "sub" ? 1 : 2
        code += dirtySource ? raw(poison, to: 1, width: 64) : value(a, to: 1, width: width)
        code += value(b, to: 2, width: width)
        code += ["\(op == "nmul" ? "fnmul" : "f" + op) \(d), \(n), \(m)"]
    }
    return code
}
for width in [16, 32, 64] {
    for op in operations where width != 16 || !op.hasPrefix("fix") {
        for read in [16, 32, 64] {
            add("\(op)\(width)to\(read)", type(read), operation(op, width: width) + ["ret"])
        }
    }
}
for width in [16, 32] {
    for op in ["neg", "abs", "sqrt", "scvt", "ucvt", "convert"] {
        add("dirty\(op)\(width)", "Double", operation(op, width: width, dirtyDest: true) + ["ret"])
    }
    add("sameDirty\(width)", type(width), operation("neg", width: width, dirtyDest: true) + ["ret"])
    for op in ["add", "sub", "mul", "div", "nmul"] {
        add("cleanSource\(op)\(width)", "Double", operation(op, width: width, dirtyDest: true) + ["ret"])
        add("dirtySource\(op)\(width)", "Double", operation(op, width: width, dirtySource: true) + ["ret"])
    }
    let r = reg(width, 0)
    add("reload\(width)", "Double", operation("neg", width: width, dirtyDest: true)
        + ["sub sp, sp, #16", "str \(r), [sp]", "ldr \(r), [sp]", "add sp, sp, #16", "ret"])
    add("copy\(width)", "Double", operation("neg", width: width, dirtyDest: true)
        + ["fmov \(r), \(r)", "ret"])
    add("gprRoundClears\(width)", "Double", operation("neg", width: width, dirtyDest: true)
        + ["fmov w8, \(r)", "fmov \(r), w8", "ret"])
    add("rawScalarCopy\(width)", "Double", raw(width == 16 ? 0xabcd3c00 : 0x123400003f800000, to: 0, width: 64)
        + ["fmov \(r), \(r)", "ret"])
}
add("rawQSpill64", "UInt64", ["fmov d0, x0", "sub sp, sp, #16", "str q0, [sp]", "ldr x0, [sp]", "add sp, sp, #16", "ret"], argument: "UInt64")
add("pairFP32", "Double", operation("neg", width: 32, dirtyDest: true)
    + value(2, to: 1, width: 32) + ["stp s0, s1, [sp, #-16]!", "ldp s0, s1, [sp], #16", "ret"])
for width in [32, 64] {
    add("pairGP\(width)", "UInt\(width)", operation("neg", width: width)
        + value(2, to: 1, width: width) + ["stp \(reg(width, 0)), \(reg(width, 1)), [sp, #-16]!",
            "ldp \(width == 64 ? "x0, x1" : "w0, w1"), [sp], #16", "ret"])
}
add("halfGPReload", "UInt32", operation("neg", width: 16)
    + ["sub sp, sp, #16", "str h0, [sp]", "ldrh w0, [sp]", "add sp, sp, #16", "ret"])
for width in [16, 32, 64] {
    let tail = width == 16 ? "ldrh w0" : width == 32 ? "ldr w0" : "ldr x0"
    let body = ["sub sp, sp, #48", "stp x29, x30, [sp, #32]"] + operation("neg", width: width, dirtyDest: width < 64)
        + ["str \(reg(width, 0)), [sp]", "mov x1, sp", "add x0, sp, #8", "mov x2, #\(width / 8)", "bl _memcpy", "\(tail), [sp, #8]", "ldp x29, x30, [sp, #32]", "add sp, sp, #48", "ret"]
    add("computedMemcpy\(width)", "UInt64", body)
}
add("shortComputedCopy64", "UInt64", ["sub sp, sp, #48", "stp x29, x30, [sp, #32]"] + operation("add", width: 64)
    + ["str d0, [sp]", "mov x1, sp", "add x0, sp, #8", "mov x2, #2", "bl _memcpy", "ldrh w0, [sp, #8]", "ldp x29, x30, [sp, #32]", "add sp, sp, #48", "ret"])
add("byteComputedCopy64", "UInt64", ["sub sp, sp, #48", "stp x29, x30, [sp, #32]"] + operation("add", width: 64)
    + ["str d0, [sp]", "mov x1, sp", "add x0, sp, #8", "mov x2, #1", "bl _memcpy", "ldrb w0, [sp, #8]", "ldp x29, x30, [sp, #32]", "add sp, sp, #48", "ret"])
add("byteGPReload16", "UInt64", operation("add", width: 16)
    + ["sub sp, sp, #16", "str h0, [sp]", "ldrb w0, [sp]", "add sp, sp, #16", "ret"])
add("copiedFPRoundTrip16", "Double", ["sub sp, sp, #48", "stp x29, x30, [sp, #32]"] + operation("neg", width: 16, dirtyDest: true)
    + ["str h0, [sp]", "mov x1, sp", "add x0, sp, #8", "mov x2, #2", "bl _memcpy", "ldr h0, [sp, #8]", "ldp x29, x30, [sp, #32]", "add sp, sp, #48", "ret"])
for read in [16, 32, 64] {
    add("wholeCopy64to\(read)", type(read), operation("add", width: 64) + ["mov v1.16b, v0.16b", "mov v0.16b, v1.16b", "ret"])
}
for width in [16, 32] {
    add("pool\(width)", "Double", ["adrp x8, L_pool\(width)@PAGE", "ldr \(reg(width, 0)), [x8, L_pool\(width)@PAGEOFF]", "fneg \(reg(width, 0)), \(reg(width, 0))", "ret"])
    add("gpWideRead\(width)", "UInt64", operation("neg", width: width) + ["fmov x0, d0", "ret"])
    add("chain\(width)", "Double", operation("neg", width: width) + ["fabs \(reg(width, 0)), \(reg(width, 0))", "ret"])
    add("wholeChain\(width)", "Double", operation("neg", width: width) + ["mov v1.16b, v0.16b", "mov v0.16b, v1.16b", "fabs \(reg(width, 0)), \(reg(width, 0))", "ret"])
    add("narrowCopy64via\(width)", "Double", operation("add", width: 64) + ["fmov \(reg(width, 0)), \(reg(width, 0))", "ret"])
}
for width in [16, 32, 64] {
    var code = value(1, to: 0, width: width) + value(1, to: 1, width: width)
    for _ in 0..<6 { code.append("fadd \(reg(width, 0)), \(reg(width, 0)), \(reg(width, 1))") }
    add("deep\(width)", type(width), code + ["ret"])
}
add("frameBitsToWide16", "Double", ["sub sp, sp, #16", "strh w0, [sp]", "ldr h0, [sp]", "add sp, sp, #16", "fneg h0, h0", "ret"], argument: "UInt64")
add("joinAgain16to64", "Double", value(1, to: 0, width: 16) + ["cmp x0, #0", "b.ne L_positive_again", "fneg h0, h0", "b L_join_again", "L_positive_again:", "fabs h0, h0", "L_join_again:", "fneg h0, h0", "ret"], argument: "UInt64")
for read in [16, 64] {
    add("call\(read)", "UInt64", ["stp x29, x30, [sp, #-16]!"] + operation("neg", width: 16, dirtyDest: read == 16)
        + ["bl SINK\(read)", "ldp x29, x30, [sp], #16", "ret"])
    add("sink\(read)", "UInt64", ["fmov \(read == 64 ? "x0, d0" : "w0, h0")", "ret"], argument: type(read))
}
add("join16to64", "Double", value(1, to: 0, width: 16) + ["cmp x0, #0", "b.ne L_positive", "fneg h0, h0", "b L_join", "L_positive:", "fabs h0, h0", "L_join:", "ret"], argument: "UInt64")
add("nepAvailable", "UInt64", ["mrs x9, fpcr", "orr x10, x9, #4", "msr fpcr, x10", "isb", "mrs x0, fpcr", "and x0, x0, #4", "msr fpcr, x9", "isb", "ret"])
for enabled in [false, true] {
    add(enabled ? "nepOne" : "nepZero", "UInt64", ["mrs x9, fpcr", "\(enabled ? "orr" : "bic") x10, x9, #4", "msr fpcr, x10", "isb"]
        + raw(0xabcd3c00, to: 0, width: 64) + ["fneg h0, h0", "fmov x0, d0", "msr fpcr, x9", "isb", "ret"])
}
for register in ["FPCR", "FPSR"] {
    let name = register.lowercased()
    add("exchange" + register, "UInt64", ["mrs x8, \(name)", "msr \(name), x0", "isb", "mov x0, x8", "ret"], argument: "UInt64")
}
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
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "FPResults",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
let types = ["UInt32": "i32", "UInt64": "i64", "Float16": "half", "Float": "float", "Double": "double"]
var symbols: [String: String] = [:]
var definitions: [String] = []
for function in functions {
    let prefix = "$s9FPResults\(function.name.count)\(function.name)"
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
        + function.code.map { line in "    " + [16, 64].reduce(line) { $0.replacingOccurrences(of: "SINK\($1)", with: "_" + symbols["sink\($1)"]!) } }
}
assembly += [".section __TEXT,__const", ".p2align 2", "L_pool16:", ".short 0x3c00", ".p2align 2", "L_pool32:", ".long 0x3f800000"]
try assembly.joined(separator: "\n").appending("\n").write(to: scratch.appendingPathComponent("case.s"), atomically: true, encoding: .utf8)
try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib", scratch.appendingPathComponent("case.s").path,
         "-o", "libFPResults.dylib"])
try JSONSerialization.data(withJSONObject: ["definitions": definitions, "symbols": symbols], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("fpresults.abi.json"))
print("Checked \(functions.count) LLVM signatures and built computed scalar FP result views")
