import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An SDK send that returns an integer struct (NSRange, in x0 and x1)
/// leaves only one word in x0, so the send is not the value used:
/// `return [s rangeOfString:@"x"]` for `.location`, and an NSNotFound test
/// of the whole send (`objc_range_return.m`). The send stays a statement and
/// the word it left reads `?`.
@Test func anIntegerStructSendIsNotItsFirstWordIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCRangeReturn.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    for wrong in ["return [arg0 rangeOfString:@\"x\"]", "([arg0 rangeOfString:@\"x\"] + 1)",
                  "([arg0 rangeOfString:@\"q\"] != 0x7fffffffffffffff)", "self->_u = [arg0 selectedRange]"] {
        #expect(!text.contains(wrong), "\(wrong)\n\(text)")
    }
    #expect(text.contains("self->_u = ?"), Comment(rawValue: text))
    #expect(SDKSelectorReturns.table["rangeOfString:"] == "a")
}

/// A selector some public declaration returns as an integer struct is no
/// proven float either: `currentTime` is a double on AVAudioPlayer and a
/// CMTime (through x8) on AVPlayer, so v0 after an unknown receiver's send
/// is not claimed.
@Test func anIntegerStructDeclarationVetoesAFloatResult() {
    #expect(SDKSelectorReturns.table["currentTime"] == "a")
    #expect(!ObjCMetadataIndex(methods: [:], fieldMaps: [:]).selectorReturnsOneFloat("currentTime"))
}
