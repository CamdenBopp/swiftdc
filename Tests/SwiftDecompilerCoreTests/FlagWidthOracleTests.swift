import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Inputs that make a 32-bit flag condition differ from its 64-bit reading:
/// the sign bit set, a high word set, and the equality cases random inputs
/// rarely reach, where `a` is exactly what the second operand becomes.
private func boundaryInputs() -> [(UInt64, UInt64)] {
    let edges: [UInt64] = [0, 1, 0x7fff_ffff, 0x8000_0000, 0xffff_ffff, 0x1_0000_0001,
                           0x8000_0000_0000_0000, .max]
    var inputs = edges.flatMap { a in edges.map { (a, $0) } }
    inputs += [(0, 0x1000_0000), (0xffff_ffdd, 0xe90), (0xffff_ffff, 0xff)]
    func sign(_ value: UInt64, _ bits: UInt64) -> UInt64 {
        UInt64(bitPattern: Int64(bitPattern: value << (64 - bits)) >> Int64(64 - bits))
    }
    for b in edges + [0x80, 0xff, 0x8000, 0x1000_0000] {
        let word = b & 0xffff_ffff
        let formed = [word, word << 4, word << 28, word >> 3, sign(word, 32) >> 3, sign(b, 8), sign(b, 16),
                      b & 0xff, b & 0xffff, sign(b, 8) << 2, b << 4, b << 28, b >> 3]
        for value in formed {
            // `a` equal to the operand, and equal to its negation for a sum;
            // a junk high word leaves a 32-bit condition unmoved.
            for a in [value, 0 &- value] {
                inputs.append((a, b))
                inputs.append(((a & 0xffff_ffff) | 0xabcd_0000_0000_0000, b))
            }
        }
    }
    var seen = Set<[UInt64]>()
    return inputs.filter { seen.insert([$0.0, $0.1]).inserted }
}

/// Every symbol is `<prefix>_<n>_<code>_<setter>_<consumer>`. A `cset`
/// function returns the condition, and a `b` function returns 1 when its
/// branch is taken. The tracer's value for each is evaluated and must equal
/// the native result on every input, or the probe must be one `declines`
/// allows. Reports claimed probes, allowed declines and native comparisons.
private func checkAgainstNative(path: String, prefix: String, expected: Int,
                                declines: (_ code: String, _ setter: String) -> Bool) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: prefix + "_")
    }
    try #require(functions.count == expected)
    let inputs = boundaryInputs()
    var wrong: [String] = []
    var declined: [String] = []
    var allowedDeclines = 0
    var claimed = 0
    var comparisons = 0
    for function in functions {
        let symbol = String(function.symbol.dropFirst())
        let parts = symbol.split(separator: "_").map(String.init)
        try #require(parts.count == 5, "\(symbol)")
        let native = unsafeBitCast(try #require(dlsym(library, symbol)), to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let value: AbstractValue?
        if parts[4] == "b" {
            let branch = try #require(function.instructions.first { $0.controlFlow == .conditionalBranch })
            value = analysis.branchConditions[branch.address]
        } else {
            value = analysis.exitValues[try #require(function.instructions.last).address]
        }
        guard let value, value != .unknown else {
            if declines(parts[2], parts[3]) { allowedDeclines += 1 }
            else { declined.append(symbol) }
            continue
        }
        claimed += 1
        let probe = ProbeValue.abstractValue(value)
        for (a, b) in inputs {
            let predicted = try probe.evaluateInteger(arguments: [a, b])
            let actual = native(a, b)
            comparisons += 1
            if predicted != actual {
                wrong.append("\(symbol)(\(String(a, radix: 16)), \(String(b, radix: 16))): read \(predicted), native \(actual)")
                break
            }
        }
    }
    print("flag-width-oracle \(prefix): functions=\(functions.count) inputs=\(inputs.count) claimed=\(claimed) allowed-declines=\(allowedDeclines) unexpected-declines=\(declined.count) comparisons=\(comparisons) wrong=\(wrong.count)")
    #expect(wrong.isEmpty, "\(wrong.count) wrong:\n\(wrong.prefix(12).joined(separator: "\n"))")
    #expect(declined.isEmpty, "\(declined.count) declined:\n\(declined.prefix(12).joined(separator: "\n"))")
}

/// A 32-bit compare reads only the word of its shifted or extended second
/// operand. `source` keeps those wider than the word, and every condition but
/// a signed order compared them uncut: `cmp w0, w1, lsl #4; cset eq` of 0 and
/// 0x10000000 read `0 == 0x100000000`, false, where the word is 0 and the
/// compare is equal. flagwidth.s probes the compares and sums, at both widths,
/// with each form of second operand, under every condition code.
@Test func compareConditionsAgreeWithNativeAtBothWidthsIfPresent() async throws {
    // The overflow of a difference is not modelled outside a conditional
    // compare, and a shifted sum's overflow runs past the expression depth limit.
    try await checkAgainstNative(path: "Fixtures/Sample/libFlagWidthProbes.dylib", prefix: "fw", expected: 1680) { code, setter in
        ["cmp", "subs"].contains(setter) ? ["vs", "vc"].contains(code)
            : ["vs", "vc", "ge", "lt", "gt", "le"].contains(code)
    }
}
