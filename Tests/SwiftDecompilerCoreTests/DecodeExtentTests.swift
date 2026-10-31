import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `objc` classifies property accessors by decoding each IMP to the next
/// boundary. Electron Framework has no LC_FUNCTION_STARTS, and boundaries
/// were function starts and IMPs only, so an accessor's extent ran to the
/// next IMP, megabytes away: `objc` passed 6 GB. Symbols bound it now, and
/// `prefixBytes` decodes only the start of an extent.
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
    let prefix = await withStableDependencies {
        await disassembler.disassembleFunctions(at: [first], in: machO, prefixBytes: span - 4, groupsAsyncFunclets: false)
    }
    #expect(prefix.first?.instructions.map(\.address) == body.instructions.dropLast().map(\.address))
}

/// Accessors are judged by the block their entry starts, over a 4 KB
/// prefix. `accessorextent.m`'s synthesized setter, decoded with the 6 KB
/// function after it, read as custom and stayed in the header;
/// `accessorextentcustom.m`'s custom getter in the same position must stay.
@Test func anAccessorIsJudgedByItsEntryBlockIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: binary.path) else { return }
    func header(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let process = Process(), pipe = Pipe()
        process.executableURL = binary
        process.arguments = ["objc", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text
    }
    if let synthesized = try header("Fixtures/Sample/libAccessorExtent.dylib") {
        #expect(synthesized.contains("@property(nonatomic) int value;"), "\(synthesized)")
        #expect(!synthesized.contains("setValue:"), "\(synthesized)")
    }
    if let custom = try header("Fixtures/Sample/libAccessorExtentCustom.dylib") {
        #expect(custom.contains("- (int)value;"), "\(custom)")
    }
}

/// The classifier on hand-built bodies: a load and a return is synthesized,
/// a tail call to objc_msgSend is custom, code that runs off the decoded
/// prefix is unknown, and a branch inside the body is custom.
@Test func theAccessorClassifierReadsTheEntryBlock() {
    func body(_ instructions: [Instruction]) -> DisassembledFunction {
        DisassembledFunction(symbol: "accessor", demangledName: nil, startAddress: 0x1000,
                             instructions: instructions, source: .address)
    }
    let load = Instruction(address: 0x1000, text: "ldr w0, [x0, #8]", controlFlow: .sequential)
    let ret = Instruction(address: 0x1004, text: "ret", controlFlow: .return)
    let junk = Instruction(address: 0x1008, text: "bl _work", controlFlow: .call, branchTarget: 0x3000, callee: .kept("work"))
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, ret, junk])) == true)
    let send = Instruction(address: 0x1004, text: "b _objc_msgSend", controlFlow: .branch, branchTarget: 0x2000,
                           callee: .kept("objc_msgSend"))
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, send, junk])) == false)
    // Running off the end: unknown when the decode was cut at the prefix;
    // custom when the extent ended there (Xcode's IDESceneKitEditor:
    // `-[SKEDocumentOperation title]` ends in a call that does not return).
    let more = Instruction(address: 0x1004, text: "ldr w1, [x0, #12]", controlFlow: .sequential)
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, more]), prefixBytes: 8) == nil)
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, more]), prefixBytes: 4096) == false)
    let abort = Instruction(address: 0x1004, text: "bl _abort", controlFlow: .call, branchTarget: 0x4000, callee: .kept("abort"))
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, abort]), prefixBytes: 4096) == false)
    let skip = Instruction(address: 0x1000, text: "cbz x0, 0x1008", controlFlow: .conditionalBranch, branchTarget: 0x1008)
    #expect(ObjCDumper.isSynthesizedAccessor(body([skip, Instruction(address: 0x1004, text: "ret", controlFlow: .return),
                                                   Instruction(address: 0x1008, text: "ret", controlFlow: .return)])) == false)
    // A conditional branch out of the decoded prefix, as its last word.
    let away = Instruction(address: 0x1004, text: "cbz x0, 0x5000", controlFlow: .conditionalBranch, branchTarget: 0x5000)
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, away])) == false)
    // A jump to later in the body.
    let jump = Instruction(address: 0x1004, text: "b 0x100c", controlFlow: .branch, branchTarget: 0x100c)
    #expect(ObjCDumper.isSynthesizedAccessor(body([load, jump, Instruction(address: 0x1008, text: "nop", controlFlow: .sequential),
                                                   Instruction(address: 0x100c, text: "ret", controlFlow: .return)])) == false)
}
