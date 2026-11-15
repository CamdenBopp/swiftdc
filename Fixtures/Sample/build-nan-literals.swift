import Foundation

// Author the machine shapes only after the host compiler proves their public
// Swift ABIs, including Float16's half result. No private binary is an input.
struct Format {
    let width: Int
    let swift: String
    let llvm: String
    let sign: UInt64
    let quiet: UInt64
    let signaling: UInt64
    let finite: UInt64
    var patterns: [(String, UInt64)] {
        [("quiet", quiet | 1), ("negative", sign | quiet | 1),
         ("signaling", signaling | 1), ("negativeSignaling", sign | signaling | 1),
         ("payload", quiet | 2)]
    }
}
let formats = [
    Format(width: 64, swift: "Double", llvm: "double", sign: 0x8000000000000000,
           quiet: 0x7ff8000000000000, signaling: 0x7ff0000000000000, finite: 0x4004000000000000),
    Format(width: 32, swift: "Float", llvm: "float", sign: 0x80000000,
           quiet: 0x7fc00000, signaling: 0x7f800000, finite: 0x40200000),
    Format(width: 16, swift: "Float16", llvm: "half", sign: 0x8000,
           quiet: 0x7e00, signaling: 0x7c00, finite: 0x4100),
]
struct Function {
    let name: String
    let swift: String
    let llvm: String
    let argument: Format?
    let code: ( [String: String] ) -> [String]
}
func materialize(_ bits: UInt64, width: Int) -> [String] {
    let register = width == 64 ? "x8" : "w8"
    var result = ["mov \(register), #\(bits & 0xffff)"]
    for shift in stride(from: 16, to: width, by: 16) {
        let word = (bits >> shift) & 0xffff
        if word != 0 { result.append("movk \(register), #\(word), lsl #\(shift)") }
    }
    result.append("fmov \(width == 64 ? "d0" : width == 32 ? "s0" : "h0"), \(register)")
    return result
}
var functions: [Function] = []
for format in formats {
    for (kind, bits) in format.patterns + [("finite", format.finite)] {
        functions.append(Function(name: kind + String(format.width), swift: format.swift,
            llvm: format.llvm, argument: nil, code: { _ in materialize(bits, width: format.width) + ["ret"] }))
    }
    functions.append(Function(name: "neg\(format.width)",
        swift: format.width == 16 ? "Float16" : "UInt\(format.width)",
        llvm: format.width == 16 ? "half" : "i\(format.width)", argument: nil, code: { _ in
            let register = format.width == 64 ? "d0" : format.width == 32 ? "s0" : "h0"
            var body = materialize(format.quiet | 1, width: format.width) + ["fneg \(register), \(register)"]
            if format.width != 16 { body.append("fmov \(format.width == 64 ? "x0" : "w0"), \(register)") }
            return body + ["ret"]
        }))
    guard format.width != 16 else { continue }
    functions.append(Function(name: "consume\(format.width)", swift: "UInt\(format.width)",
        llvm: "i\(format.width)", argument: format, code: { _ in
            ["fmov \(format.width == 64 ? "x0, d0" : "w0, s0")", "ret"]
        }))
    for (kind, bits) in [("call", format.sign | format.signaling | 1), ("finiteCall", format.finite)] {
        functions.append(Function(name: kind + String(format.width), swift: "UInt\(format.width)",
            llvm: "i\(format.width)", argument: nil, code: { symbols in
                ["stp x29, x30, [sp, #-16]!", "mov x29, sp"]
                + materialize(bits, width: format.width)
                + ["bl _\(symbols["consume\(format.width)"]!)", "ldp x29, x30, [sp], #16", "ret"]
            }))
    }
}
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("nan-abi-\(UUID().uuidString)")
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
let source = functions.map { function in
    "public func \(function.name)(\(function.argument.map { "_ value: \($0.swift)" } ?? "")) -> \(function.swift) { 0 }"
}.joined(separator: "\n")
try source.write(to: scratch.appendingPathComponent("abi.swift"), atomically: true, encoding: .utf8)
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "NaNBits",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
var symbols: [String: String] = [:]
var definitions: [String] = []
for function in functions {
    let prefix = "$s7NaNBits\(function.name.count)\(function.name)"
    let matches = ir.split(separator: "\n").filter { $0.hasPrefix("define ") && $0.contains("@\"" + prefix) }
    precondition(matches.count == 1, "Missing/ambiguous ABI: " + function.name)
    let line = String(matches[0])
    let start = line.range(of: "@\"")!.upperBound
    let end = line[start...].firstIndex(of: "\"")!
    let symbol = String(line[start..<end])
    let declaration = line[..<start].replacingOccurrences(of: "noundef ", with: "")
    precondition(declaration.contains("swiftcc " + function.llvm + " @\""), "Wrong result ABI: " + line)
    let parameters = line[line.index(after: end)...]
    if let argument = function.argument {
        precondition(parameters.hasPrefix("(\(argument.llvm) ") && !parameters.contains(","), "Wrong argument ABI: " + line)
    } else {
        precondition(parameters.hasPrefix("()"), "Unexpected hidden arguments: " + line)
    }
    symbols[function.name] = symbol
    definitions.append(line)
}
var assembly = ["// Authored NaN payload/sign/signaling fixtures; ABI checked against emitted LLVM.", ".text", "nop"]
for function in functions {
    let symbol = symbols[function.name]!
    assembly += [".p2align 2", ".globl _\(symbol)", "_\(symbol):"]
    assembly += function.code(symbols).map { "    " + $0 }
}
try assembly.joined(separator: "\n").appending("\n").write(to: scratch.appendingPathComponent("nan.s"), atomically: true, encoding: .utf8)
try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib",
         scratch.appendingPathComponent("nan.s").path, "-o", "libNaNLiterals.dylib"])
try JSONSerialization.data(withJSONObject: ["definitions": definitions], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("nanliterals.abi.json"))
print("Checked \(functions.count) LLVM signatures and built libNaNLiterals.dylib")
