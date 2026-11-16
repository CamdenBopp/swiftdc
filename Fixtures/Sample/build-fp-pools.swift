import Foundation

// Prove public Swift signatures, then assemble authored scalar loads. The
// linker may merge literals into __const: main ends in a half and edge ends
// in a single, so both narrow reads must work at the actual section boundary.
struct Format {
    let width: Int
    let swift: String
    let llvm: String
    let result: String
    let resultIR: String
    let finite: UInt64
    let nan: UInt64
    let last: UInt64
    var register: String { width == 64 ? "d0" : width == 32 ? "s0" : "h0" }
    var directive: String { width == 64 ? ".quad" : width == 32 ? ".long" : ".short" }
    var section: String { width == 64 ? "__literal8,8byte_literals" : width == 32 ? "__literal4,4byte_literals" : "__const" }
}
let formats = [
    Format(width: 64, swift: "Double", llvm: "double", result: "UInt64", resultIR: "i64",
           finite: 0x4004000000000000, nan: 0x7ff8000000000001, last: 0xfff8000000000002),
    Format(width: 32, swift: "Float", llvm: "float", result: "UInt32", resultIR: "i32",
           finite: 0x3dcccccd, nan: 0x7fc00001, last: 0xffc00002),
    Format(width: 16, swift: "Float16", llvm: "half", result: "Float16", resultIR: "half",
           finite: 0x2e66, nan: 0x7e01, last: 0xfe02),
]
struct Function {
    let name: String
    let swift: String
    let llvm: String
    let edge: Bool
    let code: [String]
}
func load(_ format: Format, _ label: String, gpr: Bool = false) -> [String] {
    ["adrp x8, \(label)@PAGE", "ldr \(gpr ? "w9" : format.register), [x8, \(label)@PAGEOFF]"]
}
func negate(_ format: Format) -> [String] {
    ["fneg \(format.register), \(format.register)"]
        + (format.width == 16 ? [] : ["fmov \(format.width == 64 ? "x0" : "w0"), \(format.register)"])
}
var functions: [Function] = []
for f in formats {
    for (name, literal) in [("negative", "finite"), ("nan", "nan")] {
        functions.append(Function(name: name + String(f.width), swift: f.result, llvm: f.resultIR,
            edge: false, code: load(f, "L_\(literal)\(f.width)") + negate(f) + ["ret"]))
    }
    functions.append(Function(name: "add\(f.width)", swift: f.swift, llvm: f.llvm, edge: false,
        code: load(f, "L_finite\(f.width)") + ["fadd \(f.register), \(f.register), \(f.register)", "ret"]))
    functions.append(Function(name: "convert\(f.width)", swift: f.width == 32 ? "Double" : "Float",
        llvm: f.width == 32 ? "double" : "float", edge: false,
        code: load(f, "L_finite\(f.width)") + ["fcvt \(f.width == 32 ? "d0" : "s0"), \(f.register)", "ret"]))
    functions.append(Function(name: "last\(f.width)", swift: f.swift, llvm: f.llvm, edge: false,
        code: load(f, "L_last\(f.width)") + ["ret"]))
    functions.append(Function(name: "mutable\(f.width)", swift: f.swift, llvm: f.llvm, edge: false,
        code: load(f, "_fpPoolMutable\(f.width)") + ["fneg \(f.register), \(f.register)", "ret"]))
    functions.append(Function(name: "edge\(f.width)", swift: f.swift, llvm: f.llvm, edge: true,
        code: load(f, "L_edge\(f.width)") + ["ret"]))
}
let single = formats[1]
functions.append(Function(name: "gpr32", swift: "Float", llvm: "float", edge: false,
    code: load(single, "L_last32", gpr: true) + ["fmov s0, w9", "ret"]))
functions.append(Function(name: "raw32", swift: "UInt32", llvm: "i32", edge: false,
    code: load(single, "L_last32", gpr: true) + ["mov w0, w9", "ret"]))
functions.append(Function(name: "edgeGPR32", swift: "Float", llvm: "float", edge: true,
    code: load(single, "L_edge32", gpr: true) + ["fmov s0, w9", "ret"]))
// LDR S0 zeroes the high half of D0. Returning D0 must reinterpret the raw
// low word as Double bits, rather than treating it as a semantic Float.
functions.append(Function(name: "edgeView64", swift: "Double", llvm: "double", edge: true,
    code: load(single, "L_edge32") + ["ret"]))

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("pool-abi-\(UUID().uuidString)")
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
let source = functions.map { "public func \($0.name)() -> \($0.swift) { 0 }" }.joined(separator: "\n")
try source.write(to: scratch.appendingPathComponent("abi.swift"), atomically: true, encoding: .utf8)
try run(["swiftc", "-parse-as-library", "-O", "-emit-ir", "-module-name", "FPPools",
         scratch.appendingPathComponent("abi.swift").path, "-o", scratch.appendingPathComponent("abi.ll").path])
let ir = try String(contentsOf: scratch.appendingPathComponent("abi.ll"), encoding: .utf8)
var definitions: [String] = []
var symbols: [String: String] = [:]
for f in functions {
    let prefix = "$s7FPPools\(f.name.count)\(f.name)"
    let matches = ir.split(separator: "\n").filter { $0.hasPrefix("define ") && $0.contains("@\"" + prefix) }
    precondition(matches.count == 1, "Missing/ambiguous ABI: " + f.name)
    let line = String(matches[0])
    let start = line.range(of: "@\"")!.upperBound
    let end = line[start...].firstIndex(of: "\"")!
    precondition(line[..<start].replacingOccurrences(of: "noundef ", with: "").contains("swiftcc \(f.llvm) @\""))
    precondition(line[line.index(after: end)...].hasPrefix("()"), "Unexpected hidden arguments: " + line)
    symbols[f.name] = String(line[start..<end])
    definitions.append(line)
}
for edge in [false, true] {
    var assembly = [".text", "nop"]
    for f in functions where f.edge == edge {
        assembly += [".p2align 2", ".globl _\(symbols[f.name]!)", "_\(symbols[f.name]!):"] + f.code.map { "    " + $0 }
    }
    for f in edge ? [formats[0], formats[2], formats[1]] : formats {
        assembly += [".section __TEXT,\(f.section)", ".p2align \(f.width == 64 ? 3 : f.width == 32 ? 2 : 1)"]
        for (name, bits) in edge ? [("edge", f.last)] : [("finite", f.finite), ("nan", f.nan), ("last", f.last)] {
            assembly += ["L_\(name)\(f.width):", "    \(f.directive) 0x\(String(bits, radix: 16))"]
        }
    }
    if !edge {
        assembly += [".text", ".p2align 2", ".globl _fpPoolTarget", "_fpPoolTarget:", "    ret",
                     ".section __DATA_CONST,__const", ".p2align 3", ".globl _fpPoolRebase", "_fpPoolRebase:", "    .quad _fpPoolTarget",
                     ".globl _fpPoolBind", "_fpPoolBind:", "    .quad _puts", ".data"]
        for f in formats {
            assembly += [".p2align \(f.width == 64 ? 3 : f.width == 32 ? 2 : 1)", ".globl _fpPoolMutable\(f.width)",
                         "_fpPoolMutable\(f.width):", "    \(f.directive) 0x\(String(f.finite, radix: 16))"]
        }
    }
    let path = scratch.appendingPathComponent(edge ? "edge.s" : "pools.s")
    try assembly.joined(separator: "\n").appending("\n").write(to: path, atomically: true, encoding: .utf8)
    try run(["clang", "-arch", "arm64", "-march=armv8.2-a+fp16", "-dynamiclib", path.path,
             "-o", edge ? "libFPPoolEdges.dylib" : "libFPPools.dylib"])
}
try JSONSerialization.data(withJSONObject: ["definitions": definitions], options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("fppools.abi.json"))
print("Checked \(functions.count) LLVM signatures and built scalar pool/edge fixtures")
