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
    /// A call out was handed an address in the emulated stack, scratch
    /// buffer or writable image: the real callee could have written there.
    let handedMemory: Bool
    /// The callee-saved registers and sp a returned run left changed.
    let changedCalleeSaved: [String]
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

    func run(
        at start: UInt64, registers: [Int: UInt64] = [:], limit: Int = 20000, poison: UInt64? = nil
    ) throws -> EmulatedRun {
        var request = "run 0x\(String(start, radix: 16)) limit=\(limit)"
        if let poison { request += " poison=0x\(String(poison, radix: 16))" }
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
        let listed = (fields["calls"] ?? "").split(separator: ",")
        let calls = listed.compactMap { hex(String($0.prefix { $0 != ">" })) }
        let changed = fields["abi"].map { $0 == "ok" ? [] : $0.split(separator: ",").map(String.init) } ?? []
        return EmulatedRun(outcome: parts[1], last: last, x: x, branches: branches, externalCalls: calls,
                           handedMemory: listed.contains { $0.hasSuffix("!") }, changedCalleeSaved: changed)
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
    /// Runs that called out of the image and were still checked.
    var checkedPastCalls = 0
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
    var returns: [UInt64: (value: ProbeValue, path: ProbeValue?)] = [:]
    for record in recorder.records {
        if record.event.id == "analysis.entry", let start = record.address,
           case .object(let registers)? = record["seeds"] {
            seeds[start] = registers.compactMap { name, value in
                guard name.hasPrefix("x"), let register = Int(name.dropFirst()), register <= 28 else { return nil }
                return (register, value)
            }
        } else if record.event.id == "render.return-value", let address = record.address,
                  record["register"] == .label("x0"), let value = record["value"] {
            returns[address] = (value, record["path"])
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
            let run = try emulator.run(at: function.startAddress, registers: registers, poison: 0x5eed_0000_0000_1111)
            sweep.runs += 1
            // A call out of the image returns at once, with a pattern where
            // the callee's results would be. No branch after it is
            // evidence. The result is the machine's only if the callee was
            // handed no address it could write through, and the run ends at
            // the same place with the same x0 when the callee instead hands
            // every register back as it got it, as one returning its
            // argument does.
            let calledOut = !run.externalCalls.isEmpty
            if calledOut {
                guard !run.handedMemory else { continue }
                let handedBack = try emulator.run(at: function.startAddress, registers: registers)
                guard handedBack.outcome == run.outcome, handedBack.last == run.last, handedBack.x[0] == run.x[0]
                else { continue }
                sweep.checkedPastCalls += 1
            }
            let counts = Dictionary(run.branches.map { ($0.pc, 1) }, uniquingKeysWith: +)
            for branch in run.branches where !calledOut && counts[branch.pc] == 1 {
                guard let constant = constants[branch.pc] else { continue }
                sweep.conditionsChecked += 1
                if constant != branch.taken {
                    sweep.mismatches[key, default: []].append(
                        "branch @0x\(String(branch.pc, radix: 16)) rendered \(constant ? 1 : 0), machine \(branch.taken ? "took it" : "did not")")
                }
            }
            guard run.outcome == "returned" || run.outcome == "external" else { continue }
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
                  let value = try? claim.value.evaluateInteger(arguments: inputs),
                  (try? claim.value.evaluateInteger(arguments: unseeded)) == value
            else { continue }
            // A claim holds on the paths it names: a `ret` two paths share
            // carries the value of one of them.
            if let path = claim.path {
                guard let taken = try? path.evaluateInteger(arguments: inputs), taken != 0,
                      (try? path.evaluateInteger(arguments: unseeded)) == taken
                else { continue }
            }
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
    "libSelectorStubShape.dylib", "libDeferThrow.dylib", "libAccessTwin.dylib", "libSpillCarry.dylib",
    "libAsyncMemoryEffects.dylib", "libCallerFrameAlias.dylib", "libCallerFrameAlias.opt.dylib",
    "libCallerFrameAlias.size.dylib", "libSample.stripped.dylib", "libObjCPackedStack.opt.dylib",
    "libSwiftArgumentBoundary.O.dylib", "libReconstruction.opt.dylib", "libSwiftTailResults.O.dylib",
    "libCalleeBodyTransfer.opt.dylib", "libFrameReach.dylib",
    "libStackHole.dylib",
    "libFPBarrierPieces.dylib", "libFPBarrierPieces.onone.dylib",
    "libWillThrowTwin.dylib",
    "libErrorCarrier.O.dylib",
    "libTypedCatch.Onone.dylib", "libTypedCatch.O.dylib",
    "libEmuImage.dylib", "libFrameFactStore.dylib",
]

/// Statements the sweep shows to be false today, each an open soundness
/// defect recorded in PRODUCTION-READINESS.md. The test fails if one of
/// them stops disagreeing, so a fix has to remove its line.
private let knownFalseStatements: Set<String> = []

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
        print("emulator-sweep \(image): functions=\(sweep.functions) runs=\(sweep.runs) returns=\(sweep.returnsChecked) conditions=\(sweep.conditionsChecked) past-calls=\(sweep.checkedPastCalls) mismatched-functions=\(sweep.mismatches.count)")
        for (key, lines) in sweep.mismatches.sorted(by: { $0.key < $1.key }) {
            print("emulator-mismatch \(key): \(Set(lines).sorted().prefix(3).joined(separator: "; "))")
        }
        total.functions += sweep.functions; total.runs += sweep.runs
        total.returnsChecked += sweep.returnsChecked; total.conditionsChecked += sweep.conditionsChecked
        total.checkedPastCalls += sweep.checkedPastCalls
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

/// The emulator runs what Apple code uses: LSE atomics, pointer
/// authentication and `fjcvtzs`. Unicorn's default CPU has none of them,
/// and each would end a run like a trap. A `brk` the program wrote is
/// still a trap.
@Test func theEmulatorRunsInstructionsPastItsDefaultCPUIfPresent() async throws {
    let image = "libEmuCPU.dylib"
    guard FileManager.default.fileExists(atPath: "Fixtures/Sample/libEmuCPU.dylib"),
          let emulator = try EmulatorOracle(image: image) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: "Fixtures/Sample/libEmuCPU.dylib")
    }
    func run(_ symbol: String, _ registers: [Int: UInt64]) throws -> EmulatedRun {
        let function = try #require(functions.first { $0.symbol == symbol }, "\(symbol)")
        return try emulator.run(at: function.startAddress, registers: registers)
    }
    let atomic = try run("_emu_cpu_lse", [0: 40, 1: 2])
    #expect(atomic.outcome == "returned" && atomic.x[0] == 42, "\(atomic.outcome) \(atomic.x[0])")
    let signed = try run("_emu_cpu_pac", [0: 0x1234])
    #expect(signed.outcome == "returned" && signed.x[0] == 0x1234, "\(signed.outcome) \(signed.x[0])")
    let converted = try run("_emu_cpu_jcvt", [:])
    #expect(converted.outcome == "returned" && converted.x[0] == 7, "\(converted.outcome) \(converted.x[0])")
    #expect(try run("_emu_cpu_brk", [:]).outcome == "trapped")
    // An encoding the emulator has no meaning for is no observation.
    #expect(try run("_emu_cpu_unallocated", [:]).outcome == "unsupported")
}

/// The emulated image is the image as dyld leaves it, and every run starts
/// from the same machine. emuimage.s states each function's behaviour. The
/// second image is the same source linked with bind opcodes in place of
/// chained fixups.
@Test(arguments: ["Fixtures/Sample/libEmuImage.dylib", "Fixtures/Sample/libEmuImage.opcodes.dylib"])
func theEmulatorLoadsTheImageAndStartsEveryRunCleanIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path),
          let emulator = try EmulatorOracle(image: URL(fileURLWithPath: path).lastPathComponent)
    else { return }
    let functions = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path) }
    func run(_ name: String, _ registers: [Int: UInt64] = [:], poison: UInt64? = nil) throws -> EmulatedRun {
        let function = try #require(functions.first { $0.symbol == "_emu_image_\(name)" }, "\(name)")
        return try emulator.run(at: function.startAddress, registers: registers, poison: poison)
    }
    // A rebased pointer leads to the word it names, and a bound one is the
    // import's own address, outside every mapping.
    let rebased = try run("rebased")
    #expect(rebased.outcome == "returned" && rebased.x[0] == 77, "\(rebased.outcome) \(rebased.x[0])")
    let bound = try run("bound")
    #expect(bound.outcome == "returned" && bound.x[0] >= 0x7_d000_0000 && bound.x[0] < 0x7_d100_0000, "\(bound.x[0])")
    // Each import has an address of its own, 16 apart.
    let two = try run("two_imports")
    #expect(two.outcome == "returned" && two.x[0] != 0 && two.x[0] < 0x1000 && two.x[0] % 16 == 0, "\(two.x[0])")
    // A call through that pointer is a call out, like one through a stub.
    let through = try run("call_pointer", poison: 1)
    #expect(through.outcome == "external" && through.externalCalls.count == 1 && through.x[0] == 5)
    #expect(!through.handedMemory)
    // What the callee returned is the pattern, and differs with it.
    #expect(try run("uses_result", poison: 1).x[0] != run("uses_result", poison: 2).x[0])
    #expect(try run("call_pointer", poison: 2).x[0] == 5)
    // An address of a local in an argument register marks the call.
    let handed = try run("passes_local", poison: 1)
    #expect(handed.handedMemory && handed.x[0] == 9)
    // Runs do not see each other: data, vector registers, the stack.
    #expect(try run("count").x[0] == 1)
    #expect(try run("count").x[0] == 1)
    #expect(try run("fill_vector").x[0] == 1)
    #expect(try run("vector_upper").x[0] == 0)
    #expect(try run("below_write", [0: 0x99]).x[0] == 0x99)
    #expect(try run("below_read").x[0] == 0)
    // A returned run names the callee-saved state it left changed.
    #expect(try run("rebased").changedCalleeSaved == [])
    #expect(try run("clobbers").changedCalleeSaved == ["x19"])
    #expect(try run("unbalanced").changedCalleeSaved == ["sp"])
    // More branches than a reply lists: the run says so and lists none.
    let spun = try run("spin")
    #expect(spun.outcome == "overflowed" && spun.branches.isEmpty)
}
