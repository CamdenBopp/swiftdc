import Foundation
import MachOKit
import Synchronization

/// The Go runtime's own function table, `__gopclntab`, which it reads to
/// print a stack trace: every function's entry and name. Go's internal
/// linker writes no `LC_FUNCTION_STARTS` and `-ldflags=-s` strips the symbol
/// table, so for 20 of the 41 Go images on the audit host (Docker's CLI
/// plugins, github-mcp-server) this table was the only record of where
/// functions begin. Without it all of `__text` was one function: 7.4 MB of
/// github-mcp-server analysed as a single body, `xrefs` at 2.77 GB.
///
/// Layout (Go 1.18 and later, `runtime/symtab.go` `pcHeader`): magic
/// 0xfffffff0 (1.18, 1.19) or 0xfffffff1 (1.20 on), two zero bytes, the
/// minimum instruction size, the pointer size, then pointer-sized `nfunc`,
/// `nfiles`, `textStart` and the offsets of `funcnametab`, `cutab`,
/// `filetab`, `pctab` and `pclntable`. `pclntable` opens with `nfunc + 1`
/// pairs of 32-bit (`entryOff`, `funcOff`); the last `entryOff` is the end of
/// the text. Each `_func` at `pclntable + funcOff` repeats its `entryOff`,
/// then the 32-bit offset of its name in `funcnametab`.
///
/// Any inconsistency declines the whole table: an older layout, a pointer
/// size or instruction size that is not arm64's, a `textStart` other than
/// `__TEXT,__text` (the linker leaves it 0 in some builds; that is read as
/// `__text`), entries out of order or past the text, a `_func` that does not
/// repeat its entry, a name outside the table.
struct GoFunctionTable: Sendable {
    let entries: [(address: UInt64, name: String)]
    /// The end of the text the table covers (its last `entryOff`).
    var textEnd: UInt64 = 0
    /// Spans the table lists as functions that hold data. The linker puts the
    /// build ID at the start of `__text` as a "function" named
    /// `go:buildid`, and its bytes are the string `\xff Go build ID:
    /// "…"`: decoded, they read as instructions (`umlal2 v31.4s, …`).
    /// A span counts only when the name and the bytes agree.
    var dataSpans: [UInt64: (end: UInt64, name: String)] = [:]

    static let buildIDName = "go:buildid"
    static let buildIDPrefix = Data([0xff] + Array(" Go build ID: \"".utf8))

    static func read(_ machO: MachOFile, bytes: (UInt64, Int) -> Data?) -> GoFunctionTable? {
        guard let section = machO.sections.first(where: { $0.sectionName == "__gopclntab" }),
              section.size >= 72,
              let text = machO.sections.first(where: { $0.segmentName == "__TEXT" && $0.sectionName == "__text" }),
              let table = bytes(UInt64(section.address), section.size), table.count == section.size
        else { return nil }
        guard var parsed = parse(table, textAddress: UInt64(text.address), textSize: UInt64(text.size))
        else { return nil }
        parsed.dataSpans = dataSpans(of: parsed.entries, textEnd: parsed.textEnd, bytes: bytes)
        return parsed
    }

    /// The entries named `go:buildid` whose bytes begin with the build ID's
    /// own prefix, each to the next entry. A name alone, or the bytes alone,
    /// is no span.
    static func dataSpans(
        of entries: [(address: UInt64, name: String)], textEnd: UInt64, bytes: (UInt64, Int) -> Data?
    ) -> [UInt64: (end: UInt64, name: String)] {
        var spans: [UInt64: (end: UInt64, name: String)] = [:]
        for (index, entry) in entries.enumerated() where entry.name == buildIDName {
            let end = index + 1 < entries.count ? entries[index + 1].address : textEnd
            guard end > entry.address, end - entry.address >= UInt64(buildIDPrefix.count),
                  let head = bytes(entry.address, buildIDPrefix.count), head == buildIDPrefix
            else { continue }
            spans[entry.address] = (end, entry.name)
        }
        return spans
    }

    static func parse(_ table: Data, textAddress: UInt64, textSize: UInt64) -> GoFunctionTable? {
        func u32(_ offset: Int) -> UInt32? {
            guard offset >= 0, offset <= table.count - 4 else { return nil }
            return table.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        func u64(_ offset: Int) -> UInt64? {
            guard offset >= 0, offset <= table.count - 8 else { return nil }
            return table.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
        }
        func offset(_ at: Int) -> Int? {
            guard let value = u64(at), value < UInt64(table.count) else { return nil }
            return Int(value)
        }
        guard let magic = u32(0), magic == 0xffff_fff0 || magic == 0xffff_fff1,
              table[table.startIndex + 4] == 0, table[table.startIndex + 5] == 0,
              table[table.startIndex + 6] == 4, table[table.startIndex + 7] == 8,
              let count = u64(8), count > 0, count < UInt64(table.count) / 8,
              let textStart = u64(24), textStart == 0 || textStart == textAddress,
              let names = offset(32), let functions = offset(64)
        else { return nil }
        let nfunc = Int(count)
        guard functions <= table.count - (nfunc + 1) * 8, let end = u32(functions + nfunc * 8),
              UInt64(end) <= textSize
        else { return nil }
        var entries: [(address: UInt64, name: String)] = []
        entries.reserveCapacity(nfunc)
        var previous: UInt32?
        for index in 0..<nfunc {
            guard let entry = u32(functions + index * 8), let funcOffset = u32(functions + index * 8 + 4),
                  entry < end, previous.map({ entry > $0 }) ?? true,
                  u32(functions + Int(funcOffset)) == entry,
                  let nameOffset = u32(functions + Int(funcOffset) + 4).map({ Int(Int32(bitPattern: $0)) }),
                  nameOffset >= 0, names + nameOffset < table.count
            else { return nil }
            let start = table.startIndex + names + nameOffset
            guard let terminator = table[start...].firstIndex(of: 0), terminator > start,
                  let name = String(data: table[start..<terminator], encoding: .utf8)
            else { return nil }
            entries.append((textAddress + UInt64(entry), name))
            previous = entry
        }
        return GoFunctionTable(entries: entries, textEnd: textAddress + UInt64(end))
    }

    /// Tables by image, so each of the many readers of function starts in a
    /// run does not re-read one.
    final class Cache: Sendable {
        private let store = Mutex<[String: GoFunctionTable?]>([:])

        func value(for key: String, compute: () -> GoFunctionTable?) -> GoFunctionTable? {
            if let hit = store.withLock({ $0[key] }) { return hit }
            let result = compute()
            store.withLock { $0[key] = .some(result) }
            return result
        }
    }
}
