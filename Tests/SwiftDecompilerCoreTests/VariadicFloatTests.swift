import Testing
import Foundation
@testable import SwiftDecompilerCore

/// On Apple arm64 a double passed to a variadic function is its bits in one
/// eight-byte stack slot. A format call printed those bits, so
/// `[NSString stringWithFormat:@"%f", 1.5]` read `0x3ff8000000000000`. A
/// slot the format names floating, written by one eight-byte store with a
/// finite normal or zero constant, now renders as that double.
@Test func floatingVariadicSlotsRenderAsDoublesIfPresent() async throws {
    for level in ["O0", "O2"] {
        let fixture = "Fixtures/Sample/libVariadicFloat.\(level).dylib"
        guard FileManager.default.fileExists(atPath: fixture) else { return }
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture)
        }
        let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
        let expected = [
            #"[NSString stringWithFormat:@"%f", 1.5]"#,
            #"[NSString stringWithFormat:@"%ld %f %@ %g", ?, 2.25, ?, 0.1]"#,
            #"[NSString stringWithFormat:@"%f %f %f", 1e+300, 123456789.125, 1e-07]"#,
            // An infinity, a NaN and a subnormal keep their bits.
            #"[NSString stringWithFormat:@"%f %f %f %f %f", 0.0, -0.0, 0x7ff0000000000000, 0x7ff8000000000000, 1]"#,
            // The format and the argument disagree: the bits stay.
            #"[NSString stringWithFormat:@"%f", 3]"#,
            #"[NSString stringWithFormat:@"%d", 0x3ff8000000000000]"#,
            ", 1.5, 2.5, 3.5, 4.5, 0.5)",
            level == "O0" ? #"__snprintf_chk(?, 64, 0, -1, "%d %f %s", 3, 2.5, "x")"#
                : #"snprintf(?, 64, "%d %f %s", 3, 2.5, "x")"#,
            level == "O0" ? #"__sprintf_chk(?, 0, -1, "%f", 2.5)"# : #"sprintf(?, "%f", 2.5)"#,
        ]
        for line in expected {
            #expect(text.contains(line), "\(level): \(line)\n\(text)")
        }
    }
}

@Test func theFormatParserClassifiesEachConversion() {
    typealias Kind = DisassembledFunction.MessageSend.FormatArgumentKind
    func kinds(_ literal: String) -> [Kind]? { DisassembledFunction.MessageSend.formatArgumentKinds(literal) }
    #expect(kinds(#"@"%ld %f %@ %g""#) == [.integer, .floating, .pointer, .floating])
    #expect(kinds(#""%Lf %lf %.2e %G %a %A %F""#) == Array(repeating: .floating, count: 7))
    // Any other length modifier on a floating conversion is not a double.
    #expect(kinds(#""%hf %qf %jf""#) == [.unsized, .unsized, .unsized])
    #expect(kinds(#""%d %i %o %u %x %X %c %C %hhd %zu""#) == Array(repeating: .integer, count: 10))
    #expect(kinds(#"@"%s %S %p %n %@""#) == Array(repeating: .pointer, count: 5))
    #expect(kinds(#"@"%*f""#) == nil)
}

/// Only an eight-byte store of a finite normal or zero constant is a double.
@Test func aFloatingSlotIsADoubleOnlyWhenItsStoreProvesOne() {
    let floating: [DisassembledFunction.MessageSend.FormatArgumentKind] = [.floating]
    func types(_ value: AbstractValue, bytes: Int,
               kinds: [DisassembledFunction.MessageSend.FormatArgumentKind] = [.floating]) -> [String]? {
        Disassembler.formatSlotTypes(kinds, values: [value], storedBytes: [bytes])
    }
    #expect(types(.immediate(0x3ff8_0000_0000_0000), bytes: 8) == ["Swift.Double"])
    #expect(types(.immediate(0), bytes: 8) == ["Swift.Double"])
    // A narrower store does not cover the slot's eight bytes.
    #expect(types(.immediate(0x3ff8_0000_0000_0000), bytes: 4) == nil)
    #expect(types(.immediate(0x3ff8_0000_0000_0000), bytes: 0) == nil)
    #expect(types(.immediate(0x3ff8_0000_0000_0000), bytes: 8, kinds: [.integer]) == nil)
    #expect(types(.immediate(0x3ff8_0000_0000_0000), bytes: 8, kinds: [.unsized]) == nil)
    #expect(types(.immediate(Double.infinity.bitPattern), bytes: 8) == nil)
    #expect(types(.immediate(Double.nan.bitPattern), bytes: 8) == nil)
    #expect(types(.immediate(1), bytes: 8) == nil) // the smallest subnormal
    #expect(types(.unknown, bytes: 8) == nil)
    #expect(Disassembler.formatSlotTypes(floating + [.floating], values: [.unknown, .immediate(0x4004_0000_0000_0000)],
                                         storedBytes: [8, 8]) == ["", "Swift.Double"])
}
