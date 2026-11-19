import Foundation
import Testing
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private let receiverTypeImages = [
    (level: "Onone", path: "Fixtures/Sample/libSwiftReceiverTypeList.Onone.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftReceiverTypeList.Onone-oracle"),
    (level: "O", path: "Fixtures/Sample/libSwiftReceiverTypeList.O.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftReceiverTypeList.O-oracle"),
    (level: "Osize", path: "Fixtures/Sample/libSwiftReceiverTypeList.Osize.dylib", oracle: "Fixtures/Sample/narrow-integer-return-SwiftReceiverTypeList.Osize-oracle"),
]

/// Select by independently demangled nlist entries, require every selected
/// start, and give analyzeEachFunction all starts so outlined helpers retain
/// their complete context. An empty API result cannot satisfy these checks.
private func receiverTypeStages(path: String, module: String, names: [String]) async throws -> [[DisassembledFunction]] {
    let image = try BinaryLoader.load(path: path)
    var entries: [String: UInt64] = [:]
    for symbol in image.symbols where symbol.offset != 0 && symbol.name.hasPrefix("_$s") {
        let name = try await demangleAsNode(String(symbol.name.dropFirst())).print(using: .default)
        for selected in names where name.hasPrefix(module + "." + selected + "(") {
            try #require(entries[selected] == nil)
            entries[selected] = UInt64(symbol.offset)
        }
    }
    try #require(entries.count == names.count)
    let selectedEntries = entries
    let addresses = Set(entries.values)
    let starts = Set(Disassembler().functionStarts(of: image))
    try #require(addresses.count == names.count && addresses.isSubset(of: starts))
    var stages: [[DisassembledFunction]] = []
    for stage in 0..<5 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: path)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: path, functionFilter: module + ".")
            case 3:
                let values: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { addresses.contains($0.startAddress) ? $0 : nil })
                return values.compactMap { $0 }
            default: return Array(await Disassembler().analyzeEachFunction(at: starts, in: image, transform: { $0 }).values)
            }
        }
        let selected = functions.filter { addresses.contains($0.startAddress) }
        try #require(selected.count == names.count && Set(selected.map(\.startAddress)) == addresses)
        stages.append(try names.map { name in try #require(selected.first { $0.startAddress == selectedEntries[name] }) })
    }
    return stages
}

@Test(arguments: ["Onone", "O", "Osize"])
func receiverExtractionKeepsFormalTypesAlignedAcrossAllAPIsIfPresent(level: String) async throws {
    let image = try #require(receiverTypeImages.first { $0.level == level })
    guard FileManager.default.fileExists(atPath: image.path) else { return }
    let names = ["gpCaller", "fpCaller", "gp2Caller", "gpFloatCaller", "gpBoolCaller"]
    for (stage, functions) in try await receiverTypeStages(path: image.path, module: "SwiftReceiverTypeList", names: names).enumerated() {
        for (name, function) in zip(names, functions) {
            let sites = function.instructions.filter {
                $0.callee?.contains(".consume") == true && ($0.controlFlow == .call || $0.controlFlow == .branch)
            }
            try #require(sites.count == 1)
            let site = try #require(sites.first)
            let argument = name == "gpFloatCaller" ? "3.5" : name == "gpBoolCaller" ? "true" : "((arg0 << 56) >>ˢ 56)"
            let receiver: String
            if level == "Onone" { receiver = name == "gp2Caller" ? "(?, ?)" : "?" }
            else if name == "gp2Caller" { receiver = "(arg1, arg2)" }
            else { receiver = name == "gpFloatCaller" || name == "gpBoolCaller" ? "arg0" : "arg1" }
            let context = Comment(rawValue: image.path + " API \(stage)\n" + function.renderStructured())
            #expect(site.callArguments == [argument], context)
            #expect(site.callSelf == receiver, context)
            for rendered in [function.renderPseudo(), function.renderStructured()] {
                #expect(rendered.contains("self: " + receiver + ", " + argument + ")"), Comment(rawValue: rendered))
            }
        }
    }
}

@Test func receiverTypeListNativeValuesAgreeWithSourceIfPresent() throws {
    for image in receiverTypeImages {
        guard FileManager.default.fileExists(atPath: image.oracle) else { continue }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: image.oracle)
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.split(separator: "\n").last == "PASS receiver type list: 774 observations", Comment(rawValue: output))
    }
}
