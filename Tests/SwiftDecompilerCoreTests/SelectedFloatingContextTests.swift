import Ccapstone
import Foundation
import Testing
@testable import SwiftDecompilerCore

private enum SelectedFloatingUse: CaseIterable {
    case field, pairedField, setter, objcReturn, optionalArgument, indirectResult
}

private func selectedFloatingContext(_ use: SelectedFloatingUse, selected: Bool = true) async throws -> DisassembledFunction {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("selected-float-\(UUID().uuidString).o")
    let header: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 1, 0, 0, 0, 0]
    var data = Data(header.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    data.append(Data(count: 1024 - data.count))
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try await withStableDependencies {
        let machO = try BinaryLoader.load(path: file.path)
        // The same independently assembled branch/dup shape as the native
        // fixture: zero selects Double 2, nonzero Double 1.
        var words: [UInt32] = [use == .objcReturn ? 0xb4000082 : 0xb4000080,
            0xd2e7fe09, 0x4e080d28, 0x14000003, 0xd2e80009, 0x4e080d28]
        if !selected {
            // The same 1.0 bits without a join. These stores keep their prior
            // raw-word rendering; only selected IEEE arms are this fix's scope.
            words = [words[1], words[2]]
        }
        var call: (Int, String)?
        switch use {
        case .field: words += [0xfd000a88] // str d8,[x20,#16]
        case .indirectResult:
            // Five Doubles exceed the four-register HFA limit: stores fill x8.
            words += [0xfd000108, 0xfd000508, 0xfd000908, 0xfd000d08, 0xfd001108]
        case .pairedField: words += [0x6d012288] // stp d8,d8,[x20,#16]
        case .setter:
            words += [0x1e604100, 0x940007f9] // fmov d0,d8; bl 0x3000
            call = (7, "VectorJoin.FPBox.value.setter : Swift.Double")
        case .objcReturn: words += [0x1e604100]
        case .optionalArgument:
            words += [0x9e660100, 0xd2800001, 0x940007f8] // fmov x0,d8; tag=some; call
            call = (8, "VectorJoin.consumeOptional(Swift.Double?) -> ()")
        }
        words += [0xd65f03c0]
        let engine = try #require(CapstoneEngine())
        let decoded = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000)
        try #require(decoded.count == words.count)
        let instructions = decoded.enumerated().map { index, instruction in
            Instruction(address: instruction.address, text: instruction.text,
                controlFlow: instruction.controlFlow, branchTarget: instruction.branchTarget,
                detail: instruction.detail, callee: .kept(index == call?.0 ? call?.1 : nil))
        }
        let objc = use == .objcReturn ? ObjCMethodBinding(className: "FPBox", selector: "choose:",
            typeEncoding: "d24@0:8q16", isClassMethod: false, signature: "") : nil
        let name: String? = use == .objcReturn ? nil : use == .indirectResult
            ? "VectorJoin.makeResult(Swift.Int) -> VectorJoin.FloatResult"
            : "VectorJoin.FPBox.choose(Swift.Int) -> ()"
        let function = DisassembledFunction(symbol: "_$s10VectorJoin5FPBoxC6chooseyySiF",
            demangledName: name, startAddress: 0x1000, instructions: instructions,
            source: objc == nil ? .symbol : .objcMetadata, objcMethod: objc)
        var fields = [(offset: 16, bytes: 8, name: "value", typeEncoding: "Sd")]
        if use == .pairedField { fields.append((offset: 24, bytes: 8, name: "other", typeEncoding: "Sd")) }
        let map = FieldMap(typeName: "VectorJoin.FPBox", instanceSize: use == .pairedField ? 32 : 24, fields: fields)
        let resultMap = FieldMap(typeName: "VectorJoin.FloatResult", instanceSize: 40,
            fields: (0..<5).map { (offset: $0 * 8, bytes: 8, name: "f\($0)", typeEncoding: "Sd") })
        let maps = ["VectorJoin.FPBox": map, "VectorJoin.FloatResult": resultMap]
        let resolver = Disassembler.ReferenceResolver(names: [0x3000: call?.1 ?? "VectorJoin.FPBox.value.setter : Swift.Double"], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [0x3000],
            objcIndex: ObjCMetadataIndex(methods: objc.map { [0x1000: [$0]] } ?? [:], fieldMaps: [:]),
            fieldMaps: maps, selfIndex: SelfTypeIndex(bindings: use == .indirectResult ? [:] : [0x1000: SelfBinding(selfTypeName: "FPBox",
                kind: "method", isInstance: true, source: .vtableSlot(type: "VectorJoin.FPBox", slot: 0))]),
            vtableIndex: VTableIndex(methods: use == .setter ? ["FPBox": [0x60: 0x3000]] : [:]), enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
            classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
            asyncIndex: .empty, asyncChainSlots: [:])
        return Disassembler().analyzeFunction(function, context: context)
    }
}

@Test func selectedFloatingWordsRespectFieldSetterObjCReturnAndOptionalPayloadTypes() async throws {
    for use in SelectedFloatingUse.allCases {
        let function = try await selectedFloatingContext(use)
        for output in [function.renderStructured(), function.renderPseudo()] {
            #expect(output.contains("1.0") && output.contains("2.0"), Comment(rawValue: "\(use)\n\(output)"))
            #expect(!output.contains("0x3ff0") && !output.contains("0x4000"), Comment(rawValue: "\(use)\n\(output)"))
            if use == .field || use == .setter { #expect(output.contains("self.value ="), Comment(rawValue: output)) }
            if use == .optionalArgument { #expect(output.contains("consumeOptional"), Comment(rawValue: output)) }
            if use == .indirectResult { #expect(output.contains("return VectorJoin.FloatResult("), Comment(rawValue: output)) }
        }
    }
    for use in [SelectedFloatingUse.field, .pairedField] {
        let function = try await selectedFloatingContext(use, selected: false)
        for output in [function.renderStructured(), function.renderPseudo()] {
            #expect(output.contains("0x3ff0000000000000"), Comment(rawValue: output))
            #expect(!output.contains("1.0"), Comment(rawValue: output))
        }
    }
}
