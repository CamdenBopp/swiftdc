import Foundation

/// Loader bindings retain their flags and lazy-entry offsets. The convenient
/// MachOKit BindingSymbol projection loses both, and walks past a normal DONE.
struct LegacyImportBindings {
    enum Kind: Equatable { case normal, lazy, weak }

    struct Binding {
        let symbol: String
        let libraryOrdinal: Int
        let segment: Int
        let offset: UInt64
        let type: UInt8
        let addend: Int64
        let isWeak: Bool
        let lazyEntry: Int?
    }

    private struct Cursor {
        let data: Data
        var position = 0

        mutating func byte() -> UInt8? {
            guard position < data.count else { return nil }
            defer { position += 1 }
            return data[data.startIndex + position]
        }

        mutating func uleb() -> UInt64? {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard let byte = byte(), index < 9 || byte & 0x7f <= 1 else { return nil }
                value |= UInt64(byte & 0x7f) << (index * 7)
                if byte & 0x80 == 0 { return value }
            }
            return nil
        }

        mutating func sleb() -> Int64? {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard let byte = byte(), index < 9 || byte == 0 || byte == 0x7f else { return nil }
                value |= UInt64(byte & 0x7f) << (index * 7)
                if byte & 0x80 == 0 {
                    let shift = (index + 1) * 7
                    if shift < 64, byte & 0x40 != 0 { value |= ~UInt64(0) << shift }
                    return Int64(bitPattern: value)
                }
            }
            return nil
        }

        mutating func symbol() -> String? {
            let start = position
            while let byte = byte() {
                if byte == 0 {
                    return String(data: data[(data.startIndex + start)..<(data.startIndex + position - 1)], encoding: .utf8)
                }
            }
            return nil
        }
    }

    /// A malformed, unsupported or bounded program supplies no partial proof.
    /// Normal/weak DONE terminates the stream. Each lazy helper enters a fresh
    /// program at its own recorded byte offset, with pointer type by default.
    static func decode(_ data: Data, kind: Kind) -> [Binding]? {
        var cursor = Cursor(data: data)
        var result: [Binding] = []
        var library: Int? = kind == .weak ? -3 : nil
        var segment: Int?
        var offset: UInt64 = 0
        var symbol: String?
        var type: UInt8 = 1
        var flags: UInt8 = 0
        var addend: Int64 = 0
        var entry = 0
        let maximumBindings = 1_000_000
        func emit(_ count: UInt64, skip: UInt64) -> Bool {
            guard count <= UInt64(maximumBindings - result.count) else { return false }
            if count == 0 { return true }
            guard let library, let segment, let symbol, !symbol.isEmpty else { return false }
            for _ in 0..<count {
                result.append(Binding(symbol: symbol, libraryOrdinal: library, segment: segment, offset: offset,
                                      type: type, addend: addend, isWeak: kind == .weak || flags & 1 != 0,
                                      lazyEntry: kind == .lazy ? entry : nil))
                offset = offset &+ 8 &+ skip
            }
            return true
        }
        while let byte = cursor.byte() {
            let opcode = byte & 0xf0, immediate = byte & 15
            if kind == .lazy, ![0, 0x10, 0x20, 0x30, 0x40, 0x60, 0x70, 0x90].contains(opcode) { return nil }
            switch opcode {
            case 0:
                if kind != .lazy { return result }
                entry = cursor.position
                library = nil; segment = nil; symbol = nil
                offset = 0; type = 1; flags = 0; addend = 0
            case 0x10:
                guard kind != .weak else { return nil }
                library = Int(immediate)
            case 0x20:
                guard kind != .weak, let value = cursor.uleb(), value <= UInt64(Int.max) else { return nil }
                library = Int(value)
            case 0x30:
                guard kind != .weak else { return nil }
                library = immediate == 0 ? 0 : Int(immediate) - 16
            case 0x40:
                flags = immediate
                guard let value = cursor.symbol() else { return nil }
                symbol = value
            case 0x50:
                guard (1...3).contains(immediate) else { return nil }
                type = immediate
            case 0x60:
                guard let value = cursor.sleb() else { return nil }
                addend = value
            case 0x70:
                guard let value = cursor.uleb() else { return nil }
                segment = Int(immediate); offset = value
            case 0x80:
                guard let value = cursor.uleb() else { return nil }
                offset &+= value
            case 0x90:
                guard emit(1, skip: 0) else { return nil }
            case 0xa0:
                guard let skip = cursor.uleb(), emit(1, skip: skip) else { return nil }
            case 0xb0:
                guard emit(1, skip: UInt64(immediate) * 8) else { return nil }
            case 0xc0:
                guard let count = cursor.uleb(), let skip = cursor.uleb(), emit(count, skip: skip) else { return nil }
            default:
                return nil
            }
        }
        return result
    }
}
