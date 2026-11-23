import Foundation
import Testing
@testable import SwiftDecompilerCore

private func integerReturnReferenceValue(_ value: AbstractValue, word: UInt64) -> UInt64? {
    switch value {
    case .argument(0), .callResult(0x1000): return word
    case .immediate(let value): return value
    case .select(let condition, let yes, let no):
        guard let condition = integerReturnReferenceValue(condition, word: word) else { return nil }
        return integerReturnReferenceValue(condition == 0 ? no : yes, word: word)
    case .binary(let op, let left, let right):
        guard let lhs = integerReturnReferenceValue(left, word: word),
              let rhs = integerReturnReferenceValue(right, word: word) else { return nil }
        switch op {
        case .add: return lhs &+ rhs
        case .equal: return lhs == rhs ? 1 : 0
        case .bitAnd: return lhs & rhs
        case .shiftLeft: return lhs &<< rhs
        case .arithmeticShiftRight: return UInt64(bitPattern: Int64(bitPattern: lhs) &>> rhs)
        default: return nil
        }
    default: return nil
    }
}

@Test func narrowIntegerReturnViewsAgreeWithLanguageConversions() {
    for word: UInt64 in [0, 1, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000,
                         0xffff, 0x10000, 0x7fff_ffff, 0x8000_0000,
                         0xffff_ffff, 0x1_0000_0001, 0xdead_beef_ffff_ff81, .max] {
        let selection = AbstractValue.select(condition: .binary(.equal, .argument(0), .immediate(1)),
            whenTrue: .argument(0), whenFalse: .immediate(0xdead_beef_0000_0080))
        for (value, reference) in [(AbstractValue.argument(0), word), (.callResult(0x1000), word),
                                   (selection, word == 1 ? word : 0xdead_beef_0000_0080)] {
            let conversions: [(String, UInt64)] = [
                ("Swift.Int8", UInt64(bitPattern: Int64(Int8(truncatingIfNeeded: reference)))),
                ("Swift.Int16", UInt64(bitPattern: Int64(Int16(truncatingIfNeeded: reference)))),
                ("Swift.Int32", UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: reference)))),
                ("Swift.UInt8", UInt64(UInt8(truncatingIfNeeded: reference))),
                ("Swift.UInt16", UInt64(UInt16(truncatingIfNeeded: reference))),
                ("Swift.UInt32", UInt64(UInt32(truncatingIfNeeded: reference))),
            ]
            for (type, expected) in conversions {
                let projected = Disassembler.integerScalarValue(value, type: type, arguments: [0: .unsignedInteger(64)],
                    atomType: { if case .callResult = $0 { return .unsignedInteger(64) }; return nil })
                #expect(integerReturnReferenceValue(projected, word: word) == expected,
                        Comment(rawValue: type + " input " + String(word, radix: 16)))
            }
        }
    }
}

@Test func narrowIntegerReturnProofDoesNotInventPhysicalBits() {
    let result = AbstractValue.callResult(0x1000)
    #expect(Disassembler.integerScalarValue(result, type: "Swift.UInt32", arguments: [:],
        atomType: { _ in .unsignedInteger(8) }) == .unknown)
    #expect(Disassembler.integerScalarValue(.argument(0), type: "Swift.UInt32", arguments: [0: .unsignedInteger(8)],
        atomType: { _ in .unsignedInteger(64) }) == .unknown)
    for type: ValueType in [.pointer, .floating(64), .boolean, .unknown] {
        #expect(Disassembler.integerScalarValue(result, type: "Swift.Int8", arguments: [:], atomType: { _ in type }) == .unknown)
    }
    for atom: AbstractValue in [.selfFieldValue(offset: 16), .argumentField(argument: 0, offset: 0), .selfPointer] {
        #expect(Disassembler.integerScalarValue(atom, type: "Swift.Int8", arguments: [:]) == .unknown)
    }
    let computed = AbstractValue.binary(.add, .argument(0), .immediate(1))
    #expect(Disassembler.integerScalarValue(computed, type: "Swift.UInt32", arguments: [0: .unsignedInteger(8)],
        atomType: { _ in .unsignedInteger(32) }) == .unknown)
    let masked = AbstractValue.binary(.bitAnd, result, .immediate(0xff))
    let projected = Disassembler.integerScalarValue(masked, type: "Swift.Int32", arguments: [:],
        atomType: { _ in .unsignedInteger(8) })
    #expect(integerReturnReferenceValue(projected, word: 0xdead_beef_0000_0081) == 129)
    // 0x80 and 0x180 have the same UInt8 result, but shifting their physical
    // words right changes the low byte to 0x40 and 0xc0 respectively.
    let shifted = AbstractValue.binary(.shiftRight, result, .immediate(1))
    #expect(Disassembler.integerScalarValue(shifted, type: "Swift.UInt8", arguments: [:],
        atomType: { _ in .unsignedInteger(8) }) == .unknown)
}

@Test func narrowIntegerReturnTypedAtomsAndCompleteBooleanWordsStayExact() {
    let comparison = AbstractValue.binary(.equal, .callResult(0x1000), .immediate(1))
    for (name, type): (String, ValueType) in [
        ("Swift.Int8", .signedInteger(8)), ("Swift.Int16", .signedInteger(16)), ("Swift.Int32", .signedInteger(32)),
        ("Swift.UInt8", .unsignedInteger(8)), ("Swift.UInt16", .unsignedInteger(16)), ("Swift.UInt32", .unsignedInteger(32)),
    ] {
        #expect(Disassembler.integerScalarValue(.argument(0), type: name, arguments: [0: type]) == .argument(0))
        #expect(Disassembler.integerScalarValue(.callResult(0x1000), type: name, arguments: [:],
            atomType: { _ in type }) == .callResult(0x1000))
        #expect(Disassembler.integerScalarValue(comparison, type: name, arguments: [:]) == comparison)
    }
}

@Test func narrowIntegerReturnBitPatternWordsStayPhysicallyComplete() {
    for width in [16, 32, 64] {
        let bits = AbstractValue.unary(.bitPattern(bits: width), .argument(0))
        for result in ["Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32"] {
            #expect(Disassembler.integerScalarValue(bits, type: result, arguments: [0: .floating(width)])
                == Disassembler.narrowedResult(bits, type: result, includingAtoms: true))
        }
    }
    let invalid = AbstractValue.unary(.bitPattern(bits: 8), .argument(0))
    #expect(Disassembler.integerScalarValue(invalid, type: "Swift.UInt8", arguments: [0: .floating(16)]) == .unknown)
}

// Explicit metadata and authored instruction words exercise return-use ordering.
// These are analysis-only ABI seams, not a native async correctness claim.
@Test func narrowIntegerCallResultProofPreservesSyncAndAsyncProducers() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("integer-return-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        let engine = try #require(CapstoneEngine())
        for isAsync in [false, true] {
            for source in [8, 16, 32, 64] {
                for result in [8, 16, 32] {
                    let callee = "IntegerReturns.produce() -> Swift.UInt\(source)"
                    let resolver = Disassembler.ReferenceResolver(names: [0x3000: callee], stringRanges: [],
                        machO: image, demangleSymbol: { _ in nil })
                    let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [0x3000],
                        objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
                        selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(),
                        payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
                        classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
                    let words: [UInt32] = isAsync ? [0x94000800, 0xf94006c8, 0xd61f0100]
                        : [0xa9bf7bfd, 0x910003fd, 0x940007fe, 0xa8c17bfd, 0xd65f03c0]
                    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
                    let instructions = engine.disassemble(bytes, address: 0x1000).map {
                        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail,
                            callee: .kept($0.controlFlow == .call ? callee : nil))
                    }
                    let name = "IntegerReturns.probe() " + (isAsync ? "async " : "") + "-> Swift.UInt\(result)"
                    var function = DisassembledFunction(symbol: "_$s14IntegerReturns5probeyyF", demangledName: name,
                        startAddress: 0x1000, instructions: instructions, source: .symbol)
                    if isAsync {
                        function = function.attachingAsyncFunclet(AsyncFuncletInfo(parent: 0x1000, parentName: name,
                            ordinal: 0, kind: nil, predecessor: nil, chain: [0x1000]))
                    }
                    let analyzed = Disassembler().analyzeFunction(function, context: context)
                    for text in [analyzed.renderPseudo(), analyzed.renderStructured()] {
                        let details = Comment(rawValue: "source \(source), result \(result), async \(isAsync)\n" + text)
                        #expect(text.components(separatedBy: "IntegerReturns.produce(").count == 2, details)
                        if source < result {
                            #expect(text.contains("return ?"), details)
                        } else if source == result {
                            #expect(text.contains("return IntegerReturns.produce()"), details)
                        } else {
                            let mask = result == 8 ? "255" : result == 16 ? "0xffff" : "0xffffffff"
                            #expect(text.contains("& " + mask), details)
                        }
                    }
                }
            }
        }
    }
}

// Ownership and result-bank eligibility come from the existing index. These
// reductions test only the width view of an already named awaited result.
private func integerAwaitedReturnProbe(callee: String?, result: Int, shared: Bool = false) async throws -> DisassembledFunction {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("integer-await-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        let engine = try #require(CapstoneEngine())
        func entry(_ start: UInt64) -> [Instruction] {
            let delta = UInt32(0x3000 - (start + 4))
            let adr = 0x10000009 | ((delta & 3) << 29) | ((delta >> 2) << 5)
            let branch = 0x14000000 | UInt32((0x4000 - (start + 16)) >> 2)
            let words: [UInt32] = [0x94000000, adr, 0xf9000409, 0xaa0003f6, branch]
            let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
            return engine.disassemble(bytes, address: start).map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.controlFlow == .call ? nil : $0.branchTarget, detail: $0.detail,
                    callee: .kept($0.controlFlow == .call ? "swift_task_alloc" : nil))
            }
        }
        let first = entry(0x1000), second = entry(0x2000)
        let index = AsyncFuncletIndex.build(hints: .init(entries: shared ? [0x1000, 0x2000] : [0x1000], awaitReturns: [0x3000]),
            functionStarts: shared ? [0x1000, 0x2000, 0x3000] : [0x1000, 0x3000],
            instructions: { $0 == 0x1000 ? first : $0 == 0x2000 ? second : [] },
            nameOf: { $0 == 0x4000 ? callee : nil })
        let name = "IntegerAwait.owner() async -> Swift.UInt\(result)"
        let info = try #require(index.info(for: 0x3000, parentName: { _ in name }))
        // Entered with the callee context; load Parent, then its ResumeParent.
        let words: [UInt32] = [0xf94002d6, 0xf94006c8, 0xd61f0100]
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let instructions = engine.disassemble(bytes, address: 0x3000).map(Disassembler.instruction(decoded:))
        let raw = DisassembledFunction(symbol: "resume", demangledName: nil, startAddress: 0x3000,
            instructions: instructions, source: .address).attachingAsyncFunclet(info)
        let resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: image, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
            objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]),
            vtableIndex: VTableIndex(), enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
            classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
            asyncIndex: index, asyncChainSlots: [:])
        return Disassembler().analyzeFunction(raw, context: context)
    }
}

@Test func narrowIntegerAwaitedReturnsUseOnlyTheirQualifiedResultBits() async throws {
    for source in [8, 16, 32, 64] {
        for result in [8, 16, 32] {
            let function = try await integerAwaitedReturnProbe(callee: "IntegerAwait.produce() async -> Swift.UInt\(source)", result: result)
            for text in [function.renderPseudo(), function.renderStructured()] {
                let details = Comment(rawValue: "source \(source), result \(result)\n" + text)
                if source < result {
                    #expect(text.contains("return ?"), details)
                    #expect(!text.contains("awaited1"), details)
                } else if source == result {
                    #expect(text.contains("return awaited1"), details)
                } else {
                    let mask = result == 8 ? "255" : result == 16 ? "0xffff" : "0xffffffff"
                    #expect(text.contains("return (awaited1 & " + mask + ")"), details)
                }
            }
        }
    }
}

@Test func narrowIntegerAwaitedReturnsNeedOwnershipBankAndErrorQualification() async throws {
    let callees: [String?] = [nil, "IntegerAwait.produce() async -> Swift.Bool",
        "IntegerAwait.produce() async -> Swift.Double", "IntegerAwait.produce() async -> ()",
        "IntegerAwait.produce() async -> A", "IntegerAwait.produce() async -> Swift.Optional<Swift.UInt8>",
        "IntegerAwait.produce() async throws(IntegerAwait.Failure) -> Swift.UInt8",
        "implicit closure #1 @Sendable () async -> Swift.UInt8"]
    for callee in callees {
        let function = try await integerAwaitedReturnProbe(callee: callee, result: 8)
        for text in [function.renderPseudo(), function.renderStructured()] {
            #expect(!text.contains("awaited1"), Comment(rawValue: text))
        }
    }
    let shared = try await integerAwaitedReturnProbe(callee: "IntegerAwait.produce() async -> Swift.UInt8", result: 8, shared: true)
    #expect(!shared.renderPseudo().contains("awaited1"))
    #expect(!shared.renderStructured().contains("awaited1"))
}
