import Foundation
import MachOKit
import MachOSwiftSection
import Demangling

/// A single decoded ARM64 instruction.
public struct Instruction: Sendable {
    /// Virtual address of the instruction.
    public let address: UInt64
    /// Raw textual form from the disassembler, e.g. `bl _$s6sample3runyyF`.
    public let text: String
    /// Human-readable annotation (e.g. a demangled call target), if any.
    public let annotation: String?
    /// Control-flow class (from Capstone), when available.
    public let controlFlow: ControlFlow?
    /// Resolved branch/call target (from Capstone), when statically known.
    public let branchTarget: UInt64?
    /// For call instructions: recovered argument values (x0…), rendered, when
    /// value-tracking could infer them.
    public let callArguments: [String]?

    public init(
        address: UInt64,
        text: String,
        annotation: String? = nil,
        controlFlow: ControlFlow? = nil,
        branchTarget: UInt64? = nil,
        callArguments: [String]? = nil
    ) {
        self.address = address
        self.text = text
        self.annotation = annotation
        self.controlFlow = controlFlow
        self.branchTarget = branchTarget
        self.callArguments = callArguments
    }
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
        let (parsed, labelByAddress) = parseObjdump(result.stdout)
        guard !parsed.isEmpty else { return [] }

        // 1b. Enrich each instruction with Capstone's control-flow class and
        //     branch target (decoded in-process from the raw __text bytes) —
        //     structural data objdump text doesn't expose.
        let controlFlow = capstoneControlFlow(in: machO)
        let instructions = parsed.map { insn -> Instruction in
            guard let decoded = controlFlow[insn.address] else { return insn }
            return Instruction(
                address: insn.address,
                text: insn.text,
                annotation: insn.annotation,
                controlFlow: decoded.controlFlow,
                branchTarget: decoded.branchTarget
            )
        }

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
        var functions = segment(
            instructions,
            boundaries: boundaries,
            labelByAddress: labelByAddress,
            metadataNames: metadataNames
        )

        // 5. Resolve adrp/add(+ldr) operand references to function, type-
        //    descriptor, string, and Swift-symbol names that objdump leaves bare.
        let resolver = ReferenceResolver(
            names: referenceIndex(functions: functions, in: machO),
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) }
        )
        functions = functions.map { annotateReferences(in: $0, resolver: resolver) }

        // 6. Value-track each function to recover call-site arguments.
        functions = functions.map { enrichCallArguments(in: $0, resolver: resolver) }

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

    /// Decode `__text` in-process with Capstone, returning a map of address →
    /// structured instruction (control-flow class + branch target).
    private func capstoneControlFlow(in machO: MachOFile) -> [UInt64: DecodedInstruction] {
        guard let engine = CapstoneEngine(),
              let text = machO.sections.first(where: {
                  $0.segmentName == "__TEXT" && $0.sectionName == "__text"
              }),
              let bytes: [UInt8] = try? machO.readElements(offset: text.offset, numberOfElements: text.size)
        else { return [:] }

        var map: [UInt64: DecodedInstruction] = [:]
        for decoded in engine.disassemble(Data(bytes), address: UInt64(text.address)) {
            map[decoded.address] = decoded
        }
        return map
    }

    // MARK: - Operand reference resolution

    /// Known target addresses → display names: every recovered function start,
    /// plus Swift type descriptors. Used to resolve adrp/add operand targets.
    private func referenceIndex(functions: [DisassembledFunction], in machO: MachOFile) -> [UInt64: String] {
        var names: [UInt64: String] = [:]
        for function in functions where names[function.startAddress] == nil {
            names[function.startAddress] = function.displayName
        }
        for type in (try? machO.swift.types) ?? [] {
            let offset: Int
            let name: String?
            switch type {
            case .enum(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            case .struct(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            case .class(let model): offset = model.descriptor.offset; name = try? model.descriptor.name(in: machO)
            }
            if let name {
                names[machO.address(forOffset: offset)] = "type descriptor for \(name)"
            }
        }
        return names
    }

    /// Walk a function's instructions tracking `adrp` page registers, and when a
    /// following `add`/`ldr` forms a concrete target, annotate it (if objdump
    /// left it bare) with a resolved name.
    private func annotateReferences(
        in function: DisassembledFunction,
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        var pageByRegister: [String: UInt64] = [:]
        var updated: [Instruction] = []
        updated.reserveCapacity(function.instructions.count)

        for insn in function.instructions {
            if let (register, page) = parseAdrp(insn.text) {
                pageByRegister[register] = page
                updated.append(insn)
                continue
            }

            // Only annotate operands objdump left without a comment of its own.
            if insn.annotation == nil, !insn.text.contains(";"),
               let (base, immediate) = parsePageOffset(insn.text),
               let page = pageByRegister[base],
               let name = resolver.reference(at: page &+ immediate) {
                updated.append(Instruction(
                    address: insn.address, text: insn.text, annotation: name,
                    controlFlow: insn.controlFlow, branchTarget: insn.branchTarget
                ))
            } else {
                updated.append(insn)
            }

            // The written (first-operand) register no longer holds an adrp page.
            // Clearing it keeps a stale page from being reused on a later op
            // (conservative: at worst we miss an annotation, never invent one).
            if let written = firstRegister(insn.text) {
                pageByRegister[written] = nil
            }
        }

        return DisassembledFunction(
            symbol: function.symbol,
            demangledName: function.demangledName,
            startAddress: function.startAddress,
            instructions: updated,
            source: function.source
        )
    }

    /// VM address ranges of C-string-literal sections (`__cstring`,
    /// `__objc_methname`, …). Used to safely resolve string-pointer arguments.
    private func stringSectionRanges(in machO: MachOFile) -> [Range<UInt64>] {
        machO.sections.compactMap { section in
            guard section.flags.type == .cstring_literals, section.size > 0 else { return nil }
            let start = UInt64(section.address)
            return start ..< (start + UInt64(section.size))
        }
    }

    /// Resolves a target address to a display name: a known function/descriptor,
    /// a C-string literal (quoted, only inside cstring sections), or a demangled
    /// Swift mangled-name string. Never guesses at arbitrary data.
    struct ReferenceResolver {
        let names: [UInt64: String]
        let stringRanges: [Range<UInt64>]
        let machO: MachOFile
        let demangleSymbol: @Sendable (String) -> String?

        func name(at target: UInt64) -> String? {
            if let name = names[target] { return name }
            if stringRanges.contains(where: { $0.contains(target) }),
               let string = Self.cString(at: target, in: machO) {
                return "\"\(string)\""
            }
            if let fileOffset = machO.fileOffset(of: target),
               let string = try? machO.readString(offset: Int(fileOffset)), !string.isEmpty,
               let demangled = demangleSymbol(string) {
                return demangled
            }
            return nil
        }

        /// `→ name` form for inline operand annotation.
        func reference(at target: UInt64) -> String? { name(at: target).map { "→ \($0)" } }

        private static func cString(at target: UInt64, in machO: MachOFile) -> String? {
            guard let fileOffset = machO.fileOffset(of: target),
                  let s = try? machO.readString(offset: Int(fileOffset)), !s.isEmpty,
                  s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f })
            else { return nil }
            let truncated = s.count > 48 ? String(s.prefix(48)) + "…" : s
            return truncated.replacingOccurrences(of: "\"", with: "\\\"")
        }
    }

    /// Run value tracking on a function and append recovered call arguments
    /// (`args(…)`) to each call instruction.
    private func enrichCallArguments(
        in function: DisassembledFunction,
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        let argumentsByAddress = ValueTracer().callArguments(in: function)
        guard !argumentsByAddress.isEmpty else { return function }

        // Callee name per call address, for nesting result-of-call arguments.
        var calleeByAddress: [UInt64: String] = [:]
        for insn in function.instructions where insn.controlFlow == .call {
            calleeByAddress[insn.address] = DisassembledFunction.calleeName(of: insn)
        }

        func renderValue(_ value: AbstractValue, depth: Int) -> String {
            switch value {
            case .unknown:
                return "?"
            case .immediate(let v):
                return v < 4096 ? String(v) : "0x" + String(v, radix: 16)
            case .address(let a):
                return resolver.name(at: a) ?? "0x" + String(a, radix: 16)
            case .callResult(let addr):
                let inner = argumentsByAddress[addr] ?? []
                guard depth < 4, let callee = calleeByAddress[addr] else { return "result" }
                // ARC/exclusivity calls return their argument — unwrap them.
                if DisassembledFunction.isRuntimeNoise(callee) {
                    return inner.first.map { renderValue($0, depth: depth + 1) } ?? "result"
                }
                return "\(DisassembledFunction.strippedCallee(callee))(\(renderArguments(inner, depth: depth + 1)))"
            }
        }

        // Render an argument list, collapsing the two-register pairs that encode
        // a Swift small string into a single quoted literal.
        func renderArguments(_ values: [AbstractValue], depth: Int) -> [String] {
            var parts: [String] = []
            var index = 0
            while index < values.count {
                if index + 1 < values.count,
                   case .immediate(let lo) = values[index],
                   case .immediate(let hi) = values[index + 1],
                   let string = ValueTracer.decodeSmallString(lo: lo, hi: hi) {
                    parts.append("\"\(string)\"")
                    index += 2
                } else {
                    parts.append(renderValue(values[index], depth: depth))
                    index += 1
                }
            }
            return parts
        }
        func renderArguments(_ values: [AbstractValue], depth: Int) -> String {
            renderArguments(values, depth: depth).joined(separator: ", ")
        }

        let instructions = function.instructions.map { insn -> Instruction in
            guard insn.controlFlow == .call, let values = argumentsByAddress[insn.address] else { return insn }
            let rendered: [String] = renderArguments(values, depth: 0)
            let note = "args(" + rendered.joined(separator: ", ") + ")"
            let merged = [insn.annotation, note].compactMap { $0 }.joined(separator: "  ")
            return Instruction(
                address: insn.address, text: insn.text, annotation: merged,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: rendered
            )
        }
        return DisassembledFunction(
            symbol: function.symbol, demangledName: function.demangledName,
            startAddress: function.startAddress, instructions: instructions, source: function.source
        )
    }

    /// `adrp x8, 12 ; 0x10000c000` → ("x8", 0x10000c000). The resolved page comes
    /// from objdump's trailing comment.
    private func parseAdrp(_ text: String) -> (register: String, page: UInt64)? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.first == "adrp", fields.count >= 2 else { return nil }
        let register = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        guard let hashIndex = text.range(of: "; 0x")?.upperBound else { return nil }
        let hex = text[hashIndex...].prefix { $0.isHexDigit }
        guard let page = UInt64(hex, radix: 16) else { return nil }
        return (register, page)
    }

    /// For `add xN, xB, #0x170` or `ldr xT, [xB, #0x170]`, return (base xB, 0x170).
    private func parsePageOffset(_ text: String) -> (base: String, offset: UInt64)? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let mnemonic = fields.first else { return nil }
        func immediate(_ token: Substring) -> UInt64? {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "#[],"))
            guard cleaned.hasPrefix("0x"), let value = UInt64(cleaned.dropFirst(2), radix: 16) else { return nil }
            return value
        }
        func register(_ token: Substring) -> String {
            String(token).trimmingCharacters(in: CharacterSet(charactersIn: "[],"))
        }
        if mnemonic == "add", fields.count >= 4 {
            guard let offset = immediate(fields[3]) else { return nil }
            return (register(fields[2]), offset)
        }
        if mnemonic.hasPrefix("ldr") || mnemonic.hasPrefix("ldur"), fields.count >= 4 {
            // ldr xT, [xB, #imm]  → fields: ["ldr", "xT,", "[xB,", "#imm]"]
            guard let offset = immediate(fields[3]) else { return nil }
            return (register(fields[2]), offset)
        }
        return nil
    }

    /// The instruction's first operand register (its destination for the ops we
    /// track), e.g. `add x0, …` → "x0". Used only for page invalidation.
    private func firstRegister(_ text: String) -> String? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { return nil }
        var token = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "[],"))
        guard let first = token.first, first == "x" || first == "w" else { return nil }
        // Normalize the 32-bit view (w0) to its 64-bit register (x0); a w-write
        // still clobbers the full register that held the adrp page.
        if first == "w" { token = "x" + token.dropFirst() }
        return token
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
