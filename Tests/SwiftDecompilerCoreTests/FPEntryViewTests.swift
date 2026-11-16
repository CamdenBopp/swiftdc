import Darwin
import Foundation
import SwiftLayout
import Testing
@testable import SwiftDecompilerCore

private let fpEntryPath = "Fixtures/Sample/libFPEntries.dylib"

@Test func fpEntryViewsRespectProvenPrecisionInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpEntryPath) else { return }
    let image = try BinaryLoader.load(path: fpEntryPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: fpEntryPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: fpEntryPath, functionFilter: "FPEntries") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    var expected: [String: String] = [:]
    for source in [16, 32, 64] {
        for result in [16, 32, 64] {
            expected["entry\(source)to\(result)"] = source == result ? "arg0" : source < result ? "?"
                : "\(result == 16 ? "Float16" : "Float")(bitPattern: UInt\(result)(truncatingIfNeeded: (arg0.bitPattern & \(result == 16 ? "0xffff" : "0xffffffff"))))"
        }
    }
    expected["clear16to32"] = "Float(bitPattern: UInt32(arg0.bitPattern))"
    expected["clear16to64"] = "Double(bitPattern: UInt64(arg0.bitPattern))"
    expected["clear32to64"] = "Double(bitPattern: UInt64(arg0.bitPattern))"
    expected["narrow32via16"] = "Double(bitPattern: UInt64((arg0.bitPattern & 0xffff)))"
    expected["narrow64via16"] = "Double(bitPattern: (arg0.bitPattern & 0xffff))"
    expected["narrow64via32"] = "Double(bitPattern: (arg0.bitPattern & 0xffffffff))"
    for result in [32, 64] {
        expected["poison16to\(result)"] = "FPEntries.entry16to\(result)(Float16(bitPattern: UInt16(truncatingIfNeeded: (arg0 & 0xffff))))"
    }
    expected["poison32to64"] = "FPEntries.entry32to64(Float(bitPattern: (arg0 & 0xffffffff)))"
    for width in [16, 32, 64] {
        expected["copy\(width)"] = "arg0"
        expected["kept\(width)"] = "arg0"
    }
    #expect(expected.count == 24)
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expression) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(group.first { $0.displayName.hasPrefix("FPEntries.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                #expect(returns == ["return " + expression], Comment(rawValue: text))
            }
        }
    }
    let recorder = ProbeRecorder()
    _ = try await Probe.recording(recorder) {
        try await withStableDependencies {
            try await Disassembler().disassemble(path: fpEntryPath, functionFilter: "FPEntries.entry")
        }
    }
    for width in [16, 32, 64] {
        let record = try #require(recorder.records.first {
            $0.event.id == ProbeEvent.entryConvention.id
                && $0.function?.name.hasPrefix("FPEntries.entry\(width)to\(width)(") == true
        })
        guard case .object(let seeds)? = record["seeds"] else {
            Issue.record("Entry probe must carry typed seed values")
            return
        }
        #expect(seeds["v0"] == ProbeValue.abstractValue(
            .unary(.floatResult(bits: width, upperZero: width == 64), .argument(0))))
    }
}

#if arch(arm64)
@Test func fpEntryNativeOracleChecksRawReadsAndDirtyCallersIfPresent() throws {
    guard FileManager.default.fileExists(atPath: fpEntryPath) else { return }
    let handle = try #require(dlopen(fpEntryPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Fixtures/Sample/fpentries.abi.json")))
    let symbols = try #require((manifest as? [String: Any])?["symbols"] as? [String: String])
    #expect(symbols.count == 24)
    func pointer(_ name: String) throws -> UnsafeMutableRawPointer { try #require(dlsym(handle, try #require(symbols[name]))) }
    func read(_ name: String, source: Int, result: Int, raw: UInt64) throws -> UInt64 {
        let p = try pointer(name)
        switch (source, result) {
        case (16,16): return UInt64(unsafeBitCast(p, to: (@convention(thin) (Float16) -> Float16).self)(Float16(bitPattern: UInt16(raw))).bitPattern)
        case (16,32): return UInt64(unsafeBitCast(p, to: (@convention(thin) (Float16) -> Float).self)(Float16(bitPattern: UInt16(raw))).bitPattern)
        case (16,64): return unsafeBitCast(p, to: (@convention(thin) (Float16) -> Double).self)(Float16(bitPattern: UInt16(raw))).bitPattern
        case (32,16): return UInt64(unsafeBitCast(p, to: (@convention(thin) (Float) -> Float16).self)(Float(bitPattern: UInt32(raw))).bitPattern)
        case (32,32): return UInt64(unsafeBitCast(p, to: (@convention(thin) (Float) -> Float).self)(Float(bitPattern: UInt32(raw))).bitPattern)
        case (32,64): return unsafeBitCast(p, to: (@convention(thin) (Float) -> Double).self)(Float(bitPattern: UInt32(raw))).bitPattern
        case (64,16): return UInt64(unsafeBitCast(p, to: (@convention(thin) (Double) -> Float16).self)(Double(bitPattern: raw)).bitPattern)
        case (64,32): return UInt64(unsafeBitCast(p, to: (@convention(thin) (Double) -> Float).self)(Double(bitPattern: raw)).bitPattern)
        default: return unsafeBitCast(p, to: (@convention(thin) (Double) -> Double).self)(Double(bitPattern: raw)).bitPattern
        }
    }
    let patterns: [Int: [UInt64]] = [
        16: [0, 1, 0x8000, 0x3c00, 0x7c00, 0x7c01, 0x7e01, 0xffff],
        32: [0, 1, 0x80000000, 0x3f800000, 0x7f800000, 0x7f800001, 0x7fc00001, 0xffffffff],
        64: [0, 1, 0x8000000000000000, 0x3ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000001, 0x7ff8000000000001, .max],
    ]
    var observations = 0
    func check(_ actual: UInt64, _ expected: UInt64, _ name: String) {
        #expect(actual == expected, Comment(rawValue: name + ": " + String(actual, radix: 16)))
        observations += 1
    }
    // These compiler-generated call sites clear unused bits. The raw callers
    // below prove that this is not a fact the callee can assume from its ABI.
    for source in [16, 32, 64] {
        for raw in try #require(patterns[source]) {
            for result in [16, 32, 64] {
                check(try read("entry\(source)to\(result)", source: source, result: result, raw: raw),
                      result == 64 ? raw : raw & ((UInt64(1) << result) - 1), "entry\(source)to\(result)")
            }
        }
    }
    for source in [16, 32, 64] {
        for raw in try #require(patterns[source]) {
            for name in ["copy", "kept"] {
                check(try read("\(name)\(source)", source: source, result: source, raw: raw), raw, "\(name)\(source)")
            }
        }
    }
    for (source, result) in [(16,32),(16,64),(32,64)] {
        for raw in try #require(patterns[source]) { check(try read("clear\(source)to\(result)", source: source, result: result, raw: raw), raw, "clear\(source)to\(result)") }
    }
    for (source, via) in [(32,16),(64,16),(64,32)] {
        for raw in try #require(patterns[source]) { check(try read("narrow\(source)via\(via)", source: source, result: 64, raw: raw), raw & ((UInt64(1) << via) - 1), "narrow\(source)via\(via)") }
    }
    for (source, result) in [(16,32),(16,64),(32,64)] {
        let p = try pointer("poison\(source)to\(result)")
        for raw: UInt64 in [0, 1, 0x3c00, 0xabcd3c00, 0x123456783f803c00, 0xfedcba983f803c00, 0x7ff8000000007e01, .max] {
            let actual: UInt64 = result == 32
                ? UInt64(unsafeBitCast(p, to: (@convention(thin) (UInt64) -> Float).self)(raw).bitPattern)
                : unsafeBitCast(p, to: (@convention(thin) (UInt64) -> Double).self)(raw).bitPattern
            check(actual, result == 64 ? raw : raw & 0xffffffff, "poison\(source)to\(result)")
        }
    }
    #expect(observations == 192)
}
#endif

@Test func fpEntryWidthEvidenceCoversScalarObjCHFAAndAsyncSeeds() {
    let arguments: [Int: ValueType] = [0: .floating(16), 1: .signedInteger(64), 2: .floating(32), 3: .floating(64)]
    let registers = ["v0": 0, "x0": 1, "v1": 2, "v2": 3]
    for entry in [MethodEntryConvention.swiftFunction(scalarArguments: registers), .swiftInstance(scalarArguments: registers)] {
        #expect(Disassembler.entryFloatingWidths(entry, argumentTypes: arguments) == ["v0": 16, "v1": 32, "v2": 64])
    }
    let method = ObjCMethodBinding(className: "Entry", selector: "take:float:double:", typeEncoding: "v@:qfd", isClassMethod: false, signature: "")
    for entry in [MethodEntryConvention.objectiveC(argumentCount: 3, scalarArguments: ["x2": 0, "v0": 1, "v1": 2]),
                  .objectiveCInitializer(argumentCount: 3, scalarArguments: ["x2": 0, "v0": 1, "v1": 2])] {
        #expect(Disassembler.entryFloatingWidths(entry, argumentTypes: arguments, objcMethod: method) == ["v0": 32, "v1": 64])
    }
    let floats = FieldMap(typeName: "PairF", instanceSize: 8, fields: [(0,4,"x","Sf"),(4,4,"y","Sf")])
    let doubles = FieldMap(typeName: "PairD", instanceSize: 16, fields: [(0,8,"x","Sd"),(8,8,"y","Sd")])
    let hfa = MethodEntryConvention.swiftValueInstance(seededRegisters: ["v0": .selfFieldValue(offset: 0), "v1": .selfFieldValue(offset: 4),
        "v2": .argumentField(argument: 1, offset: 0), "v3": .argument(0), "v4": .argumentField(argument: 1, offset: 7),
        "v5": .argument(1), "x0": .argument(3)])
    #expect(Disassembler.entryFloatingWidths(hfa, argumentTypes: arguments, fieldMap: floats, argumentFieldMaps: [1: doubles])
        == ["v0": 32, "v1": 32, "v2": 64, "v3": 16])
    let freeHFA = MethodEntryConvention.swiftFunction(scalarArguments: ["v3": 0],
        argumentFields: ["v0": [1, 0], "v1": [1, 8], "v2": [1, 7], "v4": [1]])
    #expect(Disassembler.entryFloatingWidths(freeHFA, argumentTypes: arguments, argumentFieldMaps: [1: doubles])
        == ["v0": 64, "v1": 64, "v3": 16])
    let mixed = FieldMap(typeName: "Mixed", instanceSize: 16, fields: [(0,4,"x","Sf"),(8,8,"y","Si")])
    let mixedEntry = MethodEntryConvention.swiftFunction(scalarArguments: [:],
        argumentFields: ["v0": [1, 0], "v1": [1, 8]])
    #expect(Disassembler.entryFloatingWidths(mixedEntry, argumentTypes: [:], argumentFieldMaps: [1: mixed]) == ["v0": 32])
    let wrongSize = FieldMap(typeName: "WrongSize", instanceSize: 16, fields: [(0,8,"x","Sf"),(8,8,"y","Si")])
    #expect(Disassembler.entryFloatingWidths(mixedEntry, argumentTypes: [:], argumentFieldMaps: [1: wrongSize]).isEmpty)
    let truncated = FieldMap(typeName: "Truncated", instanceSize: 4, fields: [(0,8,"x","Sd")])
    #expect(Disassembler.entryFloatingWidths(mixedEntry, argumentTypes: [:], argumentFieldMaps: [1: truncated]).isEmpty)
    // The Swift-layout initializer retains computed field ranges. A field
    // can still exceed the aggregate's declared size and must not prove a width.
    let shortLayout = FieldMap(typeName: "ShortLayout", layout: AggregateFieldLayout(fields: [
        FieldLayoutEntry(fieldName: "x", offset: 0, typeMangledName: "Sd",
            layout: StaticTypeLayout(size: 8, stride: 8, alignmentMask: 7,
                extraInhabitantCount: 0, isBitwiseTakable: true), resolution: .computed),
    ], size: 4, stride: 4, alignment: 8, extraInhabitantCount: 0))
    #expect(Disassembler.entryFloatingWidths(mixedEntry, argumentTypes: [:], argumentFieldMaps: [1: shortLayout]).isEmpty)
    let async = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: registers), seededRegisters: ["v0": .awaitResult(0), "v3": .argument(3)])
    #expect(Disassembler.entryFloatingWidths(async, argumentTypes: arguments) == ["v1": 32, "v2": 64, "v3": 64])
    #expect(Disassembler.entryFloatingWidths(nil, argumentTypes: arguments).isEmpty)
}

@Test func fpEntryPrecisionSurvivesInitialJoinsAndCallSnapshots() throws {
    let engine = try #require(CapstoneEngine())
    func function(_ words: [UInt32]) -> DisassembledFunction {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail, callee: .kept($0.controlFlow == .call ? "Entry.sink() -> ()" : nil))
        }
        return DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000, instructions: body, source: .symbol)
    }
    let entry = MethodEntryConvention.swiftFunction(scalarArguments: ["v0": 0, "x0": 1])
    let direct = function([0xd65f03c0])
    let joined = function([0xb4000040, 0xd503201f, 0xd65f03c0])
    let called = function([0x94000800, 0xd65f03c0])
    for bits in [16, 32, 64] {
        var tracer = ValueTracer()
        tracer.entryFloatWidths = ["v0": bits, "v7": 64, "x0": 16]
        let expected = AbstractValue.unary(.floatResult(bits: bits, upperZero: bits == 64), .argument(0))
        for body in [direct, joined] {
            let analysis = tracer.analyze(body, entry: entry)
            #expect(analysis.exitFloatValues[body.instructions.last!.address] == expected)
            #expect(analysis.exitValues[body.instructions.last!.address] == .argument(1))
        }
        let seeds = Dictionary(uniqueKeysWithValues: ValueTracer.entrySeeds(entry, floatWidths: tracer.entryFloatWidths).map { ($0.register, $0.value) })
        #expect(seeds["v0"] == expected)
        #expect(seeds["v7"] == nil)
        #expect(seeds["x0"] == .argument(1))
        let call = try #require(tracer.analyze(called, entry: entry).callSites.values.first)
        #expect(call.floatArguments[0] == expected)
        #expect(call.floatArguments[7] == .unknown)
    }
    for invalid in [0, 8, 128, Int.max] {
        var tracer = ValueTracer(); tracer.entryFloatWidths = ["v0": invalid]
        #expect(tracer.analyze(direct, entry: entry).exitFloatValues.isEmpty)
    }
    var tracer = ValueTracer(); tracer.entryFloatWidths = ["v00": 16]
    #expect(tracer.analyze(direct, entry: entry).exitFloatValues[0x1000] == .argument(0))
}


@Test func fpEntryPrecisionPreventsWidenedArgumentsBecomingAsyncSlotProofs() throws {
    let engine = try #require(CapstoneEngine())
    func function(_ words: [UInt32], at address: UInt64, width: Int) -> DisassembledFunction {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: address).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let type = width == 16 ? "Float16" : width == 32 ? "Float" : "Double"
        let code = width == 16 ? "s7Float16V" : width == 32 ? "Sf" : "Sd"
        return DisassembledFunction(symbol: address == 0x1000 ? "$s9FPEntries5chainys6UInt64V\(code)YaF" : "resume",
            demangledName: address == 0x1000 ? "FPEntries.chain(Swift.\(type)) async -> Swift.UInt64" : nil,
            startAddress: address, instructions: body, source: .address)
    }
    for width in [16, 32, 64] {
        // fmov x1,d0; str x1,[x22,#16]; adr x0,resume; b swift_task_switch.
        // Reading all of D0 is unproved for a half/single entry parameter.
        // It must not become a portable integer fact in the resume context.
        // This is a synthetic analysis seam, not a complete native async ABI fixture.
        let entry = function([0x9e660001, 0xf9000ac1, 0x10007fc0, 0x14000bfd], at: 0x1000, width: width)
        #expect(Disassembler.swiftScalarArgumentRegisters(of: entry) == ["v0": 0])
        let resume = function([0xf9400ac0, 0xd65f03c0], at: 0x2000, width: width)
        let raw: [UInt64: DisassembledFunction] = [0x1000: entry, 0x2000: resume]
        let index = AsyncFuncletIndex.build(hints: .init(entries: [0x1000], awaitReturns: [], continuations: [0x2000]),
            functionStarts: Set(raw.keys), instructions: { raw[$0]?.instructions ?? [] },
            nameOf: { $0 == 0x4000 ? "swift_task_switch" : raw[$0]?.displayName })
        try #require(index.chains[0x1000] == [0x1000, 0x2000])
        let functions = raw.mapValues { function in
            index.info(for: function.startAddress, parentName: { raw[$0]?.displayName })
                .map(function.attachingAsyncFunclet) ?? function
        }
        let slots = Disassembler().asyncChainSlots(index: index, function: { functions[$0] },
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex())
        let value = slots[0x2000]?[16]
        if width < 64 {
            #expect(value == nil)
        } else {
            #expect(value == .unary(.bitPattern(bits: 64),
                .unary(.floatResult(bits: 64, upperZero: true), .argument(0))))
        }
    }
}
