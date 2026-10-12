import Foundation
import Synchronization

/// Instrumentation: why the analysis decided, declined or gave up, how often,
/// and what it claimed, as typed events a test or a tool can read.
///
/// Adding an instrument is a definition and a call:
///
///     extension ProbeEvent {
///         static let arityFromBody = ProbeEvent(
///             "abi.arity-from-body", .abi, .decision,
///             "A callee with no signature takes the argument registers its body reads.")
///     }
///     Probe.record(.arityFromBody, at: site, ["callee": .name(callee), "count": .int(n)])
///
/// Nothing reaches a call site through parameters. A recorder installed with
/// `Probe.recording(_:_:)` is task-local, and so is the function being
/// analysed (`Probe.inFunction`), so the tracer, the structurer and a static
/// helper can all record without plumbing. When no recorder is installed
/// anywhere, a call costs one relaxed atomic load and a branch: the payload
/// is an autoclosure and is never built.
///
/// Instruments observe; they never decide. Nothing in the analysis may read
/// what a recorder holds, so turning instrumentation on cannot change output
/// (`probeRecordingDoesNotChangeOutput` holds the line).
public enum Probe {
    /// Recorders installed anywhere in the process. Zero is the fast path.
    static let installed = Atomic<Int>(0)
    @TaskLocal static var recorder: ProbeRecorder?
    @TaskLocal static var function: ProbeFunction?

    /// Whether any recorder is installed. Call sites need not check it; it is
    /// for skipping work that only feeds a probe.
    @inline(__always) public static var isActive: Bool {
        installed.load(ordering: .relaxed) > 0
    }

    /// Runs `body` with `recorder` receiving every event recorded in it,
    /// including in child tasks.
    public static func recording<T>(
        _ recorder: ProbeRecorder, _ body: () async throws -> T
    ) async rethrows -> T {
        installed.add(1, ordering: .relaxed)
        defer { installed.subtract(1, ordering: .relaxed) }
        return try await $recorder.withValue(recorder, operation: body)
    }

    /// Synchronous form of `recording(_:_:)`.
    public static func recording<T>(_ recorder: ProbeRecorder, _ body: () throws -> T) rethrows -> T {
        installed.add(1, ordering: .relaxed)
        defer { installed.subtract(1, ordering: .relaxed) }
        return try $recorder.withValue(recorder, operation: body)
    }

    /// The recorder and function in effect here, to re-install on another
    /// thread with `withContext`. Task-locals do not cross a `Thread`.
    static var context: (ProbeRecorder?, ProbeFunction?) { (recorder, function) }

    static func withContext<T>(_ context: (ProbeRecorder?, ProbeFunction?), _ body: () throws -> T) rethrows -> T {
        guard context.0 != nil else { return try body() }
        return try $recorder.withValue(context.0) { try $function.withValue(context.1, operation: body) }
    }

    /// Runs `body` with nothing recorded: for a pass that repeats work whose
    /// events another pass records.
    static func muted<T>(_ body: () throws -> T) rethrows -> T {
        guard isActive, recorder != nil else { return try body() }
        return try $recorder.withValue(nil, operation: body)
    }

    /// Runs `body` with events attributed to the function starting at `start`.
    @inline(__always)
    static func inFunction<T>(_ start: UInt64, _ name: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {
        guard isActive, recorder != nil else { return try body() }
        return try $function.withValue(ProbeFunction(start: start, name: name()), operation: body)
    }

    /// Records `event` at `address` (an instruction, or the function itself
    /// when nil) with `fields`.
    @inline(__always)
    static func record(
        _ event: ProbeEvent, at address: UInt64? = nil,
        _ fields: @autoclosure () -> KeyValuePairs<String, ProbeValue> = [:]
    ) {
        guard isActive, let recorder else { return }
        recorder.receive(event, function: function, address: address, fields: fields)
    }

    /// Adds `amount` to `event`'s count without emitting a trace line: for a
    /// metric too frequent to trace (one per instruction).
    @inline(__always)
    static func count(_ event: ProbeEvent, by amount: Int = 1) {
        guard isActive, let recorder else { return }
        recorder.add(event, amount)
    }

    /// Times `body` under `event`: the total and the number of runs land in
    /// the recorder's summary, never in the deterministic event stream.
    @inline(__always)
    static func timed<T>(_ event: ProbeEvent, _ body: () throws -> T) rethrows -> T {
        guard isActive, let recorder else { return try body() }
        let start = ContinuousClock.now
        defer { recorder.addTime(event, ContinuousClock.now - start) }
        return try body()
    }
}

/// The function an event happened in.
public struct ProbeFunction: Sendable, Equatable {
    public let start: UInt64
    public let name: String
}

/// One instrument: a stable identifier plus where it belongs and what it
/// means. The identifier is the schema: renaming one is a breaking change to
/// `ProbeRecorder.schema`.
public struct ProbeEvent: Sendable, Hashable {
    public enum Subsystem: String, Sendable, CaseIterable {
        case loader, metadata, objc, decode, cfg, values, abi, async, types, idioms, structure, render, graph, perf
    }

    public enum Category: String, Sendable, CaseIterable {
        /// The analysis chose one reading among others and why.
        case decision
        /// The analysis refused to claim something; the reason is the payload.
        /// Counts against completeness, never against soundness.
        case decline
        /// A bound was hit (a visit cap, a fixpoint limit): what follows is a
        /// conservative fallback, not a proof.
        case limit
        /// A semantic claim the output makes, in a form an independent oracle
        /// (DWARF, objdump, the source) can check.
        case claim
        /// A count or a cost.
        case metric
    }

    public let id: String
    public let subsystem: Subsystem
    public let category: Category
    public let meaning: String

    public init(_ id: String, _ subsystem: Subsystem, _ category: Category, _ meaning: String) {
        self.id = id
        self.subsystem = subsystem
        self.category = category
        self.meaning = meaning
    }

    public static func == (a: ProbeEvent, b: ProbeEvent) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A field value. Text derived from the binary (`.name`) is redacted unless
/// the recorder allows names, so a trace can be shared without the symbols of
/// the binary it came from.
public enum ProbeValue: Sendable, Equatable, CustomStringConvertible {
    case int(Int)
    case address(UInt64)
    case bool(Bool)
    /// A fixed string from swiftdc itself (a reason, a register name).
    case label(String)
    /// Text read from the binary: a symbol, a type, a selector.
    case name(String)

    public var description: String {
        switch self {
        case .int(let value): "\(value)"
        case .address(let value): "0x\(String(value, radix: 16))"
        case .bool(let value): "\(value)"
        case .label(let value), .name(let value): value
        }
    }
}

/// One recorded event, as a test or a sink sees it.
public struct ProbeRecord: Sendable, Equatable {
    public let sequence: Int
    public let event: ProbeEvent
    public let function: ProbeFunction?
    public let address: UInt64?
    public let fields: [(key: String, value: ProbeValue)]

    public subscript(_ key: String) -> ProbeValue? { fields.first { $0.key == key }?.value }

    public static func == (a: ProbeRecord, b: ProbeRecord) -> Bool {
        a.sequence == b.sequence && a.event == b.event && a.function == b.function
            && a.address == b.address && a.fields.elementsEqual(b.fields) { $0.key == $1.key && $0.value == $1.value }
    }
}

/// Which events a recorder keeps. Counts are kept for every event whatever
/// the filter, so a narrow trace still has whole-run metrics.
public struct ProbeFilter: Sendable {
    public var subsystems: Set<ProbeEvent.Subsystem>?
    public var categories: Set<ProbeEvent.Category>?
    public var events: Set<String>?
    /// Case-insensitive substring of the function's name.
    public var function: String?
    public var addresses: ClosedRange<UInt64>?

    public init(subsystems: Set<ProbeEvent.Subsystem>? = nil, categories: Set<ProbeEvent.Category>? = nil,
                events: Set<String>? = nil, function: String? = nil, addresses: ClosedRange<UInt64>? = nil) {
        self.subsystems = subsystems
        self.categories = categories
        self.events = events
        self.function = function
        self.addresses = addresses
    }

    func admits(_ event: ProbeEvent, function: ProbeFunction?, address: UInt64?) -> Bool {
        if let subsystems, !subsystems.contains(event.subsystem) { return false }
        if let categories, !categories.contains(event.category) { return false }
        if let events, !events.contains(event.id) { return false }
        if let needle = self.function {
            guard let name = function?.name, name.localizedCaseInsensitiveContains(needle) else { return false }
        }
        if let addresses {
            guard let where_ = address ?? function?.start, addresses.contains(where_) else { return false }
        }
        return true
    }
}

/// Receives events: counts all of them, keeps or streams the ones its filter
/// admits, and runs validators on each. Thread-safe.
public final class ProbeRecorder: Sendable {
    public static let schema = "swiftdc-probe/1"

    public enum Output: Sendable {
        /// Keep admitted records in memory (`records`), for tests.
        case capture
        /// Write each admitted record as a JSON line, then a summary line.
        case jsonLines(@Sendable (String) -> Void)
        /// Counts and times only.
        case summaryOnly
    }

    /// Returns a violation message when a record contradicts an oracle.
    public typealias Validator = @Sendable (ProbeRecord) -> String?

    struct State {
        var sequence = 0
        var records: [ProbeRecord] = []
        var counts: [ProbeEvent: Int] = [:]
        var times: [ProbeEvent: (total: Duration, runs: Int)] = [:]
        var violations: [String] = []
    }

    let filter: ProbeFilter
    let output: Output
    let includeNames: Bool
    let validators: [Validator]
    let state = Mutex(State())

    public init(filter: ProbeFilter = ProbeFilter(), output: Output = .capture, includeNames: Bool = true,
                validators: [Validator] = []) {
        self.filter = filter
        self.output = output
        self.includeNames = includeNames
        self.validators = validators
    }

    public var records: [ProbeRecord] { state.withLock { $0.records } }
    public var counts: [String: Int] {
        state.withLock { Dictionary(uniqueKeysWithValues: $0.counts.map { ($0.key.id, $0.value) }) }
    }
    public var violations: [String] { state.withLock { $0.violations } }

    public func count(of event: ProbeEvent) -> Int { state.withLock { $0.counts[event] ?? 0 } }

    func receive(_ event: ProbeEvent, function: ProbeFunction?, address: UInt64?,
                 fields: () -> KeyValuePairs<String, ProbeValue>) {
        let admitted = filter.admits(event, function: function, address: address)
        guard admitted || !validators.isEmpty else {
            state.withLock { $0.counts[event, default: 0] += 1 }
            return
        }
        let built = fields().map { (key: $0.key, value: $0.value) }
        let (record, line): (ProbeRecord, String?) = state.withLock { state in
            state.counts[event, default: 0] += 1
            state.sequence += 1
            let record = ProbeRecord(sequence: state.sequence, event: event, function: function,
                                     address: address, fields: built)
            for validator in validators {
                if let violation = validator(record) { state.violations.append(violation) }
            }
            guard admitted else { return (record, nil) }
            switch output {
            case .capture:
                state.records.append(record)
                return (record, nil)
            case .jsonLines:
                return (record, jsonLine(record))
            case .summaryOnly:
                return (record, nil)
            }
        }
        _ = record
        if let line, case .jsonLines(let write) = output { write(line) }
    }

    func add(_ event: ProbeEvent, _ amount: Int) {
        state.withLock { $0.counts[event, default: 0] += amount }
    }

    func addTime(_ event: ProbeEvent, _ duration: Duration) {
        state.withLock { state in
            let old = state.times[event] ?? (.zero, 0)
            state.times[event] = (old.total + duration, old.runs + 1)
        }
    }

    /// The closing summary: every event's count (sorted by identifier, so it
    /// is deterministic) and, separately, wall-clock times, which are not.
    public func summaryLine() -> String {
        state.withLock { state in
            let counts = state.counts.sorted { $0.key.id < $1.key.id }
                .map { "\(quoted($0.key.id)):\($0.value)" }.joined(separator: ",")
            let times = state.times.sorted { $0.key.id < $1.key.id }
                .map { "\(quoted($0.key.id)):{\"seconds\":\(Double($0.value.total.components.seconds) + Double($0.value.total.components.attoseconds) / 1e18),\"runs\":\($0.value.runs)}" }
                .joined(separator: ",")
            let violations = state.violations.map(quoted).joined(separator: ",")
            return "{\"schema\":\(quoted(Self.schema)),\"summary\":{\"counts\":{\(counts)},\"times\":{\(times)},\"violations\":[\(violations)]}}"
        }
    }

    func jsonLine(_ record: ProbeRecord) -> String {
        var parts = [
            "\"seq\":\(record.sequence)",
            "\"event\":\(quoted(record.event.id))",
            "\"subsystem\":\(quoted(record.event.subsystem.rawValue))",
            "\"category\":\(quoted(record.event.category.rawValue))",
        ]
        if let function = record.function {
            parts.append("\"function\":\(quoted(ProbeValue.address(function.start).description))")
            parts.append("\"functionName\":\(quoted(redacted(.name(function.name))))")
        }
        if let address = record.address {
            parts.append("\"address\":\(quoted(ProbeValue.address(address).description))")
        }
        let fields = record.fields.map { field -> String in
            let value: String = switch field.value {
            case .int(let n): "\(n)"
            case .bool(let b): "\(b)"
            default: quoted(redacted(field.value))
            }
            return "\(quoted(field.key)):\(value)"
        }
        parts.append("\"fields\":{\(fields.joined(separator: ","))}")
        return "{\(parts.joined(separator: ","))}"
    }

    /// A binary-derived name, or a stable 8-hex-digit FNV-1a hash of it when
    /// names are not allowed: still correlatable across events in one trace.
    func redacted(_ value: ProbeValue) -> String {
        guard case .name(let text) = value, !includeNames else { return value.description }
        var hash: UInt32 = 0x811c9dc5
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 0x01000193 }
        return "name#" + String(format: "%08x", hash)
    }
}

private func quoted(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}
