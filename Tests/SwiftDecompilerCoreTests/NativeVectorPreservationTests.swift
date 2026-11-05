import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func vectorPreservationSummariesReachEveryAnalysisPathIfPresent() async throws {
    let path = "Fixtures/Sample/libVectorPreservation.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Caller = @convention(c) () -> Double
    for (member, length, expected) in [("stale", 5, 1.0), ("keptD", 5, 2.0), ("keptQ", 5, 2.0), ("nested", 6, 1.0)] {
        let symbol = try #require(dlsym(library, "$s15VectorSummaries\(length)\(member)SdyF"))
        #expect(unsafeBitCast(symbol, to: Caller.self)() == expected)
    }
    let full = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "VectorSummaries")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    // Eight function-start records and eight text exports independently
    // identify four public callers plus four outlined private helpers.
    #expect(full.count == 8)
    #expect(filtered.count == 4)
    #expect(streamed.count == 8)
    let expected = ["stale": "return 1.0", "keptD": "return 2.0", "keptQ": "return 2.0", "nested": "return ?"]
    for (mode, functions) in [("array", full), ("filtered", filtered), ("streaming", streamed)] {
        for (member, statement) in expected.sorted(by: { $0.key < $1.key }) {
            let name = "VectorSummaries.\(member)() -> Swift.Double"
            let function = try #require(functions.first { $0.displayName == name }, "\(mode): missing \(name)")
            let text = function.renderPseudo()
            let statements = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(statements.contains(statement), "\(mode): \(text)")
        }
    }
}
