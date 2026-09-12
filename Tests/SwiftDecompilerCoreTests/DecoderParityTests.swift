import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Cross-checks swiftdc's two independent ARM64 front-ends against each other:
/// the llvm-objdump path (`disassemble(path:)`) and the in-process Capstone path
/// (`disassemble(machO:)`). They decode the same `__text` bytes, so for every
/// function both recover they must agree on the instruction boundaries.
///
/// The readiness doc calls this the cheapest unexploited oracle: two decoders
/// exist, but nothing compared them across a whole binary — both silent-
/// truncation bugs found so far lived in whichever decoder the other test path
/// did not exercise. The existing smoke test compares only `Tree.sum()`'s
/// instruction *count*; this walks every shared function and compares the full
/// address sequence, so a truncation or a dropped/invented function anywhere in
/// the binary shows up.
struct DecoderParityTests {
    static let fixtures = [
        "Fixtures/Sample/sample.release",
        "Fixtures/Sample/libReconstruction.dylib",
        "Fixtures/Sample/libReconstruction.opt.dylib",
    ]

    @Test func decodersAgreeOnInstructionBoundariesIfPresent() async throws {
        for path in Self.fixtures where FileManager.default.fileExists(atPath: path) {
            try await assertDecoderParity(path)
        }
    }

    private func assertDecoderParity(_ path: String) async throws {
        let objdump = try await withStableDependencies {
            try await Disassembler(preset: .simplified).disassemble(path: path)
        }
        let machO = try BinaryLoader.load(path: path)
        let inProcess = await withStableDependencies {
            await Disassembler(preset: .simplified).disassemble(machO: machO)
        }

        // Non-vacuous: both front-ends recovered a real body of functions.
        #expect(objdump.count > 5, "\(path): objdump recovered only \(objdump.count) functions")
        #expect(inProcess.count > 5, "\(path): in-process recovered only \(inProcess.count) functions")

        // Neither decoder silently drops or invents a function.
        let objStarts = Set(objdump.map(\.startAddress))
        let ipStarts = Set(inProcess.map(\.startAddress))
        #expect(
            objStarts == ipStarts,
            """
            \(path): function-set mismatch between decoders.
            objdump-only:    \(objStarts.subtracting(ipStarts).sorted().map(hex))
            in-process-only: \(ipStarts.subtracting(objStarts).sorted().map(hex))
            """
        )

        // Every shared function decodes to the same instruction boundaries. A
        // truncation in either decoder shows here as a shorter address list.
        let ipByStart = Dictionary(inProcess.map { ($0.startAddress, $0) }, uniquingKeysWith: { first, _ in first })
        var comparedFunctions = 0
        for objFn in objdump {
            guard let ipFn = ipByStart[objFn.startAddress] else { continue }
            comparedFunctions += 1
            let name = objFn.demangledName ?? "sub_\(hex(objFn.startAddress))"
            #expect(
                objFn.instructions.map(\.address) == ipFn.instructions.map(\.address),
                "\(path): \(name) boundary mismatch — objdump \(objFn.instructions.count) insns vs in-process \(ipFn.instructions.count)"
            )
        }
        #expect(comparedFunctions > 5, "\(path): only \(comparedFunctions) shared functions — cross-check too thin")
    }

    private func hex<T: BinaryInteger>(_ value: T) -> String { "0x" + String(value, radix: 16) }
}
