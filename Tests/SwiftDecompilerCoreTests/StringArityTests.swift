import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A Swift callee with a String, `String?` or `inout` parameter had no
/// argument layout, because the layout declined every parameter that is not
/// one scalar register. With nothing tracked its call rendered no arguments
/// (`takeTwo()` for `takeTwo(_: String, _: Int)`), and with 7 in x2 the
/// positional fallback read one argument per register (`takeTwo(?, ?, 7)`).
/// Each caller in `stringarity.swift` (-O) names its true call.
private let fixture = "Fixtures/Sample/libStringArity.dylib"

@Test func stringAndInoutParametersAreOneArgumentEachIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }
    func pseudo(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("StringArity.\(name)(") }).renderPseudo()
    }
    // Nothing tracked: one String, one Int.
    let two = try pseudo("callTwo")
    #expect(two.contains("StringArity.takeTwo(?, ?)"), "\(two)")
    let seven = try pseudo("callTwoSeven")
    #expect(seven.contains("StringArity.takeTwo(?, 7)"), "\(seven)")
    // Both words known: the literal is the one argument.
    let small = try pseudo("callTwoSmall")
    #expect(small.contains("StringArity.takeTwo(\"hi\", 7)"), "\(small)")
    let large = try pseudo("callTwoLarge")
    #expect(large.contains("StringArity.takeTwo(\"a literal longer than fifteen bytes\", 7)"), "\(large)")
    // The small strings a pair of integers could not be told from, in a slot
    // that holds a String.
    for (name, call) in [
        ("callTwoEmpty", #"StringArity.takeTwo("", 7)"#),
        ("callTwoNewline", #"StringArity.takeTwo("\n", 7)"#),
        ("callTwoAccent", #"StringArity.takeTwo("é", 7)"#),
    ] {
        let text = try pseudo(name)
        #expect(text.contains(call), "\(name): \(text)")
    }
    // x0 and x1 are the two words of a call that returns a String.
    let result = try pseudo("callTwoCallResult")
    #expect(result.contains("StringArity.takeTwo(StringArity.makeString(arg0), 7)"), "\(result)")
    // Its first word over another second word, and a call returning no
    // String, are not that String.
    for name in ["callTwoMixedResult", "callTwoWordsResult"] {
        let text = try pseudo(name)
        #expect(text.contains("StringArity.takeTwo(?, 7)"), "\(name): \(text)")
    }
    // An inout parameter is one address.
    let address = try pseudo("callInoutLoaded")
    #expect(address.contains("StringArity.takeInout(?, ?)"), "\(address)")
    // String? is two words, and nil (0 and 0) is not a literal.
    let optional = try pseudo("callOptString")
    #expect(optional.contains("StringArity.takeOptString(?, 7)"), "\(optional)")
    let none = try pseudo("callOptStringNil")
    #expect(none.contains("StringArity.takeOptString(?, 7)"), "\(none)")
    // A class method's self is x20, so its formals start at x0.
    let box = try pseudo("callBox")
    #expect(box.contains("StringArity.Box.put(?, 7)"), "\(box)")
}

/// Unit view of the footprints.
@Test func theLayoutSizesStringAndInoutParameters() {
    func slots(_ name: String) -> [Int]? {
        Disassembler.swiftCallArgumentSlots(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())?.map(\.registers)
    }
    #expect(slots("M.sink(Swift.String, Swift.Int) -> ()") == [2, 1])
    #expect(slots("M.sink(Swift.Optional<Swift.String>, Swift.Int) -> ()") == [2, 1])
    #expect(slots("M.bump(inout Swift.Int) -> ()") == [1])
    #expect(slots("M.bump(inout M.Big, Swift.String) -> ()") == [1, 2])
    // Four Strings and an Int need nine integer registers.
    #expect(slots("M.f(Swift.String, Swift.String, Swift.String, Swift.String) -> ()") == [2, 2, 2, 2])
    #expect(slots("M.f(Swift.String, Swift.String, Swift.String, Swift.String, Swift.Int) -> ()") == nil)
    // A typed throw may add an error pointer parameter.
    #expect(slots("M.f(Swift.String) throws(M.E) -> ()") == nil)
    // Still declined: a closure, an existential, a generic, and an instance
    // method of a type not known to be a class. (`Int?` is laid out in
    // `OptionalScalarTests`.)
    #expect(slots("M.f(() -> Swift.Int, Swift.Int) -> Swift.Int") == nil)
    #expect(slots("M.f(Swift.CustomStringConvertible, Swift.Int) -> Swift.Int") == nil)
    #expect(slots("M.f<A>(A, Swift.String) -> Swift.Int") == nil)
    #expect(slots("Swift.String.append(Swift.String) -> ()") == nil)
}

/// A String slot kept its two words only when they spelled a literal, so a
/// String field handed on whole rendered `?`: `Box.passLabel`
/// (`ldp x19, x20, [x20, #0x18]`, then `takeTwo(label, 7)`) read
/// `takeTwo(?, 7)`. Two words that are one String field's are that field
/// now. The field's first word over another second word, the two words of
/// a field that is no String, and a String that is only part of a field
/// are not, and stay `?`.
@Test func aStringFieldPassedWholeIsTheFieldIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "Box.pass")
    }
    func pseudo(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("StringArity.Box.\(name)(") }).renderPseudo()
    }
    let label = try pseudo("passLabel")
    #expect(label.contains("StringArity.takeTwo(self.label, 7)"), "\(label)")
    for name in ["passMixedLabel", "passSpan", "passFirstOfBoth"] {
        let text = try pseudo(name)
        #expect(text.contains("StringArity.takeTwo(?, 7)"), "\(name): \(text)")
    }
}

/// A String result's second word is an argument only in a String slot.
/// In a positional list (a value type's method, which is not laid out) it
/// trims like any unknown: `runtimearity.swift`'s `String.append` of a
/// `_typeName` call keeps reading `append(self: …, Swift._typeName(?, 0))`,
/// with no `?` for the high word after it.
@Test func aStringResultsSecondWordAloneIsNoArgumentIfPresent() async throws {
    let path = "Fixtures/Sample/libRuntimeArity.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("Swift._typeName(?, 0))") && !text.contains("Swift._typeName(?, 0), ?)"),
            Comment(rawValue: text.components(separatedBy: "\n").filter { $0.contains("_typeName") }.joined(separator: "\n")))
}

/// A String result's second word copied into x20 before a call is no
/// receiver: `string_high_receiver.s` keeps makeString's x1 in x22 and
/// moves it to x20 before `String.hasPrefix`, whose self travels in x2 and
/// x3, and the call read `hasPrefix(self: ?, "-", …)`.
@Test func aStringResultsSecondWordInX20IsNoReceiverIfPresent() async throws {
    let path = "Fixtures/Sample/libStringHighReceiver.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName.hasPrefix("High.keptValue()") }).renderPseudo()
    #expect(text.contains("Swift.String.hasPrefix(\"-\", High.makeString(3))") && !text.contains("self: ?"),
            Comment(rawValue: text))
}

/// A String slot's small string decodes whatever its words say, but only
/// when they are one: the ASCII bit agrees with the bytes, the bytes are
/// UTF-8, and nothing follows the count.
@Test func aStringSlotsSmallStringDecodesOnlyWhatItsWordsProve() {
    #expect(ValueTracer.decodeStringSmallString(lo: 0, hi: 0xe000_0000_0000_0000) == "")
    #expect(ValueTracer.decodeStringSmallString(lo: 0x0a, hi: 0xe100_0000_0000_0000) == "\n")
    #expect(ValueTracer.decodeStringSmallString(lo: 0xa9c3, hi: 0xa200_0000_0000_0000) == "é")
    // The ASCII bit set over a non-ASCII byte, and clear over ASCII ones.
    #expect(ValueTracer.decodeStringSmallString(lo: 0xa9c3, hi: 0xe200_0000_0000_0000) == nil)
    #expect(ValueTracer.decodeStringSmallString(lo: 0x6968, hi: 0xa200_0000_0000_0000) == nil)
    // Not UTF-8, a byte past the count, and no small-string discriminator.
    #expect(ValueTracer.decodeStringSmallString(lo: 0xc3, hi: 0xa100_0000_0000_0000) == nil)
    #expect(ValueTracer.decodeStringSmallString(lo: 0x6968, hi: 0xe100_0000_0000_0000) == nil)
    #expect(ValueTracer.decodeStringSmallString(lo: 0x6968, hi: 0x0200_0000_0000_0000) == nil)
}
