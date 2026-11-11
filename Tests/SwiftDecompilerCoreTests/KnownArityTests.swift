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
        // The bodies' own reads prove their parameters: `&h->delegate` is
        // `h + 8`. At -O2 copySlot and moveSlot tail-call without reading
        // theirs, which proves nothing, so they stay unknown.
        ("_loadSlot", "objc_loadWeakRetained", ["(arg0 + 8)"]),
        ("_copySlot", "objc_copyWeak", path.hasSuffix(".opt.dylib") ? ["?", "?"] : ["arg0", "arg1"]),
        ("_moveSlot", "objc_moveWeak", path.hasSuffix(".opt.dylib") ? ["?", "?"] : ["arg0", "arg1"]),
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
/// holds 1 (`libc_twins.c`, -O2 -fno-builtin). The call is an ordinary one,
/// and its body never reads the address it is passed (memset reads only
/// x1 and x2, memcpy reads x1 and x2 as numbers), so the local still holds
/// 1 after it: `sink(1)`, true of the source.
@Test func anInImageMemoryHelperTwinIsAnOrdinaryCallIfPresent() async throws {
    let path = "Fixtures/Sample/libLibcTwins.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for name in ["_useFill", "_useCopy"] {
        let text = try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
        #expect(argumentLists(of: "sink", in: text) == [["1"]], Comment(rawValue: text))
    }
}

/// A call to a printf-family name read its variadic arguments from the stack
/// by the format, whatever the callee: an in-image `printf(long, long)`
/// rendered `printf(?, …)` for `printf(x, 4)`, and an in-image
/// `fprintf(label, long, long)` dropped its 9 the same way (`libc_twins.c`).
/// The call now passes what the twin's body reads.
@Test func anInImagePrintfTwinTakesItsRegisterArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libLibcTwins.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
    }
    let printf = try text("_usePrintf")
    #expect(argumentLists(of: "printf", in: printf) == [["?", "4"]], Comment(rawValue: printf))
    let fprintf = try text("_useFprintf")
    let lists = argumentLists(of: "fprintf", in: fprintf)
    #expect(lists.count == 1 && lists.first?.count == 3 && lists.first?.last == "9", Comment(rawValue: fprintf))
}

/// Swift runtime entry points the table lacked, checked against their
/// headers. With nothing tracked each read as a call that takes nothing
/// (`swift_endAccess`, `swift_isUniquelyReferenced_nonNull_native`,
/// `_Unwind_Resume`), and the stack probe, which takes its size in x9 or
/// x15, read a stale x0 as an argument:
/// `__chkstk_darwin(type metadata accessor for ABISource.ABIOneWord(0))`.
@Test func swiftRuntimeEntryPointsTakeTheirHeadersParametersIfPresent() async throws {
    func listing(_ name: String) async throws -> String? {
        let path = "Fixtures/Sample/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return functions.map { $0.render() + "\n" + $0.renderPseudo() }.joined(separator: "\n")
    }
    guard let grid = try await listing("libGridSampler.opt.dylib"), let sample = try await listing("libSample.dylib"),
          let landing = try await listing("libLandingPadLoop.dylib"),
          let probe = try await listing("abi-source-resilient-oracle")
    else { return }
    #expect(grid.contains("→ swift_isUniquelyReferenced_nonNull_native  args(?)"))
    #expect(!grid.contains("→ swift_isUniquelyReferenced_nonNull_native\n"))
    #expect(sample.contains("→ swift_endAccess  args(?)"))
    #expect(!sample.contains("→ swift_endAccess\n"))
    #expect(landing.contains("_Unwind_Resume(?)"))
    #expect(probe.contains("→ __chkstk_darwin\n") && !probe.contains("__chkstk_darwin  args("))
}

/// A C function the SDK declares variadic with a fixed part and no format
/// (`int open(const char *, int, ...)`, `int fcntl(int, int, ...)`) read
/// `open(…)` with x0 and w1 set just before the call. Apple arm64 passes the
/// fixed arguments in registers and every variadic one on the stack, so the
/// fixed ones render from their registers at their declared widths, and the
/// uncounted rest is `…` (`variadic_calls.c`).
@Test func aDeclaredVariadicRendersItsFixedArgumentsIfPresent() async throws {
    let path = "Fixtures/Sample/libVariadicCalls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderStructured()
    }
    #expect(try text("_openReadOnly").contains("open(?, 0, …)"))
    #expect(try text("_openCreate").contains("open(?, 513, …)"))
    #expect(try text("_dupFrom").contains("fcntl(?, 0, …)"))
    // The int at its declared width: -1, not 0xffffffff.
    #expect(try text("_openNegative").contains("open(?, -1, …)"))
}
