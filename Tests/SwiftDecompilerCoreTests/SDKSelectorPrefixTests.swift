import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The sends each method of `objc_sdk_selectors.m` makes, as the pseudo view
/// spells them.
private func sends(in path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "SDSDKSender")
    }
    var lines: [String: String] = [:]
    for function in functions {
        lines[function.displayName] = function.renderPseudo().components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("[") || $0.hasPrefix("return [") }
            .joined(separator: "; ")
    }
    return lines
}

/// A send with no signature, of a selector only the SDK declares, was laid
/// out one x register per argument with nothing to doubt it: at -O2
/// `[window setAlphaValue:alpha]`, alpha passed straight through in d0,
/// rendered `setAlphaValue:arg0` (the receiver, still in x2), and
/// `removeIndexesInRange:` read one word of the range. The public
/// frameworks' declarations now doubt the layout from their first struct or
/// floating argument on (`SDKSelectorPrefixes`), so the arguments before it
/// stay (`performSelector:arg1 withObject:arg2 afterDelay:?`) and a selector
/// that takes only integers keeps its argument.
@Test(arguments: ["Fixtures/Sample/libObjCSDKSelectors.dylib", "Fixtures/Sample/libObjCSDKSelectors.opt.dylib"])
func anSDKSelectorsStructOrFloatArgumentIsNotReadFromXIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let optimized = path.hasSuffix(".opt.dylib")
    let receiver = optimized ? "arg0" : "?"
    let found = try await sends(in: path)
    let expected: [String: String] = [
        "-[SDSDKSender dim:by:]": "[\(receiver) setAlphaValue:?]",
        "-[SDSDKSender move:x:y:]": "[\(receiver) setFrameOrigin:?]",
        "-[SDSDKSender unindex:at:length:]": "[\(receiver) removeIndexesInRange:?]",
        "-[SDSDKSender later:action:object:delay:]":
            optimized ? "[arg0 performSelector:arg1 withObject:arg2 afterDelay:?]"
                : "[? performSelector:? withObject:? afterDelay:?]",
        "-[SDSDKSender fetch:at:]": "return [\(receiver) objectAtIndex:arg1]",
    ]
    for (name, line) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(found[name] == line, "\(path) \(name): \(found[name] ?? "no function")")
    }
}

/// The generated table against the public declarations it was built from
/// (AppKit and Foundation headers), private classes left out: `setNeedsDisplayInRect:(NSRect)` and
/// `setAlphaValue:(CGFloat)` keep nothing, `performSelector:(SEL)
/// withObject:(id) afterDelay:(NSTimeInterval)` keeps two, and
/// `objectAtIndex:(NSUInteger)`, which takes only an integer, is absent.
@Test func theSDKSelectorTableMatchesThePublicDeclarations() {
    let table = SDKSelectorPrefixes.table
    #expect(table.count > 4_000)
    #expect(table["setNeedsDisplayInRect:"] == 0)
    #expect(table["setAlphaValue:"] == 0)
    #expect(table["removeIndexesInRange:"] == 0)
    #expect(table["performSelector:withObject:afterDelay:"] == 2)
    #expect(table["addAttribute:value:range:"] == 2)
    #expect(table["objectAtIndex:"] == nil)
    // Only a private class (`_NSSliderCellDataDrivenMetrics`) takes a struct
    // for `setState:`; NSControl's public declaration takes an integer.
    #expect(table["setState:"] == nil)
    #expect(table["countByEnumeratingWithState:objects:count:"] == nil)
}
