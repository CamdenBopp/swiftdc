import Foundation
import Testing
@testable import SwiftDecompilerCore

private func instructions(_ words: [UInt32]) throws -> [Instruction] {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    return decoded.map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
}

/// A frame of 4 KiB or more is allocated with a shifted immediate, `sub sp,
/// sp, #0x1, lsl #12`, which the layout read as `sp -= 1`: every sp-relative
/// local after it sat 4,095 bytes off, so the regions bounding an escaped
/// address's writes were misplaced.
@Test func aFrameAllocatedWithAShiftedImmediateIsLaidOutAtItsSize() throws {
    let layout = ValueTracer.frameLayout(try instructions([
        0xa9bf7bfd,  // stp x29, x30, [sp, #-16]!     sp = -16
        0x910003fd,  // mov x29, sp
        0xd14007ff,  // sub sp, sp, #0x1, lsl #12     sp = -4112
        0xd10083ff,  // sub sp, sp, #0x20             sp = -4144
        0x910043e0,  // add x0, sp, #0x10             a local at -4128
        0x914007e1,  // add x1, sp, #0x1, lsl #12     a local at -48
        0xd65f03c0,  // ret
    ]))
    // The x29/x30 save slots, -16 and -8, bound regions too.
    #expect(layout.boundaries == [-4128, -48, -16, -8], "\(layout.boundaries)")
}
