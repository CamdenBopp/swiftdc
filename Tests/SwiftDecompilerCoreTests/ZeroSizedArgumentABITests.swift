import Foundation
import Testing
@testable import SwiftDecompilerCore

private func voidArgumentFunction(_ parameters: [String], words: [UInt32] = [], generic: Bool = false,
                                  symbol: String = "$s1M4take") throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = (words + [0xD65F_03C0]).flatMap { word in
        (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
    }
    return DisassembledFunction(symbol: symbol,
        demangledName: "M.take" + (generic ? "<A>" : "") + "(" + parameters.joined(separator: ", ") + ") -> Swift.Int",
        startAddress: 0x1000, instructions: engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .symbol)
}

@Test func voidArgumentsKeepSourceSlotsWithoutUsingEitherBank() throws {
    for type in ["()", "Swift.Void"] {
        let function = try voidArgumentFunction(["Swift.Double", type, "Swift.Int", type, "Swift.Float", "Swift.Int"])
        #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == ["v0": 0, "x0": 2, "v1": 4, "x1": 5])
        let layout = try #require(Disassembler.swiftCallArgumentLayout(callee: function.analysisName!,
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), fieldMaps: [:]))
        #expect(layout.stack.isEmpty)
        #expect(layout.slots.map(\.kind) == [.floating, .aggregate(integers: 0, floats: 0), .integer,
                                           .aggregate(integers: 0, floats: 0), .floating, .integer])
        #expect(layout.slots.map(\.type) == ["Swift.Double", type, "Swift.Int", type, "Swift.Float", "Swift.Int"])
        let banks = try #require(SwiftLowering.aggregateRegisters(of: type, fieldMaps: [:]))
        #expect(banks.integers == 0 && banks.floats == 0)
    }
}

@Test func voidArgumentsLetDecodedTailValuesKeepTheirSourceIndices() throws {
    for (parameters, register, source) in [
        (["()", "Swift.Int"], 0, 1),
        (["()", "Swift.Void", "Swift.Int"], 0, 2),
        (["Swift.Int", "()", "Swift.Int"], 1, 2),
        (Array(repeating: "Swift.Int", count: 7) + ["()", "Swift.Int"], 7, 8),
    ] {
        // mov x0, x<register>; ret
        let function = try voidArgumentFunction(parameters, words: [UInt32(0xAA00_03E0) | UInt32(register << 16)])
        let registers = try #require(Disassembler.swiftScalarArgumentRegisters(of: function))
        #expect(registers["x\(register)"] == source)
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: registers))
        #expect(analysis.exitValues[0x1004] == .argument(source))
    }
}

@Test func voidArgumentsDoNotExhaustRegistersOrEraseArity() throws {
    for parameters in [["()", "Swift.Void"], Array(repeating: "Swift.Int", count: 8) + ["()"]] {
        let function = try voidArgumentFunction(parameters)
        let registers = try #require(Disassembler.swiftScalarArgumentRegisters(of: function))
        #expect(registers.count == (parameters.count == 2 ? 0 : 8))
        let layout = try #require(Disassembler.swiftCallArgumentLayout(callee: function.analysisName!,
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), fieldMaps: [:]))
        #expect(layout.unplaced == 0)
        #expect(layout.slots.count == parameters.count)
    }
    let overflow = try voidArgumentFunction(Array(repeating: "Swift.Int", count: 8) + ["()", "Swift.Int"])
    #expect(Disassembler.swiftScalarArgumentRegisters(of: overflow) == nil)
    let layout = try #require(Disassembler.swiftCallArgumentLayout(callee: overflow.analysisName!,
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), fieldMaps: [:]))
    #expect(layout.slots.count == 9 && layout.unplaced == 1)
}

@Test func voidArgumentsDoNotChangePointersFunctionsOrUnknownTuples() throws {
    for type in ["Swift.Optional<()>", "Swift.Optional<Swift.Void>", "((), Swift.Int)", "((), ())", "Swift.Void.Type"] {
        #expect(SwiftLowering.aggregateRegisters(of: type, fieldMaps: [:]) == nil, "\(type)")
        let function = try voidArgumentFunction([type, "Swift.Int"])
        #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == nil, "\(type)")
    }
    for type in ["inout ()", "inout Swift.Void", "Swift.Array<()>", "Swift.UnsafePointer<()>"] {
        let function = try voidArgumentFunction([type, "Swift.Int"])
        #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == ["x0": 0, "x1": 1], "\(type)")
    }
}

@Test func voidArgumentsPlaceGenericMetadataAfterOnlyPhysicalFormals() throws {
    // swiftc: `@"$s1M4takeySiyt_xSitlF"(ptr noalias %0, i64 %1, ptr %A)`.
    let function = try voidArgumentFunction(["()", "A", "Swift.Int"], generic: true, symbol: "$s1M4takeySiyt_xSitlF")
    #expect(Disassembler.swiftScalarArgumentRegisters(of: function) == ["x0": 1, "x1": 2])
    #expect(Disassembler.genericMetadataRegisters(of: function, enumCaseIndex: EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex(), fieldMaps: [:]) == ["x2": "A"])
}

@Test func voidArgumentsKeepClassFieldMapsOnTheSourceArgument() throws {
    let classes = ClassTypeIndex(classNames: ["Holder"], qualifiedClassNames: ["M.Holder"])
    let holder = FieldMap(typeName: "Holder", instanceSize: 24,
        fields: [(offset: 0x10, bytes: 8, name: "v", typeEncoding: "Si")])
    let fields = ["Holder": holder, "M.Holder": holder]
    let index = ClassParameterFieldIndex(fieldMaps: fields, classTypeIndex: classes)
    // ldr x0, [x0, #0x10]; ret
    let function = try voidArgumentFunction(["()", "M.Holder"], words: [0xF940_0800])
    let registers = try #require(Disassembler.swiftScalarArgumentRegisters(of: function,
        classTypeIndex: classes, fieldMaps: fields))
    #expect(registers == ["x0": 1])
    let maps = Disassembler.classArgumentFieldMaps(of: function, scalarArguments: registers, index: index)
    #expect(maps.keys.sorted() == [1])
    var tracer = ValueTracer()
    tracer.argumentObjectFields = maps.mapValues(Disassembler.wholeWordFieldWidths)
    let analysis = tracer.analyze(function, entry: .swiftFunction(scalarArguments: registers))
    #expect(analysis.exitValues[0x1004] == .argumentField(argument: 1, offset: 0x10))
}

@Test func voidArgumentsKeepLaterParametersInARealImageIfPresent() async throws {
    let path = "Fixtures/Sample/libVoidArguments.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for (name, expression) in [("afterVoid", "(arg1 + 1)"), ("afterQualifiedVoid", "(arg1 + 2)"),
                               ("afterVoids", "(arg2 + 3)"), ("betweenIntegers", "(arg0 - arg2)"),
                               ("betweenFloats", "(arg0 - arg2)")] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("VoidArguments.\(name)(") })
        let text = function.renderStructured()
        #expect(text.contains("return \(expression)"), Comment(rawValue: text))
    }
}
