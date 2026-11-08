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
    // A constant return reads no ivar: custom, kept. The synthesized one goes.
    if let constant = try header("Fixtures/Sample/libConstantGetter.dylib") {
        #expect(constant.contains("- (int)period;"), "\(constant)")
        #expect(!constant.contains("- (int)count;"), "\(constant)")
    }
}

/// The classifier on decoded bodies: a load from self and a return is
/// synthesized, a tail call to objc_msgSend is custom, code that runs off
/// the decoded prefix is unknown, a branch inside the body is custom, and a
/// constant return touches no ivar, so it is custom.
@Test func theAccessorClassifierReadsTheEntryBlock() throws {
    let engine = try #require(CapstoneEngine())
    func decode(_ words: [UInt32], callees: [Int: String] = [:]) -> DisassembledFunction {
        var data = Data()
        for word in words { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
        let instructions = engine.disassemble(data, address: 0x1000).enumerated().map { index, decoded in
            let insn = Disassembler.instruction(decoded: decoded)
            guard let callee = callees[index] else { return insn }
            return Instruction(address: insn.address, text: insn.text, annotation: "→ \(callee)",
                               controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                               detail: insn.detail, callee: .kept(callee))
        }
        return DisassembledFunction(symbol: "accessor", demangledName: nil, startAddress: 0x1000,
                                    instructions: instructions, source: .address)
    }
    let load: UInt32 = 0xb940_0800      // ldr w0, [x0, #8]
    let store: UInt32 = 0xb900_0802     // str w2, [x0, #8]
    let ret: UInt32 = 0xd65f_03c0
    let call: UInt32 = 0x9400_0400      // bl #0x1000 past
    let tail: UInt32 = 0x1400_0400      // b #0x1000 past
    #expect(ObjCDumper.isSynthesizedAccessor(decode([load, ret, call], callees: [2: "work"])) == true)
    #expect(ObjCDumper.isSynthesizedAccessor(decode([store, ret])) == true)
    #expect(ObjCDumper.isSynthesizedAccessor(decode([load, tail], callees: [1: "objc_msgSend"])) == false)
    #expect(ObjCDumper.isSynthesizedAccessor(decode([tail], callees: [0: "objc_getProperty"])) == true)
    // ldr w1, [x0, #12] then the end: unknown when the decode was cut at
    // the prefix, and when the extent ended there, a body with no return.
    #expect(ObjCDumper.isSynthesizedAccessor(decode([load, 0xb940_0c01]), prefixBytes: 8) == nil)
    #expect(ObjCDumper.isSynthesizedAccessor(decode([load, 0xb940_0c01]), prefixBytes: 4096) == false)
    // A send, then a call that does not return, at the end of the extent.
    #expect(ObjCDumper.isSynthesizedAccessor(decode([call, call], callees: [0: "objc_msgSend", 1: "abort"]),
                                             prefixBytes: 4096) == false)
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0xb400_0040, ret, ret])) == false) // cbz x0, +8
    #expect(ObjCDumper.isSynthesizedAccessor(decode([load, 0xb400_8000])) == false)     // cbz x0, out of the prefix
    #expect(ObjCDumper.isSynthesizedAccessor(decode([load, 0x1400_0002, 0xd503_201f, ret])) == false) // b over a nop
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0x1280_0000, ret])) == false)      // mov w0, #-1: a constant
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0xaa01_03e0, 0xb940_0800, ret])) == false) // mov x0, x1 first: not self
    // A Swift @objc thunk: self copied to x19, a runtime call, then a load
    // through the copy (`mov x19, x0; bl swift_beginAccess; ldr x0, [x19, x20]`).
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0xaa00_03f3, call, 0xf874_6a60, ret],
                                                    callees: [1: "swift_beginAccess"])) == true)
    // A non-fragile ivar: `add x8, x0, x8; ldr x0, [x8]`.
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0x8b08_0008, 0xf940_0100, ret])) == true)
    // -O0: self spilled and reloaded, `sub sp, sp, #0x10; str x0, [sp, #8];
    // ldr x8, [sp, #8]; ldr w0, [x8, #8]; add sp, sp, #0x10; ret`.
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0xd100_43ff, 0xf900_07e0, 0xf940_07e8, 0xb940_0900, 0x9100_43ff, ret])) == true)
    // A slot that held something else.
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0xd100_43ff, 0xf900_07e1, 0xf940_07e8, 0xb940_0900, 0x9100_43ff, ret])) == false)
    // A copy in a caller-saved register does not survive the call.
    #expect(ObjCDumper.isSynthesizedAccessor(decode([0xaa00_03e9, call, 0xf874_6920, ret],
                                                    callees: [1: "swift_beginAccess"])) == false)
}
