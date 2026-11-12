import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A variadic SDK selector whose name has no `…WithFormat:`/`…WithObjects:`
/// suffix rendered as a fixed one, its stack-passed arguments dropped with no
/// `…`: `[s stringByAppendingFormat:@"+%ld"]` (`objc_variadic_selectors.m`).
/// The SDK's own declarations say which selectors are variadic.
@Test func aVariadicSDKSelectorKeepsItsVariadicPartIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCVariadicSelectors.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("[arg0 stringByAppendingFormat:@\"+%ld\", arg1]"), Comment(rawValue: text))
    #expect(text.contains("[NSException raise:@\"Name\" format:@\"bad %ld\", …]"), Comment(rawValue: text))
    #expect(text.contains("initWithFormat:@\"%ld\" locale:0, …]"), Comment(rawValue: text))
    #expect(SDKVariadicSelectors.all.contains("raise:format:"))
}
