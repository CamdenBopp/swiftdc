import Foundation
import Synchronization

/// Exact integer return cases. An omitted exit address requires exactly one
/// recorded exit for the function; multi-exit functions need an explicit exit.
public struct ReturnExpectation: Sendable, Codable {
    public var function: UInt64
    public var address: UInt64?
    public var expected: UInt64
    public var arguments: [UInt64]
    public var bits: Int
    public var id: String?

    public init(_ expected: UInt64, in function: UInt64, at address: UInt64? = nil,
                arguments: [UInt64] = [], bits: Int = 64, id: String? = nil) {
        self.function = function; self.address = address; self.expected = expected
        self.arguments = arguments; self.bits = bits; self.id = id
    }

    /// Build common one-argument cases with a typed, independently supplied oracle.
    public static func samples<Integer: FixedWidthInteger>(
        in function: UInt64, inputs: [Integer], bits: Int = Integer.bitWidth,
        oracle: (Integer) throws -> Integer
    ) rethrows -> [Self] {
        try inputs.map {
            Self(UInt64(truncatingIfNeeded: try oracle($0)), in: function,
                 arguments: [UInt64(truncatingIfNeeded: $0)], bits: bits)
        }
    }

    public init(signed expected: Int64, in function: UInt64, at address: UInt64? = nil,
                arguments: [Int64] = [], bits: Int = 64, id: String? = nil) {
        self.init(UInt64(bitPattern: expected), in: function, at: address,
                  arguments: arguments.map { UInt64(bitPattern: $0) }, bits: bits, id: id)
    }

    private enum CodingKeys: String, CodingKey { case function, address, expected, arguments, bits, id }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        function = try c.decode(BitPattern.self, forKey: .function).value
        address = try c.decodeIfPresent(BitPattern.self, forKey: .address)?.value
        expected = try c.decode(BitPattern.self, forKey: .expected).value
        arguments = try c.decodeIfPresent([BitPattern].self, forKey: .arguments)?.map(\.value) ?? []
        bits = try c.decodeIfPresent(Int.self, forKey: .bits) ?? 64
        id = try c.decodeIfPresent(String.self, forKey: .id)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(BitPattern(function), forKey: .function)
        try c.encodeIfPresent(address.map(BitPattern.init), forKey: .address)
        try c.encode(BitPattern(expected), forKey: .expected)
        try c.encode(arguments.map(BitPattern.init), forKey: .arguments)
        try c.encode(bits, forKey: .bits); try c.encodeIfPresent(id, forKey: .id)
    }
}

/// Portable oracle manifests are optional; Swift callers can pass cases directly.
public struct ReturnOracle: Sendable, Codable {
    public var schema = "swiftdc-oracle/1"
    public var binaryUUID: String?
    public var cases: [ReturnExpectation]
    public init(_ cases: [ReturnExpectation], binaryUUID: String? = nil) {
        self.cases = cases; self.binaryUUID = binaryUUID
    }
}

public enum ProbeScoreError: Error, CustomStringConvertible {
    case invalid(String), unsupported(String)
    public var description: String {
        switch self { case .invalid(let text), .unsupported(let text): text }
    }
}

struct BitPattern: Codable {
    let value: UInt64
    init(_ value: UInt64) { self.value = value }
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let text = try? c.decode(String.self), let value = Self.parse(text) { self.value = value }
        else if let value = try? c.decode(UInt64.self) { self.value = value }
        else if let value = try? c.decode(Int64.self) { self.value = UInt64(bitPattern: value) }
        else { throw ProbeScoreError.invalid("expected an exact 64-bit integer or hex string") }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode("0x" + String(value, radix: 16))
    }
    static func parse(_ text: String) -> UInt64? {
        if text.hasPrefix("0x") { return UInt64(text.dropFirst(2), radix: 16) }
        return UInt64(text) ?? Int64(text).map { UInt64(bitPattern: $0) }
    }
}

public extension ProbeValue {
    /// Evaluate the exported integer bit-vector domain, independently of the
    /// tracer's folding code. Unknowns, floats and provenance leaves decline.
    func evaluateInteger(arguments: [UInt64] = []) throws -> UInt64 {
        guard case .object(let wrapper) = self, wrapper["schema"]?.description == "swiftdc-value/1",
              let expression = wrapper["expression"] else {
            throw ProbeScoreError.invalid("expected swiftdc-value/1")
        }
        var budget = 1024
        func evaluate(_ value: ProbeValue, depth: Int = 0) throws -> UInt64 {
            guard depth < 32, budget > 0 else { throw ProbeScoreError.unsupported("expression evaluation limit") }
            budget -= 1
            guard case .object(let node) = value, let kind = node["kind"]?.description else {
                throw ProbeScoreError.invalid("malformed expression node")
            }
            func child(_ key: String) throws -> UInt64 {
                guard let value = node[key] else { throw ProbeScoreError.invalid("missing expression field: \(key)") }
                return try evaluate(value, depth: depth + 1)
            }
            switch kind {
            case "immediate":
                guard let bits = node["bits"], let value = BitPattern.parse(bits.description) else {
                    throw ProbeScoreError.invalid("malformed immediate bits")
                }
                return value
            case "argument":
                guard case .int(let index)? = node["index"], arguments.indices.contains(index) else {
                    throw ProbeScoreError.unsupported("oracle did not supply this argument")
                }
                return arguments[index]
            case "select": return try child(child("condition") == 0 ? "whenFalse" : "whenTrue")
            case "unary":
                let operand = try child("operand")
                switch node["operator"]?.description {
                case "negate": return 0 &- operand
                case "bitwise-not": return ~operand
                default: throw ProbeScoreError.unsupported("unsupported unary operator")
                }
            case "binary": break
            default: throw ProbeScoreError.unsupported("unsupported value: \(kind)")
            }
            let a = try child("lhs"), b = try child("rhs")
            let sa = Int64(bitPattern: a), sb = Int64(bitPattern: b)
            func truth(_ test: Bool) -> UInt64 { test ? 1 : 0 }
            switch node["operator"]?.description {
            case "add": return a &+ b
            case "subtract": return a &- b
            case "multiply": return a &* b
            case "divide":
                if b == 0 { return 0 }; if sa == .min && sb == -1 { return a }
                return UInt64(bitPattern: sa / sb)
            case "remainder":
                if b == 0 { return a }; if sa == .min && sb == -1 { return 0 }
                return UInt64(bitPattern: sa % sb)
            case "unsigned-divide": return b == 0 ? 0 : a / b
            case "unsigned-remainder": return b == 0 ? a : a % b
            case "bit-and": return a & b
            case "bit-or": return a | b
            case "bit-xor": return a ^ b
            case "shift-left", "shift-right", "arithmetic-shift-right":
                guard b < 64 else { throw ProbeScoreError.unsupported("shift amount outside 64-bit domain") }
                switch node["operator"]?.description {
                case "shift-left": return a << b
                case "shift-right": return a >> b
                default: return UInt64(bitPattern: sa >> b)
                }
            case "unsigned-multiply-high": return a.multipliedFullWidth(by: b).high
            case "multiply-high":
                return a.multipliedFullWidth(by: b).high &- (sa < 0 ? b : 0) &- (sb < 0 ? a : 0)
            case "equal": return truth(a == b)
            case "not-equal": return truth(a != b)
            case "less": return truth(sa < sb)
            case "less-equal": return truth(sa <= sb)
            case "greater": return truth(sa > sb)
            case "greater-equal": return truth(sa >= sb)
            case "unsigned-less": return truth(a < b)
            case "unsigned-less-equal": return truth(a <= b)
            case "unsigned-greater": return truth(a > b)
            case "unsigned-greater-equal": return truth(a >= b)
            default: throw ProbeScoreError.unsupported("unsupported binary operator")
            }
        }
        return try evaluate(expression)
    }
}

public struct ProbeScoreReport: Sendable, Encodable {
    public enum Outcome: String, Sendable, Encodable { case verified, refuted, notEvaluated = "not-evaluated", missing }
    public struct Result: Sendable, Encodable {
        public let expectation: ReturnExpectation
        public let outcome: Outcome
        public let actual: String?
        public let reason: String?
    }
    public let schema = "swiftdc-score/1"
    public let mode: ProbeScore.Mode
    public let results: [Result]
    public var counts: [String: Int] {
        Dictionary(uniqueKeysWithValues: Outcome.all.map { outcome in
            (outcome.rawValue, results.filter { $0.outcome == outcome }.count)
        })
    }
    public var evaluated: Int { results.filter { $0.outcome == .verified || $0.outcome == .refuted }.count }
    public var agreement: Double? {
        evaluated == 0 ? nil : Double(results.filter { $0.outcome == .verified }.count) / Double(evaluated)
    }
    public var coverage: Double { Double(evaluated) / Double(results.count) }
    /// 1 = refuted; 3 = incomplete; 0 = all verified. Invalid inputs throw.
    public var exitCode: Int32 {
        if results.contains(where: { $0.outcome == .refuted }) { return 1 }
        return evaluated == results.count ? 0 : 3
    }
    public func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
    private enum CodingKeys: String, CodingKey { case schema, mode, counts, cases, evaluated, agreement, coverage, results }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema); try c.encode(mode, forKey: .mode)
        try c.encode(counts, forKey: .counts); try c.encode(results.count, forKey: .cases)
        try c.encode(evaluated, forKey: .evaluated); try c.encode(agreement, forKey: .agreement)
        try c.encode(coverage, forKey: .coverage); try c.encode(results, forKey: .results)
    }
}
private extension ProbeScoreReport.Outcome {
    static let all: [Self] = [.verified, .refuted, .notEvaluated, .missing]
}

/// Scores live typed probes or a saved JSONL trace. It retains only the selected
/// functions' return facts (at most two per exit, to detect duplicate analyses).
public final class ProbeScore: Sendable {
    public enum Mode: String, Sendable, Codable { case recoveredReturn = "recovered-return", rawRegister = "raw-register" }
    private struct Key: Hashable { let function: UInt64; let address: UInt64? }
    private struct Fact: Sendable { let value: ProbeValue?; let integer: Bool }
    private struct State { var facts: [Key: [Fact]] = [:]; var images: [String] = [] }
    private let oracle: ReturnOracle
    private let mode: Mode
    private let functions: Set<UInt64>
    private let state = Mutex(State())

    public convenience init(_ cases: [ReturnExpectation], mode: Mode = .recoveredReturn) throws {
        try self.init(oracle: ReturnOracle(cases), mode: mode)
    }
    public init(oracle: ReturnOracle, mode: Mode = .recoveredReturn) throws {
        guard oracle.schema == "swiftdc-oracle/1", !oracle.cases.isEmpty else {
            throw ProbeScoreError.invalid("expected swiftdc-oracle/1 with at least one independent case")
        }
        guard oracle.cases.allSatisfy({ (1...64).contains($0.bits) }) else {
            throw ProbeScoreError.invalid("result width must be 1...64")
        }
        self.oracle = oracle; self.mode = mode; functions = Set(oracle.cases.map(\.function))
    }
    /// Stream typed records: no JSON round trip, full-trace array, or boilerplate validator.
    public var recorder: ProbeRecorder {
        let events: Set<String> = mode == .rawRegister ? ["loader.image", event]
            : ["loader.image", event, "render.return-outcome"]
        return ProbeRecorder(filter: ProbeFilter(events: events), output: .records { [self] in observe($0) })
    }
    private var event: String { mode == .rawRegister ? "values.exit-registers" : "render.return-value" }
    public func observe(_ record: ProbeRecord) {
        if record.event.id == "loader.image" {
            state.withLock {
                if $0.images.count < 2 { $0.images.append(record["uuid"]?.description ?? "absent") }
            }
            return
        }
        let declined = mode == .recoveredReturn && record.event.id == "render.return-outcome"
            && record["status"]?.description != "recovered"
        guard record.event.id == event || declined,
              let function = record.function?.start, functions.contains(function) else { return }
        let fact = Fact(value: record[mode == .rawRegister ? "x0" : "value"],
                        integer: mode == .rawRegister || record["register"]?.description == "x0")
        let key = Key(function: function, address: record.address)
        state.withLock { if $0.facts[key, default: []].count < 2 { $0.facts[key, default: []].append(fact) } }
    }
    public func report() throws -> ProbeScoreReport {
        let snapshot = state.withLock { $0 }
        if let uuid = oracle.binaryUUID {
            guard snapshot.images.count == 1, snapshot.images.first?.uppercased() == uuid.uppercased() else {
                throw ProbeScoreError.invalid("trace image UUID does not match the oracle")
            }
        }
        // Index once, rather than scan every exit for every case/sample.
        let byFunction = Dictionary(grouping: snapshot.facts.keys, by: \.function)
        let results = try oracle.cases.map { expectation -> ProbeScoreReport.Result in
            let keys = expectation.address.map { [Key(function: expectation.function, address: $0)] }
                ?? byFunction[expectation.function] ?? []
            let facts = keys.flatMap { snapshot.facts[$0] ?? [] }
            func result(_ outcome: ProbeScoreReport.Outcome, actual: UInt64? = nil, reason: String? = nil) -> ProbeScoreReport.Result {
                .init(expectation: expectation, outcome: outcome,
                      actual: actual.map { "0x" + String($0, radix: 16) }, reason: reason)
            }
            guard !facts.isEmpty else { return result(.missing, reason: "no captured return claim") }
            guard facts.count == 1 else { return result(.notEvaluated, reason: "multiple analyses or exits; specify one exit") }
            guard facts[0].integer, let value = facts[0].value else {
                return result(.notEvaluated, reason: "expected an integer register result")
            }
            do {
                let mask: UInt64 = expectation.bits == 64 ? .max : (1 << expectation.bits) - 1
                let actual = try value.evaluateInteger(arguments: expectation.arguments) & mask
                return result(actual == expectation.expected & mask ? .verified : .refuted, actual: actual)
            } catch ProbeScoreError.invalid(let reason) { throw ProbeScoreError.invalid(reason) }
            catch { return result(.notEvaluated, reason: String(describing: error)) }
        }
        return ProbeScoreReport(mode: mode, results: results)
    }
    /// Common case: run the existing analysis/render closure and return a report.
    public static func recording(_ cases: [ReturnExpectation], mode: Mode = .recoveredReturn,
                                 _ body: () async throws -> Void) async throws -> ProbeScoreReport {
        let score = try ProbeScore(cases, mode: mode)
        try await Probe.recording(score.recorder, body)
        return try score.report()
    }

    /// Incrementally reads JSONL in bounded chunks and requires its closing summary.
    public func readTrace(at url: URL) throws {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var pending = Data(), summaries = 0, closed = false
        func consume(_ data: Data) throws {
            guard !data.isEmpty else { return }
            let line = try JSONDecoder().decode(TraceLine.self, from: data)
            guard !closed else { throw ProbeScoreError.invalid("records after trace summary") }
            if line.summary != nil {
                guard line.schema == ProbeRecorder.schema else { throw ProbeScoreError.invalid("unsupported probe schema") }
                summaries += 1; closed = true
            } else if let record = line.record { observe(record) }
            else { throw ProbeScoreError.invalid("malformed trace record") }
        }
        while let data = try file.read(upToCount: 65536), !data.isEmpty {
            pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                try consume(Data(pending[..<newline])); pending.removeSubrange(...newline)
            }
            guard pending.count <= 16 * 1024 * 1024 else { throw ProbeScoreError.invalid("probe line exceeds 16 MiB") }
        }
        try consume(pending)
        guard summaries == 1 else { throw ProbeScoreError.invalid("expected a completed trace with one summary") }
    }
}

private struct TraceLine: Decodable {
    var schema: String?
    var summary: JSONValue?
    var seq: Int?
    var event: String?
    var subsystem: String?
    var category: String?
    var function: BitPattern?
    var functionName: String?
    var address: BitPattern?
    var fields: [String: JSONValue]?
    var record: ProbeRecord? {
        guard let event, let fields else { return nil }
        return ProbeRecord(sequence: seq ?? 0,
                           event: ProbeEvent(event, ProbeEvent.Subsystem(rawValue: subsystem ?? "") ?? .values,
                                             ProbeEvent.Category(rawValue: category ?? "") ?? .claim, ""),
                           function: function.map { ProbeFunction(start: $0.value, name: functionName ?? "") },
                           address: address?.value,
                           fields: fields.keys.sorted().map { ($0, fields[$0]!.probe) })
    }
}
private indirect enum JSONValue: Decodable {
    case value(ProbeValue)
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .value(.bool(value)) }
        else if let value = try? c.decode(Int.self) { self = .value(.int(value)) }
        else if let value = try? c.decode(String.self) { self = .value(.label(value)) }
        else if let value = try? c.decode([JSONValue].self) { self = .value(.array(value.map(\.probe))) }
        else if let value = try? c.decode([String: JSONValue].self) { self = .value(.object(value.mapValues(\.probe))) }
        else if let value = try? c.decode(Double.self) { self = .value(.label(String(value))) }
        else if c.decodeNil() { self = .value(.label("null")) }
        else { throw ProbeScoreError.invalid("unsupported JSON probe value") }
    }
    var probe: ProbeValue { switch self { case .value(let value): value } }
}
