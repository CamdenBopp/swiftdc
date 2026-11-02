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

/// Once the scan cannot follow sp or x29 it claims nothing more through
/// that register. A register delta was read as zero, so `sub sp, sp, x9`
/// (a dynamic allocation) left sp where it was and `add x0, sp, x1`
/// claimed a local at sp itself; an `ldp` that reloads x29 left the old
/// frame pointer in place. Each misplaced boundary narrows how far an
/// escaped write is assumed to reach, the unsafe direction.
@Test func aFrameLayoutClaimsNothingThroughARegisterItLostTrackOf() throws {
    let prologue: [UInt32] = [0xa9bf7bfd, 0x910003fd]  // stp x29, x30, [sp, #-16]!; mov x29, sp
    let ret: UInt32 = 0xd65f03c0
    func boundaries(_ body: [UInt32]) throws -> [Int64] {
        ValueTracer.frameLayout(try instructions(prologue + body + [ret])).boundaries
    }
    // sub sp, sp, #0x20; sub sp, sp, x9; add x0, sp, #0x10; sub x3, x29, #0x8
    #expect(try boundaries([0xd10083ff, 0xcb2963ff, 0x910043e0, 0xd10023a3]) == [-24, -16, -8])
    // sub sp, sp, #0x20; add x0, sp, x1
    #expect(try boundaries([0xd10083ff, 0x8b2163e0]) == [-16, -8])
    // ldp x29, x30, [sp], #16; add x4, x29, #0x10
    #expect(try boundaries([0xa8c17bfd, 0x910043a4]) == [-16, -8])
    // mov x29, x0; add x4, x29, #0x10
    #expect(try boundaries([0xaa0003fd, 0x910043a4]) == [-16, -8])
    // A store reads x29: stp x29, x30, [sp, #16]; add x4, x29, #0x10 is at 0.
    #expect(try boundaries([0xa9017bfd, 0x910043a4]) == [-16, -8, 0])
    // A compare reads sp: sub sp, sp, #0x20; cmp sp, x0; add x0, sp, #0x10
    #expect(try boundaries([0xd10083ff, 0xeb2063ff, 0x910043e0]) == [-32, -16, -8])
}
