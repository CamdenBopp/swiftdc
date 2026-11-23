import Foundation
import Testing
@testable import SwiftDecompilerCore

private let isolationFixtures = [
    ("Fixtures/Sample/libAsyncIsolation.O.nonsending.dylib", "Fixtures/Sample/async-isolation-O-nonsending-oracle"),
    ("Fixtures/Sample/libAsyncIsolation.O.concurrent.dylib", "Fixtures/Sample/async-isolation-O-concurrent-oracle"),
    ("Fixtures/Sample/libAsyncIsolation.Onone.nonsending.dylib", "Fixtures/Sample/async-isolation-Onone-nonsending-oracle"),
    ("Fixtures/Sample/libAsyncIsolation.Onone.concurrent.dylib", "Fixtures/Sample/async-isolation-Onone-concurrent-oracle"),
    ("Fixtures/Sample/libAsyncIsolation.Osize.nonsending.dylib", "Fixtures/Sample/async-isolation-Osize-nonsending-oracle"),
    ("Fixtures/Sample/libAsyncIsolation.Osize.concurrent.dylib", "Fixtures/Sample/async-isolation-Osize-concurrent-oracle"),
]
private let isolationImagePaths = isolationFixtures.map { $0.0 }
    + ["Fixtures/Sample/libAsyncIsolation.O.nonsending.stripped.dylib"]

private func isolationEntry(_ name: String, in functions: [DisassembledFunction]) throws -> DisassembledFunction {
    try #require(functions.first { $0.demangledName?.hasPrefix("AsyncIsolation." + name + "(") == true })
}

@Test func asyncIsolationEntriesDoNotNameUnprovedIntegerFormalsInEveryPipelineIfPresent() async throws {
    for path in isolationImagePaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "AsyncIsolation") }
        let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for (groupIndex, group) in [listing, array, filtered, streamed, Array(each.values)].enumerated() {
            for name in ["outer", "boxOuter", "pairOuter", "longOuter", "hiddenCaller"] {
                let function = try isolationEntry(name, in: group)
                for text in [function.renderPseudo(), function.renderStructured()] {
                    // No source GP location is proved by these identical
                    // signatures: x0/x1 or x2/x3 can be the first formals.
                    let gpText = name == "pairOuter" ? text.replacingOccurrences(of: "arg0.f", with: "knownFPField") : text
                    #expect(!gpText.contains("arg0") && !gpText.contains("arg1"), Comment(rawValue: path + "\n" + text))
                }
            }
            // Ordinary synchronous seeding is independently unchanged.
            let sync = try isolationEntry("sync", in: group).renderStructured()
            #expect(sync.contains("arg0") && sync.contains("arg1"), Comment(rawValue: sync))
            let leaf = try isolationEntry("single", in: group).renderStructured()
            #expect(!leaf.contains("arg0"), Comment(rawValue: leaf))
            let constants = group.filter { $0.displayName.contains("AsyncIsolation.constant(") }
            // Source rendering of this pure constant already declines in the
            // published baseline. Independently prove the new GP convention
            // preserves facts established by instructions, even in analyzeEach.
            let context = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22":.asyncContext])
            #expect(constants.contains {
                ValueTracer().analyze($0, entry: context).exitValues.values.contains(.immediate(17))
            }, Comment(rawValue: path + " pipeline " + String(groupIndex)))
        }
    }
}

@Test func asyncIsolationResumeConventionsNeverInheritEvenTheIndependentFPBank() throws {
    let engine = try #require(CapstoneEngine())
    let words: [UInt32] = [0xaa1403e6, 0x94000000, 0xd65f03c0]
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let instructions = engine.disassemble(bytes, address: 0x2000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
            branchTarget: $0.branchTarget, detail: $0.detail, callee: .kept($0.controlFlow == .call ? "unknown" : nil))
    }
    let raw = DisassembledFunction(symbol: "resume", demangledName: nil, startAddress: 0x2000, instructions: instructions, source: .address)
    for kind: AsyncResumeKind in [.continuation, .awaitReturn] {
        let function = raw.attachingAsyncFunclet(.init(parent: 0x1000,
            parentName: "Calls.owner(Swift.Double, Swift.Double) async -> Swift.Int", ordinal: 1,
            kind: kind, predecessor: 0x1000, chain: [0x1000,0x2000]))
        let base = MethodEntryConvention.swiftValueInstance(seededRegisters: ["x0":.argument(0),
            "v0":.argument(0),"v1":.argument(1),"x20":.selfPointer])
        let convention = try #require(Disassembler.asyncConvention(for: function, base: base, index: .empty))
        let site = try #require(ValueTracer().analyze(function, entry: convention).callSites[0x2004])
        #expect(site.arguments.allSatisfy { $0 == .unknown })
        #expect(site.floatArguments.allSatisfy { $0 == .unknown })
    }
}

@Test func asyncIsolationOutgoingCallsKeepIndependentFPAndDeclineUnprovedGPIfPresent() async throws {
    for path in isolationImagePaths {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let image = try BinaryLoader.load(path: path)
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(functions.map(\.startAddress)), in: image, transform: { $0 })
        }
        for group in [functions, Array(each.values)] {
          for (name, call) in [("outer", "AsyncIsolation.inner(?, ?)"),
                             ("mixOuter", "AsyncIsolation.mix(?, arg1, ?)"),
                             ("literalCaller", "AsyncIsolation.inner(?, ?)")] {
            let function = try isolationEntry(name, in: group)
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.components(separatedBy: call).count == 2, Comment(rawValue: path + "\n" + text))
            }
          }
          let hidden = try isolationEntry("hiddenCaller", in: group).renderStructured()
          if path.contains(".stripped.") {
              #expect(!hidden.contains("AsyncIsolation.hidden("), Comment(rawValue: hidden))
              #expect(hidden.contains("…"), Comment(rawValue: hidden))
          }
          if path.contains(".Onone.") {
              let stack = try isolationEntry("longLiteral", in: group).renderStructured()
              #expect(stack.contains("AsyncIsolation.long(?, ?, ?, ?, ?, ?, ?, ?, ?)"), Comment(rawValue: stack))
          }
        }
    }
}

@Test func asyncIsolationEntryProjectionKeepsFPAndSelfWithoutInventingGPMetadata() throws {
    let engine = try #require(CapstoneEngine())
    // Copy the independently fixed x20 self into a snapshot register. The
    // call's own receiver classification is intentionally unspecified.
    let words: [UInt32] = [0xaa1403e6, 0x94000000, 0xd65f03c0]
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let instructions = engine.disassemble(bytes, address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
            branchTarget: $0.branchTarget, detail: $0.detail, callee: .kept($0.controlFlow == .call ? "unknown" : nil))
    }
    let raw = DisassembledFunction(symbol: "entry", demangledName: nil, startAddress: 0x1000,
        instructions: instructions, source: .address)
    let entry = raw.attachingAsyncFunclet(.init(parent: 0x1000,
        parentName: "Calls.member(Swift.Int, Swift.Double) async -> Swift.Int", ordinal: 0,
        kind: nil, predecessor: nil, chain: [0x1000]))
    let index = AsyncFuncletIndex.build(hints: nil, functionStarts: [], instructions: { _ in [] }, nameOf: { _ in nil })
    let cases: [(MethodEntryConvention, Bool, AbstractValue?)] = [
        (.swiftFunction(scalarArguments: ["x0":0,"v0":1], genericMetadata: ["x1":"A"],
            genericWitnessTables: ["x2":0], existentialTables: ["x3":2], argumentFields: ["x4":[2,0],"v1":[2,8]]),
            false, .argumentField(argument: 2, offset: 8)),
        (.swiftInstance(scalarArguments: ["x0":0,"v0":1], existentialTables: ["x1":2]), true, nil),
        (.swiftValueInstance(seededRegisters: ["x0":.argument(0),"x1":.argumentField(argument: 2, offset: 0),
            "v0":.argument(1),"v1":.selfFieldValue(offset: 8),"x20":.selfPointer]), true, .selfFieldValue(offset: 8)),
    ]
    for (base, hasSelf, field) in cases {
        let convention = try #require(Disassembler.asyncConvention(for: entry, base: base, index: index))
        let site = try #require(ValueTracer().analyze(entry, entry: convention).callSites[0x1004])
        #expect(site.arguments.enumerated().allSatisfy {
            $0.offset == 6 && hasSelf ? $0.element == .selfPointer : $0.element == .unknown
        })
        if hasSelf { #expect(site.arguments.dropFirst(6).first == .selfPointer) }
        #expect(site.floatArguments.first == .argument(1))
        if let field { #expect(site.floatArguments[1] == field) }
    }
}

@Test func asyncIsolationConsensusRequiresAgreementAndAnEntryRatherThanAResume() throws {
    let seven = AbstractValue.immediate(7), minusThree = AbstractValue.immediate(UInt64(bitPattern: -3))
    let same: [AbstractValue] = (0..<12).map { $0.isMultiple(of: 2) ? seven : minusThree }
    #expect(Disassembler.asyncIntegerArgumentConsensus(same) == Array(same.prefix(6)) + [.unknown, .unknown])
    #expect(Disassembler.asyncIntegerArgumentConsensus([]) == Array(repeating: .unknown, count: 8))
    var different = same; different[2] = .immediate(9)
    #expect(Disassembler.asyncIntegerArgumentConsensus(different)[0] == .unknown)
    #expect(Disassembler.asyncIntegerArgumentConsensus([seven, minusThree])[0] == .unknown)
    let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [0x2000], continuations: [0x3000]),
        functionStarts: [0x1000,0x2000,0x3000], instructions: { _ in [] }, nameOf: { _ in nil })
    #expect(Disassembler.hasUnprovenAsyncIsolationPrefix(callee: nil, target: 0x1000, index: index))
    for target: UInt64 in [0x2000,0x3000] {
        #expect(!Disassembler.hasUnprovenAsyncIsolationPrefix(callee: "Calls.f(Swift.Int) async -> Swift.Int", target: target, index: index))
    }
    #expect(!Disassembler.hasUnprovenAsyncIsolationPrefix(callee: "(1) await resume partial function for Calls.f(Swift.Int) async -> Swift.Int", target: nil, index: .empty))
    #expect(Disassembler.hasUnprovenAsyncIsolationPrefix(callee: "Calls.f(Swift.Int) async -> Swift.Int", target: nil, index: .empty))
    #expect(!Disassembler.hasUnprovenAsyncIsolationPrefix(callee: "Calls.f(() async -> Swift.Int) -> Swift.Int", target: nil, index: .empty))
    #expect(!Disassembler.hasUnprovenAsyncIsolationPrefix(callee: "Calls.f(Swift.Int) -> Swift.Int", target: nil, index: .empty))
}

#if arch(arm64)
@Test func asyncIsolationCompilerFramesAndEvaluationMatchNativeAtEveryLevelIfPresent() throws {
    for (_, path) in isolationFixtures {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.contains("PASS 71 native async isolation observations"), Comment(rawValue: output))
    }
}
#endif
