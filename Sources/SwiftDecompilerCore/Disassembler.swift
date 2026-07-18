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
    /// The call's result is embedded in a later recovered expression, so flat
    /// pseudocode should not also emit it as a duplicate standalone call.
    public let resultConsumed: Bool
    /// Metadata type of a field read or written by this instruction, when the
    /// access was resolved exactly enough to name it. Objective-C encodings
    /// such as `B` let structured output distinguish booleans from integers.
    public let sourceType: String?
    /// Structured operands from Capstone's detail mode.
    ///
    /// Present on both front-ends: the objdump path already runs the full
    /// Capstone decoder and merges it by address (objdump supplies text,
    /// Capstone supplies semantics), so this is threaded through that same
    /// merge. Nil only where Capstone failed to decode an address objdump
    /// emitted — data in `__text`, or an encoding Capstone doesn't know.
    public let detail: StructuredInsn?

    public init(
        address: UInt64,
        text: String,
        annotation: String? = nil,
        controlFlow: ControlFlow? = nil,
        branchTarget: UInt64? = nil,
        callArguments: [String]? = nil,
        callSelf: String? = nil,
        resultConsumed: Bool = false,
        sourceType: String? = nil,
        detail: StructuredInsn? = nil
    ) {
        self.address = address
        self.text = text
        self.annotation = annotation
        self.controlFlow = controlFlow
        self.branchTarget = branchTarget
        self.callArguments = callArguments
        self.callSelf = callSelf
        self.resultConsumed = resultConsumed
        self.sourceType = sourceType
        self.detail = detail
    }
}

/// How a function's name/boundary was recovered — useful context, especially
/// for stripped binaries.
public enum RecoverySource: String, Sendable {
    /// Named by a symbol-table label emitted by the disassembler.
    case symbol
    /// Named from Swift `__swift5_*` metadata (survives stripping).
    case metadata
    /// Named from an Objective-C class/category method record (survives
    /// stripping and carries selector, type encoding, and IMP).
    case objcMetadata = "objc-metadata"
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
    /// Objective-C owner/selector/signature when this entry point is an IMP.
    public let objcMethod: ObjCMethodBinding?

    public init(
        symbol: String,
        demangledName: String?,
        startAddress: UInt64,
        instructions: [Instruction],
        source: RecoverySource,
        objcMethod: ObjCMethodBinding? = nil
    ) {
        self.symbol = symbol
        self.demangledName = demangledName
        self.startAddress = startAddress
        self.instructions = instructions
        self.source = source
        self.objcMethod = objcMethod
    }

    /// The name to show: demangled if available, else the raw symbol.
    public var displayName: String { demangledName ?? symbol }

    /// Render this function as annotated assembly text.
    public func render() -> String {
        var lines: [String] = []
        lines.append("\(displayName):")
        let tag: String = switch source {
        case .metadata: "  [recovered from Swift metadata]"
        case .objcMetadata: "  [recovered from Objective-C metadata]"
        case .symbol, .address: ""
        }
        if let objcMethod {
            lines.append("  // \(objcMethod.signature)  @ 0x\(String(startAddress, radix: 16))\(tag)")
            if source == .symbol { lines.append("  // \(symbol)") }
        } else if demangledName != nil {
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
                controlFlow: decoded.controlFlow, branchTarget: decoded.branchTarget,
                detail: decoded.detail
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
        // Filtering needs ObjC names before decoding; carry the same index into
        // assembly so large class graphs are parsed once, not twice.
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        // Filtered: decode only the matched functions' ranges of __text.
        let instructions: [Instruction]
        if let filter = functionFilter, !filter.isEmpty {
            let ranges = await matchedRanges(filter: filter, in: machO, objcIndex: objcIndex)
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
            functionFilter: functionFilter,
            objcIndex: objcIndex
        )
    }

    /// Disassemble only the functions beginning at `addresses`, each decoded up
    /// to the next function boundary. Lets a caller classify a handful of
    /// Objective-C accessor IMPs without decoding the whole binary.
    public func disassembleFunctions(
        at addresses: Set<UInt64>,
        in machO: MachOFile
    ) async -> [DisassembledFunction] {
        guard !addresses.isEmpty else { return [] }
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(objcIndex.addresses)
        let boundaries = boundarySet.sorted()
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text" && $0.size > 0
        }) else { return [] }
        let textEnd = UInt64(text.address + text.size)

        let instructions = addresses.sorted().flatMap { start -> [Instruction] in
            let stop = boundaries.first(where: { $0 > start }) ?? textEnd
            guard stop > start else { return [] }
            return capstoneInstructions(in: machO, span: (start, stop))
        }
        guard !instructions.isEmpty else { return [] }
        return await assemble(
            instructions: instructions,
            labelByAddress: symbolLabels(in: machO),
            in: machO,
            functionFilter: nil,
            objcIndex: objcIndex
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
        functionFilter: String?,
        objcIndex providedObjCIndex: ObjCMetadataIndex? = nil
    ) async -> [DisassembledFunction] {
        // Function boundaries: LC_FUNCTION_STARTS ∪ label addresses. Function-
        // starts survive stripping, so this re-creates boundaries a label set
        // (objdump's, or a stripped cache image's exports) couldn't cover.
        let objcIndex = providedObjCIndex ?? ObjCMetadataIndex.build(in: machO)
        var boundaries = Set(functionStarts(of: machO))
        boundaries.formUnion(labelByAddress.keys)
        // An Objective-C IMP is itself a function start. This also recovers
        // methods omitted from LC_FUNCTION_STARTS, and provides names when the
        // nlist symbol was stripped.
        boundaries.formUnion(objcIndex.addresses)

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
            metadataNames: metadataNames,
            objcIndex: objcIndex
        )

        // Resolve adrp/add(+ldr) operand references to function, type-descriptor,
        // string, and Swift-symbol names, and name direct call/branch targets.
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        let resolver = ReferenceResolver(
            names: crossImageNames(
                for: functions,
                names: referenceIndex(
                    functions: functions, labelByAddress: labelByAddress,
                    metadataNames: metadataNames, objcIndex: objcIndex, in: machO
                ),
                resolver: cacheSymbols
            ),
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO),
            cacheSymbols: cacheSymbols,
            cacheReader: machO.fullCache.map { CacheReader(full: $0) }
        )
        // Addresses whose callee uses the Swift calling convention, so `self` in
        // x20 is meaningful there.
        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
        swiftTargets.formUnion(functions.filter {
            $0.objcMethod == nil && (Self.isSwiftMangled($0.symbol) || $0.source == .metadata)
        }.map(\.startAddress))
        // A Swift-mangled Objective-C entry thunk still receives self in x0.
        swiftTargets.subtract(objcIndex.addresses)
        functions = functions.map { annotateReferences(in: $0, resolver: resolver) }
        functions = functions.map { annotateCallTargets(in: $0, resolver: resolver) }
        // The differentiator's two halves: what lives at an offset (FieldMap),
        // and whether the pointer in x20 is that type (SelfTypeIndex). Both are
        // metadata-sourced, so both survive stripping.
        let fieldMaps = (try? FieldMapBuilder.build(in: machO)) ?? [:]
        let selfIndex = SelfTypeIndex.build(in: machO)
        functions = functions.map { function in
            let objcMethod = function.objcMethod
            // Runtime-added category IMPs (an accessibility bundle is almost all
            // of them) frequently have no ObjC metadata binding, yet their symbol
            // name carries the full method shape. Recover the receiver convention
            // from the symbol so `self` survives — without it x0 is never seeded
            // and every receiver renders `?`.
            let symbolEntry = objcMethod == nil ? Self.objcEntryFromSymbol(function.symbol) : nil
            let selfTypeName = objcMethod == nil && symbolEntry == nil && !fieldMaps.isEmpty
                ? Self.selfType(of: function, selfIndex: selfIndex, fieldMaps: fieldMaps)
                : nil
            let entry: MethodEntryConvention? = if let objcMethod {
                objcMethod.isInitializer
                    ? .objectiveCInitializer(argumentCount: objcMethod.argumentCount)
                    : .objectiveC(argumentCount: objcMethod.argumentCount)
            } else if let symbolEntry {
                symbolEntry
            } else if selfTypeName != nil {
                .swiftInstance
            } else {
                nil
            }
            let fieldMap: FieldMap? = if let objcMethod, !objcMethod.isClassMethod {
                objcIndex.fieldMaps[objcMethod.className]
            } else if let className = objcMethod == nil ? Self.objcClassName(fromSymbol: function.symbol) : nil {
                // No binding, but the symbol names the owning class: its ivar
                // layout may still be indexed, so `self->_ivar` can be named.
                objcIndex.fieldMaps[className]
            } else {
                selfTypeName.flatMap { fieldMaps[$0] }
            }
            return enrichCallArguments(
                in: function, resolver: resolver, swiftTargets: swiftTargets,
                entry: entry,
                fieldMap: fieldMap,
                objcFieldSyntax: objcMethod != nil || symbolEntry != nil
            )
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
                branchTarget: decoded.branchTarget,
                detail: decoded.detail
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
        names: [UInt64: String],
        resolver: CacheSymbolResolver?
    ) -> [UInt64: String] {
        guard let resolver else { return names }
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
                    controlFlow: decoded.controlFlow, branchTarget: decoded.branchTarget,
                    detail: decoded.detail
                )
            }
        }
    }

    /// Classic `__stubs` address → imported symbol. These symbols are not
    /// function definitions and therefore never appear in `symbolLabels`, but
    /// naming them is essential for recognizing runtime tail calls such as
    /// `objc_autoreleaseReturnValue` and `objc_setProperty_nonatomic_copy`.
    private func symbolStubNames(in machO: MachOFile) -> [UInt64: String] {
        guard let table = machO.indirectSymbols else { return [:] }
        let indirect = Array(table)
        let symbols = Array(machO.symbols)
        var names: [UInt64: String] = [:]

        for section in machO.sections where section.flags.type == .symbol_stubs {
            guard let first = section.indirectSymbolIndex,
                  let count = section.numberOfIndirectSymbols,
                  count > 0, first >= 0, first + count <= indirect.count
            else { continue }
            let stubSize = section.size / count
            guard stubSize > 0 else { continue }

            for slot in 0..<count {
                guard let symbolIndex = indirect[first + slot].index,
                      symbols.indices.contains(symbolIndex)
                else { continue }
                let raw = symbols[symbolIndex].name
                guard !raw.isEmpty else { continue }
                let address = UInt64(section.address + slot * stubSize)
                names[address] = demangle(raw) ?? Self.stripLeadingUnderscore(raw)
            }
        }
        return names
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
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex
    ) -> [DisassembledFunction] {
        var functions: [DisassembledFunction] = []
        var current: [Instruction] = []
        var start: UInt64 = instructions.first?.address ?? 0

        func flush() {
            guard !current.isEmpty else { return }
            functions.append(makeFunction(start: start, instructions: current,
                                           labelByAddress: labelByAddress,
                                           metadataNames: metadataNames,
                                           objcIndex: objcIndex))
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
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex
    ) -> DisassembledFunction {
        let subName = "sub_\(String(start, radix: 16))"
        let objcMethod = objcIndex.binding(for: start)
        if let rawLabel = labelByAddress[start] {
            return DisassembledFunction(
                symbol: rawLabel,
                // Runtime metadata is authoritative about an ObjC thunk's
                // source-level identity; keep the raw Swift/C symbol below it.
                demangledName: objcMethod?.displayName ?? demangle(rawLabel),
                startAddress: start,
                instructions: instructions,
                source: .symbol,
                objcMethod: objcMethod
            )
        }
        if let objcMethod {
            return DisassembledFunction(
                symbol: subName,
                demangledName: objcMethod.displayName,
                startAddress: start,
                instructions: instructions,
                source: .objcMetadata,
                objcMethod: objcMethod
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
    private func matchedRanges(
        filter: String,
        in machO: MachOFile,
        objcIndex: ObjCMetadataIndex
    ) async -> [(start: UInt64, stop: UInt64)] {
        let needle = filter.lowercased()
        let labels = symbolLabels(in: machO)
        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(labels.keys)
        boundarySet.formUnion(objcIndex.addresses)
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
            if let objc = objcIndex.binding(for: start),
               objc.displayName.lowercased().contains(needle)
                || objc.signature.lowercased().contains(needle)
                || objc.typeEncoding.lowercased().contains(needle) {
                return true
            }
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
    /// imported/ObjC selector stubs, and Swift type descriptors. Used to resolve
    /// adrp/add operand targets and to name direct call/tail-call targets.
    private func referenceIndex(
        functions: [DisassembledFunction],
        labelByAddress: [UInt64: String],
        metadataNames: [UInt64: String],
        objcIndex: ObjCMetadataIndex,
        in machO: MachOFile
    ) -> [UInt64: String] {
        var names: [UInt64: String] = [:]
        // Keep the whole image's lightweight symbol/metadata index even when a
        // filtered disassembly decoded only one function. Its direct and
        // indirect calls can still target any other known function.
        for (address, symbol) in labelByAddress {
            names[address] = objcIndex.binding(for: address)?.displayName
                ?? demangle(symbol)
                ?? Self.stripLeadingUnderscore(symbol)
        }
        for (address, name) in metadataNames where names[address] == nil {
            names[address] = name
        }
        for address in objcIndex.addresses where names[address] == nil {
            names[address] = objcIndex.binding(for: address)?.displayName
        }
        for function in functions where names[function.startAddress] == nil {
            names[function.startAddress] = function.displayName
        }
        for (address, name) in symbolStubNames(in: machO) where names[address] == nil {
            names[address] = name
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
                    controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                    detail: insn.detail
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
            source: function.source,
            objcMethod: function.objcMethod
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
                callArguments: insn.callArguments, detail: insn.detail
            )
        }
        return DisassembledFunction(
            symbol: function.symbol, demangledName: function.demangledName,
            startAddress: function.startAddress, instructions: instructions, source: function.source,
            objcMethod: function.objcMethod
        )
    }

    /// Resolve register-indirect calls only when value tracking proves the
    /// register came from a concrete address or pointer slot and that target is
    /// a known function. This covers concrete vtable/witness-table dispatch and
    /// GOT-loaded function pointers while leaving genuinely dynamic generic or
    /// block dispatch unresolved.
    private func annotateIndirectControlFlowTargets(
        in function: DisassembledFunction,
        targets: [UInt64: AbstractValue],
        resolver: ReferenceResolver
    ) -> DisassembledFunction {
        let instructions = function.instructions.map { insn -> Instruction in
            guard insn.branchTarget == nil,
                  insn.controlFlow == .call || insn.controlFlow == .branch,
                  let value = targets[insn.address],
                  let resolved = resolver.indirectCallTarget(for: value)
            else { return insn }
            let annotation = insn.annotation.map { "\($0)  → \(resolved.name)" }
                ?? "→ \(resolved.name)"
            return Instruction(
                address: insn.address, text: insn.text, annotation: annotation,
                controlFlow: insn.controlFlow, branchTarget: resolved.address,
                callArguments: insn.callArguments, callSelf: insn.callSelf,
                resultConsumed: insn.resultConsumed, sourceType: insn.sourceType,
                detail: insn.detail
            )
        }
        return DisassembledFunction(
            symbol: function.symbol, demangledName: function.demangledName,
            startAddress: function.startAddress, instructions: instructions,
            source: function.source, objcMethod: function.objcMethod
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
        /// Cross-image export/stub resolver for dyld-cache pointer slots.
        var cacheSymbols: CacheSymbolResolver?
        /// Reads across dyld subcache files. A cache image's __AUTH_CONST — where
        /// its __cfstring lives — is usually in a *different* subcache than its
        /// header, so `machO.fileOffset(of:)` returns nil for those addresses and
        /// every read has to go through the full cache instead.
        var cacheReader: CacheReader?

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
            guard let fixups = machO.dyldChainedFixups,
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
                  let target = pointerTarget(at: address &+ 16),
                  let text = readCString(at: target)
            else { return nil }
            return "@\"\(text)\""
        }

        /// A printable C string, crossing subcaches when needed.
        private func readCString(at address: UInt64) -> String? {
            if let cacheReader {
                guard let text = cacheReader.cString(at: address), !text.isEmpty,
                      text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f })
                else { return nil }
                return text.count > 48 ? String(text.prefix(48)) + "…" : text
            }
            return Self.cString(at: address, in: machO)
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

        /// A function target proven by an abstract register value. The concrete
        /// address is present for in-image rebases/direct addresses; a GOT bind
        /// can still supply an imported function name without an in-image VM
        /// address, improving pseudocode while honestly remaining absent from
        /// the address-based call graph.
        func indirectCallTarget(for value: AbstractValue) -> (address: UInt64?, name: String)? {
            switch value {
            case .address(let target), .immediate(let target):
                return callTargetName(at: target).map { (target, $0) }
            case .loaded(let slot):
                if let target = pointerTarget(at: slot) {
                    if let name = callTargetName(at: target)
                        ?? cacheSymbols?.name(forCallTarget: target) {
                        return (target, name)
                    }
                }
                return loadedName(at: slot).map { (nil, $0) }
            default:
                return nil
            }
        }

        /// VM address held by a rebased pointer slot. Full-dyld-cache and
        /// standalone Mach-O resolvers intentionally return different spaces.
        private func pointerTarget(at slot: UInt64) -> UInt64? {
            if let full = machO.fullCache,
               let fileOffset = full.fileOffset(of: slot) {
                return full.resolveRebase(at: fileOffset)
            }
            guard let fileOffset = machO.fileOffset(of: slot),
                  let runtimeOffset = machO.resolveRebase(at: UInt64(fileOffset))
            else { return nil }
            return machO.address(forOffset: 0) &+ runtimeOffset
        }

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
    /// The type whose instance arrives in x20, for one function — or nil, which
    /// is the honest answer for everything that isn't a Swift instance method.
    ///
    /// Two sources, and they are complementary rather than redundant:
    ///
    /// - The **demangled symbol** names the type directly and covers structs and
    ///   enums, whose methods are statically dispatched and have no metadata
    ///   record at all. It dies under `strip -x -S` for anything internal.
    /// - The **vtable index** is metadata and survives stripping completely, but
    ///   only classes have vtables.
    ///
    /// The **index is consulted first**, because it is the only source that
    /// carries `isInstance`. Getting this order wrong is not academic: it made
    /// `Animal.__allocating_init` — a static entry point whose x20 holds the
    /// *metatype* — render `swift_allocObject(self, 32, 7)`, attaching an
    /// instance's identity to a metatype pointer. The vtable knows
    /// (`Animal slot 6, Init, instance=false`); the symbol does not say.
    static func selfType(
        of function: DisassembledFunction,
        selfIndex: SelfTypeIndex,
        fieldMaps: [String: FieldMap]
    ) -> String? {
        if let binding = selfIndex.binding(for: function.startAddress) {
            // Authoritative, including when it says no.
            guard binding.isInstance, fieldMaps[binding.selfTypeName] != nil else { return nil }
            return binding.selfTypeName
        }
        guard let fromSymbol = selfTypeFromDemangledName(function.demangledName),
              fieldMaps[fromSymbol] != nil
        else { return nil }
        return fromSymbol
    }

    /// Strip a trailing `(…)` argument list.
    ///
    /// Matched from the end, for two reasons. A tuple argument
    /// (`value(for: (Int, Int))`) means the *first* `(` is not where the
    /// signature starts. And a private member is spelled
    /// `Type.(name in _HASH).setter` — cutting at the first `(` there destroys
    /// the name and loses the type, which is how every private property accessor
    /// in SwiftUI went unnamed.
    static func stripSignature(_ head: String) -> String {
        guard head.hasSuffix(")") else { return head }
        var depth = 0
        for index in head.indices.reversed() {
            if head[index] == ")" {
                depth += 1
            } else if head[index] == "(" {
                depth -= 1
                if depth == 0 { return String(head[..<index]) }
            }
        }
        return head
    }

    /// Demangled names whose x20 is not an instance of the type they mention.
    ///
    /// Checked against the name with its signature already removed, so an
    /// argument label cannot trip them.
    private static let nonInstanceMarkers = [
        "static ",                  // x20 holds the metatype
        "__allocating_init",        // ditto: a static entry point
        " for ",                    // "method descriptor for", "protocol witness for"
        " of ",                     // "dispatch thunk of", "variable initialization expression of"
        "@objc ",                   // an ObjC thunk: self is in x0, not x20
    ]

    /// `sample.Dog.breed.getter : Swift.String` → `Dog`.
    ///
    /// Positional, not a search. A right-to-left scan for "the first component
    /// that happens to be a known type" would resolve
    /// `struct Foo { var Bar: Int }`'s `m.Foo.Bar.getter` to the *type* `Bar`.
    /// Property accessors nest one level deeper than methods —
    /// `Module.Type.property.accessor` vs `Module.Type.method` — so the accessor
    /// kind decides which component is the type.
    ///
    /// The `fieldMaps` membership check at the call site is the backstop:
    /// `sample.run() -> ()` also has a dot, but a module has no field map.
    static func selfTypeFromDemangledName(_ name: String?) -> String? {
        guard let name else { return nil }
        // Cut the return clause and property type first, so `foo(a: Dog.Kind)`
        // and `... : Swift.String` are not mined for type names.
        var head = name
        if let arrow = head.range(of: " -> ") { head = String(head[..<arrow.lowerBound]) }
        if let colon = head.range(of: " : ") { head = String(head[..<colon.lowerBound]) }
        head = stripSignature(head)
        guard !nonInstanceMarkers.contains(where: head.contains) else { return nil }

        let parts = head.split(separator: ".").map(String.init)
        let accessors: Set<String> = ["getter", "setter", "modify", "read", "init", "deinit"]
        // `Type.property.accessor` -> the type is 3 from the end.
        // `Type.method`            -> 2 from the end.
        let typeIndex = accessors.contains(parts.last ?? "") ? parts.count - 3 : parts.count - 2
        guard typeIndex >= 0, typeIndex < parts.count else { return nil }
        return parts[typeIndex]
    }

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

    /// Split an Objective-C method symbol (`-[Class sel:with:]`, `+[Class sel]`,
    /// or with a category `-[Class(Cat) sel]`) into its owner name and selector.
    /// Nil for anything that is not an ObjC method symbol.
    private static func objcMethodSymbolParts(_ symbol: String) -> (owner: Substring, selector: Substring)? {
        guard symbol.hasPrefix("-[") || symbol.hasPrefix("+["), symbol.hasSuffix("]") else { return nil }
        let inner = symbol.dropFirst(2).dropLast()
        guard let space = inner.firstIndex(of: " ") else { return nil }
        let owner = inner[..<space]
        let selector = inner[inner.index(after: space)...]
        // A real selector is a run of identifier characters and colons — reject
        // anything with embedded spaces (a demangled Swift name, say).
        guard !owner.isEmpty, !selector.isEmpty, !selector.contains(" ") else { return nil }
        return (owner, selector)
    }

    /// The Objective-C receiver convention implied by a method symbol name, used
    /// when no metadata binding exists. `self` is x0, `_cmd` is x1, and one
    /// explicit argument per selector colon begins at x2 — the same ABI a bound
    /// method gets. Initializer families are detected from selector spelling so
    /// `self = [super init…]` still threads through.
    private static func objcEntryFromSymbol(_ symbol: String) -> MethodEntryConvention? {
        guard let (_, selector) = objcMethodSymbolParts(symbol) else { return nil }
        let argumentCount = selector.filter { $0 == ":" }.count
        let isInitializer = selector == "init"
            || (selector.hasPrefix("init") && selector.dropFirst(4).first.map { !$0.isLowercase } == true)
        return isInitializer
            ? .objectiveCInitializer(argumentCount: argumentCount)
            : .objectiveC(argumentCount: argumentCount)
    }

    /// The owning class name from a method symbol, category suffix stripped
    /// (`-[UILabel(Accessibility) foo]` → `UILabel`), for looking up an ivar
    /// layout the metadata binding didn't provide.
    private static func objcClassName(fromSymbol symbol: String) -> String? {
        guard let (owner, _) = objcMethodSymbolParts(symbol) else { return nil }
        if let paren = owner.firstIndex(of: "(") { return String(owner[..<paren]) }
        return String(owner)
    }

    private func enrichCallArguments(
        in function: DisassembledFunction,
        resolver: ReferenceResolver,
        swiftTargets: Set<UInt64>,
        entry: MethodEntryConvention?,
        fieldMap: FieldMap?,
        objcFieldSyntax: Bool
    ) -> DisassembledFunction {
        /// A source-level field path for this method convention.
        func fieldPath(_ name: String) -> String {
            objcFieldSyntax ? "self->\(name)" : "self.\(name)"
        }

        func fieldInfo(at offset: Int, bytes: Int) -> (names: [String], type: String?)? {
            guard let fieldMap else { return nil }
            switch fieldMap.lookup(offset: offset, bytes: max(bytes, 1)) {
            case .success(.whole(let name, let type)):
                return ([name], type)
            case .success(.part(let name, let type, _, _)):
                return ([name], type)
            case .success(.spans(let names)):
                return (names, nil)
            case .failure:
                return nil
            }
        }

        /// A field name for an offset, or nil when it cannot be named honestly.
        func fieldName(at offset: Int, bytes: Int) -> String? {
            guard let names = fieldInfo(at: offset, bytes: bytes)?.names else { return nil }
            return names.count == 1 ? names[0] : "{\(names.joined(separator: ", "))}"
        }

        // A `.loaded` value only means something when we can name what lives at
        // the address; any other load is unnamed data. Sanitize recursively now
        // that arithmetic expressions can contain loaded values.
        func sanitizeValue(_ value: AbstractValue) -> AbstractValue {
            switch value {
            case .loaded(let address) where resolver.loadedName(at: address) == nil:
                return .unknown
            case .binary(let op, let lhs, let rhs):
                let lhs = sanitizeValue(lhs)
                let rhs = sanitizeValue(rhs)
                guard lhs != .unknown, rhs != .unknown else { return .unknown }
                return .binary(op, lhs, rhs)
            case .aggregate(let values):
                let values = values.map(sanitizeValue)
                return values.allSatisfy({ $0 != .unknown }) ? .aggregate(values) : .unknown
            default:
                return value
            }
        }

        func sanitize(_ values: [AbstractValue]) -> [AbstractValue]? {
            ValueTracer.trimTrailingUnknown(values.map(sanitizeValue))
        }

        let analysis = ValueTracer().analyze(function, entry: entry)
        let function = annotateIndirectControlFlowTargets(
            in: function, targets: analysis.indirectControlFlowTargets,
            resolver: resolver
        )
        var sites = analysis.callSites
        // A resolved unconditional branch outside this function is a tail call.
        // Keep internal CFG branches out: they have no callee name.
        for insn in function.instructions where insn.controlFlow == .branch {
            if DisassembledFunction.calleeName(of: insn) != nil,
               let site = analysis.branchSites[insn.address] {
                sites[insn.address] = site
            }
        }
        // A property getter is often `ldr x0, [x20, #n]; ret` — no calls at all.
        // Bailing on `sites.isEmpty` alone would skip field naming for precisely
        // the functions it is most useful in.
        guard !sites.isEmpty || !analysis.selfFieldAccesses.isEmpty || !analysis.exitValues.isEmpty
        else { return function }

        // Callee name per call/tail-call address, for nesting result expressions.
        var calleeByAddress: [UInt64: String] = [:]
        for insn in function.instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            calleeByAddress[insn.address] = DisassembledFunction.calleeName(of: insn)
        }

        /// A selector proven by either a modern per-selector message stub or an
        /// old-style selref in x1. Stack values are never appended to a call
        /// merely because they happen to exist: only a known variadic selector
        /// makes those fresh stack stores part of the source argument list.
        func selectorName(callee: String, arguments: [AbstractValue]) -> String? {
            if callee.hasPrefix("objc_msgSend"), let marker = callee.firstIndex(of: "$") {
                return String(callee[callee.index(after: marker)...])
            }
            guard callee == "objc_msgSend" || callee.hasPrefix("objc_msgSendSuper"),
                  arguments.count > 1,
                  case .loaded(let slot) = arguments[1]
            else { return nil }
            return resolver.selector(at: slot)
        }

        func isVariadicObjCSelector(_ selector: String) -> Bool {
            DisassembledFunction.MessageSend.isVariadicSelector(selector)
        }

        var argumentsByAddress: [UInt64: [AbstractValue]] = [:]
        for (address, site) in sites {
            var values = site.arguments
            if let callee = calleeByAddress[address],
               let selector = selectorName(callee: callee, arguments: values),
               !site.stackArguments.isEmpty {
                if isVariadicObjCSelector(selector) {
                    values += site.stackArguments
                } else {
                    let fixedStackCount = max(0, selector.filter({ $0 == ":" }).count - 6)
                    values += site.stackArguments.prefix(fixedStackCount)
                }
            }
            if let values = sanitize(values) { argumentsByAddress[address] = values }
        }

        /// Runtime entry points with a fixed public ABI often inherit unrelated
        /// live values in later argument registers. Keep only parameters the
        /// helper actually accepts before embedding it in a source expression.
        func normalizedArguments(callee: String, values: [AbstractValue]) -> [AbstractValue] {
            DisassembledFunction.knownCArity(of: callee).map { Array(values.prefix($0)) } ?? values
        }

        /// Render a runtime helper as the source send it lowers from.
        /// The table lives with `MessageSend` in Pseudo.swift — one definition,
        /// used by both the nested-expression and statement paths.
        func objcRuntimeIdiom(callee: String, arguments: [AbstractValue], depth: Int) -> String? {
            guard depth < 8 else { return nil }
            let rendered = arguments.prefix(2).map { renderValue($0, depth: depth + 1) }
            return DisassembledFunction.objcRuntimeIdiom(callee: callee, arguments: Array(rendered))
        }

        func renderValue(_ value: AbstractValue, depth: Int) -> String {
            switch value {
            case .unknown:
                return "?"
            case .immediate(let v):
                return v < 4096 ? String(v) : "0x" + String(v, radix: 16)
            case .argument(let index):
                return "arg\(index)"
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
            case .selfPointer:
                return "self"
            case .selfField(let offset):
                // `&self.breed`, when the field is nameable; otherwise the raw
                // offset, which is still true.
                guard let name = fieldName(at: offset, bytes: 0) else {
                    return "&self+0x\(String(offset, radix: 16))"
                }
                return "&\(fieldPath(name))"
            case .selfFieldValue(let offset):
                guard let name = fieldName(at: offset, bytes: 1) else {
                    return "self[0x\(String(offset, radix: 16))]"
                }
                return fieldPath(name)
            case .binary(let op, let lhs, let rhs):
                guard depth < 8 else { return "?" }
                return "(\(renderValue(lhs, depth: depth + 1)) \(op.symbol) \(renderValue(rhs, depth: depth + 1)))"
            case .aggregate(let values):
                return "(" + values.map { renderValue($0, depth: depth + 1) }.joined(separator: ", ") + ")"
            case .callResult(let addr):
                let inner = argumentsByAddress[addr] ?? []
                let unresolved = "/* unresolved call @ 0x\(String(addr, radix: 16)) */ ?"
                // Deeply nested message chains (`[[[[self a] b] c] d]`) are common
                // in framework code; a shallow cap turns the tail into `unresolved`.
                // callResult references cannot cycle — a call's arguments are fully
                // computed before it runs — so this bound only limits line length,
                // never termination. Kept below the depth-8 expression cap.
                guard depth < 6, let callee = calleeByAddress[addr] else { return unresolved }
                // ARC/exclusivity calls return their argument — unwrap them.
                if DisassembledFunction.isRuntimeNoise(callee) {
                    return inner.first.map { renderValue($0, depth: depth + 1) } ?? unresolved
                }
                // Checked-cast / safe-category helpers return their operand
                // unchanged; unwrap to that operand so the cast doesn't bury the
                // value. The operand index is explicit per helper, never guessed.
                if let index = DisassembledFunction.castPassthroughIndex(of: callee),
                   index < inner.count {
                    return renderValue(inner[index], depth: depth + 1)
                }
                // `objc_alloc(cls)` is `[cls alloc]`, so the argument is the
                // receiver as-is.
                //
                // It is NOT re-attributed to whatever produced that class.
                // `objc_opt_class(x)` is `[x class]`, so
                // `objc_alloc(objc_opt_class(x))` is `[[x class] alloc]`, and
                // rendering it `[x alloc]` drops a real call. Measured, because
                // the lowering is the reverse of what it looks like:
                //
                //   [self alloc]        (self is a Class)    -> objc_alloc(self)
                //   [[self class] alloc] (self is an instance) -> objc_alloc(objc_opt_class(self))
                //
                // So the composed form is exactly the case where `[x alloc]` is
                // wrong — and in an instance method it is not even valid ObjC,
                // since `alloc` is a class method. Nesting renders the `class`
                // call on its own, which is both true and what the source said.
                if let idiom = objcRuntimeIdiom(callee: callee, arguments: inner, depth: depth) {
                    return idiom
                }
                let callValues = normalizedArguments(callee: callee, values: inner)
                let arguments: [String] = renderArguments(callValues, depth: depth + 1)
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

        func callExpression(callee: String, values: [AbstractValue], depth: Int = 0) -> String {
            // Same rewrite as the nested path: a runtime helper that is an exact
            // lowering of a source send renders as that send, whether it is the
            // statement itself or an argument to one.
            if let idiom = objcRuntimeIdiom(callee: callee, arguments: values, depth: depth) {
                return idiom
            }
            let arguments: [String] = renderArguments(
                normalizedArguments(callee: callee, values: values), depth: depth
            )
            if let send = DisassembledFunction.MessageSend(callee: callee, arguments: arguments) {
                return send.rendered
            }
            return "\(DisassembledFunction.strippedCallee(callee))(\(arguments.joined(separator: ", ")))"
        }

        func fieldWrite(
            _ access: SelfFieldAccess,
            field: (names: [String], type: String?)
        ) -> String {
            if field.names.count > 1, let stored = access.storedValues,
               stored.count >= field.names.count {
                let values = stored.prefix(field.names.count).map(sanitizeValue)
                if values.allSatisfy({ $0 != .unknown }) {
                    let paths = field.names.map(fieldPath).joined(separator: ", ")
                    let rendered = values.map { renderValue($0, depth: 0) }.joined(separator: ", ")
                    return "(\(paths)) = (\(rendered))"
                }
            }
            let name = field.names.count == 1
                ? field.names[0] : "{\(field.names.joined(separator: ", "))}"
            let path = fieldPath(name)
            guard let rawValue = access.storedValue else { return "\(path) = …" }
            let value = sanitizeValue(rawValue)
            guard value != .unknown else { return "\(path) = …" }

            // The canonical compiler shape for `_count += delta` is load/add/
            // store. Preserve that source operator instead of spelling a noisy
            // self-assignment.
            if case .binary(let op, let lhs, let rhs) = value,
               case .selfFieldValue(let offset) = lhs, offset == access.offset,
               op == .add || op == .subtract {
                return "\(path) \(op == .add ? "+=" : "-=") \(renderValue(rhs, depth: 0))"
            }
            if objcFieldSyntax, field.type == "B", case .immediate(let raw) = value, raw <= 1 {
                return "\(path) = \(raw == 0 ? "NO" : "YES")"
            }
            return "\(path) = \(renderValue(value, depth: 0))"
        }

        /// Runtime helpers emitted as tail calls can express higher-level ivar
        /// operations more accurately than their low-level ABI argument list.
        func objcHelperStatement(callee: String, site: CallSite) -> String? {
            let args = site.arguments
            if callee.hasPrefix("objc_setProperty"), args.count >= 4,
               case .immediate(let rawOffset) = args[3],
               let offset = Int(exactly: rawOffset),
               let name = fieldName(at: offset, bytes: 1) {
                let value = renderValue(sanitizeValue(args[2]), depth: 0)
                let copied = callee.contains("copy") ? "[\(value) copy]" : value
                return "\(fieldPath(name)) = \(copied)"
            }
            if callee.hasPrefix("objc_storeStrong"), args.count >= 2,
               case .selfField(let offset) = args[0],
               case .immediate(0) = args[1],
               let name = fieldName(at: offset, bytes: 1) {
                return "\(fieldPath(name)) = nil"
            }
            return nil
        }

        let passthroughReturnHelpers = [
            "objc_autoreleaseReturnValue", "objc_retainAutoreleaseReturnValue",
            "objc_claimAutoreleasedReturnValue", "objc_retainAutoreleasedReturnValue",
        ]

        func renderReturnValue(_ rawValue: AbstractValue, before address: UInt64) -> String {
            let value = sanitizeValue(rawValue)
            // If this exact expression was just stored to a known ivar, return
            // the ivar's new value. This turns load/add/store/mov/ret into the
            // source-like `_count += delta; return _count` form.
            let matchingStore = analysis.selfFieldAccesses
                .filter { candidate, access in
                    candidate < address && access.isWrite
                        && access.storedValue.map(sanitizeValue) == value
                }
                .max(by: { $0.key < $1.key })?.value
            if let matchingStore,
               let name = fieldName(at: matchingStore.offset, bytes: matchingStore.bytes) {
                return fieldPath(name)
            }
            return renderValue(value, depth: 0)
        }

        func collectCallResults(in value: AbstractValue, into consumed: inout Set<UInt64>) {
            switch value {
            case .callResult(let address):
                consumed.insert(address)
            case .binary(_, let lhs, let rhs):
                collectCallResults(in: lhs, into: &consumed)
                collectCallResults(in: rhs, into: &consumed)
            case .aggregate(let values):
                for value in values { collectCallResults(in: value, into: &consumed) }
            default:
                break
            }
        }

        var consumedCallResults = Set<UInt64>()
        for access in analysis.selfFieldAccesses.values {
            if let value = access.storedValue {
                collectCallResults(in: value, into: &consumedCallResults)
            }
            for value in access.storedValues ?? [] {
                collectCallResults(in: value, into: &consumedCallResults)
            }
        }
        for insn in function.instructions {
            if let site = sites[insn.address],
               DisassembledFunction.calleeName(of: insn)
                .map({ !DisassembledFunction.isRuntimeNoise($0) }) ?? true {
                for value in site.arguments {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
                for value in site.stackArguments {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
            }
            guard function.objcMethod.map({ !$0.returnsVoid }) == true,
                  let value = analysis.exitValues[insn.address]
            else { continue }
            if insn.controlFlow == .return {
                collectCallResults(in: value, into: &consumedCallResults)
            } else if insn.controlFlow == .branch,
                      let callee = DisassembledFunction.calleeName(of: insn),
                      passthroughReturnHelpers.contains(where: callee.hasPrefix)
                        || !DisassembledFunction.isRuntimeNoise(callee) {
                collectCallResults(in: value, into: &consumedCallResults)
            }
        }

        let instructions = function.instructions.map { insn -> Instruction in
            var sourceNotes: [String] = []
            var sourceType = insn.sourceType

            // A `self` field access: the differentiator. `ldp x19, x20, [x20,
            // #0x20]` inside Dog.breed.getter is a 16-byte read of self.breed.
            if let access = analysis.selfFieldAccesses[insn.address] {
                if let field = fieldInfo(at: access.offset, bytes: access.bytes) {
                    sourceType = field.type
                    let name = field.names.count == 1
                        ? field.names[0] : "{\(field.names.joined(separator: ", "))}"
                    sourceNotes.append(access.isAddressOf
                        ? "&\(fieldPath(name))"
                        : (access.isWrite
                            ? fieldWrite(access, field: field)
                            : fieldPath(name)))
                }
            }

            let callee = DisassembledFunction.calleeName(of: insn)
            let isObjCNonVoid = function.objcMethod.map { !$0.returnsVoid } == true
            if isObjCNonVoid, let rawExit = analysis.exitValues[insn.address] {
                let exit = sanitizeValue(rawExit)
                if insn.controlFlow == .return, exit != .unknown {
                    sourceNotes.append("return \(renderReturnValue(exit, before: insn.address))")
                } else if insn.controlFlow == .branch, let callee {
                    if passthroughReturnHelpers.contains(where: callee.hasPrefix), exit != .unknown {
                        sourceNotes.append("return \(renderReturnValue(exit, before: insn.address))")
                    } else if !DisassembledFunction.isRuntimeNoise(callee),
                              let values = argumentsByAddress[insn.address] {
                        sourceNotes.append("return \(callExpression(callee: callee, values: values))")
                    }
                }
            }

            if insn.controlFlow == .branch, let callee,
               let site = sites[insn.address],
               let helper = objcHelperStatement(callee: callee, site: site) {
                sourceNotes.append(helper)
            }

            if function.objcMethod?.isInitializer == true,
               insn.controlFlow == .call,
               let callee, callee.hasPrefix("objc_msgSendSuper"),
               let values = argumentsByAddress[insn.address] {
                sourceNotes.append("self = \(callExpression(callee: callee, values: values))")
            }

            guard let site = sites[insn.address] else {
                guard !sourceNotes.isEmpty || consumedCallResults.contains(insn.address) else { return insn }
                let merged = ([insn.annotation] + sourceNotes).compactMap { $0 }.joined(separator: "  ")
                return Instruction(
                    address: insn.address, text: insn.text, annotation: merged,
                    controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                    callArguments: insn.callArguments, callSelf: insn.callSelf,
                    resultConsumed: consumedCallResults.contains(insn.address),
                    sourceType: sourceType, detail: insn.detail
                )
            }

            // x20 is `self` only under the Swift calling convention; for any
            // other callee it's a callee-saved register the caller happens to be
            // using, and calling it `self` would be a fabrication.
            let selfText: String? = {
                guard Self.isSwiftCall(insn, swiftTargets: swiftTargets),
                      site.selfValue != .unknown
                else { return nil }
                return renderValue(site.selfValue, depth: 0)
            }()

            let rendered: [String] = (argumentsByAddress[insn.address]).map { values in
                // Clamp a fixed-ABI callee's arguments to its real arity before
                // rendering the top-level statement, so a stale live register does
                // not surface as a fabricated trailing argument (`abort([? x])`).
                let clamped = callee.map { normalizedArguments(callee: $0, values: values) } ?? values
                return renderArguments(clamped, depth: 0)
            } ?? []
            guard !rendered.isEmpty || selfText != nil || !sourceNotes.isEmpty
                    || consumedCallResults.contains(insn.address)
            else { return insn }

            var notes = sourceNotes
            if let selfText { notes.append("self=\(selfText)") }
            if !rendered.isEmpty { notes.append("args(" + rendered.joined(separator: ", ") + ")") }
            let merged = ([insn.annotation] + notes).compactMap { $0 }.joined(separator: "  ")
            return Instruction(
                address: insn.address, text: insn.text, annotation: merged,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                callArguments: rendered.isEmpty ? nil : rendered,
                callSelf: selfText, resultConsumed: consumedCallResults.contains(insn.address),
                sourceType: sourceType, detail: insn.detail
            )
        }
        return DisassembledFunction(
            symbol: function.symbol, demangledName: function.demangledName,
            startAddress: function.startAddress, instructions: instructions, source: function.source,
            objcMethod: function.objcMethod
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
