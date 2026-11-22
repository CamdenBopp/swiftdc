import Ccapstone
import Foundation
import Testing
@testable import SwiftDecompilerCore

private struct MetadataLoadWord {
    enum Operand {
        case register(PhysReg)
        case memory(base: PhysReg, displacement: Int64)
    }

    var word: UInt32
    var id: aarch64_insn
    var operands: [Operand]

    static func load(_ word: UInt32, _ id: aarch64_insn, _ destination: PhysReg,
                     base: PhysReg, offset: Int64 = 0) -> Self {
        Self(word: word, id: id, operands: [.register(destination), .memory(base: base, displacement: offset)])
    }

    func check(_ detail: StructuredInsn, _ comment: Comment) throws {
        try #require(detail.id == id, comment)
        try #require(!detail.writeback && !detail.postIndex, comment)
        try #require(detail.operands.count == operands.count, comment)
        for (actual, expected) in zip(detail.operands, operands) {
            switch expected {
            case .register(let register):
                // PhysReg equality checks register bank, number and width.
                try #require(actual.operand.register == register, comment)
            case .memory(let expectedBase, let expectedDisplacement):
                let exactMemory: Bool
                if case .memory(let base, let index, let displacement) = actual.operand {
                    exactMemory = base == expectedBase && index == nil && displacement == expectedDisplacement
                } else {
                    exactMemory = false
                }
                try #require(exactMemory, comment)
            }
        }
    }
}

// AArch64InstrInfo.td LDRSBX/LDRSHX/LDRSW and LDURSBX/LDURSHX/LDURSW.
// These TableGen forms read signed 8/16/32-bit values into X8 from [X20].
private let signedSelfLoads: [(label: String, word: UInt32, id: aarch64_insn, bits: Int)] = [
    ("LDRSB", 0x3980_0288, AARCH64_INS_LDRSB, 8),
    ("LDURSB", 0x3880_0288, AARCH64_INS_LDURSB, 8),
    ("LDRSH", 0x7980_0288, AARCH64_INS_LDRSH, 16),
    ("LDURSH", 0x7880_0288, AARCH64_INS_LDURSH, 16),
    ("LDRSW", 0xB980_0288, AARCH64_INS_LDRSW, 32),
    ("LDURSW", 0xB880_0288, AARCH64_INS_LDURSW, 32),
]


@Test func narrowClassISAReadsKeepTheWitnessTransferUnresolvedIfPresent() async throws {
    let path = "Fixtures/Sample/libGenericClassPacks.dylib"
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(path) before running this test.")
        return
    }

    let owner = "GenericClassPacks.PlainBox.identityA("
    let image = try BinaryLoader.load(path: path)
    let ranges = try #require(FileBackedRanges(standalone: image))
    let source = try Data(contentsOf: URL(fileURLWithPath: path))
    let initial = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "PlainBox.identityA")
    }
    let original = try #require(initial.first { $0.displayName.hasPrefix(owner) })
    let selfPointer = PhysReg(kind: .gpr, number: 20, widthBits: 64)
    let x8 = PhysReg(kind: .gpr, number: 8, widthBits: 64)
    let x3 = PhysReg(kind: .gpr, number: 3, widthBits: 64)
    let isa = MetadataLoadWord.load(0xF940_0288, AARCH64_INS_LDR, x8, base: selfPointer)
    let candidates = original.instructions.filter { item in
        guard let detail = item.detail, detail.id == isa.id,
              detail.operands.count == 2, detail.operands[0].operand.register == x8,
              case .memory(let base, nil, 0) = detail.operands[1].operand
        else { return false }
        return base == selfPointer && !detail.writeback && !detail.postIndex
    }
    try #require(candidates.count == 1)
    let load = try #require(candidates.first)
    let offset = try #require(ranges.fileBytes(at: load.address)?.offset)
    try #require(offset >= 0 && offset <= source.count - 4)
    let originalWord = source[offset..<offset + 4].enumerated().reduce(UInt32(0)) {
        $0 | (UInt32($1.element) << (8 * $1.offset))
    }
    try #require(originalWord == isa.word)
    let originalTail = try #require(original.instructions.last)
    let branch = MetadataLoadWord(word: 0xD61F_0060, id: AARCH64_INS_BR, operands: [.register(x3)])
    let originalTailDetail = try #require(originalTail.detail)
    try branch.check(originalTailDetail, Comment(rawValue: "original terminal transfer"))

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-isa-load-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    // These variants are analyzer inputs only. Never dlopen or otherwise
    // execute any byte-modified class image.
    let controls = [("full-width LDR", isa)] + signedSelfLoads.map { load in
        ("\(load.bits)-bit \(load.label)", MetadataLoadWord.load(load.word, load.id, x8, base: selfPointer))
    }
    for (label, expected) in controls {
        let url = directory.appendingPathComponent("\(label).dylib")
        var bytes = source
        if expected.word != originalWord {
            withUnsafeBytes(of: expected.word.littleEndian) {
                bytes.replaceSubrange(offset..<offset + 4, with: $0)
            }
        }
        try bytes.write(to: url)
        let candidateImage = try BinaryLoader.load(path: url.path)
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: url.path, functionFilter: "PlainBox.identityA")
        }
        let array = await withStableDependencies {
            await Disassembler().disassemble(machO: candidateImage)
        }
        let streaming = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: candidateImage, transform: { $0 })
        }

        for (route, functions) in [("filtered", filtered), ("array", array), ("streaming", streaming)] {
            let comment = Comment(rawValue: "\(label), \(route)")
            let identity = try #require(functions.first { $0.displayName.hasPrefix(owner) }, comment)
            try #require(identity.startAddress == original.startAddress && identity.symbol == original.symbol, comment)
            try #require(identity.instructions.map(\.address) == original.instructions.map(\.address), comment)
            for (before, after) in zip(original.instructions, identity.instructions) where before.address != load.address {
                try #require(before.text == after.text && before.controlFlow == after.controlFlow &&
                             before.branchTarget == after.branchTarget, comment)
            }
            let candidateLoad = try #require(identity.instructions.first { $0.address == load.address }, comment)
            let loadDetail = try #require(candidateLoad.detail, comment)
            try expected.check(loadDetail, comment)
            let tail = try #require(identity.instructions.last, comment)
            try #require(tail.address == originalTail.address && tail.controlFlow == .branch && tail.branchTarget == nil,
                         comment)
            let detail = try #require(tail.detail, comment)
            try branch.check(detail, comment)

            for text in [identity.renderStructured(), identity.renderPseudo()] {
                if expected.word == originalWord {
                    #expect(text.contains("initializeWithCopy value witness for A("), comment)
                } else {
                    #expect(!text.contains(" value witness for "), comment)
                    let fallback = "/* unresolved indirect branch @ 0x\(String(tail.address, radix: 16)) */ indirect_jump(?)"
                    #expect(text.contains(fallback), comment)
                }
            }
        }
    }
}
