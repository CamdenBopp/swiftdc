import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A plain `<` on operands typed UInt reads as unsigned. A signed machine
/// ordering on them (`csel gt`, `cset lt`) rendered that way, so
/// `Int(bitPattern: a) > Int(bitPattern: b) ? a : b` read exactly like
/// `max(a, b)`; and an unsigned `cset lo` between a UInt and an Int read as
/// Swift's mathematical mixed `<`, false for `0 < -1` where the machine says
/// true (`signedcompare.swift`, -O). Both now say which they are.
@Test func aComparisonAgainstItsOperandsTypesSaysItsSignednessIfPresent() async throws {
    let path = "Fixtures/Sample/libSignedCompare.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix(name) }, "no \(name)").renderStructured()
    }
    let sel = try structured("SignedCompare.ubitSel(")
    #expect(sel.contains("(arg1 >\u{02E2} arg0)"), Comment(rawValue: sel))
    let zero = try structured("SignedCompare.uSignedZero(")
    #expect(zero.contains(">=\u{02E2} 0)"), Comment(rawValue: zero))
    let mixS = try structured("SignedCompare.mixS(")
    #expect(mixS.contains("(arg0 <\u{02E2} arg1)"), Comment(rawValue: mixS))
    let mixU = try structured("SignedCompare.mixU(")
    #expect(mixU.contains("(arg0 <\u{1D41} arg1)"), Comment(rawValue: mixU))
    // Controls: an unsigned ordering on UInt operands stays a plain `>`.
    let umax = try structured("SignedCompare.umax(")
    #expect(umax.contains("((arg1 > arg0) ? arg1 : arg0)"), Comment(rawValue: umax))
}
