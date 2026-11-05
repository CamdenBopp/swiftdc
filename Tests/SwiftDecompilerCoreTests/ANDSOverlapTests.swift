import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Native constant probes cover both widths, destination equal to the left,
/// right, both or neither source, four shifts and every ordinary NZCV consumer.
/// The real CPU supplies the result; this test does not reimplement flag math.
@Test func overlappingAndsFlagsAgreeWithNativeIfPresent() async throws {
    let path = "Fixtures/Sample/libANDSOverlap.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    let array = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "ANDSOverlap.case_")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: path)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    // Independently reconciled:1792 exports ==1792 LC_FUNCTION_STARTS.
    var wrongTraces: [String] = []
    var wrongRenders: [String] = []
    for (mode, functions) in [("array", array), ("filtered", filtered), ("streaming", streamed)] {
        try #require(functions.count == 1792)
        for function in functions {
            try #require(function.symbol.hasPrefix("_$s11ANDSOverlap"))
            let symbol = String(function.symbol.dropFirst())
            let native = unsafeBitCast(try #require(dlsym(library, symbol)),
                                      to: (@convention(c) () -> UInt64).self)
            let expected = native()
            #expect(expected <= 1)
            let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: [:]))
            let terminator = try #require(function.instructions.last)
            let value = try #require(analysis.exitValues[terminator.address])
            let actual = try ProbeValue.abstractValue(value).evaluateInteger(arguments: [])
            if actual != expected { wrongTraces.append("\(mode): \(function.displayName): read \(actual), native \(expected)") }
            let rendered = function.renderStructured()
            let statements = rendered.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if !statements.contains("return \(expected)") { wrongRenders.append("\(mode): \(function.displayName): \(rendered)") }
        }
    }
    print("ANDS overlap: functions=1792 modes=3 native-comparisons=5376 wrong-traces=\(wrongTraces.count) wrong-renders=\(wrongRenders.count)")
    #expect(wrongTraces.isEmpty, Comment(rawValue: wrongTraces.prefix(12).joined(separator: "\n")))
    #expect(wrongRenders.isEmpty, Comment(rawValue: wrongRenders.prefix(12).joined(separator: "\n")))
}
