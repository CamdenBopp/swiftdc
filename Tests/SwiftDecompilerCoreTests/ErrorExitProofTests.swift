import Foundation
import Testing
@testable import SwiftDecompilerCore
import Ccapstone

@Test func aThrowingSignatureDoesNotProveANormalMachineValueExit() {
    let function = DisassembledFunction(symbol: "$s1M1fyS2iKF", demangledName: "M.f(Swift.Int) throws -> Swift.Int",
        startAddress: 0x1000, instructions: [], source: .symbol)
    #expect(!function.hasProvenMachineValueReturn)
}

@Test func lostErrorSpillCannotBecomeANormalUnknownReturnIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "Reconstruction.mightFail(") }
    let function = try #require(functions.first)
    let throwingCall = try #require(function.instructions.first { DisassembledFunction.calleeName(of: $0) == "swift_willThrow" })
    let exit = try #require(function.instructions.first { $0.address > throwingCall.address && $0.controlFlow == .return })
    #expect(!(exit.annotation?.contains("return ?") ?? false))
    for text in [function.renderStructured(), function.renderPseudo()] {
        #expect(!text.contains("swift_willThrow") || text.contains("machine_return()") || text.contains("throw ?"))
        #expect(!(exit.annotation?.contains("return ?") ?? false))
    }
}

@Test func rawThrowingRetDeclinesTheSourceExitKindInBothViews() {
    let function = DisassembledFunction(symbol: "$s1M1fyS2iKF", demangledName: "M.f(Swift.Int) throws -> Swift.Int",
        startAddress: 0x1000, instructions: [Instruction(address: 0x1000, text: "ret", controlFlow: .return)], source: .symbol)
    for text in [function.renderStructured(), function.renderPseudo()] {
        #expect(text.contains("machine_return()"))
        #expect(!text.contains("return ?"))
        #expect(!text.contains("throw ?"))
    }
}

@Test func authoredErrorFlagsClassifyFinalReturnsIfPresent() async throws {
    let path = "Fixtures/Sample/libErrorExitControls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for (member, wanted, forbidden) in [
        ("success", "return 13", "machine_return()"),
        ("error", "throw ?", "return 13"),
        ("unknownError", "machine_return()", "return 13"),
        ("unknownValue", "return ?", "machine_return()"),
        ("guardedSuccess", "return 13", "machine_return()"),
        ("guardedClobber", "machine_return()", "return 13"),
        ("guardedNarrow", "machine_return()", "return 13"),
        ("guardedJoin", "machine_return()", "return 13"),
        ("guardedOpaque", "machine_return()", "return 13"),
        ("opaqueBypass", "machine_return()", "return 13"),
        ("opaqueThrowBypass", "machine_return()", "throw ?"),
        ("untouched", "return 13", "machine_return()"),
        ("preservingCall", "return 13", "machine_return()"),
        ("throwingCall", "machine_return()", "return 13"),
        ("clobberingCall", "machine_return()", "return 13"),
        ("entryBackEdge", "machine_return()", "return 13"),
        ("spillReload", "return 13", "machine_return()"),
        ("spillClobber", "machine_return()", "return 13"),
        ("spillEscape", "machine_return()", "return 13"),
        ("registerCopy", "return 13", "machine_return()"),
        ("orphanJump", "machine_return()", "return 13"),
        ("untouchedOrZero", "return 13", "machine_return()"),
        ("mergedZeroEdge", "return 13", "machine_return()"),
        ("indirectThrow", "machine_return()", "return 13"),
    ] {
        let function = try #require(functions.first { $0.displayName.contains("." + member + "(") })
        if member == "unknownError" {
            #expect(function.instructions.last?.annotation?.contains("swift-exit=unknown") == true)
        }
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains(wanted), "\(member): \(text)")
            #expect(!text.contains(forbidden), "\(member): \(text)")
        }
    }
}


@Test func rawThrowingBranchesDeclineBothUnknownExitKinds() {
    // Neither input/error register is classified; each feasible machine path
    // returns through LR. A structured block must not assert a normal return.
    let function = DisassembledFunction(symbol: "$s1M1fyS2iKF",
        demangledName: "M.f(Swift.Int) throws -> Swift.Int", startAddress: 0x1000,
        instructions: [
            Instruction(address: 0x1000, text: "cbz x0, 0x1008", controlFlow: .conditionalBranch, branchTarget: 0x1008),
            Instruction(address: 0x1004, text: "ret", controlFlow: .return),
            Instruction(address: 0x1008, text: "ret", controlFlow: .return),
        ], source: .symbol)
    let text = function.renderStructured()
    #expect(text.contains("machine_return()"), Comment(rawValue: text))
    #expect(!text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "return" })
    #expect(!text.contains("return ?"))
}

@Test func unreachableAndVoidExitsAreClassifiedIfPresent() async throws {
    let path = "Fixtures/Sample/libErrorExitControls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    // The reachable `ret` leaves x21 untouched; the orphan one has no
    // modelled entry, so its x0 of 7 is never claimed as the result.
    let orphan = try #require(functions.first { $0.displayName.contains(".orphanReturn(") })
    let orphanText = orphan.renderPseudo()
    #expect(orphanText.contains("return 13"), Comment(rawValue: orphanText))
    #expect(orphanText.contains("machine_return()"), Comment(rawValue: orphanText))
    #expect(!orphanText.contains("return 7"), Comment(rawValue: orphanText))
    // A proven normal exit with nothing to return is a bare `return`.
    for name in [".voidExit(", ".voidBranch("] {
        let void = try #require(functions.first { $0.displayName.contains(name) })
        for text in [void.renderStructured(), void.renderPseudo()] {
            #expect(text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "return" }, Comment(rawValue: text))
            #expect(!text.contains("machine_return()"), Comment(rawValue: text))
        }
    }
}

/// An instruction Capstone did not decode may write anything, x21 included.
@Test func anUndecodedInstructionEndsANoErrorPath() {
    func points(_ instructions: [Instruction]) -> Set<UInt64> {
        let function = DisassembledFunction(symbol: "$s1M1fyS2iKF", demangledName: "M.f(Swift.Int) throws -> Swift.Int",
            startAddress: 0x1000, instructions: instructions, source: .symbol)
        return SwiftErrorExitProof.noErrorPoints(blocks: function.basicBlocks(), entry: 0x1000, key: "x21",
                                                 entryIsNoError: true) { _ in true }
    }
    let ret = Instruction(address: 0x1004, text: "ret", controlFlow: .return)
    #expect(points([Instruction(address: 0x1000, text: "ret", controlFlow: .return)]).contains(0x1000))
    #expect(!points([Instruction(address: 0x1000, text: ".long 0xdeadbeef"), ret]).contains(0x1004))
}

/// A function that catches a callee's error clears x21 before the call and
/// tests it after, but its own signature does not throw: its exits are
/// returns, never an unclassified Swift exit.
@Test func aNonThrowingCatcherKeepsOrdinaryReturns() {
    let function = DisassembledFunction(symbol: "$s1M1fyS2iF", demangledName: "M.f(Swift.Int) -> Swift.Int",
        startAddress: 0x1000, instructions: [
            Instruction(address: 0x1000, text: "mov x21, #0"),
            Instruction(address: 0x1004, text: "bl 0x2000", controlFlow: .call, branchTarget: 0x2000),
            Instruction(address: 0x1008, text: "cbnz x21, 0x1010", controlFlow: .conditionalBranch, branchTarget: 0x1010),
            Instruction(address: 0x100c, text: "ret", controlFlow: .return),
            Instruction(address: 0x1010, text: "ret", controlFlow: .return),
        ], source: .symbol)
    let text = function.renderStructured()
    #expect(!text.contains("machine_return()"), Comment(rawValue: text))
    #expect(text.contains("return"), Comment(rawValue: text))
}

/// `try typedPick(x) + 1` at -O selects the error branchlessly
/// (`cmp x21, #0; csel x21, x21, x8, eq; cinc x0, x0, eq`): its one `ret`
/// both returns and throws, so it is not a normal `return`.
@Test func aBranchlessErrorSelectIsNotANormalReturnIfPresent() async throws {
    for path in ["Fixtures/Sample/libReconstruction.opt.dylib", "Fixtures/Sample/libReconstruction.osize.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "Reconstruction.typedForward(")
        }
        let function = try #require(functions.first)
        #expect(function.instructions.contains { $0.detail?.id == AARCH64_INS_CSEL }, "\(path)")
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(text.contains("machine_return()"), "\(path): \(text)")
            #expect(!text.contains("return ?"), "\(path): \(text)")
        }
    }
}

/// An async resume whose success (`mov x20, #0`) and typed throw
/// (`mov w20, #1`) meet at one ResumeParent branch is neither a plain return
/// nor a plain throw.
@Test func aMergedAsyncErrorExitIsNotANormalReturnIfPresent() async throws {
    let path = "Fixtures/Sample/libTypedThrowsAwait.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let resume = try #require(functions.first {
        $0.displayName.contains("codeAsync") && $0.asyncFunclet?.ordinal == 2
    })
    for text in [resume.renderStructured(), resume.renderPseudo()] {
        #expect(text.contains("machine_return()"), Comment(rawValue: text))
        #expect(!text.contains("return ?"), Comment(rawValue: text))
    }
}

/// Exit notes ride on `ret` and on async ResumeParent branches (rewritten
/// to return flow); the name parser must never take one for a callee.
@Test func exitNotesAreNeverCalleeNamesIfPresent() async throws {
    for path in ["Fixtures/Sample/libErrorExitControls.dylib", "Fixtures/Sample/libTypedThrowsAwait.opt.dylib"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let noted = functions.flatMap(\.instructions).filter { $0.annotation?.contains("swift-exit=") == true }
        #expect(!noted.isEmpty, "\(path)")
        for insn in noted {
            #expect(DisassembledFunction.calleeName(of: insn).map { !$0.hasPrefix("swift-exit=") } ?? true,
                    "\(path) @ \(String(insn.address, radix: 16))")
        }
    }
}
