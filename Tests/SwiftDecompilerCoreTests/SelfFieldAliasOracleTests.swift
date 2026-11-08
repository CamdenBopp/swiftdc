import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

@Test func selfFieldWriteInvalidatesPreviouslyLoadedRegisterValue() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-self-alias-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assembly = directory.appendingPathComponent("field-alias.s")
    let binary = directory.appendingPathComponent("libFieldAlias.dylib")
    try """
    .text
    .globl _probeOldFieldAfterStore
    _probeOldFieldAfterStore:
      ldr x8, [x0, #8]
      str xzr, [x0, #8]
      mov x0, x8
      ret
    .globl _probeOldFieldAfterPairStore
    _probeOldFieldAfterPairStore:
      ldr x8, [x0, #8]
      stp xzr, xzr, [x0, #8]
      mov x0, x8
      ret
    .globl _probeCurrentField
    _probeCurrentField:
      str x1, [x0, #8]
      ldr x0, [x0, #8]
      ret
    """.write(to: assembly, atomically: true, encoding: .utf8)
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
    compiler.arguments = ["-arch", "arm64", "-dynamiclib", assembly.path, "-o", binary.path]
    try compiler.run(); compiler.waitUntilExit()
    try #require(compiler.terminationStatus == 0)
    let library = try #require(dlopen(binary.path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: binary.path) }
    let memory = UnsafeMutablePointer<UInt64>.allocate(capacity: 3)
    defer { memory.deallocate() }
    memory.initialize(repeating: 0, count: 3)
    defer { memory.deinitialize(count: 3) }
    for name in ["probeOldFieldAfterStore", "probeOldFieldAfterPairStore"] {
        memory[1] = 0x1234
        let native = unsafeBitCast(try #require(dlsym(library, name)),
            to: (@convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64).self)
        #expect(native(memory) == 0x1234)
        #expect(memory[1] == 0)
        let function = try #require(functions.first { $0.symbol == "_\(name)" })
        let ret = try #require(function.instructions.last { $0.controlFlow == .return })
        let exit = ValueTracer().analyze(function,
            entry: .objectiveC(argumentCount: 0)).exitValues[ret.address]
        #expect(exit == nil || exit == .unknown,
            "\(name): stale field identity would report the new value as the old register: \(String(describing: exit))")
    }
    let current = try #require(functions.first { $0.symbol == "_probeCurrentField" })
    let ret = try #require(current.instructions.last { $0.controlFlow == .return })
    let exit = ValueTracer().analyze(current,
        entry: .objectiveC(argumentCount: 1)).exitValues[ret.address]
    #expect(exit == .selfFieldValue(offset: 8))
}
