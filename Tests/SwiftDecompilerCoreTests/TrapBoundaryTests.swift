import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

/// A trap is a terminator even if LC_FUNCTION_STARTS includes more bytes after
/// it. Ghidra's independent analysis of the assembly fixture stops at BRK;
/// swiftdc used to erase it and show only the later call.
struct TrapBoundaryTests {
    @Test func trapSplitsBeforeFollowingEffects() {
        for mnemonic in ["brk #1", "udf #0", "trap"] {
            let function = DisassembledFunction(
                symbol: "_trap_then_effect", demangledName: nil, startAddress: 0x1000,
                instructions: [
                    Instruction(address: 0x1000, text: mnemonic, controlFlow: .sequential),
                    Instruction(address: 0x1004, text: "bl _effect", controlFlow: .call),
                    Instruction(address: 0x1008, text: "ret", controlFlow: .return),
                ], source: .symbol)
            let blocks = function.basicBlocks()
            #expect(blocks.count == 2)
            #expect(blocks.first?.instructions.count == 1)
            #expect(blocks.first?.successors == [])
            for text in [function.renderPseudo(), function.renderStructured()] {
                let trap = text.range(of: "trap()")
                let effect = text.range(of: "effect()")
                #expect(trap != nil, "\(text)")
                #expect(effect != nil, "Retain bytes beyond the trap: \(text)")
                if let trap, let effect { #expect(trap.lowerBound < effect.lowerBound) }
            }
            #expect(function.renderStructured().contains("loc_1004:"))
        }
    }

    @Test func standaloneAndEffectfulTrapStayVisible() {
        for prefix in [[], [Instruction(address: 0x1000, text: "bl _effect", controlFlow: .call)]] {
            let function = DisassembledFunction(
                symbol: "_trap", demangledName: nil, startAddress: 0x1000,
                instructions: prefix + [Instruction(address: 0x1004, text: "brk #1", controlFlow: .sequential)],
                source: .symbol)
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.components(separatedBy: "trap()").count == 2, "\(text)")
            }
        }
    }

    @Test func compiledTrapFixtureRetainsTerminationInBothDecoders() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-traps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("traps.s")
        let binary = directory.appendingPathComponent("traps.dylib")
        try """
        .text
        .p2align 2
        .globl _trap_then_effect
        _trap_then_effect:
          brk #1
          bl _effect
          ret
        .globl _effect
        _effect:
          mov x0, #99
          ret
        """.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-arch", "arm64", "-dynamiclib", source.path, "-o", binary.path]
        try compiler.run()
        compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0)
        let objdump = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: binary.path)
        }
        let image = try BinaryLoader.load(path: binary.path)
        let capstone = await withStableDependencies {
            await Disassembler(preset: .default).disassemble(machO: image)
        }
        for functions in [objdump, capstone] {
            let function = try #require(functions.first { $0.symbol == "_trap_then_effect" })
            #expect(function.basicBlocks().count == 2)
            #expect(function.basicBlocks().first?.successors == [])
            #expect(function.renderStructured().contains("trap()"), "\(function.renderStructured())")
        }
    }
}
