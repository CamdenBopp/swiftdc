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
