import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The key path intrinsics take a fixed register list (their metadata
/// comes from the key path's class). With no signature, a call took the
/// registers live past them: `swift_getAtKeyPath(local_30, arg1, arg1,
/// arg2)` and `swift_setAtWritableKeyPath(arg0, arg1, local_28, arg3)`
/// (`keypathintrinsics.swift`, -O). swiftc retains a reference root
/// first, which clobbers x3, so the reference setter's live x3 comes from
/// assembly (`keypathintrinsics.s`: `mov x3, #9`).
@Test func keyPathIntrinsicsTakeTheirOwnArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libKeyPathIntrinsics.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let get = try structured("KeyPathIntrinsics.get3(")
    #expect(get.contains("swift_getAtKeyPath(local_30, arg1)\n"), Comment(rawValue: get))
    let set = try structured("KeyPathIntrinsics.set4(")
    #expect(set.contains("swift_setAtWritableKeyPath(arg0, arg1, local_28)\n"), Comment(rawValue: set))
    let setr = try structured("KeyPathIntrinsics.setr4(")
    #expect(setr.contains("swift_setAtReferenceWritableKeyPath(local_38, arg1, local_40)\n"), Comment(rawValue: setr))

    let asm = "Fixtures/Sample/libKeyPathIntrinsicsAsm.dylib"
    guard FileManager.default.fileExists(atPath: asm) else { return }
    let asmFunctions = try await withStableDependencies { try await Disassembler().disassemble(path: asm) }
    let reference = try #require(asmFunctions.first { $0.displayName.contains("setr") }).renderStructured()
    #expect(reference.contains("swift_setAtReferenceWritableKeyPath(?, ?, ?)\n"), Comment(rawValue: reference))

    // The getter's result buffer: x8 is an input it writes through, so the
    // 77 stored there before the call does not survive it.
    let slot = try #require(asmFunctions.first { $0.displayName.contains("getslot") })
    let analysis = ValueTracer().analyze(slot, entry: .swiftFunction(scalarArguments: [:]))
    let ret = try #require(slot.instructions.last { $0.controlFlow == .return })
    #expect(analysis.exitValues[ret.address] != .immediate(77), "\(String(describing: analysis.exitValues[ret.address]))")
}
