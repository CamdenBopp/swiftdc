import Ccapstone
import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let signedSelfLoadImages: [(mode: String, path: String)] = [
    ("Onone", "Fixtures/Sample/libSignedSelfLoad.Onone.dylib"),
    ("O", "Fixtures/Sample/libSignedSelfLoad.O.dylib"),
    ("Osize", "Fixtures/Sample/libSignedSelfLoad.Osize.dylib"),
]

private struct SignedScalarFixture {
    enum Consumer: Equatable {
        case float
        case integer
    }

    let owner: String
    let method: String
    let field: String
    let mangling: String
    let width: Int
    let symbol: String
    let cEntry: String
    let load: aarch64_insn
    let destination: PhysReg
    let consumer: Consumer
    let returns: String
    var usesMove: Bool { consumer == .float && destination.kind == .gpr }
    var usesNOP: Bool { method == "signedWord" }
    var resultType: String {
        if consumer == .float { return "Float" }
        return method == "rawWord" ? "UInt64" : "Int64"
    }

    static let cases: [Self] = {
        let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
        let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
        let w0 = PhysReg(kind: .gpr, number: 0, widthBits: 32)
        let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
        return [
            .init(owner: "FloatBox", method: "roundTrip", field: "f", mangling: "Sf", width: 32,
                  symbol: "_$s14SignedSelfLoad8FloatBoxV9roundTripSfyF", cEntry: "signedselfload_round_trip",
                  load: AARCH64_INS_LDRSW, destination: x8, consumer: .float, returns: "return self.f"),
            .init(owner: "FloatBox", method: "roundTripUnscaled", field: "f", mangling: "Sf", width: 32,
                  symbol: "_$s14SignedSelfLoad8FloatBoxV17roundTripUnscaledSfyF", cEntry: "signedselfload_round_trip_unscaled",
                  load: AARCH64_INS_LDURSW, destination: x8, consumer: .float, returns: "return self.f"),
            .init(owner: "FloatBox", method: "plain", field: "f", mangling: "Sf", width: 32,
                  symbol: "_$s14SignedSelfLoad8FloatBoxV5plainSfyF", cEntry: "signedselfload_plain",
                  load: AARCH64_INS_LDR, destination: s0, consumer: .float, returns: "return self.f"),
            .init(owner: "SignedBox", method: "signed", field: "i", mangling: "s5Int32V", width: 32,
                  symbol: "_$s14SignedSelfLoad9SignedBoxV6signeds5Int64VyF", cEntry: "signedselfload_signed",
                  load: AARCH64_INS_LDRSW, destination: x0, consumer: .integer, returns: "return Int64(self.i)"),
            .init(owner: "ByteBox", method: "wide", field: "i", mangling: "s4Int8V", width: 8,
                  symbol: "_$s14SignedSelfLoad7ByteBoxV4wideSfyF", cEntry: "signedselfload_wide_byte",
                  load: AARCH64_INS_LDRSB, destination: x8, consumer: .float,
                  returns: "return Float(bitPattern: UInt32(bitPattern: Int32(self.i)))"),
            .init(owner: "ShortBox", method: "wide", field: "i", mangling: "s5Int16V", width: 16,
                  symbol: "_$s14SignedSelfLoad8ShortBoxV4wideSfyF", cEntry: "signedselfload_wide_short",
                  load: AARCH64_INS_LDRSH, destination: x8, consumer: .float,
                  returns: "return Float(bitPattern: UInt32(bitPattern: Int32(self.i)))"),
            .init(owner: "FloatBox", method: "rawWord", field: "f", mangling: "Sf", width: 32,
                  symbol: "_$s14SignedSelfLoad8FloatBoxV7rawWords6UInt64VyF", cEntry: "signedselfload_raw_word",
                  load: AARCH64_INS_LDR, destination: w0, consumer: .integer,
                  returns: "return UInt64(self.f.bitPattern)"),
            .init(owner: "FloatBox", method: "signedWord", field: "f", mangling: "Sf", width: 32,
                  symbol: "_$s14SignedSelfLoad8FloatBoxV10signedWords5Int64VyF", cEntry: "signedselfload_signed_word",
                  load: AARCH64_INS_LDRSW, destination: x0, consumer: .integer,
                  returns: "return Int64(Int32(bitPattern: self.f.bitPattern))"),
        ]
    }()

    var inputs: [UInt64] {
        switch cEntry {
        case "signedselfload_signed": [0x8000_0000, 0xffff_ffff, 0x1234_5678]
        case "signedselfload_wide_byte": [0x80, 0x25]
        case "signedselfload_wide_short": [0x8000, 0x1234]
        case "signedselfload_raw_word", "signedselfload_signed_word":
            [0x8000_0000, 0x3f90_0001, 0xffc0_1234, 0x8000_0001, 0x0123_4567]
        default: [0x8000_0000, 0x3f90_0001, 0xffc0_1234]
        }
    }

    func expectedBits(_ bits: UInt64) -> UInt64 {
        switch cEntry {
        case "signedselfload_signed", "signedselfload_signed_word":
            UInt64(bitPattern: Int64(Int32(bitPattern: UInt32(bits))))
        case "signedselfload_wide_byte":
            UInt64(UInt32(bitPattern: Int32(Int8(bitPattern: UInt8(bits)))))
        case "signedselfload_wide_short":
            UInt64(UInt32(bitPattern: Int32(Int16(bitPattern: UInt16(bits)))))
        default: bits
        }
    }

    func nativeBits(_ pointer: UnsafeMutableRawPointer, input: UInt64) -> UInt64 {
        switch cEntry {
        case "signedselfload_signed":
            let call = unsafeBitCast(pointer, to: (@convention(c) (Int32) -> Int64).self)
            return UInt64(bitPattern: call(Int32(bitPattern: UInt32(input))))
        case "signedselfload_signed_word":
            let call = unsafeBitCast(pointer, to: (@convention(c) (UInt32) -> Int64).self)
            return UInt64(bitPattern: call(UInt32(input)))
        case "signedselfload_raw_word":
            let call = unsafeBitCast(pointer, to: (@convention(c) (UInt32) -> UInt64).self)
            return call(UInt32(input))
        case "signedselfload_wide_byte":
            let call = unsafeBitCast(pointer, to: (@convention(c) (Int8) -> UInt32).self)
            return UInt64(call(Int8(bitPattern: UInt8(input))))
        case "signedselfload_wide_short":
            let call = unsafeBitCast(pointer, to: (@convention(c) (Int16) -> UInt32).self)
            return UInt64(call(Int16(bitPattern: UInt16(input))))
        default:
            let call = unsafeBitCast(pointer, to: (@convention(c) (UInt32) -> UInt32).self)
            return UInt64(call(UInt32(input)))
        }
    }
}

private struct ScalarExitBits {
    let bits: UInt64
    let usesField: Bool
}

/// Interpret the machine-value expression without trusting rendered Swift or
/// guessing the signedness of a logical field leaf.
private func evaluateScalarExit(_ value: AbstractValue, fieldBits: UInt64, fieldOffset: Int = 0) -> ScalarExitBits? {
    switch value {
    case .selfFieldValue(let offset) where offset == fieldOffset:
        return ScalarExitBits(bits: fieldBits, usesField: true)
    case .immediate(let word):
        return ScalarExitBits(bits: word, usesField: false)
    case .binary(let operation, let lhs, let rhs):
        guard let a = evaluateScalarExit(lhs, fieldBits: fieldBits, fieldOffset: fieldOffset),
              let b = evaluateScalarExit(rhs, fieldBits: fieldBits, fieldOffset: fieldOffset) else { return nil }
        let word: UInt64
        switch operation {
        case .bitAnd: word = a.bits & b.bits
        case .bitOr: word = a.bits | b.bits
        case .shiftLeft where b.bits < 64: word = a.bits << b.bits
        case .arithmeticShiftRight where b.bits < 64:
            word = UInt64(bitPattern: Int64(bitPattern: a.bits) >> b.bits)
        default: return nil
        }
        return ScalarExitBits(bits: word, usesField: a.usesField || b.usesField)
    case .unary(.floatFromBits(let bits), let source), .unary(.floatResult(let bits, _), let source):
        guard bits == 32 else { return nil }
        guard let inner = evaluateScalarExit(source, fieldBits: fieldBits, fieldOffset: fieldOffset) else { return nil }
        return ScalarExitBits(bits: inner.bits & 0xffff_ffff, usesField: inner.usesField)
    default:
        return nil
    }
}

private func verifySignedScalarImage(_ path: String) async throws {
    let imageComment = Comment(rawValue: path)
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(path) before testing.")
        return
    }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST), imageComment)
    defer { dlclose(handle) }
    let image = try BinaryLoader.load(path: path)
    let layouts = try FieldMapBuilder.build(in: image)
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let stream = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "SignedSelfLoad.")
    }
    let x20 = PhysReg(kind: .gpr, number: 20, widthBits: 64)
    let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
    let w8 = PhysReg(kind: .gpr, number: 8, widthBits: 32)
    for row in SignedScalarFixture.cases {
        let owner = "SignedSelfLoad.\(row.owner)"
        let identity = "\(owner).\(row.method)"
        let comment = Comment(rawValue: "\(path): \(identity)")
        let layout = try #require(layouts[owner], comment)
        guard case .success(.whole(let fieldName, let encodedType)) = layout.lookup(offset: 0, bytes: row.width / 8) else {
            Issue.record(Comment(rawValue: "\(path): expected a complete \(row.width)-bit scalar field"))
            continue
        }
        try #require(fieldName == row.field, comment)
        let printable = FieldMap.printableTypeName(mangled: encodedType, resolved: layout.fieldTypeNames[fieldName])
        let resolved = ["Sf": "Swift.Float", "s5Int32V": "Swift.Int32", "s4Int8V": "Swift.Int8", "s5Int16V": "Swift.Int16"][row.mangling]
        try #require(printable == row.mangling || printable == resolved, comment)
        let wrapper = try #require(dlsym(handle, row.cEntry), comment)
        let nativeRows = row.inputs.map { input in (input, row.nativeBits(wrapper, input: input)) }
        for (input, observed) in nativeRows {
            #expect(observed == row.expectedBits(input), Comment(rawValue: "\(path) native \(identity) input \(input)"))
        }
        for (route, functions) in [("array", array), ("stream", stream), ("filtered", filtered)] {
            let routeComment = Comment(rawValue: "\(path) \(route): \(identity)")
            let name = identity + "() -> Swift." + row.resultType
            let matches = functions.filter { $0.symbol == row.symbol && $0.displayName == name }
            try #require(matches.count == 1, routeComment)
            let function = try #require(matches.first, routeComment)
            try #require(function.instructions.count == (row.usesMove || row.usesNOP ? 3 : 2), routeComment)
            let load = try #require(function.instructions[0].detail, routeComment)
            try #require(load.id == row.load && load.operands.count == 2 && !load.postIndex && !load.writeback, routeComment)
            try #require(load.operands[0].operand.register == row.destination, routeComment)
            let directSelf: Bool
            if case .memory(let base, nil, 0) = load.operands[1].operand {
                directSelf = base == x20
            } else {
                directSelf = false
            }
            try #require(directSelf, routeComment)
            if row.usesMove {
                let move = try #require(function.instructions[1].detail, routeComment)
                try #require(move.id == AARCH64_INS_FMOV && move.operands.count == 2, routeComment)
                try #require(move.operands.compactMap { $0.operand.register } == [s0, w8], routeComment)
            }
            if row.usesNOP {
                let nop = try #require(function.instructions[1].detail, routeComment)
                try #require(nop.id == AARCH64_INS_ALIAS_NOP && nop.operands.isEmpty, routeComment)
            }
            let tail = try #require(function.instructions.last, routeComment)
            try #require(tail.detail?.id == AARCH64_INS_RET && tail.controlFlow == .return, routeComment)

            if route == "array" {
                let analysis = ValueTracer().analyze(function, entry: .swiftInstance(scalarArguments: [:]))
                let producer = function.instructions[0]
                let access = try #require(analysis.selfFieldAccesses[producer.address], routeComment)
                try #require(analysis.selfFieldAccesses.count == 1 && access.offset == 0 &&
                             access.bytes == row.width / 8 && !access.isWrite && !access.isAddressOf, routeComment)
                let value = row.consumer == .float ? analysis.exitFloatValues[tail.address] : analysis.exitValues[tail.address]
                for (input, expected) in nativeRows {
                    let result = value.flatMap { evaluateScalarExit($0, fieldBits: input) }
                    let observed = result.map { row.consumer == .float ? $0.bits & 0xffff_ffff : $0.bits }
                    let vectorComment = Comment(rawValue: "\(path) tracer \(identity) input \(input)")
                    #expect(result?.usesField == true, vectorComment)
                    #expect(observed == expected, vectorComment)
                }
            }
            for (renderer, view) in [("pseudo", function.renderPseudo()), ("structured", function.renderStructured())] {
                let returns = view.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("return ") }
                #expect(returns == [row.returns], Comment(rawValue: "\(path) \(route) \(renderer): \(identity)"))
            }
        }
    }
}

@Test func signedSelfLoadsPreserveNativeScalarWidthAndTypedReturnsIfPresent() async throws {
    for image in signedSelfLoadImages {
        try await verifySignedScalarImage(image.path)
    }
}

private struct StorageLoadCase {
    enum Operation: Equatable {
        case signed, signedReinterpretation, zero, signedW, floatW, mixed
    }

    let owner: String
    let bits: Int
    let offset: Int64
    let opcode: aarch64_insn
    let operation: Operation

    static let cases: [Self] = [
        .init(owner: "OffsetByte", bits: 8, offset: 8, opcode: AARCH64_INS_LDRSB, operation: .signed),
        .init(owner: "OffsetHalf", bits: 16, offset: 8, opcode: AARCH64_INS_LDURSH, operation: .signed),
        .init(owner: "OffsetWord", bits: 32, offset: 8, opcode: AARCH64_INS_LDRSW, operation: .signed),
        .init(owner: "UnsignedByte", bits: 8, offset: 0, opcode: AARCH64_INS_LDRSB, operation: .signedReinterpretation),
        .init(owner: "UnsignedHalf", bits: 16, offset: 0, opcode: AARCH64_INS_LDRSH, operation: .signedReinterpretation),
        .init(owner: "UnsignedWord", bits: 32, offset: 0, opcode: AARCH64_INS_LDRSW, operation: .signedReinterpretation),
        .init(owner: "ZeroByte", bits: 8, offset: 0, opcode: AARCH64_INS_LDRB, operation: .zero),
        .init(owner: "ZeroHalf", bits: 16, offset: 0, opcode: AARCH64_INS_LDURH, operation: .zero),
        .init(owner: "SignedWByte", bits: 8, offset: 0, opcode: AARCH64_INS_LDRSB, operation: .signedW),
        .init(owner: "SignedUWByte", bits: 8, offset: 0, opcode: AARCH64_INS_LDURSB, operation: .signedW),
        .init(owner: "SignedWHalf", bits: 16, offset: 0, opcode: AARCH64_INS_LDRSH, operation: .signedW),
        .init(owner: "SignedUWHalf", bits: 16, offset: 0, opcode: AARCH64_INS_LDURSH, operation: .signedW),
        .init(owner: "FloatWByte", bits: 8, offset: 0, opcode: AARCH64_INS_LDRSB, operation: .floatW),
        .init(owner: "FloatWHalf", bits: 16, offset: 0, opcode: AARCH64_INS_LDURSH, operation: .floatW),
        .init(owner: "MixedWord", bits: 32, offset: 0, opcode: AARCH64_INS_LDRB, operation: .mixed),
    ]

    var result: (name: String, mangling: String) {
        switch operation {
        case .signed, .signedReinterpretation: ("Int64", "s5Int64V")
        case .floatW: ("Float", "Sf")
        default: ("UInt64", "s6UInt64V")
        }
    }

    var storage: (name: String, mangling: String) {
        let unsigned = operation == .signedReinterpretation || operation == .zero || operation == .mixed
        let name = (unsigned ? "UInt" : "Int") + String(bits)
        return (name, "s" + String(name.count) + name + "V")
    }

    var inputs: [UInt64] {
        let high = UInt64(1) << (bits - 1)
        switch operation {
        case .signed, .signedW, .floatW: return [high, high * 2 - 1, 0, high - 1]
        case .mixed: return [0x7654_3280, 0xfedc_ba01, 0x8001_01ff, 0, 0xffff_ffff]
        default: return [0, 1, high, high + 1, high * 2 - 1]
        }
    }

    func expected(_ input: UInt64) -> UInt64 {
        let sign = UInt64(1) << (bits - 1)
        let signed = (input ^ sign) &- sign
        switch operation {
        case .signed, .signedReinterpretation: return signed
        case .signedW, .floatW: return signed & 0xffff_ffff
        case .mixed: return ((input & 0xff) << 32) | input
        case .zero: return input
        }
    }

    var renderedReturns: [[String]] {
        switch operation {
        case .signed: [["return Int64(self.value)"]]
        case .signedReinterpretation: [["return Int64(Int" + String(bits) + "(bitPattern: self.value))"]]
        case .zero: [["return UInt64(self.value)"]]
        case .signedW: [["return UInt64(UInt32(bitPattern: Int32(self.value)))"]]
        case .floatW: [["return Float(bitPattern: UInt32(bitPattern: Int32(self.value)))"]]
        case .mixed:
            [
                ["return ((UInt64(UInt8(truncatingIfNeeded: self.value)) << 32) | UInt64(self.value))"],
                ["return (UInt64(self.value) | (UInt64(UInt8(truncatingIfNeeded: self.value)) << 32))"],
            ]
        }
    }

    func native(_ symbol: UnsafeMutableRawPointer, _ input: UInt64) -> UInt64 {
        switch (operation, bits) {
        case (.signed, 8):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int8) -> Int64).self)
            return UInt64(bitPattern: call(Int8(bitPattern: UInt8(input))))
        case (.signed, 16):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int16) -> Int64).self)
            return UInt64(bitPattern: call(Int16(bitPattern: UInt16(input))))
        case (.signed, 32):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Int64).self)
            return UInt64(bitPattern: call(Int32(bitPattern: UInt32(input))))
        case (.signedReinterpretation, 8):
            let call = unsafeBitCast(symbol, to: (@convention(c) (UInt8) -> Int64).self)
            return UInt64(bitPattern: call(UInt8(input)))
        case (.signedReinterpretation, 16):
            let call = unsafeBitCast(symbol, to: (@convention(c) (UInt16) -> Int64).self)
            return UInt64(bitPattern: call(UInt16(input)))
        case (.signedReinterpretation, 32):
            let call = unsafeBitCast(symbol, to: (@convention(c) (UInt32) -> Int64).self)
            return UInt64(bitPattern: call(UInt32(input)))
        case (.zero, 8):
            let call = unsafeBitCast(symbol, to: (@convention(c) (UInt8) -> UInt64).self)
            return call(UInt8(input))
        case (.zero, 16):
            let call = unsafeBitCast(symbol, to: (@convention(c) (UInt16) -> UInt64).self)
            return call(UInt16(input))
        case (.signedW, 8):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int8) -> UInt64).self)
            return call(Int8(bitPattern: UInt8(input)))
        case (.signedW, 16):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int16) -> UInt64).self)
            return call(Int16(bitPattern: UInt16(input)))
        case (.floatW, 8):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int8) -> UInt32).self)
            return UInt64(call(Int8(bitPattern: UInt8(input))))
        case (.floatW, 16):
            let call = unsafeBitCast(symbol, to: (@convention(c) (Int16) -> UInt32).self)
            return UInt64(call(Int16(bitPattern: UInt16(input))))
        case (.mixed, 32):
            let call = unsafeBitCast(symbol, to: (@convention(c) (UInt32) -> UInt64).self)
            return call(UInt32(input))
        default:
            preconditionFailure("Unsupported fixture C prototype")
        }
    }
}

private func checkStorageRead(
    _ instruction: Instruction, opcode: aarch64_insn, destination: PhysReg, offset: Int64, comment: Comment
) throws {
    let detail = try #require(instruction.detail, comment)
    try #require(detail.id == opcode && detail.operands.count == 2 && !detail.writeback && !detail.postIndex, comment)
    try #require(detail.operands[0].operand.register == destination, comment)
    let exactAddress: Bool
    if case .memory(let base, nil, let displacement) = detail.operands[1].operand {
        exactAddress = base == PhysReg(kind: .gpr, number: 20, widthBits: 64) && displacement == offset
    } else {
        exactAddress = false
    }
    try #require(exactAddress, comment)
}

private func storageProducerPCs(
    _ instructions: [Instruction], row: StorageLoadCase, comment: Comment
) throws -> [(pc: UInt64, bytes: Int)] {
    let caseName = row.owner
    let mixed = row.operation == .mixed
    let floating = row.operation == .floatW
    let nops = caseName == "UnsignedWord" ? 2 : 0
    let expectedCount = mixed ? 5 : (floating ? 3 : 2 + nops)
    try #require(instructions.count == expectedCount, comment)
    let load = instructions[0]
    let destination = PhysReg(kind: .gpr,
                              number: mixed ? 8 : (floating ? 17 : 0),
                              widthBits: row.result.name == "Int64" ? 64 : 32)
    try checkStorageRead(load, opcode: row.opcode, destination: destination, offset: row.offset, comment: comment)
    let tail = instructions[expectedCount - 1]
    try #require(tail.detail?.id == AARCH64_INS_RET && tail.controlFlow == .return, comment)
    if nops != 0 {
        for index in 1...nops {
            let nop = try #require(instructions[index].detail, comment)
            try #require(nop.id == AARCH64_INS_ALIAS_NOP && nop.operands.isEmpty, comment)
        }
    }
    if floating {
        let detail = try #require(instructions[1].detail, comment)
        let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
        try #require(detail.id == AARCH64_INS_FMOV && detail.operands.count == 2, comment)
        try #require(detail.operands.compactMap { $0.operand.register } == [s0, destination], comment)
    }
    if mixed {
        let full = instructions[1]
        let w0 = PhysReg(kind: .gpr, number: 0, widthBits: 32)
        let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
        let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
        try checkStorageRead(full, opcode: AARCH64_INS_LDR, destination: w0, offset: 0, comment: comment)
        let shift = try #require(instructions[2].detail, comment)
        try #require(shift.id == AARCH64_INS_LSL && shift.operands.count == 3, comment)
        try #require(shift.operands.compactMap { $0.operand.register } == [x8, x8] &&
                     shift.operands[2].operand.immediateValue == 32, comment)
        let combine = try #require(instructions[3].detail, comment)
        try #require(combine.id == AARCH64_INS_ORR && combine.operands.count == 3, comment)
        try #require(combine.operands.compactMap { $0.operand.register } == [x0, x0, x8], comment)
        return [(load.address, 1), (full.address, 4)]
    }
    return [(load.address, row.bits / 8)]
}

private func hasExactStorageLanes(_ value: AbstractValue?, input: UInt64) -> Bool {
    guard case .binary(.bitOr, let a, let b)? = value,
          let first = evaluateScalarExit(a, fieldBits: input),
          let second = evaluateScalarExit(b, fieldBits: input),
          first.usesField && second.usesField
    else { return false }
    let wide = input
    let lowByteInHighLane = (input & 0xff) << 32
    return (first.bits == wide && second.bits == lowByteInHighLane) ||
           (second.bits == wide && first.bits == lowByteInHighLane)
}

private func verifyStorageLoadImage(_ path: String) async throws {
    let imageComment = Comment(rawValue: path)
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, Comment(rawValue: "Build " + path + " before testing."))
        return
    }
    let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST), imageComment)
    defer { dlclose(handle) }
    let image = try BinaryLoader.load(path: path)
    let maps = try FieldMapBuilder.build(in: image)
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let stream = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: ".sampleStorage")
    }
    for row in StorageLoadCase.cases {
        let owner = "SignedSelfLoad." + row.owner
        let comment = Comment(rawValue: path + ": " + row.owner)
        let layout = try #require(maps[owner], comment)
        let hit = layout.lookup(offset: Int(row.offset), bytes: row.bits / 8)
        guard case .success(.whole(let field, let encoded)) = hit else {
            Issue.record(Comment(rawValue: path + ": missing exact whole field for " + row.owner))
            continue
        }
        try #require(field == "value", comment)
        let printable = FieldMap.printableTypeName(mangled: encoded, resolved: layout.fieldTypeNames[field])
        try #require(printable == row.storage.mangling || printable == "Swift." + row.storage.name, comment)
        if row.operation == .mixed {
            try #require(layout.lookup(offset: 0, bytes: 1) ==
                         .success(.part(name: field, typeMangledName: encoded, subOffset: 0, bytes: 1)), comment)
        }
        let wrapper = try #require(dlsym(handle, "storage_" + row.owner), comment)
        let native = row.inputs.map { ($0, row.native(wrapper, $0)) }
        for (input, output) in native {
            let vector = Comment(rawValue: path + " native " + row.owner + " " + String(input))
            #expect(output == row.expected(input), vector)
        }
        let symbol = "_$s14SignedSelfLoad" + String(row.owner.count) + row.owner + "V13sampleStorage" + row.result.mangling + "yF"
        let name = owner + ".sampleStorage() -> Swift." + row.result.name
        for (route, functions) in [("array", array), ("stream", stream), ("filtered", filtered)] {
            let routeComment = Comment(rawValue: path + " " + route + ": " + row.owner)
            let matches = functions.filter { $0.symbol == symbol && $0.displayName == name }
            try #require(matches.count == 1, routeComment)
            let function = try #require(matches.first, routeComment)
            let producers = try storageProducerPCs(function.instructions, row: row, comment: routeComment)
            if route == "array" {
                let trace = ValueTracer().analyze(function, entry: .swiftInstance(scalarArguments: [:]))
                try #require(trace.selfFieldAccesses.count == producers.count, routeComment)
                for (pc, bytes) in producers {
                    let access = try #require(trace.selfFieldAccesses[pc], routeComment)
                    try #require(access.offset == Int(row.offset) && access.bytes == bytes &&
                                 !access.isWrite && !access.isAddressOf, routeComment)
                }
                let tail = try #require(function.instructions.last, routeComment)
                let floating = row.operation == .floatW
                let value = floating ? trace.exitFloatValues[tail.address] : trace.exitValues[tail.address]
                for (input, oracle) in native {
                    let vector = Comment(rawValue: path + " tracer " + row.owner + " " + String(input))
                    let evaluated = value.flatMap { evaluateScalarExit($0, fieldBits: input, fieldOffset: Int(row.offset)) }
                    let observed = evaluated.map { floating ? $0.bits & 0xffff_ffff : $0.bits }
                    #expect(evaluated?.usesField == true, vector)
                    #expect(observed == oracle, vector)
                    if row.operation == .mixed {
                        #expect(hasExactStorageLanes(value, input: input), vector)
                    }
                }
            }
            for (renderer, view) in [("pseudo", function.renderPseudo()), ("structured", function.renderStructured())] {
                let observed = view.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("return ") }
                let rendererComment = Comment(rawValue: path + " " + route + " " + renderer + ": " + row.owner)
                #expect(row.renderedReturns.contains(observed), rendererComment)
            }
        }
    }
}

@Test func selfStorageLoadsPreserveNativeLowBitsAndTypedReturnsIfPresent() async throws {
    for image in signedSelfLoadImages {
        try await verifyStorageLoadImage(image.path)
    }
}

@Test func selfLoadTypedReturnsRequireCallerReturnAndClobberableScratchIfPresent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-self-return-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let signedRow = try #require(SignedScalarFixture.cases.first { $0.owner == "SignedBox" && $0.method == "signed" })
    let floatRow = try #require(SignedScalarFixture.cases.first { $0.owner == "FloatBox" && $0.method == "roundTrip" })
    let originalRET: UInt32 = 0xd65f_03c0
    let originalFloatLoad: UInt32 = 0xb980_0288
    let originalMove: UInt32 = 0x1e27_0100
    let originalSignedLoad: UInt32 = 0xb980_0280

    for (mode, path) in signedSelfLoadImages {
        let fixtureComment = Comment(rawValue: path)
        guard FileManager.default.fileExists(atPath: path) else {
            #expect(!FixturePresenceTests.enforcingFixturePresence, fixtureComment)
            continue
        }
        let source = try Data(contentsOf: URL(fileURLWithPath: path))
        let image = try BinaryLoader.load(path: path)
        let ranges = try #require(FileBackedRanges(standalone: image), fixtureComment)
        let layouts = try FieldMapBuilder.build(in: image)
        let originals = await withStableDependencies { await Disassembler().disassemble(machO: image) }

        for row in [signedRow, floatRow] {
            let identity = "SignedSelfLoad.\(row.owner).\(row.method)() -> Swift.\(row.resultType)"
            let nameFilter = "\(row.owner).\(row.method)"
            let originalCandidates = originals.filter { $0.symbol == row.symbol && $0.displayName == identity }
            try #require(originalCandidates.count == 1, fixtureComment)
            let original = try #require(originalCandidates.first, fixtureComment)
            let addresses = original.instructions.map(\.address)
            let isFloating = row.consumer == .float
            let expectedWords = isFloating ? [originalFloatLoad, originalMove, originalRET] : [originalSignedLoad, originalRET]
            try #require(addresses.count == expectedWords.count && addresses.first == original.startAddress, fixtureComment)
            let locations = try addresses.map { address in
                let offset = try #require(ranges.fileBytes(at: address)?.offset, fixtureComment)
                try #require(offset >= 0 && offset <= source.count - 4, fixtureComment)
                return offset
            }
            for (index, offset) in locations.enumerated() {
                let word = source[offset..<offset + 4].enumerated().reduce(UInt32(0)) {
                    $0 | (UInt32($1.element) << (8 * $1.offset))
                }
                try #require(word == expectedWords[index], fixtureComment)
            }

            let registers: [UInt32] = isFloating ? [18, 19, 20, 29, 30] : [0, 8, 20]
            let variants: [UInt32?] = [nil] + registers.map(Optional.some)
            for register in variants {
                let label = register.map { (isFloating ? "scratch x" : "ret x") + String($0) } ?? "original"
                var input = source
                if let register {
                    let replacements: [(Int, UInt32)] = if isFloating {
                        [(locations[0], (originalFloatLoad & ~UInt32(31)) | register),
                         (locations[1], (originalMove & ~UInt32(31 << 5)) | (register << 5))]
                    } else {
                        [(locations[1], (originalRET & ~UInt32(31 << 5)) | (register << 5))]
                    }
                    for (offset, word) in replacements {
                        withUnsafeBytes(of: word.littleEndian) {
                            input.replaceSubrange(offset..<offset + 4, with: $0)
                        }
                    }
                    try #require(input != source && input.count == source.count, fixtureComment)
                }
                let filename = "\(mode)-\(row.method)-\(register.map { String($0) } ?? "original").dylib"
                let url = directory.appendingPathComponent(filename)
                // Keep modified binaries as analyzer inputs only.
                try input.write(to: url)
                let candidate = try BinaryLoader.load(path: url.path)
                let candidateLayouts = try FieldMapBuilder.build(in: candidate)
                let owner = "SignedSelfLoad." + row.owner
                let map = try #require(layouts[owner], fixtureComment)
                let candidateMap = try #require(candidateLayouts[owner], fixtureComment)
                try #require(map.lookup(offset: 0, bytes: 4) == candidateMap.lookup(offset: 0, bytes: 4), fixtureComment)

                let array = await withStableDependencies { await Disassembler().disassemble(machO: candidate) }
                let streaming = await withStableDependencies {
                    await Disassembler().disassembleStreaming(machO: candidate, transform: { $0 })
                }
                let filtered = try await withStableDependencies {
                    try await Disassembler().disassemble(path: url.path, functionFilter: nameFilter)
                }
                for (route, functions) in [("array", array), ("streaming", streaming), ("filtered", filtered)] {
                    let comment = Comment(rawValue: "\(path) \(identity) \(label), \(route)")
                    let matches = functions.filter { $0.symbol == row.symbol && $0.displayName == identity }
                    try #require(matches.count == 1, comment)
                    let function = try #require(matches.first, comment)
                    try #require(function.startAddress == original.startAddress &&
                                 function.instructions.map(\.address) == addresses, comment)
                    let tail = try #require(function.instructions.last, comment)
                    let ret = try #require(tail.detail, comment)
                    try #require(ret.id == AARCH64_INS_RET && tail.controlFlow == .return, comment)
                    let controlRegister = PhysReg(kind: .gpr, number: Int(isFloating ? 30 : (register ?? 30)), widthBits: 64)
                    if !isFloating && register != nil {
                        try #require(ret.operands.count == 1 && ret.operands[0].operand.register == controlRegister, comment)
                    } else {
                        try #require(ret.operands.isEmpty ||
                                     (ret.operands.count == 1 && ret.operands[0].operand.register == controlRegister), comment)
                    }
                    let scratch = Int(register ?? 8)
                    let destination = PhysReg(kind: .gpr, number: isFloating ? scratch : 0, widthBits: 64)
                    try checkStorageRead(function.instructions[0], opcode: AARCH64_INS_LDRSW, destination: destination,
                                         offset: 0, comment: comment)
                    if isFloating {
                        let move = try #require(function.instructions[1].detail, comment)
                        let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
                        let wScratch = PhysReg(kind: .gpr, number: scratch, widthBits: 32)
                        try #require(move.id == AARCH64_INS_FMOV && move.operands.count == 2 &&
                                     move.operands.compactMap({ $0.operand.register }) == [s0, wScratch], comment)
                    }

                    for text in [function.renderStructured(), function.renderPseudo()] {
                        let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { $0.hasPrefix("return ") }
                        #expect(returns == [register == nil ? row.returns : "return ?"], comment)
                    }
                }
            }
        }
    }
}
