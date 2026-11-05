import Ccapstone
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
    var wrongBySetter: [String: Int] = [:]
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
            let branch = try #require(function.instructions.last { $0.controlFlow == .conditionalBranch })
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
                wrongBySetter[parts[3], default: 0] += 1
                wrong.append("\(symbol)(\(String(a, radix: 16)), \(String(b, radix: 16))): read \(predicted), native \(actual)")
                break
            }
        }
    }
    print("flag-width-oracle \(prefix): functions=\(functions.count) inputs=\(inputs.count) claimed=\(claimed) allowed-declines=\(allowedDeclines) unexpected-declines=\(declined.count) comparisons=\(comparisons) wrong=\(wrong.count)")
    if !wrongBySetter.isEmpty {
        let groups = wrongBySetter.keys.sorted().map { "\($0)=\(wrongBySetter[$0]!)" }.joined(separator: " ")
        print("flag-width-wrong-by-setter \(prefix): \(groups)")
    }
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

/// `tst` and `ands` set N and Z from the result and clear C and V. Read as a
/// comparison of a zero-extended word with 0, `tst w1, w0; cinc ge` was a test
/// that cannot vary, and `tst x0, x1; b.hs`, never taken, read `>=ᵁ 0`, always
/// true. A difference or a sum tested on its own read as the compare or the
/// add it folded to, with their carry and overflow.
@Test func testConditionsAgreeWithNativeAtBothWidthsIfPresent() async throws {
    try await checkAgainstNative(path: "Fixtures/Sample/libFlagWidthProbes.dylib", prefix: "ft", expected: 812) { _, _ in false }
}


/// A join can select both the NZCV producer and its width. Query each arm's
/// actual flags; treating the selected arithmetic result as a test invents
/// C/V, and treating a selected width as 64 misreads bit31 and word carry.
@Test func selectedFlagConditionsAgreeWithNativeIfPresent() async throws {
    try await checkAgainstNative(path: "Fixtures/Sample/libFlagWidthProbes.dylib", prefix: "fm", expected: 841) { code, setter in
        // Ordinary symbolic CMP still declines overflow outside CCMP.
        (["symcmpw", "symcmpx"].contains(setter) && ["vs", "vc"].contains(code))
            || setter == "independent"
    }
}

/// A bounded flag query must decline instead of retaining an unfinished
/// projection. Traversal depth, result-arm depth and predicate depth have
/// independent controls; the retained-state graph can itself be deeper.
@Test func selectedFlagQueriesRetainTheirBoundsIfPresent() async throws {
    let path = "Fixtures/Sample/libFlagWidthProbes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "fb_")
    }
    try #require(functions.count == 6)
    let controls = Set(["fb_choice8", "fb_result7", "fb_predicate6"])
    for function in functions {
        let symbol = String(function.symbol.dropFirst())
        let native = unsafeBitCast(try #require(dlsym(library, symbol)), to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let value = analysis.exitValues[try #require(function.instructions.last).address]
        if controls.contains(symbol) {
            let recovered = try #require(value)
            #expect(recovered != .unknown, "\(symbol)")
            guard recovered != .unknown else { continue }
            let probe = ProbeValue.abstractValue(recovered)
            for a in [0, 1, 2, 6, 7, 8, 9, UInt64.max, UInt64.max - 1] as [UInt64] {
                #expect(try probe.evaluateInteger(arguments: [a, 0]) == native(a, 0), "\(symbol)(\(a))")
            }
        } else {
            #expect(value == nil || value == .unknown, "\(symbol) must decline the exceeded query bound")
        }
    }
}

/// Backedges are not all the incoming edges of a function entry. In
/// particular the caller's NZCV is unknown even when every backedge sets C.
@Test func selectedEntryFlagsKeepTheCallerEdgeIfPresent() async throws {
    let path = "Fixtures/Sample/libFlagWidthProbes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "fe_")
    }
    try #require(functions.count == 7)
    for kind in ["common", "different", "switch", "control"] {
        let symbol = "fe_" + kind
        let function = try #require(functions.first { $0.symbol == "_" + symbol })
        let store = try #require(function.instructions.first { $0.detail?.id == AARCH64_INS_STR })
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1, "x2": 2]))
        let write = try #require(analysis.memoryWrites[store.address])
        if kind == "control" { #expect(write.values == [.immediate(1)]) }
        else { #expect(write.values == [.unknown], "\(symbol) must retain the unknown caller flags") }
        let nativeSymbol = symbol + (kind == "control" ? "" : "_caller")
        let native = unsafeBitCast(try #require(dlsym(library, nativeSymbol)),
                                  to: (@convention(c) (UInt64, UInt64, UnsafeMutablePointer<UInt64>) -> UInt64).self)
        for selector: UInt64 in [0, 1, 2] {
            for count: UInt64 in [1, 2, 3] {
                var stored: UInt64 = 99
                let returned = native(selector, count, &stored)
                let expected: UInt64 = kind == "control" || count > 1 ? 1 : 0
                #expect(stored == expected && returned == expected, "\(nativeSymbol), selector=\(selector), count=\(count)")
            }
        }
    }
}

/// A producer selection and its width cannot be paired by arm position when
/// their predicates differ. Exercise the actual query directly: current CFG
/// ancestry can decline the independent joins before this boundary is reached.
@Test func selectedFlagQueriesPairProducerAndWidthPredicatesIfPresent() async throws {
    let path = "Fixtures/Sample/libFlagWidthProbes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "independent")
    }
    let function = try #require(functions.count == 1 ? functions.first : nil)
    let native = unsafeBitCast(try #require(dlsym(library, String(function.symbol.dropFirst()))),
                              to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
    let valueChoice = AbstractValue.binary(.equal, .argument(1), .immediate(0))
    let widthChoice = AbstractValue.binary(.equal, .argument(0), .immediate(0))
    let flags = AbstractValue.select(condition: valueChoice,
        whenTrue: .binary(.subtract, .immediate(0x8000_0000), .immediate(0)),
        whenFalse: .binary(.subtract, .immediate(0x8000_0001), .immediate(0)))
    func widths(_ condition: AbstractValue) -> AbstractValue {
        .select(condition: condition, whenTrue: .immediate(32), whenFalse: .immediate(64))
    }
    let tracer = ValueTracer()
    let unpaired = tracer.flagCondition(flags, code: AArch64CC_MI, width: widths(widthChoice))
    #expect(unpaired == nil, "independent producer/width choices must decline")
    let paired = try #require(tracer.flagCondition(flags, code: AArch64CC_MI, width: widths(valueChoice)))
    let pairedProbe = ProbeValue.abstractValue(paired)
    for a: UInt64 in [0, 1, 2] {
        for b: UInt64 in [0, 1, 2] {
            // Tie the native width selector to the value selector for the
            // positive control, then vary them independently for any claim.
            #expect(try pairedProbe.evaluateInteger(arguments: [a, b]) == native(b, b))
            if let unpaired {
                #expect(try ProbeValue.abstractValue(unpaired).evaluateInteger(arguments: [a, b]) == native(a, b))
            }
        }
    }
}

/// An opaque result has unknown N/Z, but the test producer still clears C/V.
/// Unknown Boolean data may retain known alternatives in ordinary queries;
/// it must not satisfy a conditional compare's complete-input requirement.
@Test func unknownTestFlagsRetainPartialAlternativesIfPresent() async throws {
    let path = "Fixtures/Sample/libFlagWidthProbes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "fp_")
    }
    try #require(functions.count == 11)
    func containsUnknown(_ value: AbstractValue) -> Bool {
        switch value {
        case .unknown: true
        case .binary(_, let a, let b): containsUnknown(a) || containsUnknown(b)
        case .unary(_, let a): containsUnknown(a)
        case .select(let c, let a, let b): containsUnknown(c) || containsUnknown(a) || containsUnknown(b)
        default: false
        }
    }
    func containsCallResult(_ value: AbstractValue) -> Bool {
        switch value {
        case .callResult: true
        case .binary(_, let a, let b): containsCallResult(a) || containsCallResult(b)
        case .unary(_, let a): containsCallResult(a)
        case .select(let c, let a, let b): containsCallResult(c) || containsCallResult(a) || containsCallResult(b)
        default: false
        }
    }
    for name in ["plain", "known", "symbolic", "cmp", "test", "hs", "lo", "vs", "vc"] {
        let symbol = "fp_" + name
        let function = try #require(functions.first { $0.symbol == "_" + symbol })
        let native = unsafeBitCast(try #require(dlsym(library, symbol)),
                                  to: (@convention(c) (UInt64, UInt64) -> UInt64).self)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
        let value = analysis.exitValues[try #require(function.instructions.last).address]
        let isPartial = ["plain", "cmp", "test"].contains(name)
        if isPartial {
            #expect(value != nil && value != .unknown, "\(symbol) must retain 14/16")
            if let value, value != .unknown {
                if case .select(_, .immediate(14), .immediate(16)) = value {} else {
                    #expect(Bool(false), "\(symbol) must retain both known alternatives: \(value)")
                }
                #expect(containsUnknown(value), "\(symbol) must stay partial")
            }
        } else if name == "known" || name == "symbolic" {
            #expect(value != nil && value != .unknown)
            if let value {
                #expect(!containsUnknown(value))
                if name == "symbolic" { #expect(containsCallResult(value)) }
            }
        } else {
            #expect(value == .immediate(["lo", "vc"].contains(name) ? 1 : 0), "\(symbol)")
        }
        for a: UInt64 in [0, 1] {
            for b: UInt64 in [0, 1, 255, 256, 0x8000_0000, .max] {
                let actual = native(a, b)
                let zero = name == "cmp" ? b == 0 : b & 255 == 0
                let expected: UInt64 = ["plain", "known", "symbolic", "cmp", "test"].contains(name)
                    ? (zero ? 14 : 16) : (["lo", "vc"].contains(name) ? 1 : 0)
                #expect(actual == expected, "\(symbol)(\(a), \(b))")
                if let value, name != "symbolic" && (!isPartial || (name != "plain" && a == 0)) {
                    #expect(try ProbeValue.abstractValue(value).evaluateInteger(arguments: [a, b]) == actual)
                }
            }
        }
    }
    let tracer = ValueTracer()
    let unknownTest = AbstractValue.binary(.bitAnd, .unknown, .immediate(.max))
    #expect(tracer.flagCondition(unknownTest, code: AArch64CC_EQ, width: .immediate(32)) == .unknown)
    #expect(tracer.flagCondition(unknownTest, code: AArch64CC_EQ, width: .immediate(32), requireComplete: true) == nil)
    #expect(tracer.flagCondition(unknownTest, code: AArch64CC_HS, width: .immediate(32), requireComplete: true) == .immediate(0))
    let partialFlags = AbstractValue.select(condition: .argument(0),
        whenTrue: .binary(.subtract, .argument(1), .immediate(0)),
        whenFalse: .binary(.subtract, .unknown, .immediate(0)))
    let partial = tracer.flagCondition(partialFlags, code: AArch64CC_EQ, width: .immediate(64))
    #expect(partial != nil && partial != .unknown)
    if let partial { #expect(containsUnknown(partial)) }
    #expect(tracer.flagCondition(partialFlags, code: AArch64CC_EQ, width: .immediate(64), requireComplete: true) == nil)
}

/// AL/NV hold over constant and symbolic NZCV. The EQ control still chooses
/// the second operand for CMP 1,2. All selected values are known constants;
/// the symbolic cases leave CMP's operands as independent UInt64 arguments.
@Test func theAlwaysConditionsHoldOverConstantFlags() throws {
    let engine = try #require(CapstoneEngine())
    let cases: [(compare: UInt32, select: UInt32, symbolic: Bool, expected: UInt64)] = [
        (0xeb09011f, 0x9a89e100, false, 1), // cmp x8,x9; csel ... al
        (0xeb09011f, 0x9a89f100, false, 1), // cmp x8,x9; csel ... nv
        (0xeb09011f, 0x9a890100, false, 2), // cmp x8,x9; csel ... eq
        (0xeb01001f, 0x9a89e100, true, 1),  // cmp x0,x1; csel ... al
        (0xeb01001f, 0x9a89f100, true, 1),  // cmp x0,x1; csel ... nv
    ]
    for item in cases {
        let words: [UInt32] = [0xd2800028, 0xd2800049, item.compare, item.select, 0xd65f03c0]
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        try #require(decoded.count == words.count)
        let body = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let analysis = item.symbolic
            ? ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "x1": 1]))
            : ValueTracer().analyze(function, entry: nil)
        #expect(analysis.exitValues[try #require(body.last).address] == .immediate(item.expected),
                "cmp=0x\(String(item.compare, radix: 16)) csel=0x\(String(item.select, radix: 16))")
    }
}
