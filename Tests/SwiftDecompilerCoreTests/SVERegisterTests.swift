import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `sveregisters.s`. The corpus sweep found xrefs dead by SIGTRAP on five
/// copies of OpenSSL's libcrypto and a Node addon that links it: ChaCha20's
/// `lsr z9.s, z9.s, #0x19` reached the scalar shift model with a register
/// it does not model, of width 0, and `UInt64(width - 1)` trapped.
private let path = "Fixtures/Sample/libSVERegisters.dylib"

@Test func anSVEInstructionIsNoScalarOnAnyEntryPointIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: binary.path) else { return }
    for command in [["xrefs", "--unreferenced"], ["disasm"], ["disasm", "-f", "sve_alias"], ["disasm", "--structured"],
                    ["analyze"]] {
        let process = Process()
        process.executableURL = binary
        process.arguments = [command[0], path] + command.dropFirst()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .exit && process.terminationStatus == 0,
                "\(command): status \(process.terminationStatus), reason \(process.terminationReason.rawValue)")
    }
}

/// `z0`'s low 128 bits are `v0`: after `fmov d0, #2.0; lsr z0.s, z0.s, #1`
/// the tracer claimed v0 still held 2.0 (0x4000000000000000) at the return.
/// An SVE write leaves the general registers alone: `_sve_and` returns 5.
@Test func anSVEWriteLeavesNoVectorValueStandingIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let recorder = ProbeRecorder()
    _ = try await Probe.recording(recorder) {
        try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path) }
    }
    let exits = Dictionary(recorder.records.filter { $0.event == .exitRegisters }.compactMap { record in
        record.function.map { ($0.name, record.jsonLine(includeNames: false)) }
    }, uniquingKeysWith: { a, _ in a })
    let alias = try #require(exits.first { $0.key.contains("sve_alias") }?.value, "\(exits.keys.sorted())")
    #expect(alias.contains("\"v0\":{\"expression\":{\"kind\":\"unknown\"}"), "\(alias)")
    #expect(!alias.contains("0x4000000000000000"), "\(alias)")
    let and = try #require(exits.first { $0.key.contains("sve_and") }?.value)
    #expect(and.contains("\"x0\":{\"expression\":{\"bits\":\"0x5\",\"kind\":\"immediate\"}"), "\(and)")
}
