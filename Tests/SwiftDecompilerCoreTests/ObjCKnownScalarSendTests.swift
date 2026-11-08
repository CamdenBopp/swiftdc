import Foundation
import Testing
@testable import SwiftDecompilerCore

private enum ScalarSendReceiver: CaseIterable {
    case selfPointer, argument, unknown
    var prefix: [UInt32] {
        switch self {
        case .selfPointer: []
        case .argument: [0xaa0203e0] // mov x0,x2
        case .unknown: [0xaa0903e0] // mov x0,x9
        }
    }
}

/// Decode real ARM64 instructions and use the complete analyzer. This is the
/// SDK `scale` selector collision in objc_struct_lanes.m without requiring a
/// linked Apple SDK fixture. The empty Mach-O only backs address resolution;
/// the method bindings are explicit, not parsed from an unlinked object.
private func analyzeKnownScalarSend(type: String = "d", aggregateTail: Bool = false, scalarWordReturn: Bool = false,
                                    receiver: ScalarSendReceiver = .selfPointer,
                                    callerIsClass: Bool = false,
                                    declarationIsClass: Bool? = nil,
                                    declarationClass: String = "SDLanes",
                                    aliases: [String] = [], otherClassAggregate: Bool = false,
                                    otherClassAggregateIsClass: Bool? = nil,
                                    sendCallee: String = "objc_msgSend$scale",
                                    preset: DemanglePreset = .simplified) async throws -> DisassembledFunction {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("objc-scale-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try await withStableDependencies {
        let machO = try BinaryLoader.load(path: file.path)
        let callerReturn = scalarWordReturn ? "q" : aggregateTail ? "{CGRect={CGPoint=dd}{CGSize=dd}}" : "v"
        let caller = ObjCMethodBinding(className: "SDLanes", selector: aggregateTail ? "scaledFrame:" : "vertexScaled:",
            typeEncoding: "\(callerReturn)24@0:8@16", isClassMethod: callerIsClass, signature: "")
        var callees = ([type] + aliases).map {
            ObjCMethodBinding(className: declarationClass, selector: "scale", typeEncoding: "\($0)16@0:8",
                              isClassMethod: declarationIsClass ?? callerIsClass, signature: "")
        }
        if otherClassAggregate {
            callees.append(ObjCMethodBinding(className: "OtherLanes", selector: "scale", typeEncoding: "{Pair=dd}16@0:8",
                                            isClassMethod: otherClassAggregateIsClass ?? callerIsClass, signature: ""))
        }
        let index = ObjCMetadataIndex(methods: [0x1000: [caller], 0x3000: callees], fieldMaps: [:])
        #expect(SDKSelectorReturns.table["scale"] == "h")
        let resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [], objcIndex: index,
            fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
            enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        // The double result moves from d0 to CGRectInset's fifth HFA lane d4.
        // glVertex2f instead reads a float result in s0; no incorrect f/d cast.
        let words = receiver.prefix + (scalarWordReturn ? [0x94000400, 0xd65f03c0] : aggregateTail
            ? [0x94000400, 0x1e604004, 0x1e6c1005, 0x14000800]
            : [0x94000400, type == "f" ? 0x1e2c1001 : 0x1e6c1001, 0x14000800])
        let code = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(code, address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.map {
            let callee: String? = if $0.controlFlow == .call { sendCallee }
                else if $0.controlFlow == .branch { aggregateTail ? "CGRectInset" : type == "f" ? "glVertex2f" : "glVertex2d" }
                else { nil }
            return Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail, callee: .kept(callee))
        }
        let function = DisassembledFunction(symbol: caller.displayName, demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .objcMetadata, objcMethod: caller)
        return Disassembler(preset: preset).analyzeFunction(function, context: context)
    }
}

@Test func aKnownScalarSelfSendSurvivesAnSDKSelectorCollision() async throws {
    for preset in DemanglePreset.allCases {
        for isClass in [false, true] {
            for type in ["f", "d", "D"] {
                let function = try await analyzeKnownScalarSend(type: type, callerIsClass: isClass, preset: preset)
                for output in [function.renderPseudo(), function.renderStructured()] {
                    let consumer = type == "f" ? "glVertex2f" : "glVertex2d"
                    #expect(output.contains("\(consumer)([self scale], 0.5)"), Comment(rawValue: "type=\(type) preset=\(preset) class=\(isClass)\n\(output)"))
                    #expect(output.components(separatedBy: "[self scale]").count == 2, Comment(rawValue: output))
                }
            }
        }
    }
}

@Test func aKnownScalarSelfSendRemainsWholeInAnAggregateTailCall() async throws {
    for preset in DemanglePreset.allCases {
        for type in ["d", "D"] {
            let function = try await analyzeKnownScalarSend(type: type, aggregateTail: true, preset: preset)
            #expect(function.renderPseudo().contains("CGRectInset(?, [self scale], 0.5)"), Comment(rawValue: "type=\(type) preset=\(preset)\n" + function.renderPseudo()))
            #expect(function.renderStructured().contains("return CGRectInset(?, [self scale], 0.5)"), Comment(rawValue: "type=\(type) preset=\(preset)\n" + function.renderStructured()))
        }
    }
}

@Test func indexedAggregateDeclarationsKeepTheConservativeVeto() async throws {
    // This repair is only the SDK-wide selector-name collision. An actual
    // indexed aggregate implementation still vetoes scalar use, including
    // another class or the opposite method kind.
    for kind in [false, true] {
        let function = try await analyzeKnownScalarSend(otherClassAggregate: true, otherClassAggregateIsClass: kind)
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(output.contains("glVertex2d(?, 0.5)"), Comment(rawValue: output))
            #expect(output.components(separatedBy: "[self scale]").count == 2, Comment(rawValue: output))
        }
    }
}

@Test func aSuperSendDoesNotBorrowTheCurrentClassScalarDeclaration() async throws {
    // A superclass send has distinct receiver lookup. Even if the supplied
    // x0 abstract value is self, the current class cannot prove its result.
    for callee in ["objc_msgSendSuper$scale", "objc_msgSendSuper2$scale"] {
        let function = try await analyzeKnownScalarSend(sendCallee: callee)
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(output.contains("glVertex2d(?, 0.5)"), Comment(rawValue: output))
        }
    }
}

@Test func aScalarSelectorCollisionWithoutReceiverProofStillDeclines() async throws {
    for receiver in [ScalarSendReceiver.argument, .unknown] {
        let function = try await analyzeKnownScalarSend(receiver: receiver)
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(output.contains("glVertex2d(?, 0.5)"), Comment(rawValue: output))
            #expect(output.components(separatedBy: " scale]").count == 2, Comment(rawValue: output))
        }
    }
    // A method of another class or the opposite method kind does not prove
    // what this receiver's send returns.
    for function in [
        try await analyzeKnownScalarSend(declarationClass: "OtherLanes"),
        try await analyzeKnownScalarSend(declarationIsClass: true),
        try await analyzeKnownScalarSend(callerIsClass: true, declarationIsClass: false),
    ] {
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(output.contains("glVertex2d(?, 0.5)"), Comment(rawValue: output))
            #expect(output.components(separatedBy: "[self scale]").count == 2, Comment(rawValue: output))
        }
    }
}

@Test func conflictingKnownClassScalarAndAggregateDeclarationsStillDecline() async throws {
    for alias in ["{Pair=dd}", "jd", "jf", "jD", "{One=d}", "{Opaque}"] {
        for isClass in [false, true] {
            let function = try await analyzeKnownScalarSend(callerIsClass: isClass, aliases: [alias])
            for output in [function.renderPseudo(), function.renderStructured()] {
                #expect(output.contains("glVertex2d(?, 0.5)"), Comment(rawValue: "\(alias)\n\(output)"))
                #expect(output.components(separatedBy: "[self scale]").count == 2, Comment(rawValue: output))
            }
        }
    }
}


@Test func unsafeScalarSelectorExemptionsDoNotLeakIntoX0Results() async throws {
    // C float arguments have their own whole-FP-result check. Read x0 as a
    // scalar instead to isolate the aggregate-result safeguard itself: a
    // weakened receiver, owner, kind, scalar-type, or super-send guard must
    // not substitute the whole send for this unproven low result word.
    let cases: [(String, DisassembledFunction)] = [
        ("argument receiver", try await analyzeKnownScalarSend(scalarWordReturn: true, receiver: .argument)),
        ("unknown receiver", try await analyzeKnownScalarSend(scalarWordReturn: true, receiver: .unknown)),
        ("missing own declaration", try await analyzeKnownScalarSend(scalarWordReturn: true, declarationClass: "OtherLanes")),
        ("wrong class-method kind", try await analyzeKnownScalarSend(scalarWordReturn: true, declarationIsClass: true)),
        ("wrong instance-method kind", try await analyzeKnownScalarSend(scalarWordReturn: true, callerIsClass: true, declarationIsClass: false)),
        ("same-class integer conflict", try await analyzeKnownScalarSend(scalarWordReturn: true, aliases: ["q"])),
        ("integer declaration", try await analyzeKnownScalarSend(type: "q", scalarWordReturn: true)),
        ("super send", try await analyzeKnownScalarSend(scalarWordReturn: true, sendCallee: "objc_msgSendSuper$scale")),
        ("super2 send", try await analyzeKnownScalarSend(scalarWordReturn: true, sendCallee: "objc_msgSendSuper2$scale")),
    ]
    for (name, function) in cases {
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(output.contains("return ?"), Comment(rawValue: "\(name)\n\(output)"))
            #expect(output.components(separatedBy: " scale]").count == 2, Comment(rawValue: "\(name)\n\(output)"))
        }
    }
}
