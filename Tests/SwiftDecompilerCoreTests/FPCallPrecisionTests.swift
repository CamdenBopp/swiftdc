import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fpCallPath = "Fixtures/Sample/libFPReturns.dylib"
private let fpCallSources: [(String, Int, UInt64)] = [
    ("16", 16, 0x3c00), ("32", 32, 0x3f800000), ("64", 64, 0x3ff0000000000000),
    ("Dirty16", 16, 0x123456783f803c00), ("Dirty32", 32, 0x123456783f800000),
]
private func fpCallView(_ call: String, source: Int, result: Int) -> String {
    if source == result { return call }
    if source < result { return "?" }
    let type = result == 16 ? "Float16" : "Float"
    let mask = result == 16 ? "0xffff" : "0xffffffff"
    return "\(type)(bitPattern: UInt\(result)(truncatingIfNeeded: (\(call).bitPattern & \(mask))))"
}

@Test func fpCallResultsKeepDeclaredPrecisionAndEvaluationInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpCallPath) else { return }
    let image = try BinaryLoader.load(path: fpCallPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: fpCallPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: fpCallPath, functionFilter: "FPReturns") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for (label, source, _) in fpCallSources {
            for result in [16, 32, 64] {
                let call = "FPReturns.produce\(label)()"
                let value = fpCallView(call, source: source, result: result)
                for prefix in ["call", "forward"] {
                    let function = try #require(group.first { $0.displayName.hasPrefix("FPReturns.\(prefix)\(label)to\(result)(") })
                    let expected = prefix == "call" ? value : "FPReturns.sink\(result)(\(value))"
                    for text in [function.renderPseudo(), function.renderStructured()] {
                        let statements = text.split(separator: "\n").dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
                        #expect(Array(statements) == (source < result ? [call, "return " + expected] : ["return " + expected]), Comment(rawValue: text))
                        #expect(text.components(separatedBy: call).count == 2, Comment(rawValue: text))
                    }
                }
            }
        }
        for source in [32, 64] {
            for result in [16, 32, 64] {
                let call = source == 32 ? "cosf(0.0)" : "cos(0.0)"
                let value = fpCallView(call, source: source, result: result)
                let function = try #require(group.first { $0.displayName.hasPrefix("FPReturns.c\(source)to\(result)(") })
                for text in [function.renderPseudo(), function.renderStructured()] {
                    let statements = text.split(separator: "\n").dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
                    #expect(Array(statements) == (source < result ? [call, "return ?"] : ["return " + value]), Comment(rawValue: text))
                }
            }
        }
    }
}

#if arch(arm64)
@Test func fpCallNativeOracleChecksDirtyBitsAndOneEvaluationIfPresent() throws {
    guard FileManager.default.fileExists(atPath: fpCallPath) else { return }
    let handle = try #require(dlopen(fpCallPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Fixtures/Sample/fpreturns.abi.json")))
    let symbols = try #require((manifest as? [String: Any])?["symbols"] as? [String: String])
    #expect(symbols.count == 44)
    let counter = try #require(dlsym(handle, "fp_return_counter")).assumingMemoryBound(to: UInt64.self)
    func read(_ name: String, result: Int) throws -> UInt64 {
        let pointer = try #require(dlsym(handle, try #require(symbols[name])))
        switch result {
        case 16: return UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> Float16).self)().bitPattern)
        case 32: return UInt64(unsafeBitCast(pointer, to: (@convention(thin) () -> Float).self)().bitPattern)
        default: return unsafeBitCast(pointer, to: (@convention(thin) () -> Double).self)().bitPattern
        }
    }
    var observations = 0
    for (label, _, raw) in fpCallSources {
        for result in [16, 32, 64] {
            for prefix in ["call", "forward"] {
                counter.pointee = 0
                let actual = try read("\(prefix)\(label)to\(result)", result: result)
                #expect(actual == (result == 64 ? raw : raw & ((UInt64(1) << result) - 1)))
                #expect(counter.pointee == 1)
                observations += 1
            }
        }
    }
    for source in [32, 64] {
        for result in [16, 32, 64] {
            let actual = try read("c\(source)to\(result)", result: result)
            let raw: UInt64 = source == 32 ? 0x3f800000 : 0x3ff0000000000000
            // A C float result promises no high bits. Check only its ABI bits.
            let proven = min(source, result)
            let mask: UInt64 = proven == 64 ? .max : (UInt64(1) << proven) - 1
            #expect(actual & mask == raw & mask)
            observations += 1
        }
    }
    #expect(observations == 36)
}
#endif

@Test func fpCallWidthEvidenceRequiresExactSynchronousScalarTypes() {
    for (type, width) in [("Swift.Float16",16), ("Swift.Float",32), ("Swift.Float32",32),
                          ("Swift.Double",64), ("Swift.Float64",64), ("Swift.CGFloat",64), ("CoreGraphics.CGFloat",64)] {
        #expect(Disassembler.scalarFloatingWidth(type) == width)
        #expect(Disassembler.callResultBank(of: "Calls.produce() -> " + type,
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()) == .scalarFloating(bits: width))
        #expect(Disassembler.callResultBank(of: "Calls.value.getter : " + type,
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()) == .scalarFloating(bits: width))
    }
    for type in ["Calls.DoubleBox", "Swift.Optional<Swift.Float>", "(Swift.Float, Swift.Float)", "A", "Float", ""] {
        #expect(Disassembler.scalarFloatingWidth(type) == nil)
    }
    for name in ["Calls.produce() async -> Swift.Float", "Calls.produce() -> A", "objc_msgSend", "produce"] {
        #expect(Disassembler.callResultBank(of: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()) == .unknown)
    }
    for bits in [16, 32, 64] {
        let value = ValueTracer.CallResultBank.scalarFloating(bits: bits).floatingValue(at: 0x1000)
        #expect(value == .unary(.floatResult(bits: bits, upperZero: bits == 64), .callResult(0x1000)))
    }
    for bits in [0, 8, 128, Int.max] {
        #expect(ValueTracer.CallResultBank.scalarFloating(bits: bits).floatingValue(at: 0x1000) == .unknown)
    }
    #expect(ValueTracer.CallResultBank.floating.floatingValue(at: 0x1000) == .callResult(0x1000))
    #expect(ValueTracer.CallResultBank.integer.floatingValue(at: 0x1000) == nil)
}

@Test func fpCallTracerTagsOnlyProvenResultBanks() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ name: String, bank: ValueTracer.CallResultBank?, inImage: Bool = false) -> (AbstractValue?, AbstractValue?) {
        let words: [UInt32] = [0x94000800, 0xd65f03c0] // bl 0x3000; ret
        let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
        let instructions = engine.disassemble(bytes, address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail, callee: .kept($0.controlFlow == .call ? name : nil))
        }
        let function = DisassembledFunction(symbol: "probe", demangledName: nil, startAddress: 0x1000, instructions: instructions, source: .symbol)
        var tracer = ValueTracer()
        tracer.callResultBank = { _ in bank ?? .unknown }
        if inImage { tracer.inImageCallTargets = [0x3000] }
        let analysis = tracer.analyze(function)
        return (analysis.exitValues[0x1004], analysis.exitFloatValues[0x1004])
    }
    for (name, width) in [("cosf",32), ("cos",64)] {
        let result = trace(name, bank: nil)
        #expect(result.0 == nil || result.0 == .unknown)
        #expect(result.1 == .unary(.floatResult(bits: width, upperZero: width == 64), .callResult(0x1000)))
        // An in-image name twin does not inherit the system C prototype.
        #expect(trace(name, bank: nil, inImage: true).1 == .callResult(0x1000))
    }
    for width in [16,32,64] {
        let result = trace("Calls.produce() -> Swift.Float", bank: .scalarFloating(bits: width))
        #expect(result.0 == nil || result.0 == .unknown)
        #expect(result.1 == .unary(.floatResult(bits: width, upperZero: width == 64), .callResult(0x1000)))
    }
    #expect(trace("Calls.integer() -> Swift.Int", bank: .integer).0 == .callResult(0x1000))
    #expect(trace("Calls.integer() -> Swift.Int", bank: .integer).1 == nil)
    #expect(trace("Calls.aggregate() -> Calls.Box", bank: .floating).1 == .callResult(0x1000))
}

// Analysis-only Objective-C and async return seams. Explicit metadata and
// bindings back these words; this is not a native async or Objective-C fixture.
@Test func fpCallPrecisionPreservesProducersAtObjCAndAsyncReturns() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("fp-call-seam-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withStableDependencies {
        let image = try BinaryLoader.load(path: file.path)
        let engine = try #require(CapstoneEngine())
        for isAsync in [false, true] {
            for source in [16,32,64] {
                for result in [32,64] {
                    let resultType = result == 32 ? "Float" : "Double"
                    let sourceType = source == 16 ? "Float16" : source == 32 ? "Float" : "Double"
                    let call = "Calls.produce() -> Swift.\(sourceType)"
                    let method = ObjCMethodBinding(className: "FPCallProbe", selector: "value",
                        typeEncoding: "\(result == 32 ? "f" : "d")16@0:8", isClassMethod: false, signature: "")
                    let name = "Calls.probe() async -> Swift.\(resultType)"
                    let index = ObjCMetadataIndex(methods: isAsync ? [:] : [0x1000: [method]], fieldMaps: [:])
                    let resolver = Disassembler.ReferenceResolver(names: [0x3000: call], stringRanges: [], machO: image, demangleSymbol: { _ in nil })
                    let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [], objcIndex: index,
                        fieldMaps: [:], selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
                        enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(), classTypeIndex: ClassTypeIndex(),
                        classParameterFields: ClassParameterFieldIndex(), asyncIndex: .empty, asyncChainSlots: [:])
                    // bl producer; ret, or load/branch through ResumeParent.
                    let words: [UInt32] = isAsync ? [0x94000800, 0xf94006c8, 0xd61f0100] : [0x94000800, 0xd65f03c0]
                    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
                    let instructions = engine.disassemble(bytes, address: 0x1000).map {
                        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow, branchTarget: $0.branchTarget,
                            detail: $0.detail, callee: .kept($0.controlFlow == .call ? call : nil))
                    }
                    var function = DisassembledFunction(symbol: isAsync ? "probe" : method.displayName, demangledName: isAsync ? name : nil,
                        startAddress: 0x1000, instructions: instructions, source: .address, objcMethod: isAsync ? nil : method)
                    if isAsync {
                        function = function.attachingAsyncFunclet(AsyncFuncletInfo(parent: 0x1000, parentName: name,
                            ordinal: 0, kind: nil, predecessor: nil, chain: [0x1000]))
                    }
                    let analyzed = Disassembler().analyzeFunction(function, context: context)
                    for text in [analyzed.renderPseudo(), analyzed.renderStructured()] {
                        let expression = "Calls.produce()"
                        #expect(text.components(separatedBy: expression).count == 2, Comment(rawValue: text))
                        if source < result {
                            #expect(text.contains("return ?"), Comment(rawValue: text))
                            #expect(!text.contains("return " + expression), Comment(rawValue: text))
                        } else {
                            #expect(text.contains("return " + fpCallView(expression, source: source, result: result)), Comment(rawValue: text))
                        }
                    }
                }
            }
        }
    }
}
