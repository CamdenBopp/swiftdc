import Foundation
import Testing
@testable import SwiftDecompilerCore

/// An annotation's notes: split at two spaces outside a quoted literal.
/// Renderers split at every two spaces, literals included, which is how a
/// literal's text became a statement (`notetext.swift`).
private func notes(of annotation: String?) -> [String]? {
    guard let annotation else { return nil }
    var notes: [String] = []
    var note = ""
    var quoted = false
    var characters = annotation.makeIterator()
    var pending: Character?
    while let character = pending ?? characters.next() {
        pending = nil
        if quoted, character == "\\" {
            note.append(character)
            if let escaped = characters.next() { note.append(escaped) }
            continue
        }
        if character == "\"" { quoted.toggle() }
        if !quoted, character == " " {
            let next = characters.next()
            if next == " " {
                notes.append(note.trimmingCharacters(in: .whitespaces))
                note = ""
                continue
            }
            pending = next
        }
        note.append(character)
    }
    notes.append(note.trimmingCharacters(in: .whitespaces))
    return notes
}

/// The exit, binding and then-throw notes read back: the first `return `/
/// `throw ` note, overridden by a `swift-exit=` note; the first `let r`
/// note; a `then throw ?` note.
private func parsedExit(_ annotation: String?) -> Instruction.Exit? {
    guard let notes = notes(of: annotation) else { return nil }
    if notes.contains(DisassembledFunction.unresolvedSwiftExitNote) { return .unclassified }
    if notes.contains(DisassembledFunction.normalSwiftExitNote) { return .normal(nil) }
    for note in notes {
        if note.hasPrefix("return ") { return .normal(String(note.dropFirst("return ".count))) }
        if note.hasPrefix("throw ") { return .throw(String(note.dropFirst("throw ".count))) }
    }
    return nil
}

private func parsedBinding(_ annotation: String?) -> Instruction.Binding? {
    guard let note = notes(of: annotation)?.first(where: { $0.hasPrefix("let r") }),
          let assignment = note.range(of: " = ")
    else { return nil }
    return Instruction.Binding(
        name: String(note[note.index(note.startIndex, offsetBy: 4)..<assignment.lowerBound]),
        expression: String(note[assignment.upperBound...]))
}

/// `pseudoStatement` as it read the notes before the facts, with the notes
/// split outside literals: the oracle the fact-based one must agree with.
private func textStatement(of insn: Instruction) -> String? {
    if let notes = notes(of: insn.annotation), notes.contains(DisassembledFunction.thenThrowNote) {
        let rest = notes.filter { $0 != DisassembledFunction.thenThrowNote }.joined(separator: "  ")
        let base = Instruction(
            address: insn.address, text: insn.text, annotation: rest.isEmpty ? nil : rest,
            controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
            callArguments: insn.callArguments, callSelf: insn.callSelf,
            resultConsumed: insn.resultConsumed, sourceType: insn.sourceType, detail: insn.detail,
            calleeDisplayName: insn.calleeDisplayName, callee: .kept(insn.callee))
        return textStatement(of: base).map { "\($0)\nthrow ?" } ?? "throw ?"
    }
    if insn.isTrap { return "trap()" }
    if let notes = notes(of: insn.annotation) {
        if notes.contains(DisassembledFunction.unresolvedSwiftExitNote) { return DisassembledFunction.unresolvedSwiftExitStatement }
        if notes.contains(DisassembledFunction.normalSwiftExitNote) { return "return" }
    }
    if let notes = notes(of: insn.annotation) {
        let semantic = notes.first { note in
                if note.hasPrefix("return ") || note.hasPrefix("throw ") { return true }
                if note.hasPrefix("let r") { return true }
                if note.hasPrefix("yield ") { return true }
                if note.hasPrefix("await hop_to_executor(") { return true }
                if note.hasPrefix("self = ") { return true }
                if note.hasPrefix("("), note.contains("self->"), note.contains(" = ") { return true }
                guard note.hasPrefix("self.") || note.hasPrefix("self->") else { return false }
                return [" = ", " += ", " -= "].contains(where: note.contains)
            }
        if let semantic { return semantic }
    }
    return DisassembledFunction.callStatement(of: insn, hideRuntime: true)
}

/// Every exit, binding and then-throw fact equals its note read back from
/// the final annotation, and the statement built from the facts equals the
/// one built from the notes, on every instruction of every fixture. A
/// rebuild that drops a fact, or a producer that notes without one, shows
/// here as a mismatch.
@Test func exitFactsMatchTheirAnnotationsOnTheFixturesIfPresent() async throws {
    let directory = "Fixtures/Sample"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    var mismatches: [String] = []
    var exits = 0, bindings = 0, thenThrows = 0
    for name in names.sorted() where name.hasSuffix(".dylib") || name == "sample.debug" || name == "sample.release" {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: "\(directory)/\(name)") }
        for function in functions {
            for insn in function.instructions {
                let at = "\(name) \(function.displayName) @\(String(insn.address, radix: 16))"
                let exit = parsedExit(insn.annotation)
                let binding = parsedBinding(insn.annotation)
                let throwsAfter = notes(of: insn.annotation)?.contains(DisassembledFunction.thenThrowNote) == true
                if insn.exit != nil { exits += 1 }
                if insn.binding != nil { bindings += 1 }
                if insn.thenThrows { thenThrows += 1 }
                if exit != insn.exit { mismatches.append("\(at): exit \(String(describing: insn.exit)), noted \(String(describing: exit))") }
                if binding != insn.binding { mismatches.append("\(at): binding \(insn.binding?.statement ?? "nil"), noted \(binding?.statement ?? "nil")") }
                if throwsAfter != insn.thenThrows { mismatches.append("\(at): thenThrows \(insn.thenThrows), noted \(throwsAfter)") }
                let statement = DisassembledFunction.pseudoStatement(of: insn, hideRuntime: true)
                let oracle = textStatement(of: insn)
                if statement != oracle { mismatches.append("\(at): statement \(statement ?? "nil"), from notes \(oracle ?? "nil")") }
            }
        }
    }
    #expect(exits > 500 && bindings > 5 && thenThrows > 0, "exits \(exits), bindings \(bindings), thenThrows \(thenThrows)")
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(40).joined(separator: "\n"))")
}

/// Text that reads as an exit is not one: only the fact makes a statement,
/// so a note built by hand, or any annotation text, cannot fabricate a
/// `return`.
@Test func aReturnNoteWithoutTheFactIsNoStatement() {
    let noted = Instruction(address: 0x1000, text: "ret", annotation: "return 7", controlFlow: .return)
    #expect(DisassembledFunction.pseudoStatement(of: noted, hideRuntime: true) == nil)
    let proven = Instruction(address: 0x1000, text: "ret", annotation: "return 7", controlFlow: .return, exit: .normal("7"))
    #expect(DisassembledFunction.pseudoStatement(of: proven, hideRuntime: true) == "return 7")
}

/// The precedence the notes' order gave: an exit comes ahead of a yield
/// noted after it, and `self = [super init]` ahead of the binding of the
/// same call's result.
@Test func exitAndBindingFactsKeepTheirPrecedence() {
    let exit = Instruction(
        address: 0x1000, text: "ret", annotation: "return 1  yield &self.x", controlFlow: .return, exit: .normal("1"))
    #expect(DisassembledFunction.pseudoStatement(of: exit, hideRuntime: true) == "return 1")
    let binding = Instruction.Binding(name: "r0", expression: "[super init]")
    let call = Instruction(
        address: 0x1000, text: "bl _objc_msgSendSuper2",
        annotation: "objc_msgSendSuper2  self = [super init]  \(binding.statement)", controlFlow: .call,
        binding: binding)
    #expect(DisassembledFunction.pseudoStatement(of: call, hideRuntime: true) == "self = [super init]")
    let bound = Instruction(
        address: 0x1000, text: "bl _make", annotation: "make  \(binding.statement)", controlFlow: .call, binding: binding)
    #expect(DisassembledFunction.pseudoStatement(of: bound, hideRuntime: true) == "let r0 = [super init]")
}

/// A throw after an instruction ends its path in the structured view: in
/// a branch arm that returns, no valueless `return` follows the `throw ?`.
/// (A function of one block renders flat, which never adds one.)
@Test func aThrowAfterTheLastStatementEndsItsArm() {
    let function = DisassembledFunction(
        symbol: "fixture", demangledName: nil, startAddress: 0x1000,
        instructions: [
            Instruction(address: 0x1000, text: "cbz x0, 0x100c", controlFlow: .conditionalBranch, branchTarget: 0x100c),
            Instruction(address: 0x1004, text: "bl _other", annotation: "other", controlFlow: .call,
                        branchTarget: 0x3000, callee: .kept("other")),
            Instruction(address: 0x1008, text: "ret", controlFlow: .return),
            Instruction(address: 0x100c, text: "bl _work", annotation: "work  then throw ?", controlFlow: .call,
                        branchTarget: 0x2000, callee: .kept("work"), thenThrows: true),
            Instruction(address: 0x1010, text: "ret", controlFlow: .return),
        ], source: .address)
    let lines = function.renderStructured().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let thrown = lines.firstIndex(of: "throw ?") else {
        Issue.record("no throw: \(lines.joined(separator: "\n"))")
        return
    }
    #expect(lines[thrown - 1] == "work()", "\(lines.joined(separator: "\n"))")
    #expect(lines[thrown + 1] != "return", "\(lines.joined(separator: "\n"))")
}

/// The rebuilds that keep notes keep their facts: the split of a statement
/// from the throw after it, and the slimmed sites a streaming call graph
/// holds.
@Test func noteKeepingRebuildsKeepTheFacts() {
    let binding = Instruction.Binding(name: "r0", expression: "make()")
    let call = Instruction(
        address: 0x1000, text: "bl _make", annotation: "make  \(binding.statement)  then throw ?",
        controlFlow: .call, binding: binding, thenThrows: true)
    #expect(DisassembledFunction.pseudoStatement(of: call, hideRuntime: true) == "let r0 = make()\nthrow ?")
    let exit = Instruction(
        address: 0x1000, text: "ret", annotation: "return 1  then throw ?", controlFlow: .return,
        exit: .normal("1"), thenThrows: true)
    #expect(DisassembledFunction.pseudoStatement(of: exit, hideRuntime: true) == "return 1\nthrow ?")
    let function = DisassembledFunction(
        symbol: "fixture", demangledName: nil, startAddress: 0x1000,
        instructions: [call, Instruction(address: 0x1004, text: "ret", annotation: "return ?", controlFlow: .return,
                                         exit: .normal("?"))],
        source: .address)
    let sites = CallGraph.sites(of: function).instructions
    #expect(sites.first?.binding == binding && sites.first?.thenThrows == true)
    #expect(sites.last?.exit == .normal("?"))
}

/// Several exits noted on one instruction: the first is carried, unless a
/// throwing function's verdict on the exit was noted.
@Test func anInstructionCarriesTheExitRenderersReadFirst() {
    #expect(Instruction.Exit.carried(from: []) == nil)
    #expect(Instruction.Exit.carried(from: [.normal("1"), .throw("?")]) == .normal("1"))
    #expect(Instruction.Exit.carried(from: [.normal("1"), .unclassified]) == .unclassified)
    #expect(Instruction.Exit.carried(from: [.throw("?"), .normal(nil)]) == .normal(nil))
    #expect(Instruction.Exit.carried(from: [.normal(nil), .unclassified]) == .unclassified)
}

/// A string literal that reads as a note once the annotation is split at
/// two spaces stays inside its statement (`notetext.swift`, -O). Read from
/// the split, `emitReturnText` was `return 1")` with its call gone,
/// `emitThrowText` gained a `throw ?`, `emitExitText` was a bare `return`,
/// and the return and the binding were cut at the double space.
@Test func literalsThatReadAsNotesStayInsideTheirStatementsIfPresent() async throws {
    let path = "Fixtures/Sample/libNoteText.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let expected: [String: [String]] = [
        "NoteText.emitReturnText() -> ()": [#"NoteText.emit("a  return 1")"#],
        "NoteText.emitScript() -> ()": [#"NoteText.emit("function f() {\n    return 1;\n}\n")"#],
        "NoteText.emitThrowText() -> ()": [#"NoteText.emit("then throw ?")"#],
        "NoteText.emitExitText() -> ()": [#"NoteText.emit("x  swift-exit=normal  y")"#],
        "NoteText.measured() -> Swift.Int": [#"return NoteText.measure("ok  done")"#],
        "NoteText.readLabelled() -> Swift.Int": [#"let r0 = NoteText.wide("Name  Value")"#, "return (r0.e + r0.a)"],
    ]
    for (name, body) in expected.sorted(by: { $0.key < $1.key }) {
        guard let function = functions.first(where: { $0.displayName == name }) else {
            Issue.record("no \(name)")
            continue
        }
        for (view, text) in [("pseudo", function.renderPseudo()), ("structured", function.renderStructured())] {
            let lines = text.components(separatedBy: "\n").dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(Array(lines) == body, "\(name) \(view):\n\(text)")
        }
        // JSON spells each instruction's statement the same way.
        let json = try #require(try JSONSerialization.jsonObject(with: Data([function].jsonString().utf8)) as? [[String: Any]])
        let statements = (json.first?["instructions"] as? [[String: Any]] ?? []).compactMap { $0["statement"] as? String }
        #expect(statements == body, "\(name) json: \(statements)")
    }
}
