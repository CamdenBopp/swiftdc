import Foundation
import Testing
@testable import SwiftDecompilerCore

private enum TailReturnInput: CaseIterable {
    case unknownLoad, retainedUnknownLoad, knownSelf

    var words: [UInt32] {
        switch self {
        case .unknownLoad: [0xf9400100, 0x140007ff] // ldr x0,[x8]; b 0x3000
        case .retainedUnknownLoad: [0xf9400100, 0x940003ff, 0x140007fe] // ldr; bl 0x2000; b 0x3000
        case .knownSelf: [0x14000800] // b 0x3000, retaining the entry x0
        }
    }
}

// Analysis-only words with explicit method and runtime bindings. The empty
// image backs the resolver; this does not claim that unlinked bytes contain
// Objective-C metadata or form a native callable function.
private func analyzeObjCTailReturn(_ input: TailReturnInput, helper: String,
                                  returns: String, classMethod: Bool,
                                  preset: DemanglePreset) async throws -> DisassembledFunction {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("objc-tail-return-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try await withStableDependencies {
        let machO = try BinaryLoader.load(path: file.path)
        let method = ObjCMethodBinding(className: "TailReturnProbe", selector: "value",
            typeEncoding: "\(returns)16@0:8", isClassMethod: classMethod, signature: "")
        let index = ObjCMetadataIndex(methods: [0x1000: [method]], fieldMaps: [:])
        var resolver = Disassembler.ReferenceResolver(
            names: [0x2000: "swift_unknownObjectRetain", 0x3000: helper],
            stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        // Explicit unit-test resolution evidence, not imports inferred from the
        // empty object image or a helper spelling alone.
        resolver.arcFunctions = [
            0x2000: RuntimeFunctionReference(rawSymbol: "_swift_unknownObjectRetain",
                                            libraryName: "/usr/lib/swift/libswiftCore.dylib"),
            0x3000: RuntimeFunctionReference(rawSymbol: "_" + helper,
                                            libraryName: "/usr/lib/libobjc.A.dylib"),
        ]
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [], objcIndex: index,
            fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
            enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
            classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
        let engine = try #require(CapstoneEngine())
        let words = input.words
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let decoded = engine.disassemble(bytes, address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.map { decoded in
            var facts = Instruction.Facts()
            // These analysis-only inputs explicitly model proven owning-runtime
            // contracts; they do not infer provenance from the helper spelling.
            facts.arcIdentityContract = decoded.controlFlow == .branch || decoded.controlFlow == .call
            return Instruction(address: decoded.address, text: decoded.text, controlFlow: decoded.controlFlow,
                branchTarget: decoded.branchTarget, detail: decoded.detail,
                callee: .kept(decoded.controlFlow == .branch ? helper
                    : decoded.controlFlow == .call ? "swift_unknownObjectRetain" : nil), facts: facts)
        }
        let function = DisassembledFunction(symbol: method.displayName, demangledName: nil,
            startAddress: 0x1000, instructions: instructions, source: .objcMetadata, objcMethod: method)
        let analyzed = Disassembler(preset: preset).analyzeFunction(function, context: context)
        try #require(analyzed.instructions.filter {
            $0.controlFlow == .call || $0.controlFlow == .branch
        }.allSatisfy { $0.facts.arcIdentityContract })
        return analyzed
    }
}

private let tailReturnHelpers = ["objc_autoreleaseReturnValue", "objc_retainAutoreleaseReturnValue",
                                 "objc_claimAutoreleasedReturnValue", "objc_retainAutoreleasedReturnValue"]

@Test func unknownObjCPassthroughTailsKeepTheirValueExit() async throws {
    for input in [TailReturnInput.unknownLoad, .retainedUnknownLoad] {
        for helper in tailReturnHelpers {
            for classMethod in [false, true] {
                for preset in DemanglePreset.allCases {
                    let function = try await analyzeObjCTailReturn(input, helper: helper, returns: "@",
                                                                  classMethod: classMethod, preset: preset)
                    for text in [function.renderPseudo(), function.renderStructured()] {
                        #expect(text.components(separatedBy: "return ?").count == 2, Comment(rawValue: text))
                    }
                }
            }
        }
    }
}

@Test func objcPassthroughTailsKeepKnownValuesAndVoidContracts() async throws {
    for helper in tailReturnHelpers {
        for classMethod in [false, true] {
            for preset in DemanglePreset.allCases {
                let known = try await analyzeObjCTailReturn(.knownSelf, helper: helper, returns: "@",
                                                           classMethod: classMethod, preset: preset)
                let empty = try await analyzeObjCTailReturn(.unknownLoad, helper: helper, returns: "v",
                                                           classMethod: classMethod, preset: preset)
                for text in [known.renderPseudo(), known.renderStructured()] {
                    #expect(text.components(separatedBy: "return self").count == 2, Comment(rawValue: text))
                }
                for text in [empty.renderPseudo(), empty.renderStructured()] {
                    #expect(!text.contains("return ?"), Comment(rawValue: text))
                }
            }
        }
    }
}
