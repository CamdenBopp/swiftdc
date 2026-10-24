import Foundation
import MachOKit

public extension ProbeValue {
    /// A bounded, lossless description of the tracer's abstract value. This is
    /// evidence about the analysis, not a promise that every node is executable.
    /// Unsupported leaves and export truncation stay explicit for an oracle.
    static func abstractValue(_ value: AbstractValue) -> ProbeValue {
        var remaining = 1024
        func node(_ value: AbstractValue, depth: Int = 0) -> ProbeValue {
            guard depth < 32, remaining > 0 else { return .object(["kind": .label("truncated")]) }
            remaining -= 1
            func leaf(_ kind: String, _ fields: [String: ProbeValue] = [:]) -> ProbeValue {
                .object(fields.merging(["kind": .label(kind)]) { _, new in new })
            }
            func child(_ value: AbstractValue) -> ProbeValue { node(value, depth: depth + 1) }
            switch value {
            case .unknown: return leaf("unknown")
            case .immediate(let bits): return leaf("immediate", ["bits": .uint(bits)])
            case .address(let address): return leaf("address", ["address": .address(address)])
            case .loaded(let address): return leaf("loaded", ["address": .address(address)])
            case .callResult(let site): return leaf("call-result", ["site": .address(site)])
            case .callResultHigh(let site): return leaf("call-result-high", ["site": .address(site)])
            case .argument(let index): return leaf("argument", ["index": .int(index)])
            case .binary(let op, let lhs, let rhs):
                return leaf("binary", ["operator": .label(op.probeID), "lhs": child(lhs), "rhs": child(rhs)])
            case .unary(let op, let value):
                var fields: [String: ProbeValue] = ["operand": child(value)]
                switch op {
                case .negate: fields["operator"] = .label("negate")
                case .squareRoot: fields["operator"] = .label("square-root")
                case .absoluteValue: fields["operator"] = .label("absolute-value")
                case .bitwiseNot: fields["operator"] = .label("bitwise-not")
                case .byteSwap(let bits): fields["operator"] = .label("byte-swap"); fields["bits"] = .int(bits)
                case .toFloat(let bits): fields["operator"] = .label("to-float"); fields["bits"] = .int(bits)
                case .toInteger(let signed, let bits):
                    fields["operator"] = .label("to-integer"); fields["bits"] = .int(bits); fields["signed"] = .bool(signed)
                }
                return leaf("unary", fields)
            case .select(let condition, let whenTrue, let whenFalse):
                return leaf("select", ["condition": child(condition), "whenTrue": child(whenTrue), "whenFalse": child(whenFalse)])
            case .aggregate(let values):
                var exported: [ProbeValue] = []
                for value in values {
                    guard remaining > 0 else { exported.append(.object(["kind": .label("truncated")])); break }
                    exported.append(child(value))
                }
                return leaf("aggregate", ["count": .int(values.count), "values": .array(exported)])
            case .selfPointer: return leaf("self-pointer")
            case .selfField(let offset): return leaf("self-field", ["offset": .int(offset)])
            case .selfFieldValue(let offset): return leaf("self-field-value", ["offset": .int(offset)])
            case .selfVTableMethod(let offset): return leaf("self-vtable-method", ["offset": .int(offset)])
            case .argumentField(let argument, let offset): return leaf("argument-field", ["argument": .int(argument), "offset": .int(offset)])
            case .arrayLiteral(let site, let count): return leaf("array-literal", ["site": .address(site), "count": .int(count)])
            case .frame(let offset): return leaf("frame", ["offset": .int(Int(offset))])
            case .local(let index): return leaf("local", ["index": .int(index)])
            case .indirectResultPointer: return leaf("indirect-result-pointer")
            case .indirectResultField(let offset): return leaf("indirect-result-field", ["offset": .int(offset)])
            case .indirectCallResultWord(let site, let offset): return leaf("indirect-call-result-word", ["site": .address(site), "offset": .int(offset)])
            case .asyncContext: return leaf("async-context")
            case .asyncCalleeContext: return leaf("async-callee-context")
            case .asyncResumeParent: return leaf("async-resume-parent")
            case .asyncContextSlot(let offset): return leaf("async-context-slot", ["offset": .int(offset)])
            case .awaitResult(let ordinal): return leaf("await-result", ["ordinal": .int(ordinal)])
            }
        }
        return .object(["schema": .label("swiftdc-value/1"), "expression": node(value)])
    }
}

private extension AbstractBinaryOperator {
    var probeID: String {
        switch self {
        case .add: "add"
        case .subtract: "subtract"
        case .multiply: "multiply"
        case .divide: "divide"
        case .remainder: "remainder"
        case .unsignedDivide: "unsigned-divide"
        case .unsignedRemainder: "unsigned-remainder"
        case .bitAnd: "bit-and"
        case .bitOr: "bit-or"
        case .bitXor: "bit-xor"
        case .shiftLeft: "shift-left"
        case .shiftRight: "shift-right"
        case .arithmeticShiftRight: "arithmetic-shift-right"
        case .multiplyHigh: "multiply-high"
        case .unsignedMultiplyHigh: "unsigned-multiply-high"
        case .equal: "equal"
        case .notEqual: "not-equal"
        case .less: "less"
        case .lessEqual: "less-equal"
        case .greater: "greater"
        case .greaterEqual: "greater-equal"
        case .unsignedLess: "unsigned-less"
        case .unsignedLessEqual: "unsigned-less-equal"
        case .unsignedGreater: "unsigned-greater"
        case .unsignedGreaterEqual: "unsigned-greater-equal"
        }
    }
}

public extension Probe {
    /// Identity for correlating a trace with the independently executed image.
    /// No file path is exported. An absent UUID stays explicitly absent.
    static func image(_ machO: MachOFile) {
        record(.imageIdentity, ["uuid": .label(machO.loadCommands.compactMap { command -> String? in
            if case .uuid(let info) = command { return info.uuid.uuidString }
            return nil
        }.first ?? "absent"), "architecture": .label(BinaryLoader.archName(machO))])
    }

    /// Publish one completed analysis, never an iteration or speculative pass.
    /// External fixture harnesses can use this with ValueTracer directly.
    static func observe(_ analysis: FunctionAnalysis, of function: DisassembledFunction) {
        guard isActive, recorder != nil else { return }
        inFunction(function.startAddress, function.displayName) {
            let blocks = FunctionCFG(function).blocks
            var returnPaths: [UInt64: AbstractValue]?
            func path(at address: UInt64) -> ProbeValue {
                if returnPaths == nil { returnPaths = returnPathConditions(analysis, of: function) }
                return .abstractValue(returnPaths?[address] ?? .unknown)
            }
            record(.analysisSnapshot, ["symbol": .name(function.symbol), "instructions": .int(function.instructions.count),
                                      "blocks": .int(blocks.count), "calls": .int(analysis.callSites.count)])
            for block in blocks {
                record(.blockSnapshot, at: block.startAddress,
                       ["successors": .array(block.successorAddresses.map(ProbeValue.address)), "instructions": .int(block.range.count)])
            }
            for insn in function.instructions where insn.controlFlow == .return
                || analysis.indirectControlFlowTargets[insn.address] == .asyncResumeParent {
                record(.exitRegisters, at: insn.address, [
                    "x0": .abstractValue(analysis.exitValues[insn.address] ?? .unknown),
                    "v0": .abstractValue(analysis.exitFloatValues[insn.address] ?? .unknown),
                    "x21": .abstractValue(analysis.exitErrorValues[insn.address] ?? .unknown),
                    "x20": .abstractValue(analysis.exitAsyncErrorValues[insn.address] ?? .unknown),
                    "path": path(at: insn.address),
                ])
            }
            for (address, site) in analysis.callSites.sorted(by: { $0.key < $1.key }) {
                record(.callSnapshot, at: address, [
                    "arguments": .array(site.arguments.map(ProbeValue.abstractValue)),
                    "floatingArguments": .array(site.floatArguments.map(ProbeValue.abstractValue)),
                    "stackArguments": .array(site.stackArguments.map(ProbeValue.abstractValue)),
                    "receiver": .abstractValue(site.selfValue), "indirectResult": .abstractValue(site.indirectResult),
                ])
            }
            for (address, condition) in analysis.branchConditions.sorted(by: { $0.key < $1.key }) {
                record(.conditionSnapshot, at: address, ["value": .abstractValue(condition)])
            }
            for (address, bindings) in analysis.loopInitializations.sorted(by: { $0.key < $1.key }) {
                for binding in bindings {
                    record(.loopInitialization, at: address, [
                        "name": .name(binding.name), "value": .uint(binding.value),
                        "stackOffset": binding.stackOffset.map { .int(Int($0)) } ?? .label("unknown"),
                    ])
                }
            }
        }
    }

    /// Describe a committed render. Trial structuring and the flat fallback of
    /// a structured render do not call this, so the denominator is not inflated.
    static func rendered(_ output: String, of function: DisassembledFunction, view: String) {
        guard isActive, recorder != nil else { return }
        inFunction(function.startAddress, function.displayName) {
            let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let returns = lines.filter { $0 == "return" || $0.hasPrefix("return ") }
            record(.renderedFunction, ["view": .label(view), "symbol": .name(function.symbol),
                "returns": .int(returns.count), "returnStatements": .array(returns.map(ProbeValue.name)),
                "unknownReturns": .int(returns.filter { $0 == "return ?" }.count),
                "gotos": .int(lines.filter { $0.hasPrefix("goto ") }.count), "lines": .int(lines.count)])
        }
    }
}
