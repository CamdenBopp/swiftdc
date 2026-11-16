import MachOKit
import Ccapstone

/// An exact function symbol and the image supplying it. Constructed only from
/// a two-level import without an addend, or an exact runtime-image export.
struct RuntimeFunctionReference: Sendable, Equatable {
    let rawSymbol: String
    let libraryName: String

    /// A complete import island may only prepare x16/x17 and jump through x16.
    /// Tracing an arbitrary prefix that happens to leave x16 loaded is weaker:
    /// it could also store memory, change an argument, or never take that jump.
    static func pointerSlot(in instructions: [Instruction], startingAt address: UInt64) -> UInt64? {
        guard (3...4).contains(instructions.count), address % 4 == 0, let jump = instructions.last,
              jump.controlFlow == .branch, let branch = jump.detail,
              [AARCH64_INS_BR, AARCH64_INS_BRAA, AARCH64_INS_BRAAZ,
               AARCH64_INS_BRAB, AARCH64_INS_BRABZ].contains(branch.id),
              branch.operands.first?.operand.register?.key == "x16"
        else { return nil }
        // The decoder resynchronizes after unknown words. A decoded prefix
        // only proves the island when every slot from its actual entry exists.
        for (index, instruction) in instructions.enumerated() {
            let (expected, overflow) = address.addingReportingOverflow(UInt64(index * 4))
            guard !overflow, instruction.address == expected else { return nil }
        }
        for instruction in instructions.dropLast() {
            guard instruction.controlFlow == .sequential, let detail = instruction.detail,
                  !detail.updatesFlags, !detail.writeback,
                  [AARCH64_INS_ADRP, AARCH64_INS_ADD, AARCH64_INS_LDR].contains(detail.id),
                  let destination = detail.operands.first?.operand.register,
                  destination.kind == .gpr, destination.widthBits == 64,
                  destination.number == 16 || destination.number == 17
            else { return nil }
        }
        guard case .loaded(let slot)? = ValueTracer()
            .finalState(of: Array(instructions.dropLast()))["x16"] else { return nil }
        return slot
    }

    static func isDirectFunctionExport(_ symbol: ExportedSymbol) -> Bool {
        // A regular export has kind zero and no modifiers. Unknown future
        // flags provide no stronger proof than a known resolver or weak flag.
        symbol.flags.rawValue == 0
    }

    static func isARCRuntimeImage(_ name: String) -> Bool {
        ["/usr/lib/swift/libswiftCore.dylib", "@rpath/libswiftCore.dylib",
         "/usr/lib/libobjc.A.dylib", "/usr/lib/libobjc.dylib"].contains(name)
    }

    func permitsARCIdentity(named callee: String) -> Bool {
        let name = callee.hasPrefix("_") ? String(callee.dropFirst()) : callee
        let symbol = rawSymbol.hasPrefix("_") ? String(rawSymbol.dropFirst()) : rawSymbol
        guard name == symbol, DisassembledFunction.isARCReferenceHelper(name) else { return false }
        if name.hasPrefix("swift_") {
            return ["/usr/lib/swift/libswiftCore.dylib", "@rpath/libswiftCore.dylib"].contains(libraryName)
        }
        return name.hasPrefix("objc_")
            && ["/usr/lib/libobjc.A.dylib", "/usr/lib/libobjc.dylib"].contains(libraryName)
    }
}
