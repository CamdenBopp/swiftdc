import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `absolutesymbols.s`: `mask_bpp_shift` is an absolute symbol of -1, as in
/// pixman's NEON assembly, and `_abs_value` an absolute constant. The corpus
/// sweep found `xrefs` dead by SIGTRAP on six libraries (Emacs's and KiCad's
/// libpixman, Gqrx's libc++, KiCad's libcrypto, SDRangel's libavformat):
/// every symbol's value was converted to an address, and -1 is not one.
private let path = "Fixtures/Sample/libAbsoluteSymbols.dylib"

/// The fixture's symbol table entries, by name, and a way to read them.
private struct SymbolTable {
    var bytes: Data
    var entries: [String: Int] = [:]

    init?(_ bytes: Data) {
        self.bytes = bytes
        var cursor = 32, symtab: (symoff: Int, nsyms: Int, stroff: Int)?
        for _ in 0..<u32(16) {
            if u32(cursor) == 0x2 { symtab = (u32(cursor + 8), u32(cursor + 12), u32(cursor + 16)) }
            cursor += u32(cursor + 4)
        }
        guard let table = symtab else { return nil }
        for index in 0..<table.nsyms {
            let entry = table.symoff + index * 16, start = table.stroff + u32(entry)
            entries[String(decoding: bytes[start...].prefix { $0 != 0 }, as: UTF8.self)] = entry
        }
    }

    func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 }

    /// Overwrite `name`'s `n_value`.
    mutating func setValue(of name: String, to value: Data) {
        guard let entry = entries[name] else { return }
        bytes.replaceSubrange((entry + 8)..<(entry + 16), with: value)
    }
}

@Test func anAbsoluteSymbolIsNotAnAddressOnAnyEntryPointIfPresent() throws {
    let binary = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard let original = FileManager.default.contents(atPath: path), var table = SymbolTable(original),
          FileManager.default.fileExists(atPath: binary.path) else { return }
    // And a section symbol whose value is past 2^63: malformed, never a trap.
    table.setValue(of: "_caller", to: Data(repeating: 0xff, count: 8))
    let wide = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-wide-\(ProcessInfo.processInfo.processIdentifier).dylib")
    try table.bytes.write(to: wide)
    defer { try? FileManager.default.removeItem(at: wide) }
    for file in [path, wide.path] {
    for command in [["xrefs", "--unreferenced"], ["disasm"], ["disasm", "-f", "real"], ["disasm", "--structured"],
                    ["analyze"], ["dump"], ["interface"], ["layout"], ["objc"]] {
        let process = Process()
        process.executableURL = binary
        process.arguments = [command[0], file] + command.dropFirst()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .exit && process.terminationStatus == 0,
                "\(file) \(command): status \(process.terminationStatus), reason \(process.terminationReason.rawValue)")
    }
    }
}

/// A copy whose `_abs_value` equals `_real`'s address: a constant that
/// happens to match code. `_real` keeps its own name, unfolded.
@Test func anAbsoluteSymbolNamesNoFunctionIfPresent() async throws {
    guard let original = FileManager.default.contents(atPath: path), var table = SymbolTable(original) else { return }
    let real = try #require(table.entries["_real"]), constant = try #require(table.entries["_abs_value"])
    #expect(table.bytes[constant + 4] & 0x0e == 0x2, "_abs_value is N_ABS as built")
    table.setValue(of: "_abs_value", to: table.bytes[(real + 8)..<(real + 16)])

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-abs-\(ProcessInfo.processInfo.processIdentifier).dylib")
    try table.bytes.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let machO = try BinaryLoader.load(path: url.path)
    let functions = await withStableDependencies { await Disassembler(preset: .default).disassemble(machO: machO) }
    let address = UInt64(table.u32(real + 8))
    let heading = functions.first { $0.startAddress == address }?.symbol
    #expect(heading == "_real", "\(String(describing: heading))")
}
