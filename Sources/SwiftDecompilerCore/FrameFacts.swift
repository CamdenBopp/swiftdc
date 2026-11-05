/// Independently present frame-fact components. Metadata can outlive a value;
/// no operation may treat a metadata-only row as an old memory snapshot.
enum FrameFactField: Int, Sendable {
    case value = 0, width, bank, outgoing
    var mask: FrameFactFields { FrameFactFields(rawValue: UInt8(1 << rawValue)) }
}

struct FrameFactFields: OptionSet, Sendable {
    let rawValue: UInt8
    static let value = Self(rawValue: 1)
    static let width = Self(rawValue: 2)
    static let bank = Self(rawValue: 4)
    static let outgoing = Self(rawValue: 8)
    static let all: Self = [.value, .width, .bank, .outgoing]
}

enum FrameFactChange<Value> {
    case leave
    case erase
    case assign(Value)
}

/// Concrete rows specialize storage without an existential or per-row box.
/// A word-only preservation row carries no tracer metadata fields.
protocol FrameFactRecord: Equatable {
    associatedtype Payload: Equatable
    init()
    static var fields: FrameFactFields { get }
    subscript(_ field: FrameFactField) -> Payload? { get set }
    var extentBytes: Int64 { get }
}

extension FrameFactRecord {
    var componentCount: Int {
        var count = 0
        for index in 0..<4 {
            let field = FrameFactField(rawValue: index)!
            if Self.fields.contains(field.mask), self[field] != nil { count += 1 }
        }
        return count
    }
}

struct TraceFrameFact: FrameFactRecord {
    typealias Payload = AbstractValue
    var value: AbstractValue?
    var width: AbstractValue?
    var bank: AbstractValue?
    var outgoing: AbstractValue?
    init() {}
    static let fields = FrameFactFields.all
    subscript(_ field: FrameFactField) -> AbstractValue? {
        get {
            switch field {
            case .value: return value
            case .width: return width
            case .bank: return bank
            case .outgoing: return outgoing
            }
        }
        set {
            switch field {
            case .value: value = newValue
            case .width: width = newValue
            case .bank: bank = newValue
            case .outgoing: outgoing = newValue
            }
        }
    }
    var extentBytes: Int64 {
        if case .immediate(let bytes)? = width { return Int64(clamping: bytes) }
        return 8
    }
}

struct WordFrameFact<Value: Equatable>: FrameFactRecord {
    typealias Payload = Value
    var value: Value?
    init() {}
    static var fields: FrameFactFields { .value }
    subscript(_ field: FrameFactField) -> Value? {
        get { field == .value ? value : nil }
        set {
            if field == .value { value = newValue }
            else { precondition(newValue == nil, "Word facts have no metadata component") }
        }
    }
    var extentBytes: Int64 { 8 }
}

/// The sole owner of current-frame facts, relative to entry sp. Unknown values
/// remain present payloads, unlike missing values. Separate result/context and
/// MAY-alias/escape domains are deliberately not stored here.
struct FrameFacts<Record: FrameFactRecord>: Equatable, Sequence, ExpressibleByDictionaryLiteral {
    typealias Key = Int64
    typealias Value = Record.Payload
    typealias Element = (key: Int64, value: Record.Payload)
    private var rows: [Int64: Record] = [:]
    private(set) var componentCount = 0
    private(set) var valueCount = 0
    init() {}
    init(dictionaryLiteral elements: (Int64, Record.Payload)...) {
        for (offset, value) in elements { self[offset] = value }
    }
    init(_ values: [Int64: Record.Payload]) {
        for (offset, value) in values { self[offset] = value }
    }
    var isEmpty: Bool { componentCount == 0 }
    var count: Int { valueCount }
    subscript(_ offset: Int64) -> Record.Payload? {
        get { self[offset, .value] }
        set { self[offset, .value] = newValue }
    }
    subscript(_ offset: Int64, _ field: FrameFactField) -> Record.Payload? {
        get { rows[offset]?[field] }
        set {
            var row = rows[offset] ?? Record()
            row[field] = newValue
            replace(row, at: offset)
        }
    }
    private mutating func replace(_ row: Record, at offset: Int64) {
        let old = rows[offset]
        componentCount += row.componentCount - (old?.componentCount ?? 0)
        valueCount += (row[.value] == nil ? 0 : 1) - (old?[.value] == nil ? 0 : 1)
        rows[offset] = row.componentCount == 0 ? nil : row
    }
    mutating func patch(
        at offset: Int64, value: FrameFactChange<Record.Payload> = .leave,
        width: FrameFactChange<Record.Payload> = .leave,
        bank: FrameFactChange<Record.Payload> = .leave,
        outgoing: FrameFactChange<Record.Payload> = .leave
    ) {
        var row = rows[offset] ?? Record()
        func apply(_ change: FrameFactChange<Record.Payload>, _ field: FrameFactField) {
            switch change {
            case .leave: break
            case .erase: row[field] = nil
            case .assign(let value): row[field] = value
            }
        }
        apply(value, .value); apply(width, .width); apply(bank, .bank); apply(outgoing, .outgoing)
        replace(row, at: offset)
    }
    private mutating func erase(_ fields: FrameFactFields, from row: Record, at offset: Int64) {
        var updated = row
        for index in 0..<4 {
            let field = FrameFactField(rawValue: index)!
            if fields.contains(field.mask), Record.fields.contains(field.mask) { updated[field] = nil }
        }
        replace(updated, at: offset)
    }
    /// Queries are anchored ONLY on present values. No old value means no
    /// endpoint evaluation, even when width/bank/outgoing metadata remains.
    mutating func forget(
        _ effect: FrameMemoryEffect, removing fields: FrameFactFields,
        lostValue: (Record.Payload) -> Void = { _ in }
    ) {
        for (offset, row) in rows {
            guard let value = row[.value] else { continue }
            guard effect.mayInvalidate(.init(start: offset, bytes: row.extentBytes)) else { continue }
            erase(fields, from: row, at: offset)
            if fields.contains(.value) { lostValue(value) }
        }
    }
    /// Legacy start selection is not byte overlap; other metadata is untouched
    /// unless explicitly named by the caller.
    mutating func clearValueStarts(from: Int64, to: Int64?, removing fields: FrameFactFields) {
        for (offset, row) in rows {
            guard row[.value] != nil, offset >= from else { continue }
            if let to, offset >= to { continue }
            erase(fields, from: row, at: offset)
        }
    }
    mutating func removeComponents(_ fields: FrameFactFields) {
        for (offset, row) in rows { erase(fields, from: row, at: offset) }
    }
    mutating func removeAll(keepingCapacity: Bool = false) {
        rows.removeAll(keepingCapacity: keepingCapacity)
        componentCount = 0; valueCount = 0
    }
    /// Fieldwise must intersection. The tracer repairs self-isa first,
    /// collects pre-veto lost pointers next, then applies metadata vetoes.
    func intersecting(with other: Self) -> Self {
        var result = Self()
        for (offset, row) in rows {
            guard let theirs = other.rows[offset] else { continue }
            var kept = Record()
            for index in 0..<4 {
                let field = FrameFactField(rawValue: index)!
                if Record.fields.contains(field.mask), row[field] == theirs[field] { kept[field] = row[field] }
            }
            result.replace(kept, at: offset)
        }
        return result
    }
    func forEachLostValue(comparedWith final: Self, _ body: (Record.Payload) -> Void) {
        for (offset, row) in rows {
            if let value = row[.value], final[offset] != value { body(value) }
        }
    }
    func forEachMismatch(
        comparedWith final: Self, fields: FrameFactFields,
        _ body: (Int64, FrameFactField, Record.Payload) -> Void
    ) {
        for (offset, row) in rows {
            for index in 0..<4 {
                let field = FrameFactField(rawValue: index)!
                if fields.contains(field.mask), let value = row[field], final[offset, field] != value {
                    body(offset, field, value)
                }
            }
        }
    }
    struct Components: Sequence {
        fileprivate let rows: [Int64: Record]
        func makeIterator() -> ComponentIterator { ComponentIterator(rows: rows) }
    }
    struct ComponentIterator: IteratorProtocol {
        private var rows: Dictionary<Int64, Record>.Iterator
        private var current: (offset: Int64, row: Record)?
        private var fieldIndex = 4
        fileprivate init(rows: [Int64: Record]) { self.rows = rows.makeIterator() }
        mutating func next() -> (offset: Int64, field: FrameFactField, value: Record.Payload)? {
            while true {
                if let current {
                    while fieldIndex < 4 {
                        let field = FrameFactField(rawValue: fieldIndex)!
                        fieldIndex += 1
                        if let value = current.row[field] { return (current.offset, field, value) }
                    }
                }
                guard let row = rows.next() else { return nil }
                current = (row.key, row.value); fieldIndex = 0
            }
        }
    }
    var components: Components { Components(rows: rows) }
    struct Iterator: IteratorProtocol {
        private var rows: Dictionary<Int64, Record>.Iterator
        fileprivate init(rows: [Int64: Record]) { self.rows = rows.makeIterator() }
        mutating func next() -> Element? {
            while let row = rows.next() {
                if let value = row.value[.value] { return (row.key, value) }
            }
            return nil
        }
    }
    func makeIterator() -> Iterator { Iterator(rows: rows) }
    struct Keys: Sequence {
        let facts: FrameFacts
        struct Iterator: IteratorProtocol {
            var values: FrameFacts.Iterator
            mutating func next() -> Int64? { values.next()?.key }
        }
        func makeIterator() -> Iterator { Iterator(values: facts.makeIterator()) }
    }
    var keys: Keys { Keys(facts: self) }
}
