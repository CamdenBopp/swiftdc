import Darwin
import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let compareBranchInputs: [UInt64] = [
    0, 1, 0x7fff_ffff, 0x8000_0000, 0xffff_ffff,
    0x1_0000_0000, 0x1_0000_0001, 0xffff_ffff_0000_0000, .max,
]

private func compareBranchFunction(opcode: UInt32, copied: Bool, joined: Bool) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    // The taken arm returns 1 and the fallthrough arm returns 2. With a
    // common RET the tracer reconstructs a select; without it the branch
    // fact still has to describe the same machine condition.
    let copy: [UInt32] = copied ? [0xaa0003e8] : [] // mov x8, x0
    let words = copy + [opcode | (copied ? 8 : 0), 0xd2800040,
                       joined ? 0x14000002 : 0xd65f03c0, 0xd2800020, 0xd65f03c0]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let instructions = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(instructions.count == words.count)
    return DisassembledFunction(symbol: "_compareBranchWidth", demangledName: nil,
        startAddress: 0x1000, instructions: instructions.map(Disassembler.instruction(decoded:)), source: .symbol)
}

@Test func compareAndBranchConditionsReadTheEncodedRegisterWidth() throws {
    for (opcode, word, nonzero) in [
        (UInt32(0x34000060), true, false), (0x35000060, true, true),
        (0xb4000060, false, false), (0xb5000060, false, true),
    ] {
        for copied in [false, true] {
            let function = try compareBranchFunction(opcode: opcode, copied: copied, joined: false)
            let analysis = ValueTracer().analyze(function,
                entry: .swiftFunction(scalarArguments: ["x0": 0]))
            let branch = try #require(function.instructions.first { $0.controlFlow == .conditionalBranch })
            let condition = try #require(analysis.branchConditions[branch.address])
            for input in compareBranchInputs {
                let tested = word ? input & 0xffff_ffff : input
                let expected = (tested != 0) == nonzero ? UInt64(1) : 0
                let actual = try ProbeValue.abstractValue(condition).evaluateInteger(arguments: [input])
                #expect(actual == expected,
                    "opcode=\(String(opcode, radix: 16)) copied=\(copied) input=\(String(input, radix: 16))")
            }
        }
    }
}

@Test func compareAndBranchDiamondsKeepTheTestedWidthInTheirSelectedResult() throws {
    for (opcode, word, nonzero) in [
        (UInt32(0x34000060), true, false), (0x35000060, true, true),
        (0xb4000060, false, false), (0xb5000060, false, true),
    ] {
        for copied in [false, true] {
            let function = try compareBranchFunction(opcode: opcode, copied: copied, joined: true)
            let analysis = ValueTracer().analyze(function,
                entry: .swiftFunction(scalarArguments: ["x0": 0]))
            let exit = try #require(function.instructions.last)
            let result = try #require(analysis.exitValues[exit.address])
            for input in compareBranchInputs {
                let tested = word ? input & 0xffff_ffff : input
                let expected = (tested != 0) == nonzero ? UInt64(1) : 2
                let actual = try ProbeValue.abstractValue(result).evaluateInteger(arguments: [input])
                #expect(actual == expected,
                    "opcode=\(String(opcode, radix: 16)) copied=\(copied) input=\(String(input, radix: 16))")
            }
        }
    }
}

private let compareBranchFixtures = [
    ("Fixtures/Sample/libCompareBranchWidth.O0.dylib", "Fixtures/Sample/libCompareBranchWidth.O0.stripped.dylib", "Fixtures/Sample/compare-branch-width-O0-oracle"),
    ("Fixtures/Sample/libCompareBranchWidth.O2.dylib", "Fixtures/Sample/libCompareBranchWidth.O2.stripped.dylib", "Fixtures/Sample/compare-branch-width-O2-oracle"),
    ("Fixtures/Sample/libCompareBranchWidth.Os.dylib", "Fixtures/Sample/libCompareBranchWidth.Os.stripped.dylib", "Fixtures/Sample/compare-branch-width-Os-oracle"),
]

@Test func compareBranchWidthNativeCallersPassAtAllCOptimizationLevelsIfPresent() throws {
    for (_, _, path) in compareBranchFixtures {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: data, as: UTF8.self) == "PASS 72 native compare-branch-width observations\n")
    }
}

private func substituteBranchProducer(_ value: AbstractValue, site: UInt64, result: UInt64) -> AbstractValue {
    switch value {
    case .callResult(let address) where address == site: return .immediate(result)
    case .binary(let op, let left, let right):
        return .binary(op, substituteBranchProducer(left, site: site, result: result),
                       substituteBranchProducer(right, site: site, result: result))
    case .select(let condition, let yes, let no):
        return .select(condition: substituteBranchProducer(condition, site: site, result: result),
                       whenTrue: substituteBranchProducer(yes, site: site, result: result),
                       whenFalse: substituteBranchProducer(no, site: site, result: result))
    default: return value
    }
}

@Test func compareBranchResultViewsAgreeWithNativeAcrossAllAPIsIfPresent() async throws {
    for (normal, stripped, _) in compareBranchFixtures {
        for path in [normal, stripped] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let image = try BinaryLoader.load(path: path)
            let entries = Set(image.symbols.filter { $0.name.hasPrefix("_wordbranch_") }.map { UInt64($0.offset) })
            try #require(entries.count == 8)
            let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
            defer { dlclose(library) }
            for stage in 0..<5 {
                let functions: [DisassembledFunction] = try await withStableDependencies {
                    switch stage {
                    case 0: return try await Disassembler().disassemble(path: path)
                    case 1: return await Disassembler().disassemble(machO: image)
                    case 2: return try await Disassembler().disassemble(path: path, functionFilter: "wordbranch_")
                    case 3:
                        let selected: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                            machO: image, transform: { entries.contains($0.startAddress) ? $0 : nil })
                        return selected.compactMap { $0 }
                    default:
                        return Array(await Disassembler().analyzeEachFunction(at: entries, in: image, transform: { $0 }).values)
                    }
                }
                let callers = functions.filter { entries.contains($0.startAddress) }.sorted { $0.startAddress < $1.startAddress }
                try #require(callers.count == 8)
                for function in callers {
                    let context = Comment(rawValue: "\(path) stage=\(stage) \(function.symbol)")
                    let name = String(function.symbol.dropFirst())
                    let native = unsafeBitCast(try #require(dlsym(library, name)), to: (@convention(c) (UInt64) -> UInt64).self)
                    let analysis = ValueTracer().analyze(function)
                    let call = try #require(function.instructions.first { $0.controlFlow == .call })
                    let branch = try #require(function.instructions.first { $0.controlFlow == .conditionalBranch })
                    let condition = try #require(analysis.branchConditions[branch.address])
                    let exit = try #require(function.instructions.last)
                    let value = try #require(analysis.exitValues[exit.address])
                    for input in compareBranchInputs {
                        // This is the producer's actual assembly operation,
                        // supplied independently of any decompiler ABI guess.
                        let produced = input | 0x1_0000_0000
                        let actual = native(input)
                        let selected = substituteBranchProducer(value, site: call.address, result: produced)
                        #expect(try ProbeValue.abstractValue(selected).evaluateInteger() == actual, context)
                        let tested = substituteBranchProducer(condition, site: call.address, result: produced)
                        #expect(try ProbeValue.abstractValue(tested).evaluateInteger() == (actual == 1 ? 1 : 0), context)
                    }
                    let text = function.renderStructured()
                    if name.hasPrefix("wordbranch_w_") {
                        #expect(text.contains("& 0xffffffff"), Comment(rawValue: text))
                    } else {
                        #expect(!text.contains("& 0xffffffff"), Comment(rawValue: text))
                    }
                }
            }
        }
    }
}
