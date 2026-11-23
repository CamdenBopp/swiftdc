import MachOKit
import Synchronization

/// The sections whose functions are decoded: `__TEXT,__text`, and every other
/// `__TEXT` section the linker marks as instructions that `LC_FUNCTION_STARTS`
/// puts a function in. Real binaries carry such code: `__realtime`
/// (auvaltool, audiomxd), `__text_cold` (gcc's cold splitting),
/// `__lcxx_override` (libc++ operator overrides), `__text_startup`. Decoding
/// only `__text` dropped those functions without a word and left their callers'
/// direct calls unnamed.
///
/// Stub sections are not functions: `S_SYMBOL_STUBS` (`__stubs`,
/// `__auth_stubs`), `__stub_helper` and `__objc_stubs` are named as call
/// targets elsewhere and never carry a function start.
struct CodeSection: Equatable, Sendable {
    let segment: String
    let name: String
    let range: Range<UInt64>

    static func of(_ machO: MachOFile, functionStarts: [UInt64]) -> [CodeSection] {
        let starts = functionStarts.sorted()
        func holdsAStart(_ range: Range<UInt64>) -> Bool {
            var low = 0, high = starts.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] < range.lowerBound { low = mid + 1 } else { high = mid }
            }
            return low < starts.count && range.contains(starts[low])
        }
        var sections: [CodeSection] = []
        for section in machO.sections where section.segmentName == "__TEXT" && section.size > 0 {
            let start = UInt64(section.address)
            let range = start ..< start + UInt64(section.size)
            if section.sectionName == "__text" {
                sections.append(CodeSection(segment: "__TEXT", name: "__text", range: range))
                continue
            }
            let attributes = section.flags.attributes
            guard attributes.contains(.pure_instructions) || attributes.contains(.some_instructions),
                  section.flags.type != .symbol_stubs,
                  !["__stub_helper", "__objc_stubs"].contains(section.sectionName),
                  holdsAStart(range)
            else { continue }
            sections.append(CodeSection(segment: "__TEXT", name: section.sectionName, range: range))
        }
        return sections.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The import stub sections (`S_SYMBOL_STUBS`, `__objc_stubs`): a call
    /// into one reaches another image's exported function, never an
    /// outlined fragment of this one.
    static func importStubRanges(of machO: MachOFile) -> [Range<UInt64>] {
        machO.sections.compactMap { section in
            guard section.segmentName == "__TEXT", section.size > 0,
                  section.flags.type == .symbol_stubs || section.sectionName == "__objc_stubs"
            else { return nil }
            let start = UInt64(section.address)
            return start ..< start + UInt64(section.size)
        }
    }

    /// Code sections by image, so a per-function decode does not re-read
    /// `LC_FUNCTION_STARTS`.
    final class Cache: Sendable {
        private let store = Mutex<[String: [CodeSection]]>([:])

        func value(for key: String, compute: () -> [CodeSection]) -> [CodeSection] {
            if let hit = store.withLock({ $0[key] }) { return hit }
            let result = compute()
            store.withLock { $0[key] = result }
            return result
        }
    }

    /// The section holding `address`, from sections sorted by address.
    static func containing(_ address: UInt64, in sections: [CodeSection]) -> CodeSection? {
        sections.first { $0.range.contains(address) }
    }
}

/// `Disassembler.recordedStarts` by image.
final class BoundaryCache: Sendable {
    private let store = Mutex<[String: Set<UInt64>]>([:])

    func value(for key: String, compute: () -> Set<UInt64>) -> Set<UInt64> {
        if let hit = store.withLock({ $0[key] }) { return hit }
        let result = compute()
        store.withLock { $0[key] = result }
        return result
    }
}

/// `Disassembler.unmarkedEntry`'s walk, fed one decoded piece at a time.
struct UnmarkedEntryScan {
    let boundaries: Set<UInt64>
    let sections: [CodeSection]
    private var returned = false
    private var branchTargets: Set<UInt64> = []
    private var afterReturn: [UInt64] = []

    init(boundaries: Set<UInt64>, sections: [CodeSection]) {
        self.boundaries = boundaries
        self.sections = sections
    }

    /// A direct call's target no boundary marks, which settles it at once.
    mutating func read(_ instructions: [DecodedInstruction]) -> UInt64? {
        for insn in instructions {
            if returned, !["nop", "udf", "brk"].contains(insn.mnemonic), !boundaries.contains(insn.address) {
                afterReturn.append(insn.address)
            }
            returned = insn.controlFlow == .return
            guard let target = insn.branchTarget else { continue }
            if insn.controlFlow != .call {
                branchTargets.insert(target)
            } else if !boundaries.contains(target), CodeSection.containing(target, in: sections) != nil {
                return target
            }
        }
        return nil
    }

    /// Code after a return that no branch in the image reaches.
    func finish() -> UInt64? { afterReturn.first { !branchTargets.contains($0) } }
}

