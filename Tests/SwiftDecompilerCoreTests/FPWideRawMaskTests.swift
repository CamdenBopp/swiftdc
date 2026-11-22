import Ccapstone
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func widerFloatingBitViewPreservesTheNarrowRawSourceMask() {
    let field = AbstractValue.selfFieldValue(offset: 0)
    for width in [16, 32] {
        let narrow = AbstractValue.unary(.floatResult(bits: width, upperZero: true),
                                         .unary(.floatFromBits(bits: width), field))
        let mask = (UInt64(1) << width) - 1
        let exactBits = AbstractValue.binary(.bitAnd, field, .immediate(mask))
        let wide = ValueTracer.scalarView(narrow, bits: 64)
        #expect(wide == .unary(.floatFromBits(bits: 64), exactBits))
        #expect(ValueTracer.bitPattern(of: wide, bits: 64) == exactBits)
    }
}

@Test func widenedFloatingMoveCannotRecoverSelfsISAFromAWordLoad() throws {
    let engine = try #require(CapstoneEngine())
    let address: UInt64 = 0x1000
    let wordISA: UInt32 = 0xB940_0288 // ldr w8, [x20]
    let floatBits: UInt32 = 0x1E27_0100 // fmov s0, w8
    let controls: [(label: String, prefix: [UInt32], proven: Bool)] = [
        ("genuine 64-bit ISA", [0xF940_0288], true),
        ("W read alone", [wordISA], false),
        ("W to S and back to W", [wordISA, floatBits, 0x1E26_0008], false),
        ("W to S then D to X", [wordISA, floatBits, 0x9E66_0008], false),
    ]
    let target = AbstractValue.loadedFrom(
        .loadedFrom(.selfVTableMethod(offset: 0x50), offset: -8), offset: 16
    )
    for (label, prefix, proven) in controls {
        let comment = Comment(rawValue: label)
        let words = prefix + [0xF940_2902, 0xF85F_8048, 0xF940_0903, 0xD61F_0060]
        let data = Data(words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
        })
        let decoded = engine.disassemble(data, address: address)
        try #require(decoded.count == words.count, comment)
        let first = try #require(decoded.first?.detail, comment)
        try #require(first.id == AARCH64_INS_LDR && first.operands.count == 2, comment)
        try #require(first.operands[0].operand.register == PhysReg(
            kind: .gpr, number: 8, widthBits: proven ? 64 : 32), comment)
        let exactAddress: Bool
        if case .memory(let register, nil, 0) = first.operands[1].operand {
            exactAddress = register == PhysReg(kind: .gpr, number: 20, widthBits: 64)
        } else {
            exactAddress = false
        }
        try #require(exactAddress && !first.writeback && !first.postIndex, comment)
        if prefix.count == 3 {
            let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
            let w8 = PhysReg(kind: .gpr, number: 8, widthBits: 32)
            let toFloat = try #require(decoded[1].detail, comment)
            try #require(toFloat.id == AARCH64_INS_FMOV && toFloat.operands.count == 2, comment)
            try #require(toFloat.operands[0].operand.register == s0, comment)
            try #require(toFloat.operands[1].operand.register == w8, comment)
            let toInteger = try #require(decoded[2].detail, comment)
            let width = prefix[2] == 0x9E66_0008 ? 64 : 32
            try #require(toInteger.id == AARCH64_INS_FMOV && toInteger.operands.count == 2, comment)
            try #require(toInteger.operands[0].operand.register == PhysReg(
                kind: .gpr, number: 8, widthBits: width), comment)
            try #require(toInteger.operands[1].operand.register == PhysReg(
                kind: .vector, number: 0, widthBits: width), comment)
        }
        let tail = try #require(decoded.last, comment)
        try #require(tail.controlFlow == .branch && tail.detail?.id == AARCH64_INS_BR, comment)
        try #require(tail.detail?.operands.first?.operand.register == PhysReg(
            kind: .gpr, number: 3, widthBits: 64), comment)
        let function = DisassembledFunction(
            symbol: "widenedFloatBits", demangledName: nil, startAddress: address,
            instructions: decoded.map { item in
                Instruction(address: item.address, text: item.text, annotation: nil,
                            controlFlow: item.controlFlow, branchTarget: item.branchTarget, detail: item.detail)
            }, source: .address
        )
        let trace = ValueTracer().analyze(function, entry: .swiftInstance(scalarArguments: [:]))
        #expect((trace.indirectControlFlowTargets[tail.address] == target) == proven, comment)
    }
}

@Test func widenedFloatingWordReadKeepsItsIndirectTransferIfPresent() async throws {
    let path = "Fixtures/Sample/libGenericClassPacks.dylib"
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(path) before running this test.")
        return
    }

    let owner = "GenericClassPacks.PlainBox.identityA("
    let filter = "PlainBox.identityA"
    let baselineImage = try BinaryLoader.load(path: path)
    let ranges = try #require(FileBackedRanges(standalone: baselineImage))
    let fileBytes = try Data(contentsOf: URL(fileURLWithPath: path))
    let originalFunctions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: filter)
    }
    let original = try #require(originalFunctions.first { $0.displayName.hasPrefix(owner) })

    let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
    let x1 = PhysReg(kind: .gpr, number: 1, widthBits: 64)
    let x2 = PhysReg(kind: .gpr, number: 2, widthBits: 64)
    let x3 = PhysReg(kind: .gpr, number: 3, widthBits: 64)
    let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
    let x20 = PhysReg(kind: .gpr, number: 20, widthBits: 64)
    let w8 = PhysReg(kind: .gpr, number: 8, widthBits: 32)
    let h0 = PhysReg(kind: .vector, number: 0, widthBits: 16)
    let s0 = PhysReg(kind: .vector, number: 0, widthBits: 32)
    let d0 = PhysReg(kind: .vector, number: 0, widthBits: 64)

    func checkRegisters(_ instruction: Instruction, id: aarch64_insn, registers: [PhysReg],
                        comment: Comment) throws {
        let detail = try #require(instruction.detail, comment)
        try #require(detail.id == id && detail.operands.count == registers.count, comment)
        try #require(detail.operands.compactMap { $0.operand.register } == registers, comment)
    }

    func isLoad(_ instruction: Instruction, id: aarch64_insn, destination: PhysReg,
                base: PhysReg, offset: Int64) -> Bool {
        guard let detail = instruction.detail, detail.id == id,
              !detail.writeback, !detail.postIndex, detail.operands.count == 2,
              detail.operands[0].operand.register == destination,
              case .memory(let memoryBase, nil, let displacement) = detail.operands[1].operand
        else { return false }
        return memoryBase == base && displacement == offset
    }

    let isaSites = original.instructions.indices.filter { index in
        isLoad(original.instructions[index], id: AARCH64_INS_LDR, destination: x8, base: x20, offset: 0)
    }
    try #require(isaSites.count == 1)
    let isaIndex = try #require(isaSites.first)
    try #require(isaIndex >= 2)
    let prefixIndex = isaIndex - 2
    let prefix = Array(original.instructions[prefixIndex...isaIndex])
    let originalComment = Comment(rawValue: "original PlainBox prefix and transfer")
    try checkRegisters(prefix[0], id: AARCH64_INS_MOV, registers: [x1, x0], comment: originalComment)
    try checkRegisters(prefix[1], id: AARCH64_INS_MOV, registers: [x0, x8], comment: originalComment)
    let mapped = try prefix.map { instruction in
        try #require(ranges.fileBytes(at: instruction.address))
    }
    let offset = mapped[0].offset
    try #require(mapped.enumerated().allSatisfy { index, file in
        file.offset == offset + index * 4 && file.available >= 4
    })
    try #require(offset >= 0 && offset <= fileBytes.count - 12)
    let sourceWords: [UInt32] = [0xAA00_03E1, 0xAA08_03E0, 0xF940_0288]
    let loadedWords = (0..<3).map { index in
        let start = offset + index * 4
        return fileBytes[start..<start + 4].enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << (8 * $1.offset))
        }
    }
    try #require(loadedWords == sourceWords)
    let originalTail = try #require(original.instructions.last)
    try #require(originalTail.controlFlow == .branch && originalTail.branchTarget == nil)
    try checkRegisters(originalTail, id: AARCH64_INS_BR, registers: [x3], comment: originalComment)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-fp-wide-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let controls: [(label: String, words: [UInt32], loadID: aarch64_insn,
                    floatRegister: PhysReg, moveBack: [PhysReg]?)] = [
        ("original 64-bit ISA", sourceWords, AARCH64_INS_LDR, s0, nil),
        ("W to S and back to W", [0xB940_0288, 0x1E27_0100, 0x1E26_0008], AARCH64_INS_LDR, s0, [w8, s0]),
        ("W to S then D to X", [0xB940_0288, 0x1E27_0100, 0x9E66_0008], AARCH64_INS_LDR, s0, [x8, d0]),
        ("halfword to H then D to X", [0x7940_0288, 0x1EE7_0100, 0x9E66_0008], AARCH64_INS_LDRH, h0, [x8, d0]),
    ]
    for control in controls {
        let url = directory.appendingPathComponent("\(control.label).dylib")
        var candidateBytes = fileBytes
        let encoded = control.words.flatMap { word in
            (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
        }
        candidateBytes.replaceSubrange(offset..<offset + 12, with: encoded)
        try candidateBytes.write(to: url)
        let candidateImage = try BinaryLoader.load(path: url.path)
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: url.path, functionFilter: filter)
        }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: candidateImage) }
        let streaming = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: candidateImage, transform: { $0 })
        }

        for (route, functions) in [("filtered", filtered), ("array", array), ("streaming", streaming)] {
            let comment = Comment(rawValue: "\(control.label), \(route)")
            let actual = try #require(functions.first { $0.displayName.hasPrefix(owner) }, comment)
            try #require(actual.symbol == original.symbol && actual.startAddress == original.startAddress, comment)
            try #require(actual.instructions.map(\.address) == original.instructions.map(\.address), comment)
            if let moveBack = control.moveBack {
                try #require(isLoad(actual.instructions[prefixIndex], id: control.loadID,
                                    destination: w8, base: x20, offset: 0), comment)
                try checkRegisters(actual.instructions[prefixIndex + 1], id: AARCH64_INS_FMOV,
                                   registers: [control.floatRegister, w8], comment: comment)
                try checkRegisters(actual.instructions[isaIndex], id: AARCH64_INS_FMOV,
                                   registers: moveBack, comment: comment)
            } else {
                try #require(isLoad(actual.instructions[isaIndex], id: AARCH64_INS_LDR,
                                    destination: x8, base: x20, offset: 0), comment)
            }
            let suffix = actual.instructions.suffix(from: isaIndex + 1)
            try #require(suffix.count == 4, comment)
            try #require(isLoad(suffix[isaIndex + 1], id: AARCH64_INS_LDR,
                                destination: x2, base: x8, offset: 0x50), comment)
            try #require(isLoad(suffix[isaIndex + 2], id: AARCH64_INS_LDUR,
                                destination: x8, base: x2, offset: -8), comment)
            try #require(isLoad(suffix[isaIndex + 3], id: AARCH64_INS_LDR,
                                destination: x3, base: x8, offset: 0x10), comment)
            let tail = try #require(suffix.last, comment)
            try #require(tail.address == originalTail.address && tail.controlFlow == .branch && tail.branchTarget == nil,
                         comment)
            try checkRegisters(tail, id: AARCH64_INS_BR, registers: [x3], comment: comment)
            for text in [actual.renderStructured(), actual.renderPseudo()] {
                if control.moveBack == nil {
                    #expect(text.contains("initializeWithCopy value witness for A("), comment)
                } else {
                    #expect(!text.contains(" value witness for "), comment)
                    let unresolved = "/* unresolved indirect branch @ 0x\(String(tail.address, radix: 16)) */ indirect_jump(?)"
                    #expect(text.contains(unresolved), comment)
                }
            }
        }
    }
}
