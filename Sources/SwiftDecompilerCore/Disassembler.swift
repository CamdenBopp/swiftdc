import Foundation
import MachOKit
import Demangling

/// A single decoded ARM64 instruction.
public struct Instruction: Sendable {
    /// Virtual address of the instruction.
    public let address: UInt64
    /// Raw textual form from the disassembler, e.g. `bl _$s6sample3runyyF`.
    public let text: String
    /// Human-readable annotation (e.g. a demangled call target), if any.
    public let annotation: String?
}

/// How a function's name/boundary was recovered — useful context, especially
/// for stripped binaries.
public enum RecoverySource: String, Sendable {
    /// Named by a symbol-table label emitted by the disassembler.
    case symbol
    /// Named from Swift `__swift5_*` metadata (survives stripping).
    case metadata
    /// Boundary known (LC_FUNCTION_STARTS) but no name — synthesized `sub_<addr>`.
    case address
}

/// A contiguous function body recovered from `__text`.
public struct DisassembledFunction: Sendable {
    /// Raw symbol/label (e.g. `_$s6sample3runyyF`) or a synthesized `sub_<addr>`.
    public let symbol: String
    /// Demangled, readable name, if recoverable.
    public let demangledName: String?
    /// Virtual address of the first instruction.
    public let startAddress: UInt64
    public let instructions: [Instruction]
    /// Where the name/boundary came from.
    public let source: RecoverySource

    /// The name to show: demangled if available, else the raw symbol.
    public var displayName: String { demangledName ?? symbol }

    /// Render this function as annotated assembly text.
    public func render() -> String {
        var lines: [String] = []
        lines.append("\(displayName):")
        let tag = source == .metadata ? "  [recovered from metadata]" : ""
        if demangledName != nil {
            lines.append("  // \(symbol)  @ 0x\(String(startAddress, radix: 16))\(tag)")
        } else if source == .address {
            lines.append("  // unnamed function  @ 0x\(String(startAddress, radix: 16))  [boundary from LC_FUNCTION_STARTS]")
        }
        for insn in instructions {
            let addr = String(insn.address, radix: 16)
            var line = "  \(addr):  \(insn.text)"
            if let annotation = insn.annotation, !insn.text.contains(annotation) {
                line += "  ; \(annotation)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

/// Disassembles a Mach-O's `__text` to ARM64 using `llvm-objdump`, then
/// re-segments the flat instruction stream into functions using
/// `LC_FUNCTION_STARTS` (which survives stripping) and names them from the
/// symbol table or, failing that, Swift metadata.
public struct Disassembler: Sendable {
    public var preset: DemanglePreset

    public init(preset: DemanglePreset = .default) {
        self.preset = preset
    }

    public enum DisassembleError: Error, CustomStringConvertible {
        case toolFailed(String)
        public var description: String {
            switch self {
            case .toolFailed(let m): return "llvm-objdump failed: \(m)"
            }
        }
    }

    /// Disassemble the binary at `path`. For fat binaries pass `architecture`.
    /// `functionFilter`, if given, keeps only functions whose raw symbol or
    /// demangled name contains it (case-insensitive).
    public func disassemble(
        path: String,
        architecture: String? = nil,
        functionFilter: String? = nil
    ) async throws -> [DisassembledFunction] {
        let machO = try BinaryLoader.load(path: path, architecture: architecture)

        var args = ["-d", "--macho", "--no-show-raw-insn"]
        if let architecture {
            args += ["--arch", architecture]
        }
        args.append(path)

        let result = try Shell.xcrun("llvm-objdump", args)
        guard result.status == 0 else {
            throw DisassembleError.toolFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        // 1. Flat instruction stream + the symbol-table labels objdump emitted.
        let (instructions, labelByAddress) = parseObjdump(result.stdout)
        guard !instructions.isEmpty else { return [] }

        // 2. Function boundaries: LC_FUNCTION_STARTS ∪ objdump label addresses.
        //    Function-starts survive stripping, so this re-creates boundaries
        //    objdump couldn't label.
        var boundaries = Set(functionStarts(of: machO))
        boundaries.formUnion(labelByAddress.keys)

        // 3. Names from Swift metadata (class vtables + protocol witnesses) —
        //    only worth computing when many boundaries lack a symbol label
        //    (i.e. the binary looks stripped).
        let unlabeled = boundaries.subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            metadataNames = await MetadataSymbolizer(preset: preset).functionNames(in: machO)
        }

        // 4. Re-segment the flat stream at the boundaries and name each piece.
        let functions = segment(
            instructions,
            boundaries: boundaries,
            labelByAddress: labelByAddress,
            metadataNames: metadataNames
        )

        guard let needle = functionFilter?.lowercased(), !needle.isEmpty else {
            return functions
        }
        return functions.filter {
            $0.symbol.lowercased().contains(needle)
                || ($0.demangledName?.lowercased().contains(needle) ?? false)
        }
    }

    // MARK: - Segmentation

    private func segment(
        _ instructions: [Instruction],
        boundaries: Set<UInt64>,
        labelByAddress: [UInt64: String],
        metadataNames: [UInt64: String]
    ) -> [DisassembledFunction] {
        var functions: [DisassembledFunction] = []
        var current: [Instruction] = []
        var start: UInt64 = instructions.first?.address ?? 0

        func flush() {
            guard !current.isEmpty else { return }
            functions.append(makeFunction(start: start, instructions: current,
                                           labelByAddress: labelByAddress,
                                           metadataNames: metadataNames))
            current = []
        }

        for insn in instructions {
            // A boundary (other than the very first instruction) cuts a function.
            if boundaries.contains(insn.address), !current.isEmpty {
                flush()
                start = insn.address
            } else if current.isEmpty {
                start = insn.address
            }
            current.append(insn)
        }
        flush()
        return functions
    }

    private func makeFunction(
        start: UInt64,
        instructions: [Instruction],
        labelByAddress: [UInt64: String],
        metadataNames: [UInt64: String]
    ) -> DisassembledFunction {
        let subName = "sub_\(String(start, radix: 16))"
        if let rawLabel = labelByAddress[start] {
            return DisassembledFunction(
                symbol: rawLabel,
                demangledName: demangle(rawLabel),
                startAddress: start,
                instructions: instructions,
                source: .symbol
            )
        }
        if let metaName = metadataNames[start] {
            return DisassembledFunction(
                symbol: subName,
                demangledName: metaName,
                startAddress: start,
                instructions: instructions,
                source: .metadata
            )
        }
        return DisassembledFunction(
            symbol: subName,
            demangledName: nil,
            startAddress: start,
            instructions: instructions,
            source: .address
        )
    }

    // MARK: - Data sources

    /// VM addresses of every function start from LC_FUNCTION_STARTS.
    private func functionStarts(of machO: MachOFile) -> [UInt64] {
        guard let starts = machO.functionStarts else { return [] }
        return starts.map { UInt64($0.offset) }
    }

    // MARK: - objdump parsing

    /// Parse objdump output into a flat instruction list plus a map from each
    /// labeled function's start address to its raw label.
    private func parseObjdump(_ output: String) -> ([Instruction], [UInt64: String]) {
        var instructions: [Instruction] = []
        var labelByAddress: [UInt64: String] = [:]
        var pendingLabel: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let (address, text) = parseInstruction(line) {
                if let label = pendingLabel {
                    labelByAddress[address] = label
                    pendingLabel = nil
                }
                instructions.append(
                    Instruction(address: address, text: text, annotation: annotate(text))
                )
            } else if let label = parseLabel(line) {
                pendingLabel = label
            }
        }
        return (instructions, labelByAddress)
    }

    /// Matches `100000e58:\tstp x29, x30, …` → (0x100000e58, "stp …").
    private func parseInstruction(_ line: String) -> (UInt64, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let addrPart = line[line.startIndex..<colon]
        guard !addrPart.isEmpty,
              addrPart.allSatisfy({ $0.isHexDigit }),
              let address = UInt64(addrPart, radix: 16)
        else { return nil }
        let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (address, rest)
    }

    /// Matches a function label line such as `_main:` or `_$s6sample3runyyF:`.
    private func parseLabel(_ line: String) -> String? {
        guard line.hasSuffix(":"),
              let first = line.first,
              !first.isWhitespace
        else { return nil }
        let name = String(line.dropLast())
        guard !name.contains(" "), !name.contains("(") else { return nil }
        return name
    }

    // MARK: - Demangling / annotation

    /// Demangle a Swift mangled symbol token to a readable name.
    private func demangle(_ token: String) -> String? {
        var s = token
        if s.hasPrefix("_$s") || s.hasPrefix("_$S") || s.hasPrefix("_$e") {
            s.removeFirst()
        }
        guard s.hasPrefix("$s") || s.hasPrefix("$S") || s.hasPrefix("$e") || s.hasPrefix("_T") else {
            return nil
        }
        // Sync context → the sync `print` overload is selected (no await).
        guard let node = try? demangleAsNode(s) else { return nil }
        let printed = node.print(using: preset.options)
        return printed.isEmpty ? nil : printed
    }

    /// First Swift mangled token in an instruction's operands, demangled.
    private func annotate(_ text: String) -> String? {
        for token in text.split(whereSeparator: { " ,\t".contains($0) }) {
            if let demangled = demangle(String(token)) {
                return demangled
            }
        }
        return nil
    }
}
