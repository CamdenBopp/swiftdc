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
    /// For calls to a Swift function: the rendered `self` (x20), when known.
    /// Only set for Swift callees — x20 is `self` under the Swift calling
    /// convention, and merely a callee-saved register everywhere else.
    public let callSelf: String?

    public init(
        address: UInt64,
        text: String,
        annotation: String? = nil,
        controlFlow: ControlFlow? = nil,
        branchTarget: UInt64? = nil,
        callArguments: [String]? = nil,
        callSelf: String? = nil
    ) {
        self.address = address
        self.text = text
        self.annotation = annotation
        self.controlFlow = controlFlow
        self.branchTarget = branchTarget
        self.callArguments = callArguments
        self.callSelf = callSelf
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

        // Filtered: decode in-process with Capstone (only the matched functions'
        // ranges). `llvm-objdump` re-parses the whole binary on every invocation
        // and `--start/--stop-address` only bounds *decoding*, not parsing — so on
        // a large binary a filtered objdump run costs the same as a full one. The
        // in-process path reads just the matched bytes. Its instruction text is
        // Capstone's rather than objdump's, but the structure is identical.
        if let filter = functionFilter, !filter.isEmpty {
            return await disassemble(machO: machO, functionFilter: filter)
        }

        // Unfiltered: one full objdump pass (its text is the default file listing).
        var args = ["-d", "--macho", "--no-show-raw-insn"]
        if let architecture {
            args += ["--arch", architecture]
        }
        args.append(path)

        let result = try Shell.xcrun("llvm-objdump", args)
        guard result.status == 0 else {
            throw DisassembleError.toolFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        // Flat instruction stream + objdump's symbol labels, enriched with
        // Capstone's control-flow class + branch target (data objdump doesn't show).
        let (parsed, labelByAddress) = parseObjdump(result.stdout)
        guard !parsed.isEmpty else { return [] }
        let controlFlow = capstoneControlFlow(in: machO)
        let instructions = parsed.map { insn -> Instruction in
            guard let decoded = controlFlow[insn.address] else { return insn }
            return Instruction(
                address: insn.address, text: insn.text, annotation: insn.annotation,
                controlFlow: decoded.controlFlow, branchTarget: decoded.branchTarget
            )
        }

        return await assemble(
            instructions: instructions,
            labelByAddress: labelByAddress,
            in: machO,
            functionFilter: nil
        )
    }

    /// Disassemble a `MachOFile` fully in-process with Capstone — no
    /// `llvm-objdump` subprocess, so it works on images that have no standalone
    /// file on disk (dyld shared-cache frameworks). Boundaries come from
    /// `LC_FUNCTION_STARTS`, names from Swift metadata, and adrp/call operand
    /// targets are resolved against recovered function/descriptor addresses.
    public func disassemble(
        machO: MachOFile,
        functionFilter: String? = nil
    ) async -> [DisassembledFunction] {
        // Filtered: decode only the matched functions' ranges of __text.
        let instructions: [Instruction]
        if let filter = functionFilter, !filter.isEmpty {
            let ranges = await matchedRanges(filter: filter, in: machO)
            guard !ranges.isEmpty else { return [] }
            instructions = ranges.flatMap { capstoneInstructions(in: machO, span: $0) }
        } else {
            instructions = capstoneInstructions(in: machO, span: nil)
        }
        guard !instructions.isEmpty else { return [] }
        return await assemble(
            instructions: instructions,
            labelByAddress: symbolLabels(in: machO),
            in: machO,
            functionFilter: functionFilter
        )
    }

    // MARK: - Shared pipeline

    /// Segment the flat instruction stream into functions, name them, resolve
    /// operand references, and recover call arguments. Both front-ends — objdump
    /// (files) and Capstone (in-process/cache) — feed into this.
    private func assemble(
        instructions: [Instruction],
        labelByAddress: [UInt64: String],
        in machO: MachOFile,
        functionFilter: String?
    ) async -> [DisassembledFunction] {
        // Function boundaries: LC_FUNCTION_STARTS ∪ label addresses. Function-
        // starts survive stripping, so this re-creates boundaries a label set
        // (objdump's, or a stripped cache image's exports) couldn't cover.
        var boundaries = Set(functionStarts(of: machO))
        boundaries.formUnion(labelByAddress.keys)

        // Names from Swift metadata (class vtables + protocol witnesses) — worth
        // computing when many boundaries lack a symbol label (stripped binaries,
        // or an in-process decode with few/no symbols).
        let unlabeled = boundaries.subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            metadataNames = await MetadataSymbolizer(preset: preset).functionNames(in: machO)
        }

        var functions = segment(
            instructions,
            boundaries: boundaries,
            labelByAddress: labelByAddress,
            metadataNames: metadataNames
        )

        // Resolve adrp/add(+ldr) operand references to function, type-descriptor,
        // string, and Swift-symbol names, and name direct call/branch targets.
        let resolver = ReferenceResolver(
            names: crossImageNames(
                for: functions, in: machO,
                names: referenceIndex(functions: functions, in: machO)
            ),
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO)
        )
        // Addresses whose callee uses the Swift calling convention, so `self` in
        // x20 is meaningful there.
        let swiftTargets = Set(
            functions.filter { Self.isSwiftMangled($0.symbol) }.map(\.startAddress)
        )
        functions = functions.map { annotateReferences(in: $0, resolver: resolver) }
        functions = functions.map { annotateCallTargets(in: $0, resolver: resolver) }
        functions = functions.map {
            enrichCallArguments(in: $0, resolver: resolver, swiftTargets: swiftTargets)
        }

        guard let needle = functionFilter?.lowercased(), !needle.isEmpty else {
            return functions
        }
        return functions.filter {
            $0.symbol.lowercased().contains(needle)
                || ($0.demangledName?.lowercased().contains(needle) ?? false)
        }
    }

    /// `(vmaddr, size)` of the `__text` section.
    private func textSectionBounds(in machO: MachOFile) -> (address: UInt64, size: Int)? {
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text"
        }) else { return nil }
        return (UInt64(text.address), text.size)
    }

    /// Decode `__text`, or just the `[start, stop)` slice of it, in-process with
    /// Capstone. Restricting to a span is what makes `disasm --function` fast on
    /// a large binary — only the matched function's code is decoded, not the
    /// whole text section.
    private func decodeText(in machO: MachOFile, span: (start: UInt64, stop: UInt64)?) -> [DecodedInstruction] {
        guard let engine = CapstoneEngine(), let text = textSectionBounds(in: machO) else { return [] }
        let start: UInt64
        let size: Int
        if let span {
            let lo = max(span.start, text.address)
            let hi = min(span.stop, text.address + UInt64(text.size))
            guard hi > lo else { return [] }
            start = lo
            size = Int(hi - lo)
        } else {
            start = text.address
            size = text.size
        }
        guard let bytes = sectionBytes(address: start, size: size, in: machO) else { return [] }
        return engine.disassemble(bytes, address: start)
    }

    /// Decode `__text` (or `span`) into an ordered instruction stream carrying
    /// text, control-flow class, and branch target.
    private func capstoneInstructions(in machO: MachOFile, span: (start: UInt64, stop: UInt64)? = nil) -> [Instruction] {
        decodeText(in: machO, span: span).map { decoded in
            Instruction(
                address: decoded.address,
                text: decoded.text,
                annotation: nil,
                controlFlow: decoded.controlFlow,
                branchTarget: decoded.branchTarget
            )
        }
    }

    /// Raw bytes of an arbitrary section span (`__text`, `__objc_stubs`, …).
    ///
    /// For a plain file, read through the image reader. For a dyld-cache image
    /// the code usually lives in a *different* subcache file than the image
    /// header, and MachOKit's image reader only reaches the header's subcache —
    /// so locate the subcache that maps the section's VM address and read that
    /// subcache file directly.
    private func sectionBytes(address: UInt64, size: Int, in machO: MachOFile) -> Data? {
        if let full = machO.fullCache,
           let fullOffset = full.fileOffset(of: address),
           let subcache = full.cache(forOffset: fullOffset),
           let url = full.url(forOffset: fullOffset),
           let localOffset = subcache.fileOffset(of: address),
           let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: localOffset)
                return try handle.read(upToCount: size)
            } catch {
                return nil
            }
        }
        if let bytes: [UInt8] = try? machO.readElements(
            offset: machO.resolveOffset(at: address),
            numberOfElements: size
        ) {
            return Data(bytes)
        }
        return nil
    }

    /// Add names for call targets that leave a dyld-cache image.
    ///
    /// No-op for a standalone binary (objdump already names its stubs in-text).
    /// For a cache image this is most of the difference between calls being
    /// anonymous addresses and being named.
    private func crossImageNames(
        for functions: [DisassembledFunction],
        in machO: MachOFile,
        names: [UInt64: String]
    ) -> [UInt64: String] {
        guard let resolver = CacheSymbolResolver(machO: machO) else { return names }
        var names = names
        var targets = Set<UInt64>()
        for function in functions {
            for insn in function.instructions
            where insn.controlFlow == .call || insn.controlFlow == .branch {
                if let target = insn.branchTarget, names[target] == nil { targets.insert(target) }
            }
        }
        for target in targets {
            if let name = resolver.name(forCallTarget: target) {
                names[target] = demangle(name) ?? Self.stripLeadingUnderscore(name)
            }
        }
        return names
    }

    private static func stripLeadingUnderscore(_ symbol: String) -> String {
        symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
    }

    /// `stub address → objc_msgSend$selector` for this image's selector stubs.
    private func objcStubNames(in machO: MachOFile) -> [UInt64: String] {
        let selectors = ObjCSelectors.selectorTable(in: machO).bySelref
        guard !selectors.isEmpty, let engine = CapstoneEngine() else { return [:] }
        return ObjCSelectors.stubNames(in: machO, selectors: selectors) { address, size in
            guard let bytes = sectionBytes(address: address, size: size, in: machO) else { return [] }
            return engine.disassemble(bytes, address: address).map { decoded in
                Instruction(
                    address: decoded.address, text: decoded.text, annotation: nil,
                    controlFlow: decoded.controlFlow, branchTarget: decoded.branchTarget
                )
            }
        }
    }

    /// Function labels from the symbol table: `__text`-range defined symbols,
    /// keyed by VM address. Present even in dyld-cache images (exports), and a
    /// no-op when the symbol table is stripped.
    private func symbolLabels(in machO: MachOFile) -> [UInt64: String] {
        // Restrict to the __text VM range so a defined-symbol's offset that maps
        // outside code (a mis-typed symbol) can't mislabel a function.
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text"
        }) else { return [:] }
        let textRange = UInt64(text.address) ..< UInt64(text.address + text.size)

        // MachOKit's `Symbol.offset` is the nlist `n_value` — for a defined
        // symbol that's its (unslid) VM address, the same space as instruction
        // addresses and LC_FUNCTION_STARTS. (Undefined symbols have n_value 0,
        // which the __text-range filter drops.)
        var labels: [UInt64: String] = [:]
        for symbol in machO.symbols where !symbol.name.isEmpty {
            let address = UInt64(symbol.offset)
            if textRange.contains(address), labels[address] == nil {
                labels[address] = symbol.name
            }
        }
        return labels
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

    /// Decode `__text` (or `span`) in-process with Capstone, returning a map of
    /// address → structured instruction (control-flow class + branch target).
    private func capstoneControlFlow(in machO: MachOFile, span: (start: UInt64, stop: UInt64)? = nil) -> [UInt64: DecodedInstruction] {
        var map: [UInt64: DecodedInstruction] = [:]
        for decoded in decodeText(in: machO, span: span) {
            map[decoded.address] = decoded
        }
        return map
    }

    /// The `[start, stop)` ranges of every function whose raw symbol or demangled
    /// name contains `filter` — computed *without* disassembling (from
    /// `LC_FUNCTION_STARTS`, the symbol table, and Swift-metadata names).
    /// Adjacent matches (gap < 64 KB) are coalesced so a cluster is one decode.
    /// A filtered disasm decodes only these ranges instead of all of `__text`.
    private func matchedRanges(filter: String, in machO: MachOFile) async -> [(start: UInt64, stop: UInt64)] {
        let needle = filter.lowercased()
        let labels = symbolLabels(in: machO)
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(labels.keys)
        let boundaries = boundarySet.sorted()
        guard !boundaries.isEmpty else { return [] }

        // Metadata names, on the same gate `assemble` uses, so a match against a
        // metadata-named (stripped) function still finds its range.
        let unlabeled = boundarySet.subtracting(labels.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundarySet.count, 1)) * 0.25 {
            metadataNames = await MetadataSymbolizer(preset: preset).functionNames(in: machO)
        }

        let textEnd = textSectionBounds(in: machO).map { $0.address + UInt64($0.size) }
            ?? (boundaries.last! + 0x4000)

        func matches(_ start: UInt64) -> Bool {
            let symbol = labels[start] ?? "sub_\(String(start, radix: 16))"
            if symbol.lowercased().contains(needle) { return true }
            let demangled = labels[start].flatMap { demangle($0) } ?? metadataNames[start]
            return demangled?.lowercased().contains(needle) ?? false
        }

        var ranges: [(start: UInt64, stop: UInt64)] = []
        for (index, start) in boundaries.enumerated() where matches(start) {
            let stop = index + 1 < boundaries.count ? boundaries[index + 1] : textEnd
            if let last = ranges.last, start <= last.stop + 0x10000 {
                ranges[ranges.count - 1].stop = max(last.stop, stop)
            } else {
                ranges.append((start, stop))
            }
        }
        return ranges
    }

    // MARK: - Operand reference resolution

    /// Known target addresses → display names: every recovered function start,
    /// Swift type descriptors, and ObjC selector stubs. Used to resolve adrp/add
    /// operand targets and to name call targets.
    private func referenceIndex(functions: [DisassembledFunction], in machO: MachOFile) -> [UInt64: String] {
        var names: [UInt64: String] = [:]
        for function in functions where names[function.startAddress] == nil {
            names[function.startAddress] = function.displayName
        }
        // Selector stubs live in __objc_stubs, outside __text, so they are never
        // recovered as functions — without this every message send is a call to
        // an unnamed address.
        for (address, name) in objcStubNames(in: machO) where names[address] == nil {
            names[address] = name
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

    /// Annotate direct call/branch instructions with their resolved target
    /// name (`→ Type.method`). objdump already names file-mode calls in the
    /// instruction text (via stubs); this fills the in-process (Capstone) path,
    /// where the operand is a bare `#0x…` address — so calls to another function
    /// in the same image read by name and flow into `--pseudo`.
    private func annotateCallTargets(
        in function: DisassembledFunction,
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        let branchFlows: Set<ControlFlow> = [.call, .branch, .conditionalBranch]
        let instructions = function.instructions.map { insn -> Instruction in
            // Only name calls not already annotated — objdump's file-mode calls
            // carry their name in-text; this fills the bare-address in-process path.
            guard insn.annotation == nil,
                  let flow = insn.controlFlow, branchFlows.contains(flow),
                  let target = insn.branchTarget,
                  let name = resolver.callTargetName(at: target)
            else { return insn }
            return Instruction(
                address: insn.address, text: insn.text, annotation: "→ \(name)",
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: insn.callArguments
            )
        }
        return DisassembledFunction(
            symbol: function.symbol, demangledName: function.demangledName,
            startAddress: function.startAddress, instructions: instructions, source: function.source
        )
    }

    /// VM range of a named section, if present.
    private func sectionRange(named name: String, in machO: MachOFile) -> Range<UInt64>? {
        guard let section = machO.sections.first(where: { $0.sectionName == name && $0.size > 0 })
        else { return nil }
        let start = UInt64(section.address)
        return start ..< (start + UInt64(section.size))
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
        /// Selector names, by selref slot and by string address — the two ways a
        /// call site can name one.
        var selectors = SelectorTable()
        /// VM range of `__cfstring`, whose entries are the `@"…"` literals.
        var cfStringRange: Range<UInt64>?

        /// The selector a loaded address denotes, when that address is a selref
        /// slot. Nil for every other load.
        func selector(at slot: UInt64) -> String? { selectors.bySelref[slot] }

        /// A display name for the *contents* of `slot` — what an `ldr` from it
        /// yields. Either a selector ref, or a GOT-style slot bound to an
        /// imported symbol (`_OBJC_CLASS_$_NSUserDefaults` → `NSUserDefaults`,
        /// which is how a class-method receiver is materialised). Nil for any
        /// other load: unnamed data we must not guess at.
        func loadedName(at slot: UInt64) -> String? {
            if let selector = selectors.bySelref[slot] { return "@selector(\(selector))" }
            guard let symbol = boundSymbol(at: slot) else { return nil }
            if symbol.hasPrefix(Self.classSymbolPrefix) {
                return String(symbol.dropFirst(Self.classSymbolPrefix.count))
            }
            if let demangled = demangleSymbol(symbol) { return demangled }
            return symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        }

        private static let classSymbolPrefix = "_OBJC_CLASS_$_"

        /// The imported symbol a slot binds to, via the chained-fixup imports.
        private func boundSymbol(at slot: UInt64) -> String? {
            guard let fixups = try? machO.dyldChainedFixups,
                  let fileOffset = machO.fileOffset(of: slot),
                  let (imported, _) = machO.resolveBind(at: UInt64(fileOffset))
            else { return nil }
            return fixups.symbolName(for: imported.info.nameOffset)
        }

        /// `@"literal"` for a `__cfstring` entry.
        ///
        /// Layout is `struct __NSConstantString { void *isa; int32 flags; int32 _;
        /// const char *str; long length; }`, so the character pointer sits at
        /// +16 — and is itself rebased, not a literal on-disk pointer.
        func cfString(at address: UInt64) -> String? {
            guard cfStringRange?.contains(address) == true,
                  let fileOffset = machO.fileOffset(of: address &+ 16),
                  let runtimeOffset = machO.resolveRebase(at: UInt64(fileOffset))
            else { return nil }
            let target = machO.address(forOffset: 0) &+ runtimeOffset
            guard let text = Self.cString(at: target, in: machO) else { return nil }
            return "@\"\(text)\""
        }

        func name(at target: UInt64) -> String? {
            if let name = names[target] { return name }
            // A direct reference to a uniqued selector string — how a shared-cache
            // image names the selector it's about to send.
            if let selector = selectors.byStringAddress[target] { return "@selector(\(selector))" }
            if let literal = cfString(at: target) { return literal }
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

        /// Name for a direct call/branch *code* target — a recovered function or
        /// descriptor in this image. Unlike `name(at:)` it does not fall back to
        /// string/data interpretations (a branch target is code, never a
        /// cstring), so it never invents a spurious name for a call.
        func callTargetName(at target: UInt64) -> String? { names[target] }

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
    /// Whether a symbol is Swift-mangled, and so uses the Swift calling
    /// convention (`self` in x20, error in x21).
    static func isSwiftMangled(_ symbol: String) -> Bool {
        let bare = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        return bare.hasPrefix("$s") || bare.hasPrefix("$S")
    }

    /// The raw (still-mangled) callee symbol from the instruction text, for
    /// calls objdump resolved through a stub or named inline. The reference
    /// index holds *demangled* names, so the mangling — the only reliable
    /// signal that a callee is Swift — has to come from the text.
    private static func rawCalleeSymbol(of insn: Instruction) -> String? {
        if let range = insn.text.range(of: "symbol stub for: ") {
            return String(insn.text[range.upperBound...].prefix { !$0.isWhitespace && $0 != ";" })
        }
        let fields = insn.text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2, fields[1].hasPrefix("_") else { return nil }
        return String(fields[1])
    }

    /// Whether `insn` calls a Swift function.
    private static func isSwiftCall(_ insn: Instruction, swiftTargets: Set<UInt64>) -> Bool {
        if let target = insn.branchTarget, swiftTargets.contains(target) { return true }
        return rawCalleeSymbol(of: insn).map(isSwiftMangled) ?? false
    }

    private func enrichCallArguments(
        in function: DisassembledFunction,
        resolver: ReferenceResolver,
        swiftTargets: Set<UInt64>
    ) -> DisassembledFunction {
        // A `.loaded` value only means something when we can name what lives at
        // the address; any other load is unnamed data. Degrade those to
        // `.unknown` and re-trim, so tracking `ldr` doesn't leave a trailing
        // unresolvable load rendering as a spurious `?`.
        func sanitize(_ values: [AbstractValue]) -> [AbstractValue]? {
            ValueTracer.trimTrailingUnknown(values.map { value in
                guard case .loaded(let address) = value,
                      resolver.loadedName(at: address) == nil
                else { return value }
                return .unknown
            })
        }

        let sites = ValueTracer().callSites(in: function)
        let argumentsByAddress = sites.compactMapValues { sanitize($0.arguments) }
        guard !sites.isEmpty else { return function }

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
            case .loaded(let a):
                // Sanitised above, so a surviving `.loaded` always has a name.
                return resolver.loadedName(at: a) ?? "?"
            case .frame(let offset):
                // A frame-relative address: a local's address being passed
                // (inout/indirect). Named by frame offset, the way a disassembler
                // names stack slots.
                guard offset != 0 else { return "sp" }
                let magnitude = String(abs(offset), radix: 16)
                return offset < 0 ? "local_\(magnitude)" : "frame_\(magnitude)"
            case .callResult(let addr):
                let inner = argumentsByAddress[addr] ?? []
                guard depth < 4, let callee = calleeByAddress[addr] else { return "result" }
                // ARC/exclusivity calls return their argument — unwrap them.
                if DisassembledFunction.isRuntimeNoise(callee) {
                    return inner.first.map { renderValue($0, depth: depth + 1) } ?? "result"
                }
                let arguments: [String] = renderArguments(inner, depth: depth + 1)
                if let send = DisassembledFunction.MessageSend(callee: callee, arguments: arguments) {
                    return send.rendered
                }
                return "\(DisassembledFunction.strippedCallee(callee))(\(arguments.joined(separator: ", ")))"
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
            guard insn.controlFlow == .call, let site = sites[insn.address] else { return insn }

            // x20 is `self` only under the Swift calling convention; for any
            // other callee it's a callee-saved register the caller happens to be
            // using, and calling it `self` would be a fabrication.
            let selfText: String? = {
                guard Self.isSwiftCall(insn, swiftTargets: swiftTargets),
                      site.selfValue != .unknown
                else { return nil }
                return renderValue(site.selfValue, depth: 0)
            }()

            let rendered: [String] = (argumentsByAddress[insn.address]).map {
                renderArguments($0, depth: 0)
            } ?? []
            guard !rendered.isEmpty || selfText != nil else { return insn }

            var notes: [String] = []
            if let selfText { notes.append("self=\(selfText)") }
            if !rendered.isEmpty { notes.append("args(" + rendered.joined(separator: ", ") + ")") }
            let merged = ([insn.annotation] + notes).compactMap { $0 }.joined(separator: "  ")
            return Instruction(
                address: insn.address, text: insn.text, annotation: merged,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: rendered.isEmpty ? nil : rendered,
                callSelf: selfText
            )
        }
        return DisassembledFunction(
            symbol: function.symbol, demangledName: function.demangledName,
            startAddress: function.startAddress, instructions: instructions, source: function.source
        )
    }

    /// `adrp x8, 12 ; 0x10000c000` (llvm-objdump) or `adrp x8, 0x10000c000`
    /// (Capstone) → ("x8", 0x10000c000). objdump keeps the resolved page in a
    /// trailing comment; Capstone puts it straight in the operand.
    private func parseAdrp(_ text: String) -> (register: String, page: UInt64)? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.first == "adrp", fields.count >= 2 else { return nil }
        let register = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        if let hashIndex = text.range(of: "; 0x")?.upperBound {
            let hex = text[hashIndex...].prefix { $0.isHexDigit }
            if let page = UInt64(hex, radix: 16) { return (register, page) }
        }
        if fields.count >= 3 {
            let operand = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "#, "))
            if operand.hasPrefix("0x"), let page = UInt64(operand.dropFirst(2), radix: 16) {
                return (register, page)
            }
        }
        return nil
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
