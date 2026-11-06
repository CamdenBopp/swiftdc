/// Finite alternatives do not imply membership in the MAY-alias set. Empty
/// alternatives, absent alternatives, and absence of membership are distinct.
struct FrameRegisterOrigins: Hashable {
    var offsets: Set<Int64> = []
    var below: Int64?

    func union(_ other: Self) -> Self {
        Self(offsets: offsets.union(other.offsets),
             below: [below, other.below].compactMap { $0 }.max())
    }
    var isEmpty: Bool { offsets.isEmpty && below == nil }
}

protocol FrameRegisterStorage: Equatable {
    associatedtype Key: Hashable
    associatedtype Value: Equatable
    init()
    var exact: [Key: Value] { get set }
}

struct TraceFrameRegisterStorage: FrameRegisterStorage {
    var exact: [ValueTracer.Location: AbstractValue] = [:]
}

/// Sparse columns avoid putting a Set and an optional finite payload in every
/// saved-entry register row. These are the sole owners of the three fields.
struct PreservationFrameRegisterStorage: FrameRegisterStorage {
    var exact: [String: Preservation.Value] = [:]
    var aliases: Set<String> = []
    var finite: [String: FrameRegisterOrigins] = [:]
}

enum FrameRegisterPatch<Value> { case leave, erase, assign(Value) }
struct FrameRegisterCopy<Value> { let value: Value? }

/// One register-fact owner; concrete storage preserves the existing payloads.
/// Raw APIs never normalize .unknown, membership, finite-empty or orphan data.
struct FrameRegisterFacts<Storage: FrameRegisterStorage>: Equatable {
    typealias Key = Storage.Key
    typealias Value = Storage.Value
    private var storage = Storage()
    init() {}

    subscript(_ key: Key) -> Value? {
        get { storage.exact[key] }
        set {
            if let newValue { patchExact(key, .assign(newValue)) }
            else { patchExact(key, .erase) }
        }
    }
    var exactCount: Int { storage.exact.count }
    // Borrowed compatibility access: no Dictionary(uniqueKeysWithValues:),
    // filtering copy or second durable map on a State's hot read/write path.
    var exactValues: [Key: Value] {
        _read { yield storage.exact }
        _modify { yield &storage.exact }
    }
    mutating func patchExact(_ key: Key, _ change: FrameRegisterPatch<Value>) {
        switch change {
        case .leave: break
        case .erase: storage.exact[key] = nil
        case .assign(let value): storage.exact[key] = value
        }
    }
    func snapshotForCopy(_ key: Key) -> FrameRegisterCopy<Value> {
        FrameRegisterCopy(value: storage.exact[key])
    }
    mutating func installCopy(
        _ source: FrameRegisterCopy<Value>, at destination: Key,
        fallback: Value, normalize: (Value) -> Value? = { $0 }
    ) {
        self[destination] = normalize(source.value ?? fallback)
    }
    mutating func reset() { storage = Storage() }

    func intersectingExact(with other: Self) -> Self {
        var result = Self()
        for (key, value) in storage.exact where other[key] == value {
            result[key] = value
        }
        return result
    }
    func forEachLostExact(comparedWith other: Self, _ body: (Key, Value) -> Void) {
        for (key, value) in storage.exact where other[key] != value { body(key, value) }
    }

    /// OR over selected per-key inputs. Projection is frontend policy; it is
    /// never a permission to collapse an escape transaction to one Any input.
    func containsSelected<Keys: Sequence>(
        _ keys: Keys, where predicate: (Key, Value?) -> Bool
    ) -> Bool where Keys.Element == Key {
        for key in keys where predicate(key, self[key]) { return true }
        return false
    }
    struct Selected<Keys: Sequence>: Sequence where Keys.Element == Key {
        let facts: FrameRegisterFacts<Storage>
        let keys: Keys
        struct Iterator: IteratorProtocol {
            var facts: FrameRegisterFacts<Storage>
            var keys: Keys.Iterator
            mutating func next() -> (key: Key, value: Value?)? {
                guard let key = keys.next() else { return nil }
                return (key, facts[key])
            }
        }
        func makeIterator() -> Iterator { Iterator(facts: facts, keys: keys.makeIterator()) }
    }
    func selected<Keys: Sequence>(_ keys: Keys) -> Selected<Keys> where Keys.Element == Key {
        Selected(facts: self, keys: keys)
    }
}

typealias TraceFrameRegisterFacts = FrameRegisterFacts<TraceFrameRegisterStorage>
typealias PreservationFrameRegisterFacts = FrameRegisterFacts<PreservationFrameRegisterStorage>

extension FrameRegisterFacts where Storage == PreservationFrameRegisterStorage {
    var aliasKeys: Set<String> {
        _read { yield storage.aliases }
        _modify { yield &storage.aliases }
    }
    var finiteOrigins: [String: FrameRegisterOrigins] {
        _read { yield storage.finite }
        _modify { yield &storage.finite }
    }
    func mayAlias(_ key: String) -> Bool { storage.aliases.contains(key) }

    mutating func installPreservation(
        _ key: String, value: Preservation.Value, mayAlias: Bool = false
    ) {
        // Only this semantic setter performs the old normalization. Raw init,
        // raw copy/import, and exact equality keep explicit .unknown present.
        self[key] = value == .unknown ? nil : value
        storage.finite[key] = nil
        switch value {
        case .stack, .below: storage.aliases.insert(key)
        default:
            if mayAlias { storage.aliases.insert(key) }
            else { storage.aliases.remove(key) }
        }
    }
    mutating func copyPreservation(from source: String, to destination: String) {
        let sourceValue = snapshotForCopy(source)
        let sourceAlias = mayAlias(source)
        let sourceFinite = storage.finite[source]
        installCopy(sourceValue, at: destination, fallback: .unknown) { $0 == .unknown ? nil : $0 }
        storage.finite[destination] = nil
        switch sourceValue.value ?? .unknown {
        case .stack, .below: storage.aliases.insert(destination)
        default:
            if sourceAlias { storage.aliases.insert(destination) }
            else { storage.aliases.remove(destination) }
        }
        storage.finite[destination] = sourceFinite
    }
    func origins(_ key: String) -> FrameRegisterOrigins? {
        switch self[key] ?? .unknown {
        case .stack(let offset): return .init(offsets: [offset])
        case .below(let bound): return .init(below: bound)
        default: break
        }
        if let finite = storage.finite[key] { return finite }
        return mayAlias(key) ? nil : FrameRegisterOrigins()
    }
    func escapeOrigins(_ key: String) -> PossibleFrameOrigins {
        switch self[key] ?? .unknown {
        case .stack(let offset): return .finite(offsets: [offset], below: nil)
        case .below(let bound): return .finite(offsets: [], below: bound)
        case .unknown where storage.finite[key] != nil:
            let finite = storage.finite[key] ?? FrameRegisterOrigins()
            return .finite(offsets: finite.offsets, below: finite.below)
        default: return .any
        }
    }
    func mergedPreservation(with other: Self) -> Self {
        var result = intersectingExact(with: other)
        // Repair must values before deriving MAY alternatives, as before.
        forEachLostExact(comparedWith: other) { key, mine in
            if result[key] == nil, case .below(let a) = mine, case .below(let b)? = other[key] {
                result[key] = .below(max(a, b))
            }
        }
        result.storage.aliases = storage.aliases.union(other.storage.aliases)
        for key in result.storage.aliases where result[key] == nil {
            guard let mine = origins(key), let theirs = other.origins(key) else { continue }
            let combined = mine.union(theirs)
            // Legacy normalization: dropping an empty finite union leaves
            // alias membership present and therefore exposes Any next time.
            if !combined.isEmpty { result.storage.finite[key] = combined }
        }
        return result
    }
}

/// Only current-frame coordinates. No case classifies or proves disjointness
/// for absolute/self/result/context addresses; frontends keep those policies.
enum FrameCoordinate: Equatable {
    case point(Int64), below(Int64)
}

struct FrameCoordinateAccess: Equatable {
    let start: Int64
    let after: FrameCoordinate?
}

enum FrameCoordinatePlanner {
    static func shiftedPoint(_ offset: Int64, by delta: Int64, subtracting: Bool) -> Int64 {
        subtracting ? offset &- delta : offset &+ delta
    }
    static func exactAccess(
        _ coordinate: FrameCoordinate, displacement: Int64,
        postIndex: Bool, writeback: Bool, trailingImmediate: Int64?
    ) -> FrameCoordinateAccess? {
        guard case .point(let offset) = coordinate else { return nil }
        if postIndex {
            return .init(start: offset, after: .point(shiftedPoint(offset, by: trailingImmediate ?? 0, subtracting: false)))
        }
        let start = exactStart(offset, displacement: displacement, postIndex: false)
        return .init(start: start, after: writeback ? .point(start) : nil)
    }
    static func exactStart(_ offset: Int64, displacement: Int64, postIndex: Bool) -> Int64 {
        postIndex ? offset : shiftedPoint(offset, by: displacement, subtracting: false)
    }
    static func exactWriteback(_ offset: Int64, delta: Int64) -> Int64 {
        shiftedPoint(offset, by: delta, subtracting: false)
    }
    static func belowAccess(
        _ coordinate: FrameCoordinate, displacement: Int64,
        postIndex: Bool, writeback: Bool, trailingImmediate: Int64?
    ) -> FrameCoordinateAccess? {
        guard case .below(let bound) = coordinate else { return nil }
        let delta = postIndex ? (trailingImmediate ?? 0) : displacement
        let (limit, overflow) = bound.addingReportingOverflow(max(postIndex ? 0 : displacement, 0))
        guard !overflow else { return nil }
        let after: FrameCoordinate? = writeback || postIndex
            ? .below(shiftedPoint(bound, by: max(delta, 0), subtracting: false)) : nil
        return .init(start: limit, after: after)
    }
}
