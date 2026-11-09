import Foundation
import Testing
@testable import SwiftDecompilerCore

private func run(_ tool: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

/// A value witness of a concrete type (`destroy value witness for
/// Swift.Optional`) is named from a metadata accessor, which a stripped
/// binary keeps, so no function of the stripped toolchain library may name
/// fewer of them than its unstripped twin. Tracking the value-witness
/// table's size field of argument metadata (`[[arg - 8] + 0x40]`) made sp
/// symbolic where it sizes a stack allocation, a callee's restore of its
/// callee-saved registers went unproven, and eight functions lost all
/// their names (224 -> 128).
@Test func aStrippedLibraryKeepsItsConcreteValueWitnessesIfPresent() async throws {
    guard let swiftc = run("/usr/bin/xcrun", ["--find", "swiftc"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    else { return }
    let host = URL(fileURLWithPath: swiftc).deletingLastPathComponent()
        .appendingPathComponent("../lib/swift/host/libSwiftCompilerPluginMessageHandling.dylib").standardizedFileURL
    guard FileManager.default.fileExists(atPath: host.path) else { return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-witness-oracle-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stripped = directory.appendingPathComponent("lib.stripped.dylib")
    try FileManager.default.copyItem(at: host, to: stripped)
    try #require(run("/usr/bin/strip", ["-x", stripped.path]) != nil)

    func concreteWitnesses(_ path: String) async throws -> [UInt64: Int] {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return Dictionary(functions.map { function in
            (function.startAddress, function.renderStructured().components(separatedBy: " value witness for Swift.").count - 1)
        }, uniquingKeysWith: +)
    }
    let named = try await concreteWitnesses(host.path)
    let bare = try await concreteWitnesses(stripped.path)
    #expect(named.values.reduce(0, +) > 0)
    let lost = named.filter { bare[$0.key, default: 0] < $0.value }.keys.sorted()
    #expect(lost.isEmpty, "\(lost.map { String($0, radix: 16) })")
}
