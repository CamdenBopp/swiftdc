import Foundation
import Testing
@testable import SwiftDecompilerCore

private let asyncFPRaw = "Fixtures/Sample/libAsyncFPReturns.dylib"
private let asyncFPControl = "Fixtures/Sample/libAsyncFPReturnsControl.dylib"
private let asyncFPProducers = [("16",16), ("32",32), ("64",64), ("Dirty16",16), ("Dirty32",32)]

@Test func awaitedFPViewsRespectDeclaredPrecisionInGroupedPipelinesIfPresent() async throws {
    for (path, numeric) in [(asyncFPRaw, false), (asyncFPControl, true)] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "AsyncFPReturns.view") }
        let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
        for group in [listing, array, filtered, streamed] {
            for (label, source) in asyncFPProducers {
                for result in [16, 32, 64] {
                    let function = try #require(group.first {
                        $0.asyncFunclet?.kind == .awaitReturn
                            && $0.asyncFunclet?.parentName?.hasPrefix("AsyncFPReturns.view\(label)to\(result)(") == true
                    })
                    let type = result == 16 ? "Float16" : result == 32 ? "Float" : "Double"
                    let expected: String
                    if source == result { expected = "awaited1" }
                    else if numeric { expected = "\(type)(awaited1)" }
                    else if source < result { expected = "?" }
                    else { expected = "\(type)(bitPattern: UInt\(result)(truncatingIfNeeded: (awaited1.bitPattern & \(result == 16 ? "0xffff" : "0xffffffff"))))" }
                    for text in [function.renderPseudo(), function.renderStructured()] {
                        let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                        #expect(returns == ["return " + expected], Comment(rawValue: text))
                    }
                    let parent = try #require(group.first { $0.startAddress == function.asyncFunclet?.parent })
                    for text in [parent.renderPseudo(), parent.renderStructured()] {
                        #expect(text.components(separatedBy: "await AsyncFPReturns.produce\(label)(arg0)").count == 2, Comment(rawValue: text))
                    }
                }
            }
        }
        // analyzeEach deliberately omits grouping. Without its ownership and
        // suspension oracle it must not fabricate a named awaited value.
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for function in each.values {
            #expect(!function.renderPseudo().contains("awaited1"))
            #expect(!function.renderStructured().contains("awaited1"))
        }
    }
}

#if arch(arm64)
@Test func awaitedFPNativeFramesPreserveRawBitsConversionsAndEvaluationIfPresent() throws {
    for (path, arguments) in [("Fixtures/Sample/async-fp-raw-oracle", [String]()),
                              ("Fixtures/Sample/async-fp-control-oracle", ["--converted"])] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments; process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.split(separator: "\n").filter { $0.hasPrefix("view") }.count == 105, Comment(rawValue: output))
        #expect(output.contains("PASS 105 native async observations"), Comment(rawValue: output))
    }
}
#endif

private func awaitedFPConventionFixture(_ callee: String?, conflictingOwner: Bool = false) throws -> (DisassembledFunction, AsyncFuncletIndex) {
    let engine = try #require(CapstoneEngine())
    func entry(at start: UInt64) -> [Instruction] {
        let delta = UInt32(0x3000 - (start + 4))
        let adr = 0x10000009 | ((delta & 3) << 29) | ((delta >> 2) << 5)
        let branch = 0x14000000 | UInt32((0x4000 - (start + 16)) >> 2)
        let words: [UInt32] = [0x94000000, adr, 0xf9000409, 0xaa0003f6, branch]
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        return engine.disassemble(bytes, address: start).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.controlFlow == .call ? nil : $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? "swift_task_alloc" : nil))
        }
    }
    let first = entry(at: 0x1000); let second = entry(at: 0x2000)
    let index = AsyncFuncletIndex.build(hints: .init(entries: conflictingOwner ? [0x1000,0x2000] : [0x1000], awaitReturns: [0x3000]),
        functionStarts: conflictingOwner ? [0x1000,0x2000,0x3000] : [0x1000,0x3000],
        instructions: { $0 == 0x1000 ? first : $0 == 0x2000 ? second : [] },
        nameOf: { $0 == 0x4000 ? callee : nil })
    let info = try #require(index.info(for: 0x3000, parentName: { _ in "Calls.owner() async -> Swift.Double" }))
    let raw = DisassembledFunction(symbol: "resume", demangledName: nil, startAddress: 0x3000, instructions: [], source: .address)
    return (raw.attachingAsyncFunclet(info), index)
}

@Test func awaitedFPPrecisionRequiresTheExistingOwnershipBankAndErrorProofs() throws {
    for (type, bits) in [("Swift.Float16",16), ("Swift.Float",32), ("Swift.Float32",32),
                         ("Swift.Double",64), ("Swift.Float64",64), ("Swift.CGFloat",64), ("CoreGraphics.CGFloat",64)] {
        let (function, index) = try awaitedFPConventionFixture("Calls.produce() async -> " + type)
        let convention = try #require(Disassembler.asyncConvention(for: function,
            base: .swiftValueInstance(seededRegisters: ["v0": .argument(0)]), index: index))
        guard case .asyncFunclet(_, let seeds) = convention else { Issue.record("Expected await-return convention"); continue }
        #expect(seeds["v0"] == .unary(.floatResult(bits: bits, upperZero: bits == 64), .awaitResult(1)))
        #expect(seeds["x0"] == nil)
        #expect(seeds["x22"] == .asyncCalleeContext)
    }
    let names: [String?] = [nil, "Calls.produce() async -> Swift.Int", "Calls.produce() async -> ()",
        "Calls.produce() async -> Calls.Big", "Calls.produce() async -> A", "Calls.produce() async -> Swift.Optional<Swift.Float>",
        "Calls.produce() async throws(Calls.Failure) -> Swift.Float",
        // A source-type-only closure label isolates the generic-convention
        // guard from the separate rejection of a trailing enclosing signature.
        "implicit closure #1 @Sendable () async -> Swift.Float",
        "implicit closure #1 @Sendable () async -> Swift.Float in Calls.owner() async -> Swift.Double"]
    for name in names {
        let (function, index) = try awaitedFPConventionFixture(name)
        let convention = try #require(Disassembler.asyncConvention(for: function, base: nil, index: index))
        guard case .asyncFunclet(_, let seeds) = convention else { Issue.record("Expected owned context"); continue }
        #expect(seeds["v0"] == nil, Comment(rawValue: name ?? "unknown"))
        if Disassembler.awaitedResultRegister(into: 0x3000, index: index) == "x0" { #expect(seeds["x0"] == .awaitResult(1)) }
        else { #expect(seeds["x0"] == nil) }
    }
    let (shared, index) = try awaitedFPConventionFixture("Calls.produce() async -> Swift.Float", conflictingOwner: true)
    #expect(Disassembler.asyncConvention(for: shared, base: nil, index: index) == nil)
}

@Test func awaitedFPWordCopiesKeepLowBitsWithoutInventingWiderValues() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ move: UInt32, seed: AbstractValue) -> (AbstractValue?, AbstractValue?) {
        // Same-width vector-register FMOV, then a full D0 read into X0.
        let words: [UInt32] = [move, 0x9e660000, 0xd65f03c0]
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let instructions = engine.disassemble(bytes, address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "copy", demangledName: nil, startAddress: 0x1000, instructions: instructions, source: .address)
        let analysis = ValueTracer().analyze(function, entry: .swiftValueInstance(seededRegisters: ["v1": seed]))
        return (analysis.exitFloatValues[0x1008], analysis.exitValues[0x1008])
    }
    let half = AbstractValue.unary(.floatResult(bits: 16, upperZero: false), .awaitResult(1))
    let single = AbstractValue.unary(.floatResult(bits: 32, upperZero: false), .awaitResult(2))
    let double = AbstractValue.unary(.floatResult(bits: 64, upperZero: true), .awaitResult(3))
    for (word, seed): (UInt32, AbstractValue) in [(0x1e604020, half), (0x1e604020, single), (0x1e204020, half),
                                                 (0x1e604020, .aggregate([half]))] {
        let (floating, integer) = trace(word, seed: seed)
        #expect(floating == (seed == .aggregate([half]) ? half : seed))
        #expect(integer == nil || integer == .unknown)
    }
    let choice = AbstractValue.select(condition: .argument(2), whenTrue: .aggregate([half]), whenFalse: .aggregate([single]))
    let copied = AbstractValue.select(condition: .argument(2), whenTrue: half, whenFalse: single)
    #expect(trace(0x1e604020, seed: choice).0 == copied)
    // Full/truncating writes must keep the ordinary clearing/projection path.
    #expect(ValueTracer.partialFloatingCopy(single, bits: 32) == nil)
    #expect(ValueTracer.partialFloatingCopy(double, bits: 32) == nil)
    #expect(ValueTracer.partialFloatingCopy(.unary(.floatResult(bits: 16, upperZero: true), .awaitResult(1)), bits: 64) == nil)
    #expect(ValueTracer.partialFloatingCopy(.aggregate([half, single]), bits: 64) == nil)
    #expect(ValueTracer.partialFloatingCopy(.select(condition: .argument(2), whenTrue: half, whenFalse: double), bits: 32) == nil)
    #expect(ValueTracer.partialFloatingCopy(.select(condition: .argument(2), whenTrue: half, whenFalse: .unknown), bits: 64) == nil)
    #expect(ValueTracer.partialFloatingCopy(.unary(.floatResult(bits: 8, upperZero: false), .awaitResult(1)), bits: 64) == nil)
    for bits in [0,16,128,Int.max] { #expect(ValueTracer.partialFloatingCopy(half, bits: bits) == nil) }
    var deep = half
    for _ in 0..<8 { deep = .aggregate([deep]) }
    #expect(ValueTracer.partialFloatingCopy(deep, bits: 64) == nil)
}
