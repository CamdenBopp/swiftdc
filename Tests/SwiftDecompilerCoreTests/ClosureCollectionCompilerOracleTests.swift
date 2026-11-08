import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The compiler's own word for the closure-collection fixture's calling
/// convention, on the target swiftdc reads. Every other lowering test asks
/// swiftdc to agree with itself or with a table written from the docs. Here
/// swiftc emits LLVM IR for arm64-apple-macos at each optimization level,
/// and the `define` lines say how many words each parameter and result take
/// and in which bank, whatever SwiftLowering believes.
private let oracleFixtureSource = "Fixtures/Sample/closurecollections.swift"
private let oracleFixture = "Fixtures/Sample/libClosureCollections.dylib"
private let oracleFunctions = [
    "takeArray", "takeContiguous", "takeDictionary", "takeNested",
    "passArray", "passContiguous", "passDictionary", "passNested",
    "returnArray", "returnDictionary", "returnBuffer",
]

private enum OracleWord: Equatable { case integer, float }

private struct OracleSignature {
    let parameters: [OracleWord]
    let result: [OracleWord]
}

private func oracleWord(_ type: Substring) -> OracleWord? {
    switch type {
    case "ptr", "i1", "i8", "i16", "i32", "i64": .integer
    case "float", "double": .float
    default: nil
    }
}

/// The types in an IR list, `ptr readonly captures(none) %0, i64 %1`: each
/// entry's first word. An attribute can hold a comma of its own
/// (`captures(ret: address, provenance)`), so only a top-level one divides.
private func oracleWords(_ list: Substring) -> [OracleWord?] {
    var entries: [Substring] = []
    var depth = 0
    var start = list.startIndex
    for index in list.indices {
        switch list[index] {
        case "(": depth += 1
        case ")": depth -= 1
        case "," where depth == 0:
            entries.append(list[start ..< index])
            start = list.index(after: index)
        default: break
        }
    }
    if start < list.endIndex { entries.append(list[start...]) }
    return entries.map { $0.split(separator: " ").first.flatMap(oracleWord) }
}

/// `define swiftcc <result> @"<symbol>"(<parameters>) …`, by symbol. A word
/// this does not know stays nil in the list, so a shape nobody modelled
/// fails the comparison rather than dropping out of it. The list ends at the
/// line's last `)`: only `#0 {` follows it.
private func oracleSignatures(in ir: String) throws -> [String: OracleSignature] {
    var signatures: [String: OracleSignature] = [:]
    for line in ir.split(separator: "\n") where line.hasPrefix("define ") {
        guard let convention = line.range(of: " swiftcc "),
              let at = line.range(of: " @\"", range: convention.upperBound ..< line.endIndex),
              let close = line.range(of: "\"(", range: at.upperBound ..< line.endIndex),
              let end = line.range(of: ")", options: .backwards)
        else { continue }
        let symbol = String(line[at.upperBound ..< close.lowerBound])
        guard symbol.hasPrefix("$s18ClosureCollections") else { continue }
        var result = line[convention.upperBound ..< at.lowerBound]
        if result.hasPrefix("{"), result.hasSuffix("}") { result = result.dropFirst().dropLast() }
        let words = result == "void" ? [] : oracleWords(result)
        let parameters = oracleWords(line[close.upperBound ..< end.lowerBound])
        signatures[symbol] = OracleSignature(parameters: try parameters.map { try #require($0, "\(line)") },
                                             result: try words.map { try #require($0, "\(line)") })
    }
    return signatures
}

private func oracleIR(level: String, in directory: URL) throws -> String {
    let output = directory.appendingPathComponent("\(level).ll")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--sdk", "macosx", "swiftc", "-target", "arm64-apple-macos15.0",
                         "-parse-as-library", "-\(level)", "-emit-ir",
                         "-module-name", "ClosureCollections", oracleFixtureSource, "-o", output.path]
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0, "swiftc -\(level) -emit-ir")
    return try String(contentsOf: output, encoding: .utf8)
}

/// Whether the IR's words are what a lowering claims. `.unknown` agrees with
/// nothing: every type in the fixture is classified.
private func oracleAgrees(_ lowering: SwiftLowering, _ words: ArraySlice<OracleWord>) -> Bool {
    switch lowering {
    case .zeroSized: words.isEmpty
    case .oneInteger: words.elementsEqual([.integer])
    case .oneFloat: words.elementsEqual([.float])
    case .direct: words.count >= 2
    case .unknown: false
    }
}

@Test func closureCollectionLoweringMatchesTheCompilersIRIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: oracleFixture),
          FileManager.default.fileExists(atPath: oracleFixtureSource) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: oracleFixture) }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdc-oracle-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for level in ["Onone", "O", "Osize"] {
        let signatures = try oracleSignatures(in: try oracleIR(level: level, in: directory))
        // An IR format this no longer parses must not pass by comparing nothing.
        #expect(signatures.count == oracleFunctions.count, "\(level)")
        for name in oracleFunctions {
            let function = try #require(functions.first {
                $0.displayName.hasPrefix("ClosureCollections.\(name)(")
            }, "\(name)")
            let symbol = function.symbol.hasPrefix("_") ? String(function.symbol.dropFirst()) : function.symbol
            let signature = try #require(signatures[symbol], "\(level) \(symbol)")
            let analysisName = try #require(function.analysisName)
            let split = try #require(DisassembledFunction.splitSignature(analysisName))
            let range = try #require(DisassembledFunction.outermostArgumentListRange(of: split.head))
            let parameters = DisassembledFunction.splitTopLevelArguments(split.head[range])
                .map { SwiftLowering.of(Disassembler.parameterType($0)) }

            // Walk the IR words parameter by parameter. A `.direct` value's
            // width is not in its lowering: it takes what the one-word
            // parameters after it leave.
            var position = 0
            var integerRegisters: [String: Int] = [:]
            var everyParameterIsOneInteger = true
            for (index, lowering) in parameters.enumerated() {
                let after = parameters.count - index - 1
                let count = lowering == .direct ? signature.parameters.count - position - after : 1
                let end = min(position + max(count, 0), signature.parameters.count)
                #expect(oracleAgrees(lowering, signature.parameters[position ..< end]),
                        "\(level) \(name) parameter \(index): \(lowering)")
                if lowering == .oneInteger {
                    integerRegisters["x\(position)"] = index
                } else {
                    everyParameterIsOneInteger = false
                }
                position = end
            }
            #expect(position == signature.parameters.count, "\(level) \(name)")
            if everyParameterIsOneInteger {
                #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == integerRegisters,
                        "\(level) \(name)")
            }

            #expect(oracleAgrees(SwiftLowering.of(split.result), signature.result[...]), "\(level) \(name) result")
            let register = Disassembler.swiftReturnRegister(forReturnType: split.result)
            #expect(register == (signature.result == [.integer] ? .integer : nil), "\(level) \(name) result register")
        }
    }
}
