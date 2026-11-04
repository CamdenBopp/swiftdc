import Foundation
import Testing
@testable import SwiftDecompilerCore

private enum ObjCResultUse: CaseIterable {
    case low, high, tail, scalarArgument, orderedScalarArgument, xorLow, andLow

    var words: [UInt32] {
        switch self {
        case .low: [0x94000400, 0xd65f03c0] // bl send; ret
        case .high: [0x94000400, 0xaa0103e0, 0xd65f03c0] // bl send; mov x0,x1; ret
        case .tail: [0x14000400] // b send
        case .xorLow: [0x94000400, 0xd2400000, 0xd65f03c0] // eor x0,x0,#1
        case .andLow: [0x94000400, 0x92400000, 0xd65f03c0] // and x0,x0,#1
        case .scalarArgument: [0x94000400, 0x940007ff, 0xd65f03c0] // bl send; bl takeOne; ret
        case .orderedScalarArgument: [0x94000400, 0xaa0003f3, 0x94000bfe, 0xaa1303e0, 0x940007fc, 0xd65f03c0] // save low word in x19 across sideEffect
        }
    }
}

/// Real decoder and full analyzer with explicit method bindings. The empty
/// Mach-O backs the resolver, not an unlinked ObjC metadata parsing claim.
private func analyzeObjCSendResult(_ types: [String], use: ObjCResultUse, preset: DemanglePreset, callerReturn: String = "q", selector: String = "abiRange:", builtEmptyIndex: Bool = false) async throws -> DisassembledFunction {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("objc-result-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try await withStableDependencies {
        let machO = try BinaryLoader.load(path: file.path)
        let method = ObjCMethodBinding(className: "StructResultProbe", selector: "field:",
            typeEncoding: "\(callerReturn)@:q", isClassMethod: false, signature: "")
        let callees = types.enumerated().map { offset, type in
            ObjCMethodBinding(className: offset == 0 ? "StructResultProbe" : "OtherResultProbe",
                selector: selector, typeEncoding: selector.contains(":") ? "\(type)24@0:8q16" : "\(type)16@0:8", isClassMethod: false, signature: "")
        }
        let index = builtEmptyIndex ? ObjCMetadataIndex.build(in: machO)
            : ObjCMetadataIndex(methods: [0x1000: [method], 0x3000: callees], fieldMaps: [:])
        if builtEmptyIndex { #expect(index.count == 0) }
        let resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [], objcIndex: index,
            fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
            enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        let code = Data(use.words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(code, address: 0x1000)
        try #require(decoded.count == use.words.count)
        let instructions = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call || $0.controlFlow == .branch
                    ? ($0.address == 0x1000 ? "objc_msgSend$\(selector)"
                        : use == .orderedScalarArgument && $0.address == 0x1008 ? "ABI.sideEffect() -> ()" : "takeOne(Swift.Int) -> Swift.Int") : nil))
        }
        let function = DisassembledFunction(symbol: method.displayName, demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .objcMetadata, objcMethod: method)
        return Disassembler(preset: preset).analyzeFunction(function, context: context)
    }
}

@Test func objcAggregateSendResultsDoNotBecomeWholeScalarValues() async throws {
    // Integer pairs, one-word structs, HFA, complex, opaque aggregates,
    // indirect-sized structs and unions all differ from a scalar source value.
    for type in ["{SDRange=qq}", "r{SDRange=qq}", "{SDOne=q}", "{Pair=dd}", "jd", "{Opaque}", "{Large=qqq}", "(Choice=qd)"] {
        for preset in DemanglePreset.allCases {
            for use in ObjCResultUse.allCases {
                let function = try await analyzeObjCSendResult([type], use: use, preset: preset)
                for output in [function.renderPseudo(), function.renderStructured()] {
                    let context = Comment(rawValue: "\(type) \(use) \(preset)\n\(output)")
                    #expect(!output.contains("return [self abiRange:"), context)
                    #expect(!output.contains("takeOne([self abiRange:"), context)
                    #expect(output.components(separatedBy: "[self abiRange:arg0]").count == 2, context)
                    if use == .low || use == .high { #expect(output.contains("return ?"), context) }
                    if use == .scalarArgument || use == .orderedScalarArgument { #expect(output.contains("takeOne(?)"), context) }
                    if use == .orderedScalarArgument {
                        #expect(output.components(separatedBy: "sideEffect(").count == 2, context)
                        let send = try #require(output.range(of: "[self abiRange:arg0]"))
                        let effect = try #require(output.range(of: "sideEffect("))
                        let consumer = try #require(output.range(of: "takeOne(?)"))
                        #expect(send.lowerBound < effect.lowerBound && effect.lowerBound < consumer.lowerBound, context)
                    }
                }
            }
        }
    }
}

@Test func objcScalarAndUnavailableSendResultsKeepTheirExistingPrecision() async throws {
    for types in [["q"], []] {
        for preset in DemanglePreset.allCases {
            for use in [ObjCResultUse.low, .tail, .scalarArgument] {
                let function = try await analyzeObjCSendResult(types, use: use, preset: preset)
                for output in [function.renderPseudo(), function.renderStructured()] {
                    let expected = use == .scalarArgument ? "return takeOne([self abiRange:arg0])" : "return [self abiRange:arg0]"
                    #expect(output.contains(expected), Comment(rawValue: output))
                    #expect(output.components(separatedBy: "[self abiRange:arg0]").count == 2)
                }
            }
        }
    }
}

@Test func objcSendResultAgreementIsIndependentOfArguments() async throws {
    // Both declarations pass the same scalar parameter, but a scalar-only
    // interpretation of the selector's return is not safe.
    for use in [ObjCResultUse.low, .tail, .scalarArgument] {
        let function = try await analyzeObjCSendResult(["q", "{SDRange=qq}"], use: use, preset: .simplified)
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(!output.contains("return [self abiRange:"), Comment(rawValue: output))
            #expect(!output.contains("takeOne([self abiRange:"), Comment(rawValue: output))
            #expect(output.components(separatedBy: "[self abiRange:arg0]").count == 2)
        }
    }
}

@Test func objcFloatingScalarSendResultsRemainWholeValues() async throws {
    for type in ["f", "d", "D"] {
        for use in [ObjCResultUse.low, .tail] {
            let function = try await analyzeObjCSendResult([type], use: use, preset: .simplified, callerReturn: type)
            for output in [function.renderPseudo(), function.renderStructured()] {
                #expect(output.contains("return [self abiRange:arg0]"), Comment(rawValue: output))
                #expect(output.components(separatedBy: "[self abiRange:arg0]").count == 2)
            }
        }
    }
}

@Test func objcAggregateSelectorResultsIncludeOpaqueAndSDKDeclarations() {
    let scalar = ObjCMethodBinding(className: "Probe", selector: "abiScalar", typeEncoding: "q@:", isClassMethod: false, signature: "")
    let opaque = ObjCMethodBinding(className: "Probe", selector: "abiOpaque", typeEncoding: "r{Opaque}@:", isClassMethod: false, signature: "")
    let index = ObjCMetadataIndex(methods: [0x1000: [scalar], 0x2000: [opaque]], fieldMaps: [:])
    #expect(index.selectorMayReturnAggregate("abiOpaque"))
    #expect(index.selectorMayReturnAggregate("CGRectValue"))
    #expect(!index.selectorMayReturnAggregate("abiScalar"))
    #expect(!index.selectorMayReturnAggregate("abiUnknownResult"))
}

@Test func objcAggregateSelectorNamesCannotTriggerSwiftBooleanIdioms() async throws {
    for use in [ObjCResultUse.low, .scalarArgument, .xorLow, .andLow] {
        let function = try await analyzeObjCSendResult(["{SDRange=qq}"], use: use, preset: .simplified,
            selector: "__derived_enum_equals")
        for output in [function.renderPseudo(), function.renderStructured()] {
            #expect(!output.contains("self =="), Comment(rawValue: output))
            let expected = switch use {
            case .low: "return ?"
            case .xorLow: "(? ^ 1)"
            case .andLow: "(? & 1)"
            default: "takeOne(?)"
            }
            #expect(output.contains(expected), Comment(rawValue: output))
            #expect(output.components(separatedBy: "[self __derived_enum_equals]").count == 2)
        }
    }
}

@Test func objcSDKResultGuardSurvivesAnImageWithoutObjCMetadata() async throws {
    // PerFunctionContext requires a nonoptional ObjC index. The reachable
    // no-metadata case is the empty index returned by the real builder.
    for preset in DemanglePreset.allCases {
        for use in [ObjCResultUse.low, .tail, .scalarArgument] {
            let aggregate = try await analyzeObjCSendResult([], use: use, preset: preset,
                selector: "CGRectValue", builtEmptyIndex: true)
            for output in [aggregate.renderPseudo(), aggregate.renderStructured()] {
                #expect(!output.contains("return [self CGRectValue]"), Comment(rawValue: output))
                #expect(!output.contains("takeOne([self CGRectValue])"), Comment(rawValue: output))
                #expect(output.components(separatedBy: "[self CGRectValue]").count == 2, Comment(rawValue: output))
                if use == .low { #expect(output.contains("return ?"), Comment(rawValue: output)) }
                if use == .scalarArgument { #expect(output.contains("takeOne(?)"), Comment(rawValue: output)) }
            }
            let unknown = try await analyzeObjCSendResult([], use: use, preset: preset,
                selector: "abiUnknownResult", builtEmptyIndex: true)
            for output in [unknown.renderPseudo(), unknown.renderStructured()] {
                let expected = use == .scalarArgument
                    ? "return takeOne([self abiUnknownResult])" : "return [self abiUnknownResult]"
                #expect(output.contains(expected), Comment(rawValue: output))
            }
        }
    }
}

/// clang -O2: `[self range:value].location` is `bl objc_msgSend$range:; ret`.
/// x0 is one field of the struct, not the send.
@Test func objcAggregateSendResultsAreNotScalarsInARealImageIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCSendResults.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ selector: String) throws -> String {
        try #require(functions.first { $0.displayName == "-[SDStructResultProbe \(selector)]" }).renderStructured()
    }
    for (selector, send) in [("location:", "range"), ("length:", "range"), ("oneField:", "one")] {
        let rendered = try text(selector)
        #expect(rendered.contains("[self \(send):arg0]"), Comment(rawValue: rendered))
        #expect(!rendered.contains("return [self"), Comment(rawValue: rendered))
    }
    #expect(try text("consumeLocation:").contains("consumeLong(?)"))
    #expect(try text("scalarForward:").contains("return [self scalar:arg0]"))
}
