import Foundation
import Testing
import Demangling
@testable import SwiftDecompilerCore

// Entirely authored, analysis-only arm64 reductions. Public standard-library
// symbol spellings select real generic/dependent-name parsing; these tiny
// bodies deliberately do not implement those library functions. No application
// body, compiler/linker invocation, imports, or native execution is involved.
private enum GenericInputOp: Sendable {
    case word(UInt32), call(String)
}
private struct GenericInputBody: Sendable {
    let key: String
    let symbol: String
    let code: [GenericInputOp]
}
private struct GenericInputProgram: Sendable {
    let bodies: [GenericInputBody]
    let addresses: [String: UInt64]
    let words: [String: [UInt32]]

    init(_ bodies: [GenericInputBody]) {
        self.bodies = bodies
        var addresses: [String: UInt64] = [:]
        var cursor: UInt64 = 0x2000
        for body in bodies {
            precondition(addresses[body.key] == nil)
            addresses[body.key] = cursor
            cursor += UInt64(body.code.count * 4)
        }
        self.addresses = addresses
        var words: [String: [UInt32]] = [:]
        for body in bodies {
            words[body.key] = body.code.enumerated().map { index, op in
                switch op {
                case .word(let word): return word
                case .call(let target):
                    let from = addresses[body.key]! + UInt64(index * 4)
                    let displacement = Int64(addresses[target]!) - Int64(from)
                    precondition(displacement % 4 == 0 && displacement >= -(1 << 27) && displacement < (1 << 27))
                    return 0x9400_0000 | (UInt32(truncatingIfNeeded: displacement >> 2) & 0x03ff_ffff)
                }
            }
        }
        self.words = words
    }

    static func bytes(_ words: [UInt32]) -> Data {
        Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    }
    func functions() throws -> [UInt64: DisassembledFunction] {
        let engine = try #require(CapstoneEngine())
        return Dictionary(uniqueKeysWithValues: try bodies.map { body in
            let start = addresses[body.key]!
            let decoded = engine.disassemble(Self.bytes(words[body.key]!), address: start)
            let instructions = decoded.map(Disassembler.instruction(decoded:))
            let mangled = body.symbol.hasPrefix("_$s") ? String(body.symbol.dropFirst()) : body.symbol
            let demangled: String?
            if body.symbol.hasPrefix("_$s") {
                demangled = try demangleAsNode(mangled).print(using: .default)
            } else {
                demangled = nil
            }
            let function = DisassembledFunction(symbol: body.symbol, demangledName: demangled,
                startAddress: start, instructions: instructions, source: .symbol)
            try #require(["missing", "placedMissing", "extensionMissing"].contains(body.key) ? instructions.isEmpty : instructions.count == body.code.count)
            return (start, function)
        })
    }
    // A minimal ordinary-symbol MH_OBJECT. It is never linked or executed.
    func image() -> Data {
        let textOffset = 0x2000
        let text = Self.bytes(bodies.flatMap { words[$0.key]! })
        let symbolOffset = (textOffset + text.count + 15) & ~15
        let stringOffset = symbolOffset + bodies.count * 16
        var strings = Data([0]), indexes: [String: UInt32] = [:]
        for body in bodies {
            indexes[body.key] = UInt32(strings.count)
            strings.append(Data(body.symbol.utf8)); strings.append(0)
        }
        let size = stringOffset + strings.count
        func u32(_ value: UInt32) -> Data { Self.bytes([value]) }
        func u64(_ value: UInt64) -> Data { u32(UInt32(truncatingIfNeeded: value)) + u32(UInt32(value >> 32)) }
        func name(_ text: String) -> Data {
            let data = Data(text.utf8)
            return data + Data(repeating: 0, count: 16 - data.count)
        }
        var segment = u32(0x19) + u32(152) + name("__TEXT")
        segment += u64(0) + u64(UInt64(size)) + u64(0) + u64(UInt64(size))
        segment += Self.bytes([7, 5, 1, 0])
        segment += name("__text") + name("__TEXT") + u64(UInt64(textOffset)) + u64(UInt64(text.count))
        segment += Self.bytes([UInt32(textOffset), 2, 0, 0, 0x8000_0400, 0, 0, 0])
        let symtab = Self.bytes([2, 24, UInt32(symbolOffset), UInt32(bodies.count), UInt32(stringOffset), UInt32(strings.count)])
        var image = Self.bytes([0xfeed_facf, 0x0100_000c, 0, 1, 2, UInt32(segment.count + symtab.count), 0, 0])
        image += segment + symtab
        image += Data(repeating: 0, count: textOffset - image.count)
        image += text
        image += Data(repeating: 0, count: symbolOffset - image.count)
        for body in bodies {
            image += u32(indexes[body.key]!)
            image += Data([0x0f, 1, 0, 0])
            image += u64(addresses[body.key]!)
        }
        image += strings
        precondition(image.count == size)
        return image
    }
}

private let genericInputSymbols: [String: String] = [
    "extension": "_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ",
    "extensionMissing": "_$sSa10FoundationE36_unconditionallyBridgeFromObjectiveCySayxGSo7NSArrayCSgFZ",
    "array": "_$sSa6append10contentsOfyqd__n_t7ElementQyd__RszSTRd__lFs5UInt8V_SayAFGTg5",
    "missing": "_$sSa6append10contentsOfyqd__n_t7ElementQyd__RszSTRd__lFs6UInt16V_SayAFGTg5",
    "slice": "_$sSa6append10contentsOfyqd__n_t7ElementQyd__RszSTRd__lFs5UInt8V_s10ArraySliceVyAFGTg5",
    "set": "_$sSh9formUnionyyqd__n7ElementQyd__RszSTRd__lFSS_ShySSGTg5",
    // Existing public authored Specializations fixture's dependent-member form.
    "dependent": "_$s15Specializations10firstCounty7ElementQzSgxSlRzlFSaySiG_Tg5",
    // A real same-type-constrained specialization has no complete layout proof.
    "float": "_$sSa6append10contentsOfyqd__n_t7ElementQyd__RszSTRd__lFSd_SaySdGTg5",
    // Existing public authored fixture's provable scalar substitution control.
    "placed": "_$s15Specializations4bumpyxxSjRzlFSd_Tg5",
    "placedMissing": "_$s15Specializations4bumpyxxSjRzlFSi_Tg5",
    "zero": "_$s13GenericInputs4zeroxmylFSi_Tg5",
    "metadata": "_$s13GenericInputs12metadataOnlyxmylFSi_Tg5",
    "self": "_$s13GenericInputs3BoxV7observeyyFSi_Tg5",
    "sret": "_$s13GenericInputs4makexylFSi_Tg5",
    "possible": "_$sSh9formUnionyyqd__n7ElementQyd__RszSTRd__lFSi_ShySiGTg5",
]
// A nil argument list is not sufficient evidence that a zero-formal control
// reached its real callee. Require the canonical symbol and its typed resolved
// name on every route, including the unfiltered LLVM listing path.
private func genericInputExpectedName(_ target: String, in program: GenericInputProgram) throws -> String {
    let body = try #require(program.bodies.first { $0.key == target })
    try #require(body.symbol.hasPrefix("_$s"))
    #expect(!body.symbol.contains(" ") && !body.symbol.contains("("))
    return try demangleAsNode(String(body.symbol.dropFirst())).print(using: .default)
}
private func genericInputRequireResolvedCallee(
    _ call: Instruction, target: String, in program: GenericInputProgram
) throws {
    let expected = try genericInputExpectedName(target, in: program)
    let actual = try #require(DisassembledFunction.calleeName(of: call))
    #expect(actual == expected, Comment(rawValue: actual))
}
private func genericInputRenderWithResolvedNames(_ function: DisassembledFunction) -> String {
    // These claims contain actual typed callee names, never expected names or
    // fallback labels. They let the String-only wrapper carry fidelity evidence
    // back to the test without relying on assertions in its render callback.
    let claims = function.instructions.filter { $0.controlFlow == .call }.map {
        "// resolved callee: " + (DisassembledFunction.calleeName(of: $0) ?? "<unresolved>")
    }
    return function.renderPseudo() + "\n" + claims.joined(separator: "\n")
}
private func genericInputRequireStreamNames(_ rendered: [String], in program: GenericInputProgram) throws {
    for body in program.bodies where body.key.hasPrefix("caller_") {
        let targets = body.code.compactMap { op -> String? in
            if case .call(let target) = op { return target }
            return nil
        }
        try #require(targets.count == 1)
        let expected = try genericInputExpectedName(targets[0], in: program)
        let text = try #require(rendered.first { $0.hasPrefix(body.symbol + " {") })
        #expect(text.contains("// resolved callee: " + expected), Comment(rawValue: text))
        #expect(!text.contains("// resolved callee: <unresolved>"), Comment(rawValue: text))
    }
}

private let genericInputRet = GenericInputOp.word(0xd65f_03c0)
private let genericInputForgetResult = GenericInputOp.word(0xaa09_03e8) // mov x8,x9
private let genericInputRequired = ["array", "slice", "set", "dependent", "float"]
private let genericInputOpaque = genericInputRequired + ["missing", "possible"]

private func genericInputProgram() -> GenericInputProgram {
    var bodies: [GenericInputBody] = []
    for target in genericInputOpaque {
        for mode in ["absent", "unknown", "snapshot"] {
            var code = [genericInputForgetResult]
            if mode == "unknown" {
                // Only unknown dataflow, not a floating-point constant.
                code.append(.word(target == "slice" ? 0xf940_0123 : target == "float" ? 0xfd40_0120 : 0xf940_0120))
                // ldr x3,[x9]; ldr d0,[x9]; or ldr x0,[x9].
            }
            if mode == "snapshot" { code.append(.word(0xd280_0927)) } // mov x7,#73: unrelated live value
            code += [.call(target), genericInputRet]
            let key = "caller_" + target + "_" + mode
            bodies.append(.init(key: key, symbol: "sub_generic_input_" + key, code: code))
        }
    }
    for target in ["extension", "extensionMissing"] {
        for mode in ["absent", "unknown", "snapshot"] {
            var code = [genericInputForgetResult]
            if mode == "unknown" { code.append(.word(0xf940_0120)) } // ldr x0,[x9]
            if mode == "snapshot" { code.append(.word(0xd280_0927)) } // unrelated x7=73
            code += [.call(target), genericInputRet]
            let key = "caller_" + target + "_" + mode
            bodies.append(.init(key: key, symbol: "sub_generic_input_" + key, code: code))
        }
    }
    for target in ["placed", "placedMissing", "zero", "metadata", "self", "sret"] {
        let key = "caller_" + target
        bodies.append(.init(key: key, symbol: "sub_generic_input_" + key,
            code: [genericInputForgetResult, .call(target), genericInputRet]))
    }
    let code: [String: [GenericInputOp]] = [
        "extension": [.word(0x9100_2c0a), genericInputRet], // add x10,x0,#11
        "extensionMissing": [.word(0xffff_ffff), .word(0xffff_ffff)],
        "missing": [.word(0xffff_ffff), .word(0xffff_ffff)], // declared body, no decoded summary
        "array": [.word(0x9100_240a), genericInputRet],      // add x10,x0,#9: own entry x0
        "slice": [.word(0x9100_246a), genericInputRet],      // add x10,x3,#9: own entry x3
        "set": [.word(0x9100_1c0b), genericInputRet],        // add x11,x0,#7: own entry x0
        "dependent": [.word(0x9100_140c), genericInputRet],  // add x12,x0,#5: own entry x0
        "float": [.word(0x1e61_4001), genericInputRet],      // fneg d1,d0: own entry d0
        "placedMissing": [.word(0xffff_ffff), .word(0xffff_ffff)],
        "placed": [.word(0x1e60_2800), genericInputRet],     // fadd d0,d0,d0
        "zero": [genericInputRet],
        "metadata": [.word(0x9100_240a), genericInputRet],   // x0 can be hidden metadata; zero printed formals
        "self": [.word(0x9100_168a), genericInputRet],       // add x10,x20,#5: actual implicit-self read
        "sret": [.word(0xf900_011f), genericInputRet],       // str xzr,[x8]: actual implicit-result write
        "possible": [.call("array"), genericInputRet],     // possible transitive read, no own input read
    ]
    for key in genericInputSymbols.keys.sorted() {
        bodies.append(.init(key: key, symbol: genericInputSymbols[key]!, code: code[key]!))
    }
    return GenericInputProgram(bodies)
}

@Test func unavailableGenericInputCasesHaveIndependentOwnReadWitnesses() throws {
    let program = genericInputProgram(), functions = try program.functions()
    let starts = Set(program.addresses.values)
    var summaries = Dictionary(uniqueKeysWithValues: functions.keys.sorted().compactMap { address -> (UInt64, CalleeRegisterSummary)? in
        guard let summary = CalleeRegisterSummary.of(functions[address]!, isFunction: starts.contains) else { return nil }
        return (address, summary)
    })
    for target in genericInputSymbols.keys.sorted() {
        let function = try #require(functions[program.addresses[target]!])
        #expect(function.analysisName == (try genericInputExpectedName(target, in: program)))
    }
    for target in genericInputRequired {
        let function = try #require(functions[program.addresses[target]!])
        let name = function.analysisDisplayName
        #expect(name.hasPrefix("generic specialization <"))
        #expect(DisassembledFunction.splitSignature(name) != nil)
        #expect(Disassembler.signatureSpecializationKeepsLayout(name))
        #expect(DisassembledFunction.specializedSignatureProof(symbol: function.symbol, printedName: name) == .unavailable)
        for anyContext in [false, true] {
            let layout: Disassembler.SwiftArgumentLayout? = Disassembler.swiftCallArgumentLayout(
                callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), anyContext: anyContext)
            #expect(layout == nil)
        }
        let summary = try #require(summaries[program.addresses[target]!])
        #expect(summary.provenArgumentReads == (target == "float" ? [] : target == "slice" ? [3] : [0]))
        #expect(summary.provenFloatArgumentReads == (target == "float" ? [0] : []))
        for mode in ["absent", "unknown"] {
            let caller = try #require(functions[program.addresses["caller_" + target + "_" + mode]!])
            #expect(ValueTracer().analyze(caller).callSites.isEmpty)
        }
        let snapshot = try #require(functions[program.addresses["caller_" + target + "_snapshot"]!])
        #expect(ValueTracer().analyze(snapshot).callSites.values.contains { $0.arguments.count == 8 })
    }
    let missing = try #require(functions[program.addresses["missing"]!])
    #expect(missing.analysisDisplayName.hasPrefix("generic specialization <Swift.UInt16"))
    #expect(missing.instructions.isEmpty)
    #expect(summaries[program.addresses["missing"]!] == nil)
    #expect(DisassembledFunction.specializedSignatureProof(symbol: missing.symbol, printedName: missing.analysisDisplayName) == .unavailable)
    for target in ["missing", "possible"] {
        for mode in ["absent", "unknown"] {
            let caller = try #require(functions[program.addresses["caller_" + target + "_" + mode]!])
            #expect(ValueTracer().analyze(caller).callSites.isEmpty)
        }
    }
    for target in ["extension", "extensionMissing"] {
        let function = try #require(functions[program.addresses[target]!])
        #expect(function.analysisDisplayName.hasPrefix("static (extension in Foundation):Swift."))
        let layout: Disassembler.SwiftArgumentLayout? = Disassembler.swiftCallArgumentLayout(
            callee: function.analysisDisplayName, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), anyContext: false)
        let known = try #require(layout)
        #expect(known.slots.count + known.unplaced == 1)
        let leading: Disassembler.SwiftArgumentLayout? = Disassembler.swiftCallArgumentLayout(
            callee: function.analysisDisplayName, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), anyContext: true)
        #expect(leading == nil)
        if target == "extensionMissing" {
            #expect(function.instructions.isEmpty && summaries[program.addresses[target]!] == nil)
        } else {
            #expect(summaries[program.addresses[target]!]!.provenArgumentReads == [0])
        }
        for mode in ["absent", "unknown"] {
            let caller = try #require(functions[program.addresses["caller_" + target + "_" + mode]!])
            #expect(ValueTracer().analyze(caller).callSites.isEmpty)
        }
    }
    CalleeRegisterSummary.closeOverReads(&summaries)
    let possible = try #require(summaries[program.addresses["possible"]!])
    #expect(possible.argumentReads == [0] && possible.provenArgumentReads.isEmpty)
    let possibleFunction = try #require(functions[program.addresses["possible"]!])
    #expect(DisassembledFunction.specializedSignatureProof(symbol: possibleFunction.symbol,
        printedName: possibleFunction.analysisDisplayName) == .unavailable)
    for (target, result) in [("zero", "Swift.Int.Type"), ("metadata", "Swift.Int.Type"), ("sret", "Swift.Int")] {
        let function = try #require(functions[program.addresses[target]!])
        let member = target == "metadata" ? "metadataOnly" : target == "sret" ? "make" : "zero"
        #expect(DisassembledFunction.specializedSignatureProof(symbol: function.symbol,
            printedName: function.analysisDisplayName) == .signature("GenericInputs.\(member)() -> \(result)"))
    }
    let selfFunction = try #require(functions[program.addresses["self"]!])
    #expect(DisassembledFunction.specializedSignatureProof(symbol: selfFunction.symbol,
        printedName: selfFunction.analysisDisplayName) == .unavailable)
    #expect(summaries[program.addresses["self"]!]?.readsSelfRegister == true)

    for target in ["zero", "self", "sret"] {
        let summary = try #require(summaries[program.addresses[target]!])
        #expect(summary.provenArgumentReads.isEmpty && summary.provenFloatArgumentReads.isEmpty)
    }
    // Metadata is a physical x0 input, but a zero-formal source call remains
    // zero-formal. Raw register presence is not a source-parameter count.
    #expect(summaries[program.addresses["metadata"]!]?.provenArgumentReads == [0])
    let placedMissing = try #require(functions[program.addresses["placedMissing"]!])
    #expect(placedMissing.instructions.isEmpty && summaries[program.addresses["placedMissing"]!] == nil)
    #expect(DisassembledFunction.specializedSignature(symbol: placedMissing.symbol, printedName: placedMissing.analysisDisplayName)
        == "Specializations.bump(Swift.Int) -> Swift.Int")
    let placed = try #require(functions[program.addresses["placed"]!])
    #expect(DisassembledFunction.specializedSignature(symbol: placed.symbol, printedName: placed.analysisDisplayName)
        == "Specializations.bump(Swift.Double) -> Swift.Double")
}

@Test func unavailableGenericInputsRenderOpaqueAcrossEveryProductionSummaryRoute() async throws {
    let program = genericInputProgram()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("generic-input-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("generic-input.o")
    try program.image().write(to: file)
    let image = try BinaryLoader.load(path: file.path)
    let selected = Set(program.bodies.filter { $0.key.hasPrefix("caller_") }.map { program.addresses[$0.key]! })
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let path = try await withStableDependencies { try await Disassembler().disassemble(path: file.path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: file.path, functionFilter: "sub_generic_input_caller_")
    }
    let selectedArray = await withStableDependencies {
        await Disassembler().disassembleFunctions(at: selected, in: image, groupsAsyncFunclets: false)
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: selected, in: image, transform: { $0 })
    }
    let streaming = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let renderedStream = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: image, render: genericInputRenderWithResolvedNames)
    }
    try genericInputRequireStreamNames(renderedStream, in: program)
    for functions in [array, path, filtered, selectedArray, Array(each.values), streaming] {
        for target in genericInputOpaque {
            for mode in ["absent", "unknown", "snapshot"] {
                let symbol = "sub_generic_input_caller_" + target + "_" + mode
                let caller = try #require(functions.first { $0.symbol == symbol })
                let call = try #require(caller.instructions.first {
                    $0.controlFlow == .call && $0.branchTarget == program.addresses[target]
                })
                try genericInputRequireResolvedCallee(call, target: target, in: program)
                // Existing opaque-arity representation, not a fabricated
                // source count from the highest integer register read.
                #expect(call.callArguments == ["…"], Comment(rawValue: caller.renderPseudo()))
                for text in [caller.renderPseudo(), caller.renderStructured()] {
                    #expect(text.contains("(…)"), Comment(rawValue: text))
                    #expect(!text.contains("arg0") && !text.contains("73"), Comment(rawValue: text))
                }
            }
        }
        for target in ["zero", "metadata", "self", "sret"] {
            let caller = try #require(functions.first { $0.symbol == "sub_generic_input_caller_" + target })
            let call = try #require(caller.instructions.first {
                $0.controlFlow == .call && $0.branchTarget == program.addresses[target]
            })
            try genericInputRequireResolvedCallee(call, target: target, in: program)
            #expect(call.callArguments == nil, Comment(rawValue: caller.renderPseudo()))
            #expect(!caller.renderPseudo().contains("…"), Comment(rawValue: caller.renderPseudo()))
        }
        for target in ["extension", "extensionMissing"] {
            for mode in ["absent", "unknown", "snapshot"] {
                let symbol = "sub_generic_input_caller_" + target + "_" + mode
                let caller = try #require(functions.first { $0.symbol == symbol })
                let call = try #require(caller.instructions.first {
                    $0.controlFlow == .call && $0.branchTarget == program.addresses[target]
                })
                try genericInputRequireResolvedCallee(call, target: target, in: program)
                #expect(call.callArguments == ["?"], Comment(rawValue: caller.renderPseudo()))
                for text in [caller.renderPseudo(), caller.renderStructured()] {
                    #expect(text.contains("_unconditionallyBridgeFromObjectiveC(?)"), Comment(rawValue: text))
                }
            }
        }
        for target in ["placed", "placedMissing"] {
            let placed = try #require(functions.first { $0.symbol == "sub_generic_input_caller_" + target })
            let call = try #require(placed.instructions.first {
                $0.controlFlow == .call && $0.branchTarget == program.addresses[target]
            })
            try genericInputRequireResolvedCallee(call, target: target, in: program)
            #expect(call.callArguments == ["?"], Comment(rawValue: placed.renderPseudo()))
        }
    }
    for target in genericInputOpaque {
        for mode in ["absent", "unknown", "snapshot"] {
            let prefix = "sub_generic_input_caller_" + target + "_" + mode + " {"
            let text = try #require(renderedStream.first { $0.hasPrefix(prefix) })
            #expect(text.contains("(…)"), Comment(rawValue: text))
        }
    }
}

// The extension cases above are also present in the generic streaming API.
// The streaming-render wrapper is covered by the existing opaque cases; no
// separate argument recovery occurs in that one-line wrapper.

// Append to GenericInputPresenceTests.swift so its private GenericInputProgram,
// GenericInputBody and GenericInputOp helpers remain in the same source file.
// No application instruction/body is used: the reductions below are authored
// ADD/MOV/RET operations. The public Foundation names select accessor parsing.
private let setterInputSymbol = "_$s10Foundation13URLComponentsV10queryItemsSayAA12URLQueryItemVGSgvs"
private let setterInputGetterSymbol = "_$s10Foundation13URLComponentsV10queryItemsSayAA12URLQueryItemVGSgvg"
private let setterInputInitSymbol = "_$s12SetterInputs5ValueVACycfC"
private let setterInputTargets = ["setter", "missing"]
private let setterInputModes = ["absent", "unknown", "snapshot", "self"]

private func setterInputProgram() -> GenericInputProgram {
    var bodies: [GenericInputBody] = []
    for target in setterInputTargets {
        for mode in setterInputModes {
            var code = [genericInputForgetResult] // mov x8,x9: clear default indirect result
            if mode == "unknown" || mode == "self" {
                code.append(.word(0xf940_0120)) // ldr x0,[x9]: untracked assigned input
            }
            if mode == "snapshot" {
                code.append(.word(0xd280_0927)) // mov x7,#73: unrelated snapshot value
            }
            if mode == "snapshot" || mode == "self" {
                code.append(.word(0x9100_03f4)) // add x20,sp,#0: separate receiver address
            }
            code += [.call(target), genericInputRet]
            let key = "caller_" + target + "_" + mode
            bodies.append(.init(key: key, symbol: "sub_setter_input_" + key, code: code))
        }
    }
    // The same separately supplied receiver plus unrelated live x7 must not
    // create a source value argument for a zero-explicit-formal getter.
    bodies.append(.init(key: "caller_getter", symbol: "sub_setter_input_caller_getter",
        code: [genericInputForgetResult, .word(0xd280_0927), .word(0x9100_03f4),
               .call("getter"), genericInputRet]))
    // The initializer has no assigned property value or explicit parameters.
    bodies.append(.init(key: "caller_init", symbol: "sub_setter_input_caller_init",
        code: [genericInputForgetResult, .word(0xd280_0927), .call("initializer"), genericInputRet]))

    bodies.append(.init(key: "setter", symbol: setterInputSymbol,
        code: [.word(0x9100_140a), // add x10,x0,#5: independent own machine input read
               .word(0x9100_1e8b), // add x11,x20,#7: actual receiver use
               genericInputRet]))
    // GenericInputProgram.functions() explicitly permits an empty decode only
    // for key "missing". Reuse that existing authored undecodable construction;
    // the duplicate public setter spelling selects the same source contract at
    // another declared entry, rather than borrowing a body input summary.
    bodies.append(.init(key: "missing", symbol: setterInputSymbol,
        code: [.word(0xffff_ffff), .word(0xffff_ffff)]))
    bodies.append(.init(key: "getter", symbol: setterInputGetterSymbol,
        code: [.word(0x9100_1e8b), genericInputRet])) // receiver only, no assigned value
    bodies.append(.init(key: "initializer", symbol: setterInputInitSymbol,
        code: [genericInputRet]))
    return GenericInputProgram(bodies)
}

@Test func concreteValueSetterContractIsKnownWithoutClaimingItsRegisterLayout() throws {
    let program = setterInputProgram(), functions = try program.functions()
    let setter = try #require(functions[program.addresses["setter"]!])
    let name = setter.analysisDisplayName
    #expect(name.hasPrefix("Foundation.URLComponents.queryItems.setter : "))
    #expect(name.contains("Foundation.URLQueryItem"))
    #expect(name.contains("Optional") || name.hasSuffix("?"))
    #expect(name.contains("Array") || name.contains("["))
    #expect(DisassembledFunction.signatureKnown(displayName: name, objcSignature: nil))
    #expect(DisassembledFunction.splitSignature(name) == nil)
    // Keep the existing class/static-only ABI normalizer conservative. A
    // required logical assigned value does not prove its physical placement.
    #expect(Disassembler.setterLayoutName(name, classTypeIndex: ClassTypeIndex()) == nil)
    for anyContext in [false, true] {
        let layout: Disassembler.SwiftArgumentLayout? = Disassembler.swiftCallArgumentLayout(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            anyContext: anyContext)
        #expect(layout == nil)
    }
    let getter = try #require(functions[program.addresses["getter"]!])
    #expect(getter.analysisDisplayName.hasPrefix("Foundation.URLComponents.queryItems.getter : "))
    let initializer = try #require(functions[program.addresses["initializer"]!])
    let signature = try #require(DisassembledFunction.splitSignature(initializer.analysisDisplayName))
    let parameters = try #require(DisassembledFunction.outermostArgumentListRange(of: signature.head))
    #expect(signature.head[parameters].trimmingCharacters(in: .whitespaces).isEmpty)
    #expect(initializer.analysisDisplayName == "SetterInputs.Value.init() -> SetterInputs.Value")
    let typeMarker = try #require(name.range(of: ".setter : "))
    #expect(Disassembler.ordinarySetterAssignedValueType(name) == String(name[typeMarker.upperBound...]))
    #expect(Disassembler.ordinarySetterAssignedValueType(
        "SetterInputs.Value.callback.setter : (Swift.Int) -> Swift.String") == "(Swift.Int) -> Swift.String")
    for excluded in [
        getter.analysisDisplayName, initializer.analysisDisplayName,
        "SetterInputs.Value.subscript.setter : (Swift.Int) -> Swift.Int",
        "dispatch thunk of SetterInputs.Value.item.setter : Swift.Int",
        "generic specialization <Swift.Int> of SetterInputs.Value.item.setter : Swift.Int",
        "function signature specialization <Arg[0] = Dead> of SetterInputs.Value.item.setter : Swift.Int",
        "partial apply forwarder for SetterInputs.Value.item.setter : Swift.Int",
    ] {
        #expect(Disassembler.ordinarySetterAssignedValueType(excluded) == nil)
    }
}

@Test func valueSetterInputCasesHaveIndependentSnapshotAndReceiverPremises() throws {
    let program = setterInputProgram(), functions = try program.functions()
    let starts = Set(program.addresses.values)
    let setter = try #require(functions[program.addresses["setter"]!])
    let setterSummary = try #require(CalleeRegisterSummary.of(setter, isFunction: starts.contains))
    // This corroborates the authored reduction only. It does not assert that
    // this register is a complete Foundation value or fixes a source count.
    #expect(setterSummary.provenArgumentReads == [0])
    #expect(setterSummary.readsSelfRegister)
    let missing = try #require(functions[program.addresses["missing"]!])
    #expect(missing.instructions.isEmpty)
    #expect(CalleeRegisterSummary.of(missing, isFunction: starts.contains) == nil)
    for target in setterInputTargets {
        for mode in setterInputModes {
            let caller = try #require(functions[program.addresses["caller_" + target + "_" + mode]!])
            let sites = ValueTracer().analyze(caller).callSites
            if mode == "absent" || mode == "unknown" {
                // Fresh known self would itself create a site; these modes
                // deliberately have none and independently cover x8 clearing.
                #expect(sites.isEmpty)
            } else {
                let site = try #require(sites.values.first)
                #expect(site.selfValue == .frame(0))
                if mode == "snapshot" {
                    #expect(site.arguments.count == 8)
                    #expect(site.arguments.last == .immediate(73))
                } else {
                    // Existing site because of self, no integer arguments.
                    #expect(site.arguments.isEmpty)
                }
            }
        }
    }
    let getter = try #require(functions[program.addresses["getter"]!])
    let getterSummary = try #require(CalleeRegisterSummary.of(getter, isFunction: starts.contains))
    #expect(getterSummary.provenArgumentReads.isEmpty && getterSummary.readsSelfRegister)
    let initializer = try #require(functions[program.addresses["initializer"]!])
    let initializerSummary = try #require(CalleeRegisterSummary.of(initializer, isFunction: starts.contains))
    #expect(initializerSummary.provenArgumentReads.isEmpty && !initializerSummary.readsSelfRegister)
}

@Test func valueSetterAssignedInputRemainsUnplacedAcrossEveryProductionSummaryRoute() async throws {
    let program = setterInputProgram()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("setter-input-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("setter-input.o")
    try program.image().write(to: file)
    let image = try BinaryLoader.load(path: file.path)
    let selected = Set(program.bodies.filter { $0.key.hasPrefix("caller_") }.map { program.addresses[$0.key]! })
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let path = try await withStableDependencies { try await Disassembler().disassemble(path: file.path) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: file.path, functionFilter: "sub_setter_input_caller_")
    }
    let selectedArray = await withStableDependencies {
        await Disassembler().disassembleFunctions(at: selected, in: image, groupsAsyncFunclets: false)
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: selected, in: image, transform: { $0 })
    }
    let streaming = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let renderedStream = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: image, render: genericInputRenderWithResolvedNames)
    }
    try genericInputRequireStreamNames(renderedStream, in: program)
    for functions in [array, path, filtered, selectedArray, Array(each.values), streaming] {
        let getter = try #require(functions.first { $0.symbol == "sub_setter_input_caller_getter" })
        let getterCall = try #require(getter.instructions.first {
            $0.controlFlow == .call && $0.branchTarget == program.addresses["getter"]
        })
        try genericInputRequireResolvedCallee(getterCall, target: "getter", in: program)
        let receiver = try #require(getterCall.callSelf)
        #expect(!receiver.isEmpty)
        #expect(getterCall.callArguments == nil, Comment(rawValue: getter.renderPseudo()))
        #expect(!getter.renderPseudo().contains("73"))
        let initializer = try #require(functions.first { $0.symbol == "sub_setter_input_caller_init" })
        let initCall = try #require(initializer.instructions.first {
            $0.controlFlow == .call && $0.branchTarget == program.addresses["initializer"]
        })
        try genericInputRequireResolvedCallee(initCall, target: "initializer", in: program)
        #expect(initCall.callArguments == nil && initCall.callSelf == nil,
                Comment(rawValue: initializer.renderPseudo()))
        #expect(!initializer.renderPseudo().contains("73"))
        for target in setterInputTargets {
            for mode in setterInputModes {
                let symbol = "sub_setter_input_caller_" + target + "_" + mode
                let caller = try #require(functions.first { $0.symbol == symbol })
                let call = try #require(caller.instructions.first {
                    $0.controlFlow == .call && $0.branchTarget == program.addresses[target]
                })
                try genericInputRequireResolvedCallee(call, target: target, in: program)
                // Exactly one logical assigned value comes from the concrete
                // property contract. Its physical location remains unplaced.
                #expect(call.callArguments == ["?"], Comment(rawValue: caller.renderPseudo()))
                if mode == "snapshot" || mode == "self" {
                    #expect(call.callSelf == receiver, Comment(rawValue: caller.renderPseudo()))
                } else {
                    #expect(call.callSelf == nil, Comment(rawValue: caller.renderPseudo()))
                }
                for text in [caller.renderPseudo(), caller.renderStructured()] {
                    #expect(text.contains("queryItems.setter("), Comment(rawValue: text))
                    #expect(!text.contains("73"), Comment(rawValue: text))
                }
                let statement = DisassembledFunction.callStatement(of: call, hideRuntime: false)
                let expected = "Foundation.URLComponents.queryItems.setter("
                    + (call.callSelf.map { "self: \($0), " } ?? "") + "?)"
                #expect(statement == expected, Comment(rawValue: caller.renderPseudo()))
            }
        }
    }
    let getterText = try #require(renderedStream.first {
        $0.hasPrefix("sub_setter_input_caller_getter {")
    })
    #expect(getterText.contains("queryItems.getter(self: "))
    #expect(!getterText.contains(", ?)") && !getterText.contains("73"))
    let initText = try #require(renderedStream.first {
        $0.hasPrefix("sub_setter_input_caller_init {")
    })
    #expect(initText.contains("SetterInputs.Value.init()") && !initText.contains("73"))
    for target in setterInputTargets {
        for mode in setterInputModes {
            let prefix = "sub_setter_input_caller_" + target + "_" + mode + " {"
            let text = try #require(renderedStream.first { $0.hasPrefix(prefix) })
            let expected = mode == "snapshot" || mode == "self" ? ", ?)" : "setter(?)"
            #expect(text.contains(expected), Comment(rawValue: text))
            #expect(!text.contains("73"), Comment(rawValue: text))
        }
    }
}

// Append to GenericInputPresenceTests.swift: uses its private authored image
// builder. These are real non-Swift nlist names, not demangled annotations.
// No application body, native fixture, compiler/linker, or target execution.
private let rawSetterDisplaySymbol = "_RawSetterInputs.Value.item.setter : Swift.Int"
private let rawSetterDisplayCallee = "RawSetterInputs.Value.item.setter : Swift.Int"
private let rawSetterDisplayModes = ["absent", "unknown", "snapshot", "self"]

private func rawSetterDisplayProgram() -> GenericInputProgram {
    var bodies: [GenericInputBody] = []
    for mode in rawSetterDisplayModes {
        var code = [genericInputForgetResult] // clear default incoming x8 fact
        if mode == "unknown" { code.append(.word(0xf940_0120)) } // ldr x0,[x9]
        if mode == "snapshot" { code.append(.word(0xd280_0927)) } // unrelated x7=73
        if mode == "snapshot" || mode == "self" {
            code.append(.word(0x9100_03f4)) // separate known x20=sp
        }
        code += [.call("rawSetter"), genericInputRet]
        bodies.append(.init(key: "caller_" + mode,
            symbol: "sub_raw_setter_display_caller_" + mode, code: code))
    }
    // RET establishes no own machine input read. Its raw label is not a Swift
    // declaration: the label alone cannot establish one assigned source value.
    bodies.append(.init(key: "rawSetter", symbol: rawSetterDisplaySymbol,
        code: [genericInputRet]))
    return GenericInputProgram(bodies)
}

private func rawSetterDisplayRequireCallee(_ call: Instruction) throws {
    // A route that loses the spaced symbol is a setup failure, never an
    // admitted demonstration that the new setter policy passed or failed.
    let actual = try #require(DisassembledFunction.calleeName(of: call))
    try #require(actual == rawSetterDisplayCallee)
}

private func rawSetterDisplayRenderWithClaims(_ function: DisassembledFunction) -> String {
    let claims = function.instructions.filter { $0.controlFlow == .call }.map { call in
        let callee = DisassembledFunction.calleeName(of: call) ?? "<unresolved>"
        let arguments = call.callArguments.map { "[" + $0.joined(separator: ", ") + "]" } ?? "<none>"
        let receiver = call.callSelf ?? "<none>"
        return "// raw-label-callee: " + callee
            + "\n// raw-label-args: " + arguments
            + "\n// raw-label-self: " + receiver
    }
    return function.renderPseudo() + "\n" + claims.joined(separator: "\n")
}

@Test func rawSetterDisplayLabelHasIndependentNonSwiftAndNoInputPremises() throws {
    let program = rawSetterDisplayProgram(), functions = try program.functions()
    let target = try #require(functions[program.addresses["rawSetter"]!])
    try #require(target.symbol == rawSetterDisplaySymbol)
    try #require(!target.symbol.hasPrefix("_$s") && !target.symbol.hasPrefix("$s"))
    try #require(target.instructions.count == 1)
    try #require(target.instructions.first?.controlFlow == .return)
    let starts = Set(program.addresses.values)
    let summary = try #require(CalleeRegisterSummary.of(target, isFunction: starts.contains))
    try #require(summary.argumentReads.isEmpty && summary.provenArgumentReads.isEmpty)
    try #require(summary.provenFloatArgumentReads.isEmpty && !summary.readsSelfRegister)
    // Keep the helper a text-only predicate. Declaration provenance belongs
    // to its production call-site admission, not to this string parser.
    try #require(Disassembler.ordinarySetterAssignedValueType(rawSetterDisplayCallee) == "Swift.Int")
    try #require(Disassembler.setterLayoutName(rawSetterDisplayCallee,
        classTypeIndex: ClassTypeIndex()) == nil)
    for anyContext in [false, true] {
        let layout: Disassembler.SwiftArgumentLayout? = Disassembler.swiftCallArgumentLayout(
            callee: rawSetterDisplayCallee, enumCaseIndex: EnumCaseIndex(),
            classTypeIndex: ClassTypeIndex(), anyContext: anyContext)
        try #require(layout == nil)
    }
    for mode in rawSetterDisplayModes {
        let caller = try #require(functions[program.addresses["caller_" + mode]!])
        let sites = ValueTracer().analyze(caller).callSites
        if mode == "absent" || mode == "unknown" {
            try #require(sites.isEmpty)
        } else {
            let site = try #require(sites.values.first)
            try #require(site.selfValue == .frame(0))
            if mode == "snapshot" {
                try #require(site.arguments.count == 8 && site.arguments.last == .immediate(73))
            } else {
                try #require(site.arguments.isEmpty)
            }
        }
    }
}

@Test func rawSetterDisplayLabelDoesNotDeclareAnAssignedValueAcrossInProcessRoutes() async throws {
    let program = rawSetterDisplayProgram()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("raw-setter-display-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("raw-setter-display.o")
    try program.image().write(to: file)
    let image = try BinaryLoader.load(path: file.path)
    try #require(image.symbols.contains { $0.name == rawSetterDisplaySymbol })
    let selected = Set(rawSetterDisplayModes.map { program.addresses["caller_" + $0]! })
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: file.path, functionFilter: "sub_raw_setter_display_caller_")
    }
    let selectedArray = await withStableDependencies {
        await Disassembler().disassembleFunctions(at: selected, in: image, groupsAsyncFunclets: false)
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: selected, in: image, transform: { $0 })
    }
    let streaming = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let renderedStream = await withStableDependencies {
        await Disassembler().disassembleStreamingRender(machO: image, render: rawSetterDisplayRenderWithClaims)
    }
    // The unfiltered path/LLVM API is deliberately absent: parseLabel rejects
    // these spaced nlist names. Existing canonical-mangled tests cover LLVM.
    // Its inability to retain this raw callee cannot be counted as policy red.
    for functions in [array, filtered, selectedArray, Array(each.values), streaming] {
        for mode in rawSetterDisplayModes {
            let caller = try #require(functions.first {
                $0.symbol == "sub_raw_setter_display_caller_" + mode
            })
            let call = try #require(caller.instructions.first {
                $0.controlFlow == .call && $0.branchTarget == program.addresses["rawSetter"]
            })
            try rawSetterDisplayRequireCallee(call)
            #expect(call.callArguments == nil, Comment(rawValue: caller.renderPseudo()))
            #expect(call.callSelf == nil, Comment(rawValue: caller.renderPseudo()))
            for text in [caller.renderPseudo(), caller.renderStructured()] {
                #expect(!text.contains("73"), Comment(rawValue: text))
            }
        }
    }
    for mode in rawSetterDisplayModes {
        let text = try #require(renderedStream.first {
            $0.hasPrefix("sub_raw_setter_display_caller_" + mode + " {")
        })
        try #require(text.contains("// raw-label-callee: " + rawSetterDisplayCallee))
        #expect(text.contains("// raw-label-args: <none>"), Comment(rawValue: text))
        #expect(text.contains("// raw-label-self: <none>"), Comment(rawValue: text))
        #expect(!text.contains("73"), Comment(rawValue: text))
    }
}
