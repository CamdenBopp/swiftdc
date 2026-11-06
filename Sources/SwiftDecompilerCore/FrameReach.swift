/// Legacy marker identities and payloads remain independent of their geometric
/// coverage. Dynamic allocation evidence is present but does not escape memory.
enum TraceReachKey: Hashable {
    case point(Int64), below(Int64), all, dynamic(Int64)
}

struct FrozenFrameRange: Hashable {
    let floor: Int64
    let bound: Int64
}

enum FrozenReachKey: Hashable {
    case range(FrozenFrameRange)
    case whole
}

struct ReachPresence: Equatable {}
struct FrameReachEntry<Key, Payload> {
    let key: Key
    let payload: Payload
}

enum FrameReachProjection {
    case none
    case finite(Int64, Int64)
    case whole
}

/// Only the function's register-save area may bound a tracer escape. A
/// separately calculated address is not evidence of a separate object.
struct TraceLayoutEvidence: Sendable {
    private let sortedSaveStarts: [Int64]
    init(prologueSaveSlots: Set<Int64>) {
        sortedSaveStarts = prologueSaveSlots.sorted()
    }
    func upperBound(after offset: Int64) -> Int64? {
        sortedSaveStarts.first { $0 > offset }
    }
}
struct NoFrameQueryEvidence {}

/// Snapshot once at escape, from the live `.entry` save facts at that point.
/// Only the frozen bounds below enter range equality, never this evidence.
struct LiveEntrySaveEvidence {
    let sortedEntryStarts: [Int64]
    func range(from offset: Int64) -> FrozenFrameRange? {
        guard !sortedEntryStarts.contains(where: { offset >= $0 && offset < $0 &+ 8 }),
              let next = sortedEntryStarts.first(where: { $0 > offset })
        else { return nil }
        return FrozenFrameRange(floor: offset, bound: next)
    }
    func range(below bound: Int64) -> FrozenFrameRange? {
        guard sortedEntryStarts.contains(where: { $0 >= bound }) else { return nil }
        return FrozenFrameRange(floor: Int64.min, bound: bound)
    }
}

/// A producer-side input, not a replacement for the register alias lattice.
/// A present empty finite input remains distinct from Any and from no input.
enum PossibleFrameOrigins {
    case none
    case finite(offsets: Set<Int64>, below: Int64?)
    case any
}

protocol FrameReachStorage: Equatable {
    associatedtype Key: Hashable
    associatedtype Payload: Equatable
    associatedtype QueryEvidence
    associatedtype Entries: Sequence where Entries.Element == FrameReachEntry<Key, Payload>
    init()
    static var wholeKey: Key { get }
    subscript(_ key: Key) -> Payload? { get set }
    var entries: Entries { get }
    func project(_ key: Key, using evidence: QueryEvidence) -> FrameReachProjection
    mutating func reset()
}

struct TraceReachStorage: FrameReachStorage {
    typealias Key = TraceReachKey
    typealias Payload = AbstractValue
    typealias QueryEvidence = TraceLayoutEvidence
    private var markers: [Key: Payload] = [:]
    init() {}
    static var wholeKey: Key { .all }
    subscript(_ key: Key) -> Payload? {
        get { markers[key] }
        set { markers[key] = newValue }
    }
    func project(_ key: Key, using evidence: QueryEvidence) -> FrameReachProjection {
        switch key {
        case .point(let start):
            let bound = start >= 0 ? Int64.max : (evidence.upperBound(after: start) ?? 0)
            return .finite(start, bound)
        case .below(let bound): return .finite(Int64.min, bound)
        case .all: return .whole
        case .dynamic: return .none
        }
    }
    mutating func reset() { markers.removeAll() }
    struct Entries: Sequence {
        fileprivate let markers: [Key: Payload]
        struct Iterator: IteratorProtocol {
            private var base: Dictionary<Key, Payload>.Iterator
            fileprivate init(_ markers: [Key: Payload]) { base = markers.makeIterator() }
            mutating func next() -> FrameReachEntry<Key, Payload>? {
                guard let entry = base.next() else { return nil }
                return FrameReachEntry(key: entry.key, payload: entry.value)
            }
        }
        func makeIterator() -> Iterator { Iterator(markers) }
    }
    var entries: Entries { Entries(markers: markers) }
}

struct FrozenReachStorage: FrameReachStorage {
    typealias Key = FrozenReachKey
    typealias Payload = ReachPresence
    typealias QueryEvidence = NoFrameQueryEvidence
    fileprivate var ranges: Set<FrozenFrameRange> = []
    private var whole = false
    init() {}
    static var wholeKey: Key { .whole }
    subscript(_ key: Key) -> Payload? {
        get {
            switch key {
            case .range(let range): return ranges.contains(range) ? ReachPresence() : nil
            case .whole: return whole ? ReachPresence() : nil
            }
        }
        set {
            switch key {
            case .range(let range):
                if newValue != nil { ranges.insert(range) } else { ranges.remove(range) }
            case .whole: whole = newValue != nil
            }
        }
    }
    func project(_ key: Key, using evidence: QueryEvidence) -> FrameReachProjection {
        switch key {
        case .range(let range): return .finite(range.floor, range.bound)
        case .whole: return .whole
        }
    }
    mutating func reset() { ranges.removeAll(); whole = false }
    struct Entries: Sequence {
        fileprivate let ranges: Set<FrozenFrameRange>
        fileprivate let whole: Bool
        struct Iterator: IteratorProtocol {
            private var ranges: Set<FrozenFrameRange>.Iterator
            private var whole: Bool
            fileprivate init(_ ranges: Set<FrozenFrameRange>, _ whole: Bool) {
                self.ranges = ranges.makeIterator(); self.whole = whole
            }
            mutating func next() -> FrameReachEntry<Key, Payload>? {
                if let range = ranges.next() { return FrameReachEntry(key: .range(range), payload: ReachPresence()) }
                if whole { whole = false; return FrameReachEntry(key: .whole, payload: ReachPresence()) }
                return nil
            }
        }
        func makeIterator() -> Iterator { Iterator(ranges, whole) }
    }
    var entries: Entries { Entries(ranges: ranges, whole: whole) }
}

/// The actual durable frame-reach owner. Storage specializes representation;
/// presence/count, payload intersection, ordered union, reset and effect
/// emission are shared algorithms. Whole coverage does not absorb identities.
struct DurableFrameReach<Storage: FrameReachStorage>: Equatable {
    private var storage = Storage()
    private(set) var logicalCount = 0
    init() {}
    subscript(_ key: Storage.Key) -> Storage.Payload? {
        get { storage[key] }
        set {
            let wasPresent = storage[key] != nil
            storage[key] = newValue
            let isPresent = storage[key] != nil
            if wasPresent != isPresent { logicalCount += isPresent ? 1 : -1 }
        }
    }
    var entries: Storage.Entries { storage.entries }
    var hasWhole: Bool { storage[Storage.wholeKey] != nil }
    mutating func formUnion(_ other: Self) {
        for entry in other.entries { self[entry.key] = entry.payload }
    }
    func union(_ other: Self) -> Self {
        var result = self
        result.formUnion(other)
        return result
    }
    /// Only the raw State intersection; tracer's later MAY phase unions
    /// every marker back in, preserving right-input payload overwrite order.
    func equalPayloadIntersection(_ other: Self) -> Self {
        var result = Self()
        for entry in entries where other[entry.key] == entry.payload { result[entry.key] = entry.payload }
        return result
    }
    mutating func reset() { storage.reset(); logicalCount = 0 }
    /// Prepare once per consumer action. The existing shared effect performs
    /// all extent queries; there is no per-analysis reach predicate here.
    func effect(
        using evidence: Storage.QueryEvidence,
        arithmetic: FrameMemoryEffect.FactEndArithmetic,
        includingCallerOwned: Bool = false
    ) -> FrameMemoryEffect {
        var regions = Set<FrameMemoryEffect.Region>()
        var everything = false
        for entry in entries {
            switch storage.project(entry.key, using: evidence) {
            case .none: break
            case .finite(let floor, let bound): regions.insert(.finite(lower: floor, upper: bound))
            case .whole: everything = true
            }
        }
        if includingCallerOwned { regions.insert(.atOrAbove(0)) }
        return FrameMemoryEffect(regions, arithmetic: arithmetic, everything: everything)
    }
}

typealias TraceFrameReach = DurableFrameReach<TraceReachStorage>
typealias FrozenFrameReach = DurableFrameReach<FrozenReachStorage>

extension DurableFrameReach where Storage == FrozenReachStorage {
    /// Forwarding compatibility view, not another stored range map.
    var frozenRanges: Set<FrozenFrameRange> {
        get { storage.ranges }
        set {
            let whole = hasWhole
            reset()
            for range in newValue { self[.range(range)] = ReachPresence() }
            if whole { self[.whole] = ReachPresence() }
        }
    }
    /// Resolve the entire input before insertion. If one alternative is
    /// unbounded, legacy markEscape sets whole without adding partial ranges
    /// from that input. Previously recorded ranges still remain.
    mutating func recordEscape(_ input: PossibleFrameOrigins, against evidence: LiveEntrySaveEvidence) {
        switch input {
        case .none: return
        case .any: self[.whole] = ReachPresence()
        case .finite(let offsets, let below):
            var resolved: [FrozenFrameRange] = []
            for offset in offsets.sorted() {
                guard let range = evidence.range(from: offset) else {
                    self[.whole] = ReachPresence()
                    return
                }
                resolved.append(range)
            }
            if let below {
                guard let range = evidence.range(below: below) else {
                    self[.whole] = ReachPresence()
                    return
                }
                resolved.append(range)
            }
            for range in resolved { self[.range(range)] = ReachPresence() }
        }
    }
}
