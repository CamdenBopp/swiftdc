import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A `ret` whose value was not recovered used to render as a bare `return`, even
/// for a function whose signature says `-> Swift.Int`. That reads as "returns
/// nothing" when it means "we did not recover what it returns" — and it
/// contradicts the tool's own contract that an unprovable value renders `?`.
///
/// It was not a rare corner: bare returns were roughly 45% of all returns in the
/// fixture (121 bare vs 143 with a value).
///
/// The fix is one-sided on purpose. `return ?` is printed only where the
/// signature PROVES a value exists; anything unrecognisable keeps the bare form,
/// because asserting a value that is not there would be its own fabrication.

// MARK: - Signature classification (unit)

@Test func provenValueReturningSignaturesAreRecognised() {
    let cases = [
        "Reconstruction.threeWay(Swift.Int) -> Swift.Int",
        "Reconstruction.castToString(Any) -> Swift.Optional<Swift.String>",
        "Reconstruction.Priority.rawValue.getter : Swift.Int",
    ]
    for name in cases {
        #expect(
            DisassembledFunction.signatureReturnsValue(displayName: name, objcSignature: nil),
            "should be recognised as value-returning: \(name)"
        )
    }
}

@Test func voidAndUnknownSignaturesDeclineToClaimAValue() {
    let cases = [
        "Reconstruction.Counter.advance() -> ()",
        "Reconstruction.Direction.hash(into: inout Swift.Hasher) -> ()",
        "dispatch thunk of Sample.Widget.reset() -> ()",
        "sample.someThing() -> Swift.Void",
        // Unrecognisable: no signature at all. Declining here is the point —
        // these are the majority of real output on a stripped binary.
        "sub_100001234",
        "lazy protocol witness table accessor for type Reconstruction.Direction",
        // A setter yields nothing, and must not be caught by the getter rule.
        "Reconstruction.Counter.value.setter : Swift.Int",
    ]
    for name in cases {
        #expect(
            !DisassembledFunction.signatureReturnsValue(displayName: name, objcSignature: nil),
            "should NOT be claimed as value-returning: \(name)"
        )
    }
}

@Test func objectiveCSignaturesDecideByTheirDeclaredReturnType() {
    // The ObjC branch is exercised here rather than end-to-end: every ObjC method
    // in the fixture already recovers its return value, so no bare return reaches
    // this path in observed output. Unit coverage is what there is.
    #expect(DisassembledFunction.signatureReturnsValue(
        displayName: "-[SDObjCCounter incrementBy:]",
        objcSignature: "- (long long)incrementBy:(long long)arg0;"
    ))
    #expect(DisassembledFunction.signatureReturnsValue(
        displayName: "-[SDObjCCounter name]", objcSignature: "- (id)name;"
    ))
    #expect(!DisassembledFunction.signatureReturnsValue(
        displayName: "-[SDWidget reset]", objcSignature: "- (void)reset;"
    ))
    // A selector's colons must not be read as the Swift `.getter :` form.
    #expect(!DisassembledFunction.signatureReturnsValue(
        displayName: "-[SDWidget setLabel:]", objcSignature: "- (void)setLabel:(id)arg0;"
    ))
}

// MARK: - End to end

private let fixture = "Fixtures/Sample/libReconstruction.dylib"

private func structured(_ filter: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: fixture, functionFilter: filter)
    }
    return functions.map { $0.renderStructured() }.joined(separator: "\n")
}

@Test func anUnrecoveredValueReturnSaysSoIfPresent() async throws {
    // `threeWay` is a three-way branch whose result is a phi across arms; the
    // value is not recovered at -Onone. It must not read as though the function
    // returns nothing.
    guard let text = try await structured("threeWay") else { return }
    #expect(text.contains("-> Swift.Int"))
    #expect(text.contains("return ?"))
    #expect(text.range(of: #"(?m)^\s+return\s*$"#, options: .regularExpression) == nil)
}

@Test func aVoidFunctionKeepsItsBareReturnIfPresent() async throws {
    // The adversarial half: a genuinely void function returns nothing, so a bare
    // `return` is CORRECT there. Over-applying `?` would invent a missing value.
    guard let text = try await structured("Counter.advance") else { return }
    #expect(text.contains("-> ()"))
    #expect(text.range(of: #"(?m)^\s+return\s*$"#, options: .regularExpression) != nil)
    #expect(!text.contains("return ?"))
}

@Test func aThrowingFunctionsErrorExitKeepsItsBareReturnIfPresent() async throws {
    // A throwing function's error exit really does yield no value — the result
    // travels in x21. Whether an exit is the error path is not known per-block,
    // so these decline rather than assert a missing value on a throw path.
    guard let text = try await structured("mightFail") else { return }
    #expect(text.contains("throws -> Swift.Int"))
    #expect(!text.contains("return ?"))
}

@Test func everyRenderedQuestionReturnHasAValueReturningSignatureIfPresent() async throws {
    // The population-level guard: across the whole fixture, `return ?` must never
    // appear under a signature that yields nothing. A per-function test would not
    // notice a classifier that over-claims on some other shape.
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture)
    }

    var checked = 0
    var offenders: [String] = []
    for function in functions {
        let text = function.renderStructured()
        guard text.contains("return ?") else { continue }
        checked += 1
        if function.displayName.hasSuffix("-> ()") { offenders.append(function.displayName) }
    }

    #expect(offenders.isEmpty, "`return ?` under a void signature: \(offenders)")
    // Naming the floor, not just asserting emptiness: if recovery changes so that
    // nothing renders `return ?` any more, the check above passes vacuously.
    #expect(checked >= 5, "only \(checked) function(s) rendered `return ?` — expected several")
}
