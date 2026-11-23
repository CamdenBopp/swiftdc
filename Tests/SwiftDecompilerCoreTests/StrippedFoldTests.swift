import Testing
import Foundation
@testable import SwiftDecompilerCore

/// strippedfold.swift, -O. Strip removes the evidence that a body is folded,
/// so the one name left at it reads as the only function there. The shapes a
/// fold actually lands on decline at a reference; the heading keeps the name,
/// which is true of the body.
private let unstripped = "Fixtures/Sample/libStrippedFold.dylib"
private let stripped = "Fixtures/Sample/libStrippedFold.stripped.dylib"

private func pseudo(_ path: String, _ filter: String) async throws -> String {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

private func wholeImage(_ path: String) async throws -> [DisassembledFunction] {
    try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: path) }
}

@Test func aCallIntoAFoldedConstantBodyDeclinesAfterStripIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    // `Local.other` and the specialization of `closureUser` share the body;
    // only `Local`'s vtable names it once the symbols are gone.
    let text = try await pseudo(stripped, "viaClosure")
    #expect(text.contains("sub_"), Comment(rawValue: text))
    #expect(!text.contains("Local"), Comment(rawValue: text))
    let witness = try await pseudo(stripped, "viaWitness")
    #expect(!witness.contains("Shape.method"), Comment(rawValue: witness))
}

@Test func theFilteredAndWholeImagePathsDeclineAlikeIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let whole = try await wholeImage(stripped).first { $0.displayName.contains("viaClosure") }
    let text = try #require(whole).renderPseudo()
    #expect(!text.contains("Local"), Comment(rawValue: text))
    let streamed = try await withStableDependencies {
        let machO = try BinaryLoader.load(path: stripped)
        return await Disassembler(preset: .default).disassembleStreaming(machO: machO) { function in
            function.displayName.contains("viaClosure") ? function.renderPseudo() : ""
        }
    }.joined()
    #expect(streamed.contains("viaClosure"), Comment(rawValue: streamed))
    #expect(!streamed.contains("Local"), Comment(rawValue: streamed))
}

/// A bare `ret` carrying a surviving export: the continuation `modify`
/// returns is the resume half folded with `Exported.w.setter`, and the symbol
/// table holds no second name to say so.
@Test func aReferenceToABareRetExportDeclinesAfterStripIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let text = try await pseudo(stripped, "Exported.w.modify")
    #expect(!text.isEmpty)
    #expect(!text.contains("w.setter"), Comment(rawValue: text))
}

@Test func theHeadingOfATrivialBodyKeepsItsNameIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let functions = try await wholeImage(stripped)
    let setter = try #require(functions.first { $0.displayName.contains("Exported.w.setter") })
    #expect(setter.render().contains("decline this name"), "\(setter.render())")
    let leaf = functions.filter { $0.source == .metadata && $0.displayName.contains("Local.method") }
    #expect(leaf.count >= 2, "\(leaf.map(\.displayName))")
}

/// Through a slot the owner is known, so the name stands.
@Test func aDispatchThroughSelfsSlotStillNamesATrivialBodyIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let functions = try await wholeImage(stripped)
    let text = functions.filter { $0.source == .metadata }.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(text.contains("self.method()"), Comment(rawValue: text))
}

@Test func aCallIntoABodyWithWorkOfItsOwnKeepsItsNameAfterStripIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let text = try await pseudo(stripped, "callsWork")
    #expect(text.contains("StrippedFold.work("), Comment(rawValue: text))
}

/// An image with no unlabeled function start has every partner in its symbol
/// table, so it suspects nothing. `Exported.w.setter` keeps its fold there as
/// a proven one, and a lone trivial body keeps its name.
@Test func anUnstrippedImageSuspectsNothingIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: unstripped) else { return }
    let functions = try await wholeImage(unstripped)
    #expect(!functions.contains { $0.render().contains("decline this name") })
    let spare = try await pseudo(unstripped, "Local.same")
    #expect(spare.contains("Local.same"), Comment(rawValue: spare))
}

/// libReconstruction -Osize has a function start with no symbol, but it keeps
/// its locals, so its outlined fragments, `mov`s and `ret`, keep their names.
@Test func anUnlabeledStartAloneSuspectsNothingIfPresent() async throws {
    let fixture = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await wholeImage(fixture)
    #expect(functions.contains { $0.source == .address })
    #expect(!functions.contains { $0.render().contains("decline this name") })
    #expect(functions.contains { $0.renderPseudo().contains("OUTLINED_FUNCTION_6(") })
}

/// Every function of a C dylib is an export: no local symbol, and no start
/// without a symbol, so `finished`, a bare `ret`, is still `finished`.
@Test func aDylibOfExportsSuspectsNothingIfPresent() async throws {
    let fixture = "Fixtures/Sample/libLoopSwitch.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let functions = try await wholeImage(fixture)
    #expect(!functions.contains { $0.render().contains("decline this name") })
    #expect(functions.contains { $0.renderPseudo().contains("finished(") })
}

@Suite struct TrivialBodyShapes {
    private let ret: UInt32 = 0xD65F_03C0

    @Test func aBareReturnIsTrivial() {
        #expect(TrivialBody.matches([ret, 0, 0]))
        // The section can end with it.
        #expect(TrivialBody.matches([ret]))
    }

    @Test func aConstantOrArgumentMovedToAResultRegisterIsTrivial() {
        let moves: [UInt32] = [
            0x5280_6140, // mov w0, #0x30a
            0xD280_0020, // mov x0, #1
            0x1280_0000, // mov w0, #-1
            0xAA01_03E0, // mov x0, x1
            0x2A01_03E0, // mov w0, w1
            0xB27F_03E0, // mov x0, #2 (orr with xzr)
            0x1E6E_1000, // fmov d0, #1.0
            0x1E60_4020, // fmov d0, d1
            0x2F00_E400, // movi d0, #0
            0x6F00_E400, // movi.2d v0, #0
            0x4EA1_1C20, // mov.16b v0, v1
        ]
        for move in moves {
            #expect(TrivialBody.matches([move, ret, 0]), "\(String(move, radix: 16))")
        }
        #expect(TrivialBody.matches([0xD280_0020, 0xD280_0041, ret])) // mov x0; mov x1; ret
    }

    @Test func aBodyThatComputesIsNotTrivial() {
        let bodies: [[UInt32]] = [
            [0x8B00_0020, ret, 0], // add x0, x1, x0
            [0xF940_0680, ret, 0], // ldr x0, [x20, #8]
            [0xF900_0280, ret, 0], // str x0, [x20]
            [0x9400_0010, ret, 0], // bl
            [0x1400_0010, ret, 0], // b
            [0xF280_0020, ret, 0], // movk x0, #1
            [0xD280_0020, 0x8B00_0020, ret], // mov x0, #1; add x0, x1, x0
            [0xD280_0020, 0xD280_0041, 0xD280_0062], // three moves, no return in reach
        ]
        for body in bodies {
            #expect(!TrivialBody.matches(body), "\(body.map { String($0, radix: 16) })")
        }
    }

    /// -Onone routes a constant through x8. Only that level emits the shape.
    @Test func aMoveThroughAScratchRegisterIsNotTrivial() {
        #expect(!TrivialBody.matches([0xD280_0028, 0xAA08_03E0, ret])) // mov x8, #1; mov x0, x8; ret
        #expect(!TrivialBody.matches([0xAA01_03F3, ret, 0])) // mov x19, x1; ret
    }

    @Test func noWordsAreNotAShape() {
        #expect(!TrivialBody.matches([]))
    }
}
