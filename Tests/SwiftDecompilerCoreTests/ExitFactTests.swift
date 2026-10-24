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

/// The first note `pseudoStatement` read as a statement that is not an exit
/// or a binding: a field write (a tuple of Swift or Objective-C fields
/// too), `self = …`, a yield or an executor hop.
private func isStatementNote(_ note: String) -> Bool {
    if note.hasPrefix("yield ") { return true }
    if note.hasPrefix("await hop_to_executor(") { return true }
    if note.hasPrefix("self = ") { return true }
    if note.hasPrefix("("), note.contains("self->") || note.contains("self."), note.contains(" = ") { return true }
    guard note.hasPrefix("self.") || note.hasPrefix("self->") else { return false }
    return [" = ", " += ", " -= "].contains(where: note.contains)
}

/// The rest of the first note that starts with `prefix`.
private func parsedNote(_ annotation: String?, after prefix: String) -> String? {
    notes(of: annotation)?.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
}

/// The items of a `loop-update: a | b` or `loop-init: a | b` note.
private func parsedList(_ annotation: String?, after prefix: String) -> [String] {
    parsedNote(annotation, after: prefix)?.components(separatedBy: " | ")
        .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
}

/// The note the structurer read as a field of self: `self.x` with no
/// assignment.
private func parsedFieldRead(_ annotation: String?) -> String? {
    notes(of: annotation)?.first {
        ($0.hasPrefix("self.") || $0.hasPrefix("self->")) && ![" = ", " += ", " -= "].contains(where: $0.contains)
    }
}

/// `pseudoStatement` as it read the notes before the facts, with the notes
/// split outside literals: the oracle the fact-based one must agree with.
private func textStatement(of insn: Instruction) -> String? {
    if let notes = notes(of: insn.annotation), notes.contains(DisassembledFunction.thenThrowNote) {
        let rest = notes.filter { $0 != DisassembledFunction.thenThrowNote }.joined(separator: "  ")
        var facts = insn.facts
        facts.thenThrows = false
        let base = Instruction(
            address: insn.address, text: insn.text, annotation: rest.isEmpty ? nil : rest,
            controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
            callArguments: insn.callArguments, callSelf: insn.callSelf,
            resultConsumed: insn.resultConsumed, sourceType: insn.sourceType, detail: insn.detail,
            calleeDisplayName: insn.calleeDisplayName, callee: .kept(insn.callee), facts: facts)
        return textStatement(of: base).map { "\($0)\nthrow ?" } ?? "throw ?"
    }
    if insn.isTrap { return "trap()" }
    if let notes = notes(of: insn.annotation) {
        if notes.contains(DisassembledFunction.unresolvedSwiftExitNote) { return DisassembledFunction.unresolvedSwiftExitStatement }
        if notes.contains(DisassembledFunction.normalSwiftExitNote) { return "return" }
    }
    if let notes = notes(of: insn.annotation) {
        let semantic = notes.first { note in
                note.hasPrefix("return ") || note.hasPrefix("throw ") || note.hasPrefix("let r") || isStatementNote(note)
            }
        if let semantic { return semantic }
    }
    return DisassembledFunction.callStatement(of: insn, hideRuntime: true)
}

/// Every fact equals its note read back from the final annotation, and the
/// statement built from the facts equals the one built from the notes, on
/// every instruction of every fixture. A rebuild that drops a fact, or a
/// producer that notes without one, shows here as a mismatch.
@Test func exitFactsMatchTheirAnnotationsOnTheFixturesIfPresent() async throws {
    let directory = "Fixtures/Sample"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    var mismatches: [String] = []
    var counts: [String: Int] = [:]
    for name in names.sorted() where name.hasSuffix(".dylib") || name == "sample.debug" || name == "sample.release" {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: "\(directory)/\(name)") }
        for function in functions {
            for insn in function.instructions {
                let at = "\(name) \(function.displayName) @\(String(insn.address, radix: 16))"
                func check<Value: Equatable>(_ kind: String, _ fact: Value, _ noted: Value, present: Bool) {
                    if present { counts[kind, default: 0] += 1 }
                    if fact != noted { mismatches.append("\(at): \(kind) \(fact), noted \(noted)") }
                }
                let annotation = insn.annotation
                check("exit", insn.exit, parsedExit(annotation), present: insn.exit != nil)
                check("binding", insn.binding, parsedBinding(annotation), present: insn.binding != nil)
                check("thenThrows", insn.thenThrows,
                      notes(of: annotation)?.contains(DisassembledFunction.thenThrowNote) == true, present: insn.thenThrows)
                check("statement", insn.statement?.text, notes(of: annotation)?.first(where: isStatementNote),
                      present: insn.statement != nil)
                check("await", insn.awaitBinding, parsedNote(annotation, after: "await="), present: insn.awaitBinding != nil)
                check("jump", insn.indirectJumpTarget, parsedNote(annotation, after: DisassembledFunction.indirectJumpNote),
                      present: insn.indirectJumpTarget != nil)
                check("condition", insn.condition, parsedNote(annotation, after: "cond: "), present: insn.condition != nil)
                check("loopUpdates", insn.loopUpdates, parsedList(annotation, after: "loop-update: "),
                      present: !insn.loopUpdates.isEmpty)
                check("loopInitializations", insn.loopInitializations, parsedList(annotation, after: "loop-init: "),
                      present: !insn.loopInitializations.isEmpty)
                check("fieldRead", insn.fieldRead, parsedFieldRead(annotation), present: insn.fieldRead != nil)
                check("selfDispatch", insn.isSelfDispatch, notes(of: annotation)?.contains("dispatch=self") == true,
                      present: insn.isSelfDispatch)
                let statement = DisassembledFunction.pseudoStatement(of: insn, hideRuntime: true)
                let oracle = textStatement(of: insn)
                if statement != oracle { mismatches.append("\(at): statement \(statement ?? "nil"), from notes \(oracle ?? "nil")") }
            }
        }
    }
    // About half of each count on 2026-10-22, so a producer that stops
    // writing its fact fails here even where the note is also gone.
    let floors = ["exit": 1300, "binding": 90, "thenThrows": 4, "statement": 240, "await": 13, "jump": 34,
                  "condition": 330, "loopUpdates": 5, "loopInitializations": 5, "fieldRead": 150, "selfDispatch": 21]
    for (kind, floor) in floors.sorted(by: { $0.key < $1.key }) {
        #expect(counts[kind, default: 0] >= floor, "\(kind): \(counts[kind, default: 0]) facts, expected at least \(floor)")
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(40).joined(separator: "\n"))")
}

/// Text that reads as an exit is not one: only the fact makes a statement,
/// so a note built by hand, or any annotation text, cannot fabricate a
/// `return`.
@Test func aReturnNoteWithoutTheFactIsNoStatement() {
    let noted = Instruction(address: 0x1000, text: "ret", annotation: "return 7", controlFlow: .return)
    #expect(DisassembledFunction.pseudoStatement(of: noted, hideRuntime: true) == nil)
    let proven = Instruction(address: 0x1000, text: "ret", annotation: "return 7", controlFlow: .return,
                             facts: .init(exit: .normal("7")))
    #expect(DisassembledFunction.pseudoStatement(of: proven, hideRuntime: true) == "return 7")
}

/// The same for every other statement note and call marker: text that
/// reads as one changes nothing without its fact.
@Test func statementNotesWithoutTheirFactsAreNoStatements() {
    func statement(_ text: String, _ annotation: String, _ flow: ControlFlow?, _ facts: Instruction.Facts = .init(),
                   callee: String? = nil) -> String? {
        DisassembledFunction.pseudoStatement(
            of: Instruction(address: 0x1000, text: text, annotation: annotation, controlFlow: flow,
                            branchTarget: callee == nil ? nil : 0x2000, callee: .kept(callee), facts: facts),
            hideRuntime: true)
    }
    #expect(statement("str x0, [x20]", "self.x = 1", nil) == nil)
    #expect(statement("str x0, [x20]", "self.x = 1", nil, .init(statement: .assignment("self.x = 1"))) == "self.x = 1")
    #expect(statement("bl _make", "make  self = b  yield &self.x  await hop_to_executor(?)", .call, callee: "make")
        == "make()")
    #expect(statement("bl _make", "make  await=r9", .call, callee: "make") == "make()")
    #expect(statement("bl _make", "make  await=r9", .call, .init(awaitBinding: "r9"), callee: "make")
        == "let r9 = await make()")
    #expect(statement("bl _make", "make  dispatch=self", .call, callee: "make") == "make()")
    #expect(statement("bl _make", "make  dispatch=self", .call, .init(isSelfDispatch: true), callee: "make")
        == "self.make()")
    #expect(statement("br x0", "jump=f", .branch) == nil)
    #expect(statement("br x0", "jump=f", .branch, .init(indirectJumpTarget: "f")) == "indirect_jump(f)")
    #expect(statement("br x0", "jump=f  await=r1", .branch, .init(indirectJumpTarget: "f")) == "indirect_jump(f)")
    #expect(statement("br x0", "jump=f  await=r1", .branch, .init(awaitBinding: "r1", indirectJumpTarget: "f"))
        == "let r1 = await indirect_call(f)")
}

/// Every field write is a statement, a tuple of Swift fields too.
@Test func aFieldWriteIsAStatement() {
    #expect(Disassembler.fieldWriteStatement("self.x = 1") == .assignment("self.x = 1"))
    #expect(Disassembler.fieldWriteStatement("self->_x = 1") == .assignment("self->_x = 1"))
    #expect(Disassembler.fieldWriteStatement("(self->_a, self->_b) = (1, 2)")
        == .assignment("(self->_a, self->_b) = (1, 2)"))
    #expect(Disassembler.fieldWriteStatement("(self.a, self.b) = (arg0, arg1)")
        == .assignment("(self.a, self.b) = (arg0, arg1)"))
}

/// The precedence the notes' order gave: an exit comes ahead of a yield
/// noted after it, and a statement (`self = [super init]`) ahead of the
/// binding of the same call's result.
@Test func exitAndBindingFactsKeepTheirPrecedence() {
    let exit = Instruction(
        address: 0x1000, text: "ret", annotation: "return 1  yield &self.x", controlFlow: .return,
        facts: .init(exit: .normal("1"), statement: .yield("&self.x")))
    #expect(DisassembledFunction.pseudoStatement(of: exit, hideRuntime: true) == "return 1")
    let binding = Instruction.Binding(name: "r0", expression: "[super init]")
    let call = Instruction(
        address: 0x1000, text: "bl _objc_msgSendSuper2",
        annotation: "objc_msgSendSuper2  self = [super init]  \(binding.statement)", controlFlow: .call,
        facts: .init(binding: binding, statement: .selfInitialization("[super init]")))
    #expect(DisassembledFunction.pseudoStatement(of: call, hideRuntime: true) == "self = [super init]")
    let bound = Instruction(
        address: 0x1000, text: "bl _make", annotation: "make  \(binding.statement)", controlFlow: .call,
        facts: .init(binding: binding))
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
                        branchTarget: 0x2000, callee: .kept("work"), facts: .init(thenThrows: true)),
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
        controlFlow: .call, facts: .init(binding: binding, thenThrows: true))
    #expect(DisassembledFunction.pseudoStatement(of: call, hideRuntime: true) == "let r0 = make()\nthrow ?")
    let exit = Instruction(
        address: 0x1000, text: "ret", annotation: "return 1  then throw ?", controlFlow: .return,
        facts: .init(exit: .normal("1"), thenThrows: true))
    #expect(DisassembledFunction.pseudoStatement(of: exit, hideRuntime: true) == "return 1\nthrow ?")
    let function = DisassembledFunction(
        symbol: "fixture", demangledName: nil, startAddress: 0x1000,
        instructions: [call, Instruction(address: 0x1004, text: "ret", annotation: "return ?", controlFlow: .return,
                                         facts: .init(exit: .normal("?")))],
        source: .address)
    let sites = CallGraph.sites(of: function).instructions
    #expect(sites.first?.binding == binding && sites.first?.thenThrows == true)
    #expect(sites.last?.exit == .normal("?"))

    // Every other fact, through both.
    let every = Instruction.Facts(
        thenThrows: true, statement: .assignment("self.x = 1"), awaitBinding: "r1", indirectJumpTarget: "f",
        condition: "(a < b)", loopUpdates: ["i += 1"], loopInitializations: ["var i = 0"], fieldRead: "self.y",
        isSelfDispatch: true)
    let marked = Instruction(address: 0x1000, text: "bl _make", annotation: "make", controlFlow: .call,
                             branchTarget: 0x2000, callee: .kept("make"), facts: every)
    #expect(DisassembledFunction.pseudoStatement(of: marked, hideRuntime: true) == "self.x = 1\nthrow ?")
    var unassigned = every
    unassigned.statement = nil
    let awaited = Instruction(address: 0x1000, text: "bl _make", annotation: "make", controlFlow: .call,
                              branchTarget: 0x2000, callee: .kept("make"), facts: unassigned)
    #expect(DisassembledFunction.pseudoStatement(of: awaited, hideRuntime: true) == "let r1 = await self.make()\nthrow ?")
    let streamed = CallGraph.sites(of: DisassembledFunction(
        symbol: "fixture", demangledName: nil, startAddress: 0x1000, instructions: [marked], source: .address))
    #expect(streamed.instructions.first?.facts == every)
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
/// and the return and the binding were cut at the double space. So were
/// the field write, the jump target and the baked condition; each
/// `emit…Text` that holds a statement note printed the piece instead of
/// the call (twice when the literal's own `add` carried it too),
/// `emitAwaitText` was `let r9") = await …`, and `emitDispatchText` was a
/// call through `self`.
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
        "NoteText.emitFieldWriteText() -> ()": [#"NoteText.emit("a  self.x = 1")"#],
        "NoteText.emitIvarWriteText() -> ()": [#"NoteText.emit("a  self->x -= 1")"#],
        "NoteText.emitTupleWriteText() -> ()": [#"NoteText.emit("a  (self->a, b) = (1, 2)")"#],
        "NoteText.emitSelfInitText() -> ()": [#"NoteText.emit("a  self = b")"#],
        "NoteText.emitYieldText() -> ()": [#"NoteText.emit("a  yield &self.x")"#],
        "NoteText.emitHopText() -> ()": [#"NoteText.emit("a  await hop_to_executor(MainActor)")"#],
        "NoteText.emitAwaitText() -> ()": [#"NoteText.emit("a  await=r9")"#],
        "NoteText.emitDispatchText() -> ()": [#"NoteText.emit("a  dispatch=self")"#],
        "NoteText.Tally.remeasure() -> ()": [#"self.count = NoteText.measure("ok  done")"#],
        "NoteText.runHandler() -> ()": [#"indirect_jump(NoteText.handler("a  b"))"#],
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
    // The baked condition is whole: it was `if ((arg0 == "a) {`.
    let isLabel = functions.first { $0.displayName == "NoteText.isLabel(Swift.UnsafeRawPointer) -> ()" }
    let structured = isLabel?.renderStructured().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(structured?.dropFirst().first == #"if (arg0 == "a  b") {"#, "\(structured ?? [])")
    // The call graph's edge is a direct tail call, not a dispatch through
    // self (`xrefs` said a subclass override may run instead).
    let graph = CallGraph(functions: functions)
    let dispatchText = try #require(functions.first { $0.displayName == "NoteText.emitDispatchText() -> ()" })
    let edges = graph.callees(of: dispatchText.startAddress)
    #expect(edges.count == 1 && edges.allSatisfy { !$0.isSelfDispatch }, "\(edges)")
}

/// The structurer reads a branch's condition, a loop's induction updates
/// and declarations, a field read and `self = …` from the facts, so a note
/// alone changes nothing and a fact alone is enough.
@Test func theStructurerReadsBranchFactsNotNotes() {
    func render(withFacts: Bool) -> [String] {
        func insn(_ address: UInt64, _ text: String, note: String? = nil, flow: ControlFlow? = nil, to target: UInt64? = nil,
                  callee: String? = nil, proven: Instruction.Facts = .init()) -> Instruction {
            Instruction(address: address, text: text, annotation: withFacts ? nil : note, controlFlow: flow,
                        branchTarget: target, callee: .kept(callee), facts: withFacts ? proven : .init())
        }
        let function = DisassembledFunction(
            symbol: "fixture", demangledName: nil, startAddress: 0x1000,
            instructions: [
                insn(0x1000, "bl _objc_msgSendSuper2", note: "objc_msgSendSuper2  self = [super init]", flow: .call,
                     to: 0x3000, callee: "objc_msgSendSuper2", proven: .init(statement: .selfInitialization("[super init]"))),
                insn(0x1004, "cbz x0, 0x1030", flow: .conditionalBranch, to: 0x1030),
                insn(0x1008, "ldr x8, [x20, #0x10]", note: "self.flag", proven: .init(fieldRead: "self.flag")),
                insn(0x100c, "cbz x8, 0x1030", flow: .conditionalBranch, to: 0x1030),
                insn(0x1010, "cmp x9, #0xa"),
                insn(0x1014, "b.ge 0x1030", note: "cond: (i >= 10)  loop-update: i += 1  loop-init: var i = 0",
                     flow: .conditionalBranch, to: 0x1030,
                     proven: .init(condition: "(i >= 10)", loopUpdates: ["i += 1"], loopInitializations: ["var i = 0"])),
                insn(0x1018, "bl _work", note: "work", flow: .call, to: 0x2000, callee: "work"),
                insn(0x101c, "b 0x1010", flow: .branch, to: 0x1010),
                insn(0x1030, "ret", flow: .return),
            ], source: .address)
        return function.renderStructured().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    let proven = render(withFacts: true)
    let noted = render(withFacts: false)
    let fromFacts = ["if (self == 0) {", "if (self.flag == 0) {", "var i = 0", "while (i < 10) {", "i += 1"]
    for line in fromFacts {
        #expect(proven.contains(where: { $0.hasPrefix(line) }), "\(line) missing:\n\(proven.joined(separator: "\n"))")
        #expect(!noted.contains(where: { $0.hasPrefix(line) }), "\(line) from a note:\n\(noted.joined(separator: "\n"))")
    }
}
