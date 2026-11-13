import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The runtime-noise list matches by prefix, and `objc_autorelease` and
/// `objc_retain` also matched an `@autoreleasepool`'s push and pop and
/// `objc_retainBlock`, so the pool's scope vanished (`pool` read only
/// `work(…)`) and a block copied to the heap read as nothing
/// (`runtimestatements.m`, -O2).
@Test func runtimeCallsThatAreStatementsStayVisibleIfPresent() async throws {
    let path = "Fixtures/Sample/libRuntimeStatements.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let pool = try structured("_pool")
    #expect(pool.contains("objc_autoreleasePoolPush()") && pool.contains("objc_autoreleasePoolPop("), Comment(rawValue: pool))
    let heap = try structured("_heap")
    #expect(heap.contains("objc_retainBlock("), Comment(rawValue: heap))
    #expect(DisassembledFunction.isRuntimeNoise("objc_retain_x19"))
}

/// `[C new]` compiles to `objc_opt_new(C)`, and the runtime sends `+new`
/// when the class overrides it. It rendered `[[C alloc] init]`, the same as
/// `objc_alloc_init` (`optnew.m`: Counted overrides +new to count).
@Test func objcOptNewIsANewSendIfPresent() async throws {
    let path = "Fixtures/Sample/libOptNew.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let make = try #require(functions.first { $0.displayName == "_make" }).renderStructured()
    #expect(make.contains("[Counted new]"), Comment(rawValue: make))
    let makeInit = try #require(functions.first { $0.displayName == "_makeInit" }).renderStructured()
    #expect(makeInit.contains("[[Counted alloc] init]"), Comment(rawValue: makeInit))
}

