import Foundation
import Testing
@testable import SwiftDecompilerCore

private func pseudo(_ name: String, in path: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: name)
    }
    return try #require(functions.first { $0.displayName.hasPrefix(name) }).renderPseudo()
}

/// A runtime entry point of known C arity shows exactly its parameters.
/// `swift_errorRelease` whose object was unknown read `swift_errorRelease()`,
/// a call that takes nothing.
@Test func aKnownArityCallKeepsItsUnknownParametersIfPresent() async throws {
    guard let text = try await pseudo("SwiftErrorProbe.tryHidden(", in: "Fixtures/Sample/libSwiftErrorProbe.dylib")
    else { return }
    #expect(text.contains("swift_errorRelease(?)"), Comment(rawValue: text))
    #expect(!text.contains("swift_errorRelease()"), Comment(rawValue: text))
}

/// And no more than its parameters: `memset` read stale x3 and x4 as two
/// more arguments.
@Test func aKnownArityCallDropsRegistersPastItsParametersIfPresent() async throws {
    guard let text = try await pseudo("ABISource.ABIFiveWords.init(", in: "Fixtures/Sample/libABISource.dylib")
    else { return }
    #expect(text.contains("memset(local_38, 0, 40)"), Comment(rawValue: text))
    #expect(!text.contains("memset(local_38, 0, 40,"), Comment(rawValue: text))
}

/// The argument lists of every call to `callee` in `text`, each split at its
/// top-level commas: `[[]]` for one call that takes nothing.
private func argumentLists(of callee: String, in text: String) -> [[String]] {
    var lists: [[String]] = []
    var searchStart = text.startIndex
    while let found = text.range(of: callee + "(", range: searchStart..<text.endIndex) {
        searchStart = found.upperBound
        // A whole name: `objc_copyWeak(` must not match `_objc_copyWeak(`.
        if found.lowerBound > text.startIndex {
            let before = text[text.index(before: found.lowerBound)]
            if before.isLetter || before.isNumber || before == "_" { continue }
        }
        var depth = 1
        var index = found.upperBound
        while index < text.endIndex, depth > 0 {
            if text[index] == "(" { depth += 1 } else if text[index] == ")" { depth -= 1 }
            if depth > 0 { index = text.index(after: index) }
        }
        let inner = text[found.upperBound..<index]
        lists.append(inner.isEmpty ? [] : DisassembledFunction.splitTopLevelArguments(inner))
    }
    return lists
}

/// Entries the table had wrong against their headers, and entry points that
/// take nothing but printed whatever x0 held (`known_arity.c`). `exit(int)`
/// read `exit()`; `objc_loadWeakRetained(id *)` read a phantom second `?`,
/// and `objc_copyWeak`/`objc_moveWeak(id *, id *)` a phantom third; the
/// functions of no parameters read the stale `malloc(8)` as their argument.
@Test(arguments: ["Fixtures/Sample/libKnownArity.dylib", "Fixtures/Sample/libKnownArity.opt.dylib"])
func aKnownCArityMatchesTheHeaderIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let expected: [(function: String, callee: String, arguments: [String])] = [
        ("_quit", "exit", ["3"]),
        ("_loadSlot", "objc_loadWeakRetained", ["?"]),
        ("_copySlot", "objc_copyWeak", ["?", "?"]),
        ("_moveSlot", "objc_moveWeak", ["?", "?"]),
        ("_lastErrno", "__error", []),
        ("_mainOr", "pthread_main_np", []),
        ("_roll", "arc4random", []),
        ("_makeGroup", "dispatch_group_create", []),
        ("_endCatch", "objc_end_catch", []),
        ("_terminate", "objc_terminate", []),
    ]
    for (name, callee, arguments) in expected {
        guard let function = functions.first(where: { $0.displayName == name }) else {
            Issue.record("no \(name) in \(path)")
            continue
        }
        for (view, text) in [("pseudo", function.renderPseudo()), ("structured", function.renderStructured())] {
            #expect(argumentLists(of: callee, in: text) == [arguments], "\(path) \(name) \(view):\n\(text)")
        }
    }
}

/// `swift_unexpectedError(error, filenameStart, filenameLength, isAscii,
/// line)` takes five arguments (swift/include/swift/Runtime/Error.h:128).
/// The table gave it none, so a failed `try!` read `swift_unexpectedError()`
/// and lost the error and the location it reports (`forcedtry.swift`).
@Test(arguments: ["Fixtures/Sample/libForcedTry.dylib", "Fixtures/Sample/libForcedTry.opt.dylib"])
func aFailedForcedTryPassesItsFiveArgumentsIfPresent(path: String) async throws {
    guard let text = try await pseudo("ForcedTry.forced(", in: path) else { return }
    let lists = argumentLists(of: "swift_unexpectedError", in: text)
    #expect(lists.count == 1, Comment(rawValue: text))
    let arguments = lists.first ?? []
    #expect(arguments.count == 5, Comment(rawValue: text))
    // `isAscii` and the line of the `try!`, both constants at the call.
    #expect(arguments.suffix(2) == ["1", "17"], Comment(rawValue: text))
}

/// The known-arity table applied by name, so an in-image function sharing a
/// libc entry's name took the library's arity (`arity_twin.c`, -O2): its
/// `arc4random(long *, long)` rendered `arc4random()`, and the frame address
/// passed in x0 did not escape into it, so the local it writes read as the
/// value stored before the call (`sink(5)`; native 7). A call to an in-image
/// function is bounded by its own body, which also keeps a stale x2 out and
/// lets a relay read x0 and x1 through it; the table is for calls that leave
/// the image.
@Test func anInImageNameTwinIsNotGivenTheLibraryArityIfPresent() async throws {
    let path = "Fixtures/Sample/libArityTwin.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
    }
    let direct = try text("_useTwin")
    #expect(argumentLists(of: "arc4random", in: direct) == [["?", "7"]], Comment(rawValue: direct))
    let frame = try text("_useTwinFrame")
    #expect(argumentLists(of: "arc4random", in: frame) == [["local_18", "7"]], Comment(rawValue: frame))
    #expect(!frame.contains("sink(5)"), Comment(rawValue: frame))
    // Its body bounds a stale x2 out, and a relay reads x0 and x1 through it.
    let stale = try text("_useTwinStale")
    #expect(argumentLists(of: "arc4random", in: stale) == [["?", "7"]], Comment(rawValue: stale))
    let relayed = try text("_useRelay")
    #expect(argumentLists(of: "relay", in: relayed) == [["?", "5"]], Comment(rawValue: relayed))
}

/// The value tracker modelled any callee named `memset` or `memcpy` as the
/// stores it performs, so an in-image `memset` whose body writes nothing
/// made `useFill` render `sink(0)`, the fill byte, for a local that still
/// holds 1 (`libc_twins.c`, -O2 -fno-builtin). The call is now an ordinary
/// one that may write the local it receives.
@Test func anInImageMemoryHelperTwinIsAnOrdinaryCallIfPresent() async throws {
    let path = "Fixtures/Sample/libLibcTwins.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for name in ["_useFill", "_useCopy"] {
        let text = try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
        #expect(argumentLists(of: "sink", in: text).allSatisfy { $0.isEmpty || $0 == ["?"] }, Comment(rawValue: text))
    }
}
