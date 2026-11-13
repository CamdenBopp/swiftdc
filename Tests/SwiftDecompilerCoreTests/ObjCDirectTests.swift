import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A direct Objective-C method takes no `_cmd`: self in x0, its first
/// keyword in x1, at the call and in its own body (`objcdirect.m`). Read
/// like an ordinary method, `[box mix:5 with:9]` rendered
/// `[? mix:9 with:?]` and the body named its second argument `arg0`.
@Test(arguments: ["Fixtures/Sample/libObjCDirect.O0.dylib", "Fixtures/Sample/libObjCDirect.dylib"])
func aDirectObjCMethodTakesItsArgumentsFromX1IfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    // Filtered: the whole-file listing path does not name a local symbol
    // (`sub_688` for `-[DMBox mix:with:]`), an open defect of its own.
    func structured(_ name: String) async throws -> String {
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: name)
        }
        return try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    let variable = try await structured("_useVar")
    #expect(variable.contains("mix:arg1 with:arg2") || variable.contains("mix:(arg1 & 0xffffffff) with:(arg2 & 0xffffffff)"),
            Comment(rawValue: variable))
    guard path.hasSuffix(".O0.dylib") else { return }
    #expect(try await structured("_useTwo").contains("[? mix:5 with:9]"))
    #expect(try await structured("_useExtra").contains("[? extra:7]"))
    let body = try await structured("-[DMBox mix:with:]")
    #expect(body.contains("[self mix:(((arg0 & 0xffffffff) - 100) & 0xffffffff) with:(((arg1 & 0xffffffff) + 1) & 0xffffffff)]"),
            Comment(rawValue: body))
}
