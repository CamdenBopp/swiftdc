import Foundation
import Testing
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let outlinedContextImages = [
    (level: "Onone", path: "Fixtures/Sample/libAsyncOutlinedContext.Onone.dylib", oracle: "Fixtures/Sample/async-outlined-context-Onone-oracle"),
    (level: "O", path: "Fixtures/Sample/libAsyncOutlinedContext.O.dylib", oracle: "Fixtures/Sample/async-outlined-context-O-oracle"),
    (level: "Osize", path: "Fixtures/Sample/libAsyncOutlinedContext.Osize.dylib", oracle: "Fixtures/Sample/async-outlined-context-Osize-oracle"),
]

/// Select by independently demangled nlist entries, require every selected
/// start, and give analyzeEachFunction all starts so outlined helpers retain
/// their complete context. An empty API result cannot satisfy these checks.
private func outlinedContextStages(path: String, module: String, names: [String]) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    var entries: [String: UInt64] = [:]
    for symbol in image.symbols where symbol.offset != 0 && symbol.name.hasPrefix("_$s") {
        let name = try await demangleAsNode(String(symbol.name.dropFirst())).print(using: .default)
        for selected in names where name == selected {
            try #require(entries[selected] == nil)
            entries[selected] = UInt64(symbol.offset)
        }
    }
    try #require(entries.count == names.count)
    let selectedEntries = entries
    let addresses = Set(entries.values)
    let starts = Set(Disassembler().functionStarts(of: image))
    try #require(addresses.count == names.count && addresses.isSubset(of: starts))
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: module + ".")
            case 3:
                let values: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { addresses.contains($0.startAddress) ? $0 : nil })
                return values.compactMap { $0 }
            default: return Array(await Disassembler().analyzeEachFunction(at: starts, in: image, transform: { $0 }).values)
            }
        }
        let selected = functions.filter { addresses.contains($0.startAddress) }
        try #require(selected.count == names.count && Set(selected.map(\.startAddress)) == addresses)
        stages.append(try names.map { name in try #require(selected.first { $0.startAddress == selectedEntries[name] }) })
    }
    return stages
}

@Test(arguments: ["Onone", "O", "Osize"])
func outlinedContextSetupPreservesGroupingAndAccessorDeclinesAcrossAPIsIfPresent(level: String) async throws {
    let image = try #require(outlinedContextImages.first { $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let parent = "AsyncOutlinedContext.sequence() async -> Swift.Int64"
    let names = [parent, "(1) await resume partial function for " + parent, "(2) await resume partial function for " + parent]
    for (stage, functions) in try await outlinedContextStages(path: image.path, module: "AsyncOutlinedContext", names: names).enumerated() {
        let chain = functions.map(\.startAddress)
        if stage == 4 {
            // analyzeEachFunction intentionally classifies accessor bodies
            // without recovering suspension edges or owning awaited results.
            for function in functions {
                #expect(function.asyncFunclet == nil)
                #expect(!function.renderPseudo().contains("let awaited"))
                #expect(!function.renderStructured().contains("let awaited"))
            }
            continue
        }
        for (ordinal, function) in functions.enumerated() {
            let info = try #require(function.asyncFunclet)
            let context = Comment(rawValue: image.path + " API \(stage)\n" + function.renderStructured())
            #expect(info.chain == chain && info.parent == chain[0] && info.ordinal == ordinal, context)
            if ordinal > 0 {
                #expect(info.kind == .awaitReturn && info.predecessor == chain[ordinal - 1], context)
            }
        }
        for (ordinal, producer) in ["first", "second"].enumerated() {
            let expected = "let awaited\(ordinal + 1) = await AsyncOutlinedContext." + producer + "()"
            #expect(functions[ordinal].renderPseudo().contains(expected))
            #expect(functions[ordinal].renderStructured().contains(expected))
        }
    }
}

@Test func outlinedContextNativeControlReturnsTheSourceSumIfPresent() throws {
    for image in outlinedContextImages {
        guard FileManager.default.fileExists(atPath: image.oracle) else { continue }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: image.oracle)
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.split(separator: "\n").last == "PASS native outlined async context: 7 observations", Comment(rawValue: output))
    }
}

private func outlinedHeaderIndex(helper: [UInt32], name: String?, allocated: Bool = true,
                                 helperIsStart: Bool = true, after: [UInt32] = [],
                                 hintsPresent: Bool = true, resumeRegister: UInt32 = 8,
                                 before: [UInt32] = []) throws -> AsyncFuncletIndex {
    func branch(_ from: UInt64, _ to: UInt64, link: Bool) -> UInt32 {
        (link ? 0x94000000 : 0x14000000) | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
    }
    // adr x8, resume; independent native/llvm evidence covers the same
    // STP/MOV/RET encoding in the own-source default-Osize library.
    var entry: [UInt32] = [allocated ? branch(0x1000, 0x4000, link: true) : 0xd503201f]
    entry += before
    let adrPC = 0x1000 + UInt64(entry.count * 4)
    let delta = UInt64(0x2000) - adrPC
    let adr = UInt32(0x10000000) | resumeRegister | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5
    entry += [adr]
    entry += [branch(0x1000 + UInt64(entry.count * 4), 0x3000, link: true)]
    entry += after
    entry += [branch(0x1000 + UInt64(entry.count * 4), 0x5000, link: false)]
    let bodies: [UInt64: [UInt32]] = [0x1000: entry, 0x2000: [0xd65f03c0], 0x3000: helper,
                                    0x4000: [0xd65f03c0], 0x5000: [0xd65f03c0], 0x6000: [0xd65f03c0]]
    let engine = try #require(CapstoneEngine())
    var decoded: [UInt64: [Instruction]] = [:]
    for (address, words) in bodies {
        decoded[address] = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: address).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        try #require(decoded[address]?.count == words.count)
    }
    var starts = Set(bodies.keys)
    if !helperIsStart { starts.remove(0x3000) }
    return AsyncFuncletIndex.build(
        hints: hintsPresent ? .init(entries: [0x1000], awaitReturns: [0x2000], continuations: []) : nil,
        functionStarts: starts, instructions: { decoded[$0] ?? [] },
        nameOf: { address in
            switch address {
            case 0x3000: name
            case 0x4000: "swift_task_alloc"
            case 0x5000: "Own.worker() async -> Swift.Int64"
            default: nil
            }
        })
}

@Test func outlinedContextHeaderProofRequiresTheWholeHelperAndLiveFields() throws {
    let canonical: [UInt32] = [0xa9002016, 0xaa0003f6, 0xd65f03c0]
    for hints in [true, false] {
        for name: String? in [nil, "OUTLINED_FUNCTION_4", "ordinaryName"] {
            let index = try outlinedHeaderIndex(helper: canonical, name: name, hintsPresent: hints)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
            #expect(index.suspensions[0x100c]?.resume == 0x2000)
            #expect(index.suspensions[0x1008] == nil)
        }
    }
    // Physical input registers and helper names do not establish its role;
    // the complete body and the live caller facts do.
    for (helper, resumeRegister, before) in [
        ([UInt32(0xa9002416), 0xaa0003f6, 0xd65f03c0], UInt32(9), [UInt32]()),
        ([0xa9002015, 0xaa0003f6, 0xd65f03c0], UInt32(8), []),
        ([0xa9002036, 0xaa0103f6, 0xd65f03c0], UInt32(8), [0xaa0003e1]),
        ([0xa90023b6, 0xaa1d03f6, 0xd65f03c0], UInt32(8), [0xaa0003fd]),
    ] {
        let index = try outlinedHeaderIndex(helper: helper, name: nil,
                                           resumeRegister: resumeRegister, before: before)
        #expect(index.chains[0x1000] == [0x1000, 0x2000])
    }
    // BL overwrites x30 before the helper sees any of its inputs.
    for (helper, resumeRegister, before) in [
        ([UInt32(0xa9007816), 0xaa0003f6, 0xd65f03c0], UInt32(30), [UInt32]()),
        ([0xa90023d6, 0xaa1e03f6, 0xd65f03c0], UInt32(8), [0xaa0003fe]),
    ] {
        let index = try outlinedHeaderIndex(helper: helper, name: nil,
                                           resumeRegister: resumeRegister, before: before)
        #expect(index.chains[0x1000] != [0x1000, 0x2000])
    }
    let nearMisses: [[UInt32]] = [
        [0xa9402016, 0xaa0003f6, 0xd65f03c0], // A load is not a header store.
        [0xa9802016, 0xaa0003f6, 0xd65f03c0], // Writeback is outside this proof.
        [0xa9002016, 0xaa2003f6, 0xd65f03c0], // MVN does not preserve the pointer.
        [0xa9002016, 0x2a0003f6, 0xd65f03c0], // A 32-bit move loses pointer bits.
        [0xa9002016, 0xaa0003f5, 0xd65f03c0], // The pointer must reach x22.
        [0xa9002016, 0xaa0003f6, 0x140007fe], // A tail call has unproved effects.
        [0xa900a016, 0xaa0003f6, 0xd65f03c0], // ResumeParent written at +16.
        [0xa9002036, 0xaa0003f6, 0xd65f03c0], // Stores through an unproved x1.
        [0x29002016, 0xaa0003f6, 0xd65f03c0], // Only 32-bit context words.
        [0xa9002016, 0xaa0103f6, 0xd65f03c0], // Hands over a different pointer.
        [0xa9002016, 0xd65f03c0],             // No handoff into x22.
        [0xa9002016, 0xaa0003f6, 0xd65f0120], // Returns through unproved x9.
        [0xa9002016, 0xaa0003f6, 0xf90006df, 0xd65f03c0], // Clears saved resume.
        [0xa9002016, 0xaa0003f6, 0x94000bfe, 0xd65f03c0], // Another call.
    ]
    for helper in nearMisses {
        let index = try outlinedHeaderIndex(helper: helper, name: "OUTLINED_FUNCTION_4")
        #expect(index.chains[0x1000] != [0x1000, 0x2000])
    }
    for (before, after) in [
        ([UInt32(0x10007ff6)], [UInt32(0xf9000416)]), // x22's old code address is gone.
        ([0xb0000016], [0x910002c9, 0xf9000409]),    // x22's old page is gone.
        ([0x10007ffe], [0xf900041e]),              // BL replaces the old x30 address.
        ([0xb000001e], [0x910003c9, 0xf9000409]),   // BL replaces the old x30 page.
        ([0xaa0003fe], [0xaa1e03f6]),              // BL replaces the old x30 context alias.
        // The Parent store overwrites a prior resume field for an overlapping context.
        ([0x910022d3, 0x910042c0, 0x10007fa9, 0xf9000009], [0xaa1303f6]),
        // The ResumeParent store partially overwrites another context's saved word.
        ([0x910052d3, 0x910042c0, 0x10007fa9, 0xf800c009], [0xaa1303f6]),
    ] {
        let index = try outlinedHeaderIndex(helper: canonical, name: nil, after: after, before: before)
        #expect(index.chains[0x1000] != [0x1000, 0x2000])
    }
    for (allocated, start, after) in [(false, true, [UInt32]()), (true, false, []),
                                    (true, true, [0xf90006df]), // Overwrite after returning.
                                    (true, true, [0x940013fd])] { // Unknown call after returning.
        let index = try outlinedHeaderIndex(helper: canonical, name: "OUTLINED_FUNCTION_4",
                                           allocated: allocated, helperIsStart: start, after: after)
        #expect(index.chains[0x1000] != [0x1000, 0x2000])
    }
}

@Test func outlinedContextHeaderRejectsLinkRegisterFactsCopiedAfterAnEarlierCall() throws {
    let canonical: [UInt32] = [0xa9002016, 0xaa0003f6, 0xd65f03c0]
    for hints in [true, false] {
        for (materialize, copy): (UInt32, UInt32) in [(0x10007fde, 0xaa1e03e8), (0xb000001e, 0x910003c8)] {
            let index = try outlinedHeaderIndex(helper: canonical, name: nil,
                hintsPresent: hints, resumeRegister: 9,
                before: [0xaa0003f3, materialize, 0xaa1f03e0, 0x940013fc,
                         0xaa1303e0, copy])
            #expect(index.chains[0x1000] != [0x1000, 0x2000])
        }
        let index = try outlinedHeaderIndex(helper: [0xa9002036, 0xaa0103f6, 0xd65f03c0], name: nil,
            hintsPresent: hints,
            before: [0xaa0003fe, 0xaa1f03e0, 0x940013fd, 0xaa1e03e1])
        #expect(index.chains[0x1000] != [0x1000, 0x2000])
    }
}
