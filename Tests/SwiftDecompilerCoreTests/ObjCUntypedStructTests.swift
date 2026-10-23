import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The sends each method of `objc_untyped_struct.m` makes, as the pseudo view
/// spells them.
private func sends(in path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "SDUntypedStruct")
    }
    var lines: [String: String] = [:]
    for function in functions {
        lines[function.displayName] = function.renderPseudo().components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("[") }
            .joined(separator: "; ")
    }
    return lines
}

/// A send with no signature lays its explicit arguments out one x register
/// each from x2. When an implementation in the image takes a struct for the
/// selector, that layout is doubtful, the same way a floating-point
/// parameter already made it: `[u span:NSMakeRange(3, 4) count:5]` rendered
/// `span:3 count:4` (the range's location and length, from x2-x3), and at -O
/// `[u place:p flags:7]`, with p passed through in d0-d1, rendered `place:7`.
/// The arguments before the struct keep their registers (`count:5 span:?`),
/// but only up to the first struct in any implementation of the selector,
/// and `tally:` takes one long, so its send keeps its arguments.
@Test(arguments: ["Fixtures/Sample/libObjCUntypedStruct.dylib", "Fixtures/Sample/libObjCUntypedStruct.opt.dylib"])
func untypedSendOfAStructTakingSelectorDeclinesItsArgumentsIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let receiver = path.hasSuffix(".opt.dylib") ? "arg0" : "?"
    let found = try await sends(in: path)
    let expected: [String: String] = [
        "-[SDUntypedStructChild sendSpanTo:]": "[\(receiver) span:? count:?]",
        "-[SDUntypedStructChild sendPlaceTo:at:]": "[? place:? flags:?]",
        "-[SDUntypedStructChild sendTallyTo:]": "[\(receiver) tally:5]",
        "-[SDUntypedStructChild sendCountTo:]": "[\(receiver) count:5 span:?]",
        // Two implementations, the struct first in one: nothing is kept.
        "-[SDUntypedStructChild sendPairTo:]": "[\(receiver) pair:? with:? tail:?]",
        "-[SDUntypedStructChild span:count:]": "[super span:? count:?]",
    ]
    for (name, line) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(found[name] == line, "\(path) \(name): \(found[name] ?? "no function")")
    }
}

/// Which parameter types travel in one x register: the untyped layout's
/// assumption about every explicit argument.
@Test func onlyIntegerAndPointerTypesTakeOneXRegister() {
    for type in ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q", "B", "@", "@\"NSString\"", "#", ":", "*", "^v",
                 "^{CGRect={CGPoint=dd}{CGSize=dd}}"] {
        #expect(ObjCArgumentABI.takesOneXRegister(type), "\(type)")
    }
    for type in ["f", "d", "D", "{_NSRange=QQ}", "{CGPoint=dd}", "(U=iq)", "[4i]", "b3", "v", ""] {
        #expect(!ObjCArgumentABI.takesOneXRegister(type), "\(type)")
    }
}
