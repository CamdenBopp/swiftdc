import Foundation
import Testing
@testable import SwiftDecompilerCore

// A block that leaves the function without a `ret` (a tail call, a call with
// no instruction after it) is a sink. The structurer's drain appends detached
// blocks as labels after the main walk, so a sink that ended silently read as
// falling through into whatever label came next. `tailcallsinks.c` and
// `tailcallsinks.swift` hold the shapes.

/// The structured body of one function, as trimmed lines.
private func structuredLines(_ path: String, _ filter: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
    let function = try #require(functions.first { $0.displayName == filter || $0.symbol == "_" + filter },
                                "\(filter) not found in \(path)")
    return function.renderStructured()
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
}

/// The line after the only line that starts with `statement`.
private func line(after statement: String, in lines: [String]) -> String? {
    let hits = lines.indices.filter { lines[$0].hasPrefix(statement) }
    #expect(hits.count == 1, "\(statement) occurs \(hits.count) times:\n\(lines.joined(separator: "\n"))")
    guard let hit = hits.first, hit + 1 < lines.count else { return nil }
    return lines[hit + 1]
}

/// `s9`: `b C` ends the loop's normal exit and `b B` its else arm. The drain
/// appended `loc_570: B()` right after `C()`, so C() read as continuing into
/// B(). Both tail calls now end with `return`.
@Test func tailCallSinkEndsWithReturnIfPresent() async throws {
    guard let lines = try await structuredLines("Fixtures/Sample/libTailCallSinks.dylib", "s9") else { return }
    let text = lines.joined(separator: "\n")
    #expect(line(after: "C(", in: lines) == "return", "\(text)")
    #expect(line(after: "B(", in: lines) == "return", "\(text)")
}

/// `v9`: the tail call's result is the function's result. With no signature
/// the value is not claimed, but the path still visibly ends.
@Test func valueTailCallSinkEndsWithReturnIfPresent() async throws {
    guard let lines = try await structuredLines("Fixtures/Sample/libTailCallSinks.dylib", "v9") else { return }
    #expect(line(after: "Q(", in: lines) == "return", "\(lines.joined(separator: "\n"))")
}

/// `n9`: `bl abort` is the last instruction. A `return` there would claim
/// abort returns and the function then returns; neither is proven. The
/// render says only that nothing follows.
@Test func callAtEndOfCodeEndsWithoutAReturnIfPresent() async throws {
    guard let lines = try await structuredLines("Fixtures/Sample/libTailCallSinks.dylib", "n9") else { return }
    let text = lines.joined(separator: "\n")
    #expect(line(after: "abort(", in: lines) == ControlFlowStructure.noFallThrough, "\(text)")
    #expect(line(after: "C(", in: lines) == "return", "\(text)")
    // The abort path claims no return: C()'s is the only one.
    #expect(lines.filter { $0.hasPrefix("return") }.count == 1, "\(text)")
    // `t9`: `bl t9.cold.1` (B, then a trap) is the last instruction too.
    guard let cold = try await structuredLines("Fixtures/Sample/libTailCallSinks.dylib", "t9") else { return }
    #expect(line(after: "t9.cold.1(", in: cold) == ControlFlowStructure.noFallThrough, "\(cold.joined(separator: "\n"))")
}

/// `i9`: `br x0` through f already reads as a jump; it gains nothing, and
/// `C()` still ends with `return`.
@Test func indirectJumpSinkIsUnchangedIfPresent() async throws {
    guard let lines = try await structuredLines("Fixtures/Sample/libTailCallSinks.dylib", "i9") else { return }
    let text = lines.joined(separator: "\n")
    let jump = try #require(lines.firstIndex { $0.contains("indirect_jump(") }, "\(text)")
    #expect(jump + 1 == lines.count || !lines[jump + 1].hasPrefix("return"), "\(text)")
    #expect(!lines.contains(ControlFlowStructure.noFallThrough), "\(text)")
    #expect(line(after: "C(", in: lines) == "return", "\(text)")
}

/// The Swift -O shape: both tail calls (`b fb`, `b fc`) end with `return`.
@Test func swiftTailCallSinkEndsWithReturnIfPresent() async throws {
    guard let lines = try await structuredLines("Fixtures/Sample/libTailCallSinks.opt.dylib", "TailCallSinks.s9(Swift.Int) -> ()") else { return }
    let text = lines.joined(separator: "\n")
    #expect(line(after: "TailCallSinks.fb(", in: lines) == "return", "\(text)")
    #expect(line(after: "TailCallSinks.fc(", in: lines) == "return", "\(text)")
}

/// `cbz x0, ret; <sink>; ret`: the sink's last instruction under each kind
/// of transfer, rendered on its own.
private func renderedSink(_ sink: Instruction, isAsync: Bool) -> [String] {
    let blocks = [
        BasicBlock(startAddress: 0x100, instructions: [
            Instruction(address: 0x100, text: "cbz x0, 0x200", controlFlow: .conditionalBranch, branchTarget: 0x200)
        ], successors: [0x200, 0x104]),
        BasicBlock(startAddress: 0x104, instructions: [sink], successors: sink.branchTarget.map { [$0] } ?? []),
        BasicBlock(startAddress: 0x200, instructions: [
            Instruction(address: 0x200, text: "ret", controlFlow: .return)
        ], successors: []),
    ]
    return ControlFlowStructure(blocks: blocks, isAsync: isAsync)
        .renderLines(header: "f() {", objcLine: nil)
        .map { $0.trimmingCharacters(in: .whitespaces) }
}

private func tailCall(_ facts: Instruction.Facts = .init()) -> Instruction {
    Instruction(address: 0x104, text: "b 0x9000", annotation: "→ work", controlFlow: .branch,
                branchTarget: 0x9000, callee: .kept("work"), facts: facts)
}

/// A synchronous tail call returns through its callee. An async one passes
/// a continuation, and a suspension or an executor hop resumes in another
/// funclet, so those claim no return.
@Test func tailCallSinkReturnsOnlyWhenSynchronous() {
    let sync = renderedSink(tailCall(), isAsync: false)
    #expect(line(after: "work(", in: sync) == "return", "\(sync)")
    let async = renderedSink(tailCall(), isAsync: true)
    #expect(line(after: "work(", in: async) == ControlFlowStructure.noFallThrough, "\(async)")
    let suspension = renderedSink(tailCall(.init(awaitBinding: "")), isAsync: false)
    #expect(line(after: "await work(", in: suspension) == ControlFlowStructure.noFallThrough, "\(suspension)")
    let hop = renderedSink(tailCall(.init(statement: .executorHop("?"))), isAsync: false)
    #expect(hop.contains(ControlFlowStructure.noFallThrough), "\(hop)")
    #expect(hop.filter { $0.hasPrefix("return") }.count == 1, "\(hop)")
    // A tail call already proven the exit (`return work()`) adds nothing.
    let proven = renderedSink(tailCall(.init(exit: .normal("work()"))), isAsync: false)
    #expect(line(after: "return work()", in: proven) == "}", "\(proven)")
}

/// An async function's tail call into the runtime (`b swift_continuation_await`)
/// suspends: nothing returns to the caller there, so no `return` follows it.
@Test func asyncRuntimeTailCallClaimsNoReturnIfPresent() async throws {
    guard let lines = try await structuredLines(
        "Fixtures/Sample/libRuntimeArity.dylib",
        "(1) suspend resume partial function for RuntimeArity.resumeFailing(Swift.Int, Swift.Int) async throws -> Swift.Int"
    ) else { return }
    #expect(line(after: "swift_continuation_await(", in: lines) == ControlFlowStructure.noFallThrough,
            "\(lines.joined(separator: "\n"))")
}

/// A stripped resume funclet has no async signature: the recovered funclet
/// alone makes its tail call a transfer that claims no return. An async
/// signature alone does too, where the funclet index found nothing.
@Test func strippedFuncletTailCallClaimsNoReturn() {
    func render(_ funclet: AsyncFuncletInfo?, name: String? = nil) -> [String] {
        let function = DisassembledFunction(
            symbol: "sub_100", demangledName: name, startAddress: 0x100,
            instructions: [
                Instruction(address: 0x100, text: "cbz x0, 0x108", controlFlow: .conditionalBranch, branchTarget: 0x108),
                tailCall(),
                Instruction(address: 0x108, text: "ret", controlFlow: .return),
            ],
            source: .address, asyncFunclet: funclet)
        return function.renderStructured().components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    let resume = AsyncFuncletInfo(parent: 0x50, parentName: nil, ordinal: 1, kind: .awaitReturn,
                                  predecessor: 0x50, chain: [0x50, 0x100])
    let funclet = render(resume)
    #expect(line(after: "work(", in: funclet) == ControlFlowStructure.noFallThrough, "\(funclet)")
    let plain = render(nil)
    #expect(line(after: "work(", in: plain) == "return", "\(plain)")
    let signed = render(nil, name: "M.f(Swift.Int) async -> ()")
    #expect(line(after: "work(", in: signed) == ControlFlowStructure.noFallThrough, "\(signed)")
}

/// A register branch with no callee and no jump target is an async
/// function's proven return. In a synchronous function nothing explains it.
@Test func registerBranchSinkReturnsOnlyInAsync() {
    let branch = Instruction(address: 0x104, text: "br x16", controlFlow: .branch)
    let async = renderedSink(branch, isAsync: true)
    #expect(async.filter { $0 == "return" }.count == 2, "\(async)")
    let sync = renderedSink(branch, isAsync: false)
    #expect(sync.filter { $0 == "return" }.count == 1, "\(sync)")
    #expect(sync.contains(ControlFlowStructure.noFallThrough), "\(sync)")
}
