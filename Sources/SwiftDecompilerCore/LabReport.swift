import Foundation

/// What the analysis concluded about one function, instruction by
/// instruction, without rendering it: the convention its entry was seeded
/// with, the registers reaching each call, how the call's arguments were laid
/// out, each branch condition and the registers at each exit.
///
/// It runs the ordinary filtered analysis under an in-memory probe
/// recorder, so it reports exactly what `disasm` decides, and reads only the
/// probe records: the recorder never changes the analysis
/// (`probeRecordingDoesNotChangeOutputIfPresent`). It answers "what does x20
/// hold at this call" in one run, where a render shows only the end product.
public enum LabReport {
    public static func report(path: String, architecture: String? = nil, function filter: String) async throws -> String {
        let recorder = ProbeRecorder(output: .capture)
        let functions = try await Probe.recording(recorder) {
            try await Disassembler().disassemble(path: path, architecture: architecture, functionFilter: filter)
        }
        guard !functions.isEmpty else { return "No function matches \"\(filter)\".\n" }
        var byFunction: [UInt64: [ProbeRecord]] = [:]
        for record in recorder.records {
            guard let start = record.function?.start else { continue }
            byFunction[start, default: []].append(record)
        }
        return functions.sorted { $0.startAddress < $1.startAddress }.map { function in
            report(function, records: byFunction[function.startAddress] ?? [])
        }.joined(separator: "\n")
    }

    static func report(_ function: DisassembledFunction, records: [ProbeRecord]) -> String {
        var byAddress: [UInt64: [ProbeRecord]] = [:]
        for record in records { if let address = record.address { byAddress[address, default: []].append(record) } }
        var lines = ["\(function.displayName)  @ 0x\(String(function.startAddress, radix: 16))"]
        if let entry = records.first(where: { $0.event == .entryConvention }) {
            var line = "  entry  \(entry["convention"]?.description ?? "?")"
            if let selfType = entry["selfType"]?.description, selfType != "none" { line += "  self: \(selfType)" }
            if case .object(let seeds)? = entry["seeds"] {
                // x8's seed is the ABI's, the same in every function.
                let shown = seeds.keys.sorted(by: registerOrder)
                    .filter { !($0 == "x8" && value(seeds[$0]!) == "indirect-result-pointer") }
                    .map { "\($0)=\(value(seeds[$0]!))" }
                line += "  seeds: " + (shown.isEmpty ? "none" : shown.joined(separator: " "))
            }
            lines.append(line)
        } else {
            lines.append("  entry  (not recorded)")
        }
        func spelled(_ insn: Instruction) -> String { insn.text.replacingOccurrences(of: "\t", with: " ") }
        let width = function.instructions.map { spelled($0).count }.max().map { min($0, 40) } ?? 0
        for insn in function.instructions {
            let address = String(insn.address, radix: 16)
            let text = spelled(insn).padding(toLength: max(width, spelled(insn).count), withPad: " ", startingAt: 0)
            var facts: [String] = []
            if insn.controlFlow == .call || insn.controlFlow == .branch,
               let callee = DisassembledFunction.calleeName(of: insn) {
                facts.append("→ \(callee)")
            }
            for record in byAddress[insn.address] ?? [] {
                switch record.event {
                case .callSnapshot: facts.append(callFacts(record))
                case .argumentLayout:
                    facts.append("layout \(record["strategy"]?.description ?? "?")(\(record["count"]?.description ?? "?"))")
                case .conditionSnapshot: facts.append("cond \(value(record["value"]))")
                case .exitRegisters: facts.append(exitFacts(record))
                default: break
                }
            }
            lines.append("  \(address)  \(text)" + (facts.isEmpty ? "" : "  ; " + facts.joined(separator: "  ; ")))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func callFacts(_ record: ProbeRecord) -> String {
        var parts: [String] = []
        if case .array(let arguments)? = record["arguments"] {
            for (index, argument) in arguments.enumerated() where value(argument) != "?" {
                parts.append("x\(index)=\(value(argument))")
            }
        }
        if case .array(let floats)? = record["floatingArguments"] {
            for (index, argument) in floats.enumerated() where value(argument) != "?" {
                parts.append("v\(index)=\(value(argument))")
            }
        }
        if case .array(let stack)? = record["stackArguments"] {
            for (index, argument) in stack.enumerated() where value(argument) != "?" {
                parts.append("sp+\(index * 8)=\(value(argument))")
            }
        }
        for (key, name) in [("receiver", "x20"), ("indirectResult", "x8")] {
            let shown = value(record[key])
            if shown != "?", shown != "indirect-result-pointer" { parts.append("\(name)=\(shown)") }
        }
        return "call " + (parts.isEmpty ? "(nothing known)" : parts.joined(separator: " "))
    }

    private static func exitFacts(_ record: ProbeRecord) -> String {
        let parts = ["x0", "v0", "x21", "x20"].compactMap { key -> String? in
            let shown = value(record[key])
            return shown == "?" ? nil : "\(key)=\(shown)"
        }
        return "exit " + (parts.isEmpty ? "(nothing known)" : parts.joined(separator: " "))
    }

    private static func registerOrder(_ a: String, _ b: String) -> Bool {
        func rank(_ register: String) -> Int { (register.hasPrefix("v") ? 100 : 0) + (Int(register.dropFirst()) ?? 99) }
        return rank(a) < rank(b)
    }

    private static let operators: [String: String] = [
        "add": "+", "subtract": "-", "multiply": "*", "divide": "/", "remainder": "%",
        "unsigned-divide": "/ᵁ", "unsigned-remainder": "%ᵁ", "bit-and": "&", "bit-or": "|", "bit-xor": "^",
        "shift-left": "<<", "shift-right": ">>ᵁ", "arithmetic-shift-right": ">>",
        "multiply-high": "*hi", "unsigned-multiply-high": "*hiᵁ", "equal": "==", "not-equal": "!=",
        "less": "<", "less-equal": "<=", "greater": ">", "greater-equal": ">=",
        "unsigned-less": "<ᵁ", "unsigned-less-equal": "<=ᵁ", "unsigned-greater": ">ᵁ", "unsigned-greater-equal": ">=ᵁ",
    ]

    /// A compact, lossless-enough spelling of a probe value for reading.
    static func value(_ probe: ProbeValue?) -> String {
        guard let probe else { return "?" }
        if case .object(let fields) = probe, let expression = fields["expression"] { return node(expression) }
        return node(probe)
    }

    private static func hex(_ value: ProbeValue?) -> String { value?.description ?? "?" }

    private static func node(_ probe: ProbeValue) -> String {
        guard case .object(let fields) = probe, let kind = fields["kind"]?.description else { return probe.description }
        switch kind {
        case "unknown": return "?"
        case "truncated": return "…"
        case "immediate":
            if case .uint(let bits)? = fields["bits"], bits < 10 { return "\(bits)" }
            return hex(fields["bits"])
        case "address": return hex(fields["address"])
        case "loaded": return "[\(hex(fields["address"]))]"
        case "call-result": return "r@\(hex(fields["site"]))"
        case "call-result-high": return "r@\(hex(fields["site"])).hi"
        case "argument": return "arg\(fields["index"]?.description ?? "?")"
        case "self-pointer": return "self"
        case "self-field": return "&self+\(fields["offset"]?.description ?? "?")"
        case "self-field-value": return "self[\(fields["offset"]?.description ?? "?")]"
        case "frame":
            guard case .int(let offset)? = fields["offset"] else { return "frame(?)" }
            return offset < 0 ? "sp-0x\(String(-offset, radix: 16))" : "sp+0x\(String(offset, radix: 16))"
        case "binary":
            let op = fields["operator"]?.description ?? "?"
            return "(\(node(fields["lhs"] ?? .label("?"))) \(operators[op] ?? op) \(node(fields["rhs"] ?? .label("?"))))"
        case "unary":
            return "\(fields["operator"]?.description ?? "?")(\(node(fields["operand"] ?? .label("?"))))"
        case "select":
            return "(\(node(fields["condition"] ?? .label("?"))) ? \(node(fields["whenTrue"] ?? .label("?"))) : \(node(fields["whenFalse"] ?? .label("?"))))"
        case "loaded-from":
            return "[\(node(fields["base"] ?? .label("?"))) + \(fields["offset"]?.description ?? "?")]"
        default:
            let rest = fields.keys.filter { $0 != "kind" }.sorted().map { "\($0): \(fields[$0].map(node) ?? "?")" }
            return rest.isEmpty ? kind : "\(kind)(\(rest.joined(separator: ", ")))"
        }
    }
}
