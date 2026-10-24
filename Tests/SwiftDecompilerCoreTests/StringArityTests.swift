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
    // x0 is the call's first result word; the second is not tracked, so the
    // String is not proven to be that call's.
    let result = try pseudo("callTwoCallResult")
    #expect(result.contains("StringArity.takeTwo(?, 7)"), "\(result)")
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
