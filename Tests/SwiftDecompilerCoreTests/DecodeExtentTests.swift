import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `objc` classifies property accessors by decoding each IMP to the next
/// boundary. Electron Framework has no LC_FUNCTION_STARTS, and boundaries
/// were function starts and IMPs only, so an accessor's extent ran to the
/// next IMP, megabytes away: `objc` passed 6 GB. Symbols bound it now, and
/// an extent past `maxBytes` is declined.
@Test func aDecodeByAddressStopsAtTheNextSymbolIfPresent() async throws {
    let path = "Fixtures/Sample/libNoFunctionStarts.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    #expect(machO.functionStarts.map { Array($0).isEmpty } ?? true)
    let symbols = Dictionary(machO.symbols.compactMap { symbol in
        Disassembler.sectionAddress(of: symbol).map { (symbol.name, $0) }
    }, uniquingKeysWith: { a, _ in a })
    let first = try #require(symbols["_first"]), second = try #require(symbols["_second"])
    let disassembler = Disassembler(preset: .default)
    let decoded = await withStableDependencies { await disassembler.disassembleFunctions(at: [first], in: machO) }
    let body = try #require(decoded.first { $0.startAddress == first })
    #expect(body.instructions.allSatisfy { $0.address < second }, "\(body.instructions.map(\.text))")

    let span = second - first
    let declined = await withStableDependencies {
        await disassembler.disassembleFunctions(at: [first], in: machO, maxBytes: span - 4)
    }
    #expect(declined.isEmpty)
    let kept = await withStableDependencies {
        await disassembler.disassembleFunctions(at: [first], in: machO, maxBytes: span, groupsAsyncFunclets: false)
    }
    #expect(kept.map(\.startAddress) == [first])
}

/// The accessor classification passes the limit: `accessorextent.m`'s
/// synthesized setter, decoded together with the 6 KB function after it,
/// read as custom and stayed in the header.
@Test func anAccessorDecodedPastTheLimitIsNotCalledCustomIfPresent() throws {
    let path = "Fixtures/Sample/libAccessorExtent.dylib"
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: binary.path) else { return }
    let process = Process(), pipe = Pipe()
    process.executableURL = binary
    process.arguments = ["objc", path]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let header = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(header.contains("@property(nonatomic) int value;"), "\(header)")
    #expect(!header.contains("setValue:"), "\(header)")
}
