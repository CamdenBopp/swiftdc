import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `emu-oracle` (emuoracle.c) runs code from a fixture image under an
/// emulator and reports what the machine did: how the run ended, the
/// registers at the end, each conditional branch's outcome, each call out
/// of the image. It shares nothing with swiftdc. These tests hold the
/// tracer's claims to it: a branch condition evaluated on the inputs must
/// be the branch the machine took, and an exit value must be what was in
/// x0, for every function of an image and a set of inputs, stripped
/// bodies, traps and loops included.
private let fixtures = "Fixtures/Sample"

struct EmulatedRun {
    let outcome: String
    /// The last instruction run inside the image: the `ret` of a run that returned.
    let last: UInt64
    let x: [UInt64]
    /// Each conditional branch run, in order, and whether it was taken.
    let branches: [(pc: UInt64, taken: Bool)]
    /// The site of each call out of the image.
    let externalCalls: [UInt64]
}

/// One emulator process per image, one request per run.
final class EmulatorOracle {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffered = Data()

    /// Nil when the oracle is not built (Unicorn is not installed).
    init?(image: String) throws {
        let oracle = "Fixtures/Sample/emu-oracle"
        guard FileManager.default.fileExists(atPath: oracle) else { return nil }
        process.executableURL = URL(fileURLWithPath: oracle)
        process.arguments = ["\(fixtures)/\(image)"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    deinit {
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func line() throws -> String {
        while true {
            if let newline = buffered.firstIndex(of: 0x0a) {
                let text = String(decoding: buffered[buffered.startIndex..<newline], as: UTF8.self)
                buffered.removeSubrange(buffered.startIndex...newline)
                return text
            }
            let more = output.fileHandleForReading.availableData
            guard !more.isEmpty else { throw EmulatorError.closed }
            buffered.append(more)
        }
    }

    enum EmulatorError: Error { case closed, malformed(String) }

    func run(at start: UInt64, registers: [Int: UInt64] = [:], limit: Int = 20000) throws -> EmulatedRun {
        var request = "run 0x\(String(start, radix: 16)) limit=\(limit)"
        for (register, value) in registers.sorted(by: { $0.key < $1.key }) {
            request += " x\(register)=0x\(String(value, radix: 16))"
        }
        try input.fileHandleForWriting.write(contentsOf: Data((request + "\n").utf8))
        let reply = try line()
        let parts = reply.split(separator: " ").map(String.init)
        guard parts.count >= 3, parts[0] == "OUT" else { throw EmulatorError.malformed(reply) }
        var fields: [String: String] = [:]
        for part in parts.dropFirst(2) {
            guard let equals = part.firstIndex(of: "=") else { continue }
            fields[String(part[..<equals])] = String(part[part.index(after: equals)...])
        }
        func hex(_ text: String?) -> UInt64? { text.flatMap { UInt64($0.dropFirst(2), radix: 16) } }
        guard let last = hex(fields["last"]) else { throw EmulatorError.malformed(reply) }
        let x = try (0...28).map { index -> UInt64 in
            guard let value = hex(fields["x\(index)"]) else { throw EmulatorError.malformed(reply) }
            return value
        }
        let branches = try (fields["branches"] ?? "").split(separator: ",").map { item -> (pc: UInt64, taken: Bool) in
            let sides = item.split(separator: ":")
            guard sides.count == 2, let pc = hex(String(sides[0])) else { throw EmulatorError.malformed(reply) }
            return (pc, sides[1] == "t")
        }
        let calls = (fields["calls"] ?? "").split(separator: ",").compactMap { hex(String($0.prefix { $0 != ">" })) }
        return EmulatedRun(outcome: parts[1], last: last, x: x, branches: branches, externalCalls: calls)
    }
}

/// Inputs that separate signed from unsigned, word from doubleword, zero
/// from non-zero, and one argument from the next.
private let inputVectors: [[UInt64]] = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [1, 2, 3, 4, 5, 6, 7, 8],
    [9, 7, 5, 3, 1, 2, 4, 6],
    [.max, .max, .max, .max, .max, .max, .max, .max],
    [0x8000_0000, 0x7fff_ffff, 0xffff_ffff, 0x1_0000_0000, 3, 100, 0x80, 0xff],
    [0x8000_0000_0000_0000, 0x7fff_ffff_ffff_ffff, 1, .max, 0, 10, 0xffff, 64],
    [5, 5, 5, 5, 5, 5, 5, 5],
    [100, 7, 3, 2, 255, 256, 65535, 65536],
]

struct EmulatorSweep {
    var functions = 0, runs = 0
    var returnsChecked = 0, conditionsChecked = 0
    /// `image symbol`: what was stated and what the machine did.
    var mismatches: [String: [String]] = [:]
}

/// What the whole pipeline states about `image`, against the emulator.
///
/// Two kinds of statement are checked, both from an ordinary run:
/// - a recovered return (`render.return-value`, the probe's claim): its
///   value, evaluated on the inputs, must be x0 when the run returned
///   through that `ret`;
/// - a branch rendered as a constant (`cond: 1`, `cond: 0`): the machine
///   must take it, or not, on every run that reaches it.
/// The inputs go where the function's own entry convention seeds its
/// arguments (`analysis.entry`), so `arg0` is whatever swiftdc says it is.
/// A rendered integer: `7`, `-1`, `0x2a`. Nil for anything else.
private func integerLiteral(_ text: String) -> UInt64? {
    if text.hasPrefix("0x") { return UInt64(text.dropFirst(2), radix: 16) }
    if let signed = Int64(text) { return UInt64(bitPattern: signed) }
    return UInt64(text)
}

func sweepAgainstEmulator(_ image: String) async throws -> EmulatorSweep? {
    guard FileManager.default.fileExists(atPath: "\(fixtures)/\(image)"),
          let emulator = try EmulatorOracle(image: image) else { return nil }
    let recorder = ProbeRecorder()
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) {
            try await Disassembler(preset: .default).disassemble(path: "\(fixtures)/\(image)")
        }
    }
    var seeds: [UInt64: [(register: Int, value: ProbeValue)]] = [:]
    var returns: [UInt64: ProbeValue] = [:]
    for record in recorder.records {
        if record.event.id == "analysis.entry", let start = record.address,
           case .object(let registers)? = record["seeds"] {
            seeds[start] = registers.compactMap { name, value in
                guard name.hasPrefix("x"), let register = Int(name.dropFirst()), register <= 28 else { return nil }
                return (register, value)
            }
        } else if record.event.id == "render.return-value", let address = record.address,
                  record["register"] == .label("x0"), let value = record["value"] {
            returns[address] = value
        }
    }
    var sweep = EmulatorSweep()
    for function in functions where !function.instructions.isEmpty && function.instructions.count <= 2000 {
        let own = Set(function.instructions.map(\.address))
        let constants: [UInt64: Bool] = Dictionary(uniqueKeysWithValues: function.instructions.compactMap { insn in
            guard insn.controlFlow == .conditionalBranch, let condition = insn.facts.condition else { return nil }
            if ["1", "true"].contains(condition) { return (insn.address, true) }
            if ["0", "false"].contains(condition) { return (insn.address, false) }
            return nil
        })
        let stated = returns.filter { own.contains($0.key) }
        // `return // x0 = 7`: what x0 holds at a `ret` of a function nothing
        // proves returns a value. It has no claim record, so read the fact.
        let held: [UInt64: UInt64] = Dictionary(uniqueKeysWithValues: function.instructions.compactMap { insn in
            guard case .unprovenResult(let text)? = insn.facts.exit, let value = integerLiteral(text) else { return nil }
            return (insn.address, value)
        })
        guard !stated.isEmpty || !constants.isEmpty || !held.isEmpty else { continue }
        sweep.functions += 1
        let key = "\(image) \(function.symbol)"
        // Each vector runs twice: the registers nothing seeds are all
        // distinct, then all zero. A function that hands an unseeded
        // register on as a pointer faults under the first and runs under
        // the second.
        let entrySeeds = seeds[function.startAddress] ?? []
        let probe: [UInt64] = (0..<8).map { 0x1000 + UInt64($0) }
        let carried = Set(probe.indices.filter { index in
            var moved = probe
            moved[index] ^= 0x1357_9bdf
            return entrySeeds.contains {
                (try? $0.value.evaluateInteger(arguments: probe)) != (try? $0.value.evaluateInteger(arguments: moved))
            }
        })
        for inputs in inputVectors { for distinct in [true, false] {
            var registers = Dictionary(uniqueKeysWithValues: (0...18).map { ($0, distinct ? 0x5a5a_0000 + UInt64($0) * 0x101 : 0) })
            for seed in entrySeeds {
                if let value = try? seed.value.evaluateInteger(arguments: inputs) { registers[seed.register] = value }
            }
            let run = try emulator.run(at: function.startAddress, registers: registers)
            sweep.runs += 1
            // After a call out of the image the emulator's registers are
            // not the machine's: nothing later in the run is evidence.
            guard run.externalCalls.isEmpty else { continue }
            let counts = Dictionary(run.branches.map { ($0.pc, 1) }, uniquingKeysWith: +)
            for branch in run.branches where counts[branch.pc] == 1 {
                guard let constant = constants[branch.pc] else { continue }
                sweep.conditionsChecked += 1
                if constant != branch.taken {
                    sweep.mismatches[key, default: []].append(
                        "branch @0x\(String(branch.pc, radix: 16)) rendered \(constant ? 1 : 0), machine \(branch.taken ? "took it" : "did not")")
                }
            }
            guard run.outcome == "returned" else { continue }
            if let value = held[run.last] {
                sweep.returnsChecked += 1
                if value != run.x[0] {
                    sweep.mismatches[key, default: []].append(
                        "x0 @0x\(String(run.last, radix: 16)) stated 0x\(String(value, radix: 16)), machine 0x\(String(run.x[0], radix: 16))")
                }
            }
            // An argument no register carries is on the stack, which a run
            // does not seed: a claim that moves with one is not checked.
            var unseeded = inputs
            for index in inputs.indices where !carried.contains(index) { unseeded[index] ^= 0x1357_9bdf }
            guard let claim = stated[run.last],
                  let value = try? claim.evaluateInteger(arguments: inputs),
                  (try? claim.evaluateInteger(arguments: unseeded)) == value
            else { continue }
            sweep.returnsChecked += 1
            if value != run.x[0] {
                sweep.mismatches[key, default: []].append(
                    "return @0x\(String(run.last, radix: 16)) stated 0x\(String(value, radix: 16)), machine 0x\(String(run.x[0], radix: 16))")
            }
        } }
    }
    return sweep
}

/// The images swept on every run. `SWIFTDC_EMU_IMAGES` replaces the list
/// (comma-separated, or `all` for every dylib in the fixtures) to explore.
private let sweptImages = [
    "libInt64Fields.dylib", "libInt64Fields.onone.dylib", "libOptionSubset.dylib",
    "libTrapTail.dylib", "libTrapTail.stripped.dylib", "libErrorLookalike.dylib", "libHookPath.dylib",
    "libSelectorStubShape.dylib", "libDeferThrow.dylib", "libAccessTwin.dylib",
    "libAsyncMemoryEffects.dylib", "libCallerFrameAlias.dylib", "libCallerFrameAlias.opt.dylib",
    "libCallerFrameAlias.size.dylib", "libSample.stripped.dylib", "libObjCPackedStack.opt.dylib",
    "libSwiftArgumentBoundary.O.dylib", "libReconstruction.opt.dylib", "libSwiftTailResults.O.dylib",
]

/// Statements the sweep shows to be false today, each an open soundness
/// defect recorded in PRODUCTION-READINESS.md. The test fails if one of
/// them stops disagreeing, so a fix has to remove its line.
private let knownFalseStatements: Set<String> = [
    // `return // x0 = 7` after a fragment whose `st4` writes 64 bytes
    // across the caller's frame: the machine returns 0x4444444444444444.
    "libAsyncMemoryEffects.dylib _async_memory_st4",
    // `if (1)` on a slot the callee rewrote through a pointer made from
    // its entry stack pointer: the machine reads 99 and does not branch.
    "libCallerFrameAlias.dylib _entry_pointer_copy_probe",
    "libCallerFrameAlias.opt.dylib _entry_pointer_copy_probe",
    "libCallerFrameAlias.size.dylib _entry_pointer_copy_probe",
]

@Test func pipelineStatementsAgreeWithTheEmulatorIfPresent() async throws {
    var images = sweptImages
    let exploring = ProcessInfo.processInfo.environment["SWIFTDC_EMU_IMAGES"]
    if let exploring {
        images = exploring == "all"
            ? try FileManager.default.contentsOfDirectory(atPath: fixtures).filter { $0.hasSuffix(".dylib") }.sorted()
            : exploring.split(separator: ",").map(String.init)
    }
    var total = EmulatorSweep()
    for image in images {
        guard let sweep = try await sweepAgainstEmulator(image) else { continue }
        print("emulator-sweep \(image): functions=\(sweep.functions) runs=\(sweep.runs) returns=\(sweep.returnsChecked) conditions=\(sweep.conditionsChecked) mismatched-functions=\(sweep.mismatches.count)")
        for (key, lines) in sweep.mismatches.sorted(by: { $0.key < $1.key }) {
            print("emulator-mismatch \(key): \(Set(lines).sorted().prefix(3).joined(separator: "; "))")
        }
        total.functions += sweep.functions; total.runs += sweep.runs
        total.returnsChecked += sweep.returnsChecked; total.conditionsChecked += sweep.conditionsChecked
        total.mismatches.merge(sweep.mismatches) { $0 + $1 }
    }
    guard total.runs > 0 else { return }
    let unexpected = total.mismatches.keys.filter { !knownFalseStatements.contains($0) }.sorted()
    #expect(unexpected.isEmpty, "false statements:\n\(unexpected.map { "\($0): \(total.mismatches[$0]!.first!)" }.joined(separator: "\n"))")
    guard exploring == nil else { return }
    let fixed = knownFalseStatements.filter { total.mismatches[$0] == nil }.sorted()
    #expect(fixed.isEmpty, "no longer false, remove from knownFalseStatements: \(fixed)")
    // Not vacuous: the default list states and checks real claims.
    #expect(total.returnsChecked >= 1000, "checked \(total.returnsChecked) returns")
    #expect(total.conditionsChecked >= 150, "checked \(total.conditionsChecked) constant conditions")
}

/// The emulator against the native oracle, where both can answer: the
/// same image, the same inputs, the same outcome.
@Test func theEmulatorAgreesWithNativeExecutionIfPresent() async throws {
    let native = "\(fixtures)/sprint-native-oracle"
    guard FileManager.default.fileExists(atPath: native), FileManager.default.fileExists(atPath: "\(fixtures)/emu-oracle")
    else { return }
    func start(_ image: String, _ symbol: String) async throws -> UInt64 {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: "\(fixtures)/\(image)")
        }
        return try #require(functions.first { $0.symbol == symbol }, "\(symbol)").startAddress
    }
    // (image, symbol, x0…, native outcome, native x0 when it returned)
    let cases: [(String, String, [UInt64], String, UInt64?)] = [
        ("libTrapTail.stripped.dylib", "_$s8TrapTail11wrapNonZeroyS2iF", [5], "returned", 5),
        ("libTrapTail.stripped.dylib", "_$s8TrapTail11wrapNonZeroyS2iF", [0], "trapped", nil),
        ("libTrapTail.stripped.dylib", "_$s8TrapTail14wrapAboveThreeyS2i_SitF", [5, 2], "trapped", nil),
        ("libTrapTail.stripped.dylib", "_$s8TrapTail14wrapUnlessNineyS2iF", [9], "hung", nil),
        ("libTrapTail.stripped.dylib", "_$s8TrapTail8wrapSameyS2iF", [5], "returned", 5),
        ("libInt64Fields.dylib", "_$s11Int64Fields11wideCombineys6UInt64VAA4WideV_ADtF", [100, 7, 3], "returned", 79),
        ("libOptionSubset.dylib", "_$s12OptionSubset6allowsySbAA6AccessV_ADtF", [7, 5], "returned", 1),
        ("libOptionSubset.dylib", "_$s12OptionSubset6allowsySbAA6AccessV_ADtF", [5, 7], "returned", 0),
        ("libErrorLookalike.dylib", "_$s9Lookalike11viaAllocLogyS2iKF", [1], "returned", 5),
        ("libErrorLookalike.dylib", "_$s9Lookalike15viaWillThrowLogyS2iKF", [1], "returned", 6),
        ("libHookPath.dylib", "_$s8HookPath6eitherySiSb_SitKF", [0, 0], "returned", 7),
        // Not libSelectorStubShape: its hand-made stub sits in __objc_stubs,
        // which the emulator takes for a call out of the image.
    ]
    var emulators: [String: EmulatorOracle] = [:]
    for (image, symbol, inputs, outcome, result) in cases {
        if emulators[image] == nil { emulators[image] = try EmulatorOracle(image: image) }
        let emulator = try #require(emulators[image])
        let registers = Dictionary(uniqueKeysWithValues: inputs.enumerated().map { ($0.offset, $0.element) })
        let run = try emulator.run(at: try await start(image, symbol), registers: registers)
        #expect(run.outcome == outcome, "\(symbol) \(inputs): emulator \(run.outcome), native \(outcome)")
        if let result { #expect(run.x[0] & 0xff == result & 0xff && (result > 1 ? run.x[0] == result : true), "\(symbol) \(inputs): x0 \(run.x[0])") }
    }
    // The error register, which the native driver reads through its
    // trampoline: the arm without the hook leaves its argument in x21.
    let hook = try #require(try EmulatorOracle(image: "libHookPath.dylib"))
    let either = try await start("libHookPath.dylib", "_$s8HookPath6eitherySiSb_SitKF")
    #expect(try hook.run(at: either, registers: [0: 0, 1: 9]).x[21] == 9)
    #expect(try hook.run(at: either, registers: [0: 0, 1: 0]).x[21] == 0)
}
