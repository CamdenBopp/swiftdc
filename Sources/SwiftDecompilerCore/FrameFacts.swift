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

/// Storage specializes representation, not frame-fact operations. In
/// particular, MAY presence needs a Set rather than a dictionary of empty
/// payloads. Neither implementation keeps a second map or an array of rows.
protocol FrameFactStorage: Equatable, Sequence where Element == (key: Int64, value: Record) {
    associatedtype Record: FrameFactRecord
    init()
    subscript(_ offset: Int64) -> Record? { get set }
    mutating func removeAll(keepingCapacity: Bool)
}

struct DictionaryFrameFactStorage<Record: FrameFactRecord>: FrameFactStorage {
    private var rows: [Int64: Record] = [:]
    init() {}
    subscript(_ offset: Int64) -> Record? {
        get { rows[offset] }
        set { rows[offset] = newValue }
    }
    mutating func removeAll(keepingCapacity: Bool) { rows.removeAll(keepingCapacity: keepingCapacity) }
    func makeIterator() -> Dictionary<Int64, Record>.Iterator { rows.makeIterator() }
}

struct MayFrameSlotStorage: FrameFactStorage {
    typealias Record = WordFrameFact<ReachPresence>
    private var starts: Set<Int64> = []
    init() {}
    subscript(_ offset: Int64) -> Record? {
        get {
            guard starts.contains(offset) else { return nil }
            var record = Record()
            record.value = ReachPresence()
            return record
        }
        set {
            if newValue?.value != nil { starts.insert(offset) }
            else { starts.remove(offset) }
        }
    }
    mutating func removeAll(keepingCapacity: Bool) { starts.removeAll(keepingCapacity: keepingCapacity) }
    struct Iterator: IteratorProtocol {
        private var starts: Set<Int64>.Iterator
        fileprivate init(_ starts: Set<Int64>) { self.starts = starts.makeIterator() }
        mutating func next() -> (key: Int64, value: Record)? {
            guard let start = starts.next() else { return nil }
            var record = Record()
            record.value = ReachPresence()
            return (start, record)
        }
    }
    func makeIterator() -> Iterator { Iterator(starts) }
}

/// The sole owner of current-frame facts, relative to entry sp. Unknown values
/// remain present payloads, unlike missing values. Must facts and MAY presence
/// share lookup, installation, removal, counts and effect queries; their joins
/// remain explicitly different. Result/context and escape domains stay separate.
struct StoredFrameFacts<Storage: FrameFactStorage>: Equatable, Sequence, ExpressibleByDictionaryLiteral {
    typealias Record = Storage.Record
    typealias Key = Int64
    typealias Value = Record.Payload
    typealias Element = (key: Int64, value: Record.Payload)
    private var rows = Storage()
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
    /// A read-side query over the same present values and byte extents used
    /// by forgetting. Metadata-only rows do not represent memory snapshots.
    func containsValue(affectedBy effect: FrameMemoryEffect) -> Bool {
        for (offset, row) in rows where row[.value] != nil {
            if effect.mayInvalidate(.init(start: offset, bytes: row.extentBytes)) { return true }
        }
        return false
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
        fileprivate let rows: Storage
        func makeIterator() -> ComponentIterator { ComponentIterator(rows: rows) }
    }
    struct ComponentIterator: IteratorProtocol {
        private var rows: Storage.Iterator
        private var current: (offset: Int64, row: Record)?
        private var fieldIndex = 4
        fileprivate init(rows: Storage) { self.rows = rows.makeIterator() }
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
        private var rows: Storage.Iterator
        fileprivate init(rows: Storage) { self.rows = rows.makeIterator() }
        mutating func next() -> Element? {
            while let row = rows.next() {
                if let value = row.value[.value] { return (row.key, value) }
            }
            return nil
        }
    }
    func makeIterator() -> Iterator { Iterator(rows: rows) }
    struct Keys: Sequence {
        let facts: StoredFrameFacts
        struct Iterator: IteratorProtocol {
            var values: StoredFrameFacts.Iterator
            mutating func next() -> Int64? { values.next()?.key }
        }
        func makeIterator() -> Iterator { Iterator(values: facts.makeIterator()) }
    }
    var keys: Keys { Keys(facts: self) }
}

typealias FrameFacts<Record: FrameFactRecord> = StoredFrameFacts<DictionaryFrameFactStorage<Record>>
typealias MayFrameSlots = StoredFrameFacts<MayFrameSlotStorage>

extension StoredFrameFacts where Storage == MayFrameSlotStorage {
    func contains(_ offset: Int64) -> Bool { self[offset] != nil }
    mutating func insert(_ offset: Int64) { self[offset] = ReachPresence() }
    mutating func remove(_ offset: Int64) { self[offset] = nil }
    mutating func formUnion<Offsets: Sequence>(_ offsets: Offsets) where Offsets.Element == Int64 {
        for offset in offsets { insert(offset) }
    }
    /// MAY presence survives on either predecessor. Never use the must-fact
    /// intersection for these slots, even when an exact frame value is lost.
    func mayUnion(with other: Self) -> Self {
        var result = self
        result.formUnion(other.keys)
        return result
    }
}
