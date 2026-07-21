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
        /// The tool succeeded and produced output, but nothing in it parsed as an
        /// instruction — while the binary's own `LC_FUNCTION_STARTS` says it has
        /// functions. An empty result is only trustworthy when an independent
        /// source agrees the binary is empty; here one does not, so this is an
        /// analysis failure and must be reported as one rather than returned as
        /// "no functions".
        case parsedNothing(lines: Int, knownStarts: Int)
        public var description: String {
            switch self {
            case .toolFailed(let m): return "llvm-objdump failed: \(m)"
            case .parsedNothing(let lines, let starts):
                return """
                    disassembly parse failed: llvm-objdump produced \(lines) lines but no \
                    instruction was recognised, while LC_FUNCTION_STARTS lists \(starts) \
                    function(s). This is a parser defect, not an empty binary.
                    """
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
        // Cross-check an empty parse against independent binary evidence before
        // believing it. `LC_FUNCTION_STARTS` is emitted by the linker and survives
        // stripping, so it is an oracle the disassembler cannot talk itself out of.
        // Returning [] here unconditionally is what let a leading-whitespace parse
        // bug masquerade as "no functions" on every low-based dylib.
        if parsed.isEmpty {
            let knownStarts = functionStarts(of: machO).count
            guard knownStarts == 0 else {
                throw DisassembleError.parsedNothing(
                    lines: result.stdout.split(separator: "\n").count,
                    knownStarts: knownStarts
                )
            }
            return []
        }
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

    /// Render every function of a cache image **streaming** — decode, analyse,
    /// render, and release one function at a time, never holding the whole
    /// image's instructions. This is the memory fix for the whole-image path:
    /// the array `disassemble(machO:)` holds all decoded instructions at once
    /// (the measured peak), whereas this bounds resident memory to roughly one
    /// function plus the cross-function name index.
    ///
    /// Output is identical to mapping `render` over `disassemble(machO:)` because
    /// it reuses the same building blocks: boundaries are instruction-aligned, so
    /// the spans between sorted boundaries are exactly the functions `segment`
    /// would cut, and each is named by the same `makeFunction` and analysed by
    /// the same `analyzeFunction`.
    ///
    /// Returns the rendered blocks in address order. Only for the unfiltered
    /// whole-image case; callers wanting the `[DisassembledFunction]` array (JSON,
    /// xrefs, analyze) keep using `disassemble(machO:)`.
    public func disassembleStreamingRender(
        machO: MachOFile, render: (DisassembledFunction) -> String
    ) async -> [String] {
        let objcIndex = ObjCMetadataIndex.build(in: machO)
        let labelByAddress = symbolLabels(in: machO)
        guard let text = textSectionBounds(in: machO) else { return [] }
        let textStart = text.address
        let textEnd = text.address + UInt64(text.size)

        var boundarySet = Set(functionStarts(of: machO))
        boundarySet.formUnion(labelByAddress.keys)
        boundarySet.formUnion(objcIndex.addresses)
        // `segment` starts the first function at the first decoded instruction
        // (the text start), even when that address is not itself a boundary.
        boundarySet.insert(textStart)
        let boundaries = boundarySet.filter { $0 >= textStart && $0 < textEnd }.sorted()
        guard !boundaries.isEmpty else { return [] }

        // Metadata names, on the same gate `assemble`/`matchedRanges` use.
        let unlabeled = Set(boundaries).subtracting(labelByAddress.keys)
        var metadataNames: [UInt64: String] = [:]
        if Double(unlabeled.count) > Double(max(boundaries.count, 1)) * 0.25 {
            metadataNames = await MetadataSymbolizer(preset: preset).functionNames(in: machO)
        }

        func span(_ index: Int) -> (start: UInt64, stop: UInt64) {
            (boundaries[index], index + 1 < boundaries.count ? boundaries[index + 1] : textEnd)
        }

        // Cross-function name index. `referenceIndex` and `swiftTargets` read only
        // name-level fields, so name-only stubs (no instructions) suffice.
        let stubs = boundaries.map {
            makeFunction(start: $0, instructions: [], labelByAddress: labelByAddress,
                         metadataNames: metadataNames, objcIndex: objcIndex)
        }
        let cacheSymbols = CacheSymbolResolver(machO: machO)
        var names = referenceIndex(
            functions: stubs, labelByAddress: labelByAddress,
            metadataNames: metadataNames, objcIndex: objcIndex, in: machO
        )
        // Pass 1: gather cross-image call targets, one function's instructions at
        // a time, then resolve once — reproduces `crossImageNames` without holding
        // the whole image.
        var targets = Set<UInt64>()
        for index in boundaries.indices {
            let instructions = capstoneInstructions(in: machO, span: span(index))
            collectUnnamedCallTargets(in: instructions, names: names, into: &targets)
        }
        names = resolveCrossImageNames(targets, into: names, resolver: cacheSymbols)
        let resolver = ReferenceResolver(
            names: names,
            stringRanges: stringSectionRanges(in: machO),
            machO: machO,
            demangleSymbol: { self.demangle($0) },
            selectors: ObjCSelectors.selectorTable(in: machO),
            cfStringRange: sectionRange(named: "__cfstring", in: machO),
            cacheSymbols: cacheSymbols,
            cacheReader: machO.fullCache.map { CacheReader(full: $0) }
        )

        var swiftTargets = Set(labelByAddress.compactMap { address, symbol in
            Self.isSwiftMangled(symbol) ? address : nil
        })
        swiftTargets.formUnion(metadataNames.keys)
        swiftTargets.formUnion(stubs.filter {
            $0.objcMethod == nil && (Self.isSwiftMangled($0.symbol) || $0.source == .metadata)
        }.map(\.startAddress))
        swiftTargets.subtract(objcIndex.addresses)

        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: (try? FieldMapBuilder.build(in: machO)) ?? [:],
            selfIndex: SelfTypeIndex.build(in: machO),
            vtableIndex: VTableIndex.build(in: machO),
            enumCaseIndex: EnumCaseIndex.build(in: machO),
            classTypeIndex: ClassTypeIndex.build(in: machO)
        )

        // Pass 2: decode each span, analyse, render, release. `segment` skips a
        // span that decodes to nothing, so this does too.
        var rendered: [String] = []
        rendered.reserveCapacity(boundaries.count)
        for index in boundaries.indices {
            let instructions = capstoneInstructions(in: machO, span: span(index))
            guard !instructions.isEmpty else { continue }
            let function = makeFunction(
                start: boundaries[index], instructions: instructions,
                labelByAddress: labelByAddress, metadataNames: metadataNames, objcIndex: objcIndex
            )
            rendered.append(render(analyzeFunction(function, context: context)))
        }
        return rendered
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
        // The differentiator's two halves: what lives at an offset (FieldMap),
        // and whether the pointer in x20 is that type (SelfTypeIndex). Both are
        // metadata-sourced, so both survive stripping.
        let fieldMaps = (try? FieldMapBuilder.build(in: machO)) ?? [:]
        let selfIndex = SelfTypeIndex.build(in: machO)
        let vtableIndex = VTableIndex.build(in: machO)
        // No-payload enum case names, so an immediate tag returned from an
        // enum-typed function renders as `.case` instead of a bare integer.
        let enumCaseIndex = EnumCaseIndex.build(in: machO)
        // Class (reference) type names, so a single-register `Optional<SomeClass>`
        // (nil == 0) seeds like a scalar and its `!= nil` reconstructs, while a
        // value-typed (tagged) optional still declines.
        let classTypeIndex = ClassTypeIndex.build(in: machO)
        let context = PerFunctionContext(
            resolver: resolver, swiftTargets: swiftTargets, objcIndex: objcIndex,
            fieldMaps: fieldMaps, selfIndex: selfIndex, vtableIndex: vtableIndex,
            enumCaseIndex: enumCaseIndex, classTypeIndex: classTypeIndex
        )
        functions = functions.map { analyzeFunction($0, context: context) }

        guard let needle = functionFilter?.lowercased(), !needle.isEmpty else {
            return functions
        }
        return functions.filter {
            $0.symbol.lowercased().contains(needle)
                || ($0.demangledName?.lowercased().contains(needle) ?? false)
        }
    }

    /// Cross-function state, built once for a whole image, that the per-function
    /// analysis reads but never mutates. Bundled so the same `analyzeFunction`
    /// runs from both the array path (`assemble`) and the streaming path.
    struct PerFunctionContext {
        let resolver: ReferenceResolver
        let swiftTargets: Set<UInt64>
        let objcIndex: ObjCMetadataIndex
        let fieldMaps: [String: FieldMap]
        let selfIndex: SelfTypeIndex
        let vtableIndex: VTableIndex
        let enumCaseIndex: EnumCaseIndex
        let classTypeIndex: ClassTypeIndex
    }

    /// The complete per-function analysis: resolve references and call targets,
    /// recover the receiver convention and field maps, and enrich call arguments.
    /// Extracted verbatim from `assemble`'s map so both paths produce identical
    /// output by construction; the streaming path calls it one function at a time.
    func analyzeFunction(
        _ rawFunction: DisassembledFunction, context: PerFunctionContext
    ) -> DisassembledFunction {
        var function = annotateReferences(in: rawFunction, resolver: context.resolver)
        function = annotateCallTargets(in: function, resolver: context.resolver)

        let objcMethod = function.objcMethod
        // Runtime-added category IMPs (an accessibility bundle is almost all
        // of them) frequently have no ObjC metadata binding, yet their symbol
        // name carries the full method shape. Recover the receiver convention
        // from the symbol so `self` survives — without it x0 is never seeded
        // and every receiver renders `?`.
        let symbolEntry = objcMethod == nil ? Self.objcEntryFromSymbol(function.symbol) : nil
        let classSelfTypeName = objcMethod == nil && symbolEntry == nil && !context.fieldMaps.isEmpty
            ? Self.selfType(of: function, selfIndex: context.selfIndex, fieldMaps: context.fieldMaps)
            : nil
        // A nonmutating HFA-struct instance method passes `self` decomposed in
        // SIMD registers rather than through x20, so it needs the value-self
        // path even when the name-based `selfType` already found the type (it
        // would otherwise seed x20, which this ABI leaves as garbage). The
        // HFA + no-`[x20]` guards inside confine it to exactly that shape.
        let valueSelf = objcMethod == nil && symbolEntry == nil
            ? Self.swiftValueTypeSelfFields(of: function, fieldMaps: context.fieldMaps)
            : nil
        let selfTypeName = classSelfTypeName ?? valueSelf?.typeName
        let entry: MethodEntryConvention? = if let objcMethod {
            objcMethod.isInitializer
                ? .objectiveCInitializer(argumentCount: objcMethod.argumentCount)
                : .objectiveC(argumentCount: objcMethod.argumentCount)
        } else if let symbolEntry {
            symbolEntry
        } else if let valueSelf {
            .swiftValueInstance(seededRegisters: valueSelf.seeded)
        } else if classSelfTypeName != nil {
            .swiftInstance(scalarArguments: Self.swiftScalarArgumentRegisters(of: function, enumCaseIndex: context.enumCaseIndex, classTypeIndex: context.classTypeIndex) ?? [:])
        } else if let scalarArgs = Self.swiftScalarArgumentRegisters(of: function, enumCaseIndex: context.enumCaseIndex, classTypeIndex: context.classTypeIndex) {
            .swiftFunction(scalarArguments: scalarArgs)
        } else {
            nil
        }
        let fieldMap: FieldMap? = if let objcMethod, !objcMethod.isClassMethod {
            context.objcIndex.fieldMaps[objcMethod.className]
        } else if let className = objcMethod == nil ? Self.objcClassName(fromSymbol: function.symbol) : nil {
            // No binding, but the symbol names the owning class: its ivar
            // layout may still be indexed, so `self->_ivar` can be named.
            context.objcIndex.fieldMaps[className]
        } else if let valueSelf {
            valueSelf.fieldMap
        } else {
            classSelfTypeName.flatMap {
                Self.selfFieldMap(of: function, simpleName: $0, fieldMaps: context.fieldMaps)
            }
        }
        return enrichCallArguments(
            in: function, resolver: context.resolver, swiftTargets: context.swiftTargets,
            entry: entry,
            fieldMap: fieldMap,
            objcFieldSyntax: objcMethod != nil || symbolEntry != nil,
            selfTypeName: selfTypeName, vtableIndex: context.vtableIndex,
            argumentFieldMaps: valueSelf?.argumentFieldMaps ?? [:],
            enumCaseIndex: context.enumCaseIndex,
            argumentEnumTypes: Self.swiftEnumArgumentTypes(of: function, enumCaseIndex: context.enumCaseIndex),
            boolArguments: Self.swiftBoolArgumentIndices(of: function),
            classTypeIndex: context.classTypeIndex
        )
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
        guard resolver != nil else { return names }
        var targets = Set<UInt64>()
        for function in functions {
            collectUnnamedCallTargets(in: function.instructions, names: names, into: &targets)
        }
        return resolveCrossImageNames(targets, into: names, resolver: resolver)
    }

    /// Accumulate call/branch targets not already named, so the streaming path can
    /// gather them one function at a time instead of holding the whole image's
    /// instructions. Split out of `crossImageNames`; the two callers together
    /// reproduce its exact behaviour.
    private func collectUnnamedCallTargets(
        in instructions: [Instruction], names: [UInt64: String], into targets: inout Set<UInt64>
    ) {
        for insn in instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            if let target = insn.branchTarget, names[target] == nil { targets.insert(target) }
        }
    }

    /// Resolve accumulated cross-image call targets to names.
    private func resolveCrossImageNames(
        _ targets: Set<UInt64>, into names: [UInt64: String], resolver: CacheSymbolResolver?
    ) -> [UInt64: String] {
        guard let resolver else { return names }
        var names = names
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

    /// How many function boundaries the binary itself declares, from
    /// `LC_FUNCTION_STARTS`.
    ///
    /// This is the independent oracle for recovery *completeness*: the linker
    /// emits it, it survives stripping, and it is computed without decoding a
    /// single instruction — so it cannot be wrong for the same reason a decoder
    /// is wrong. Recovering far fewer functions than this is evidence of silent
    /// truncation, which is the failure mode that reads exactly like a valid
    /// answer. Callers should compare and say so.
    ///
    /// Zero means the load command is absent (some cache images), not that the
    /// binary has no functions — an absent oracle proves nothing either way.
    public func declaredFunctionCount(in machO: MachOFile) -> Int {
        functionStarts(of: machO).count
    }

    /// VM addresses of every function start from LC_FUNCTION_STARTS, **deduped**.
    ///
    /// The load command is a ULEB128 list of *deltas*, zero-padded to alignment.
    /// Each padding byte decodes as a delta of zero, which reads as "another
    /// function at the same address as the last one", so the raw list ends in a
    /// run of repeats. Measured on the fixtures: 453 raw vs 449 distinct, 182 vs
    /// 176, 172 vs 171 — and the distinct count matches `dyld_info
    /// -function_starts` exactly in every case.
    ///
    /// This matters because the count is used as the **oracle** for recovery
    /// completeness (`declaredFunctionCount`), so an inflated denominator makes
    /// the coverage warning compare against a number the binary does not
    /// actually declare and prints a wrong figure in the `parsedNothing`
    /// diagnostic. The boundary callers were always unaffected — they wrap this
    /// in a `Set` — so deduping here changes counts only.
    private func functionStarts(of machO: MachOFile) -> [UInt64] {
        guard let starts = machO.functionStarts else { return [] }
        var seen: Set<UInt64> = []
        return starts.compactMap { entry in
            let address = UInt64(entry.offset)
            return seen.insert(address).inserted ? address : nil
        }
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
        resolver: ReferenceResolver,
        selfTypeName: String? = nil,
        vtableIndex: VTableIndex = VTableIndex()
    ) -> DisassembledFunction {
        /// Resolve a `blr` target to a (name, address). A class vtable dispatch is
        /// resolved through the class's metadata layout; anything else through the
        /// generic indirect-target resolver.
        func resolve(_ value: AbstractValue) -> (address: UInt64?, name: String)? {
            if case .selfVTableMethod(let offset) = value,
               let selfTypeName,
               let address = vtableIndex.methodAddress(type: selfTypeName, offset: offset),
               let name = resolver.name(at: address) {
                return (address, name)
            }
            return resolver.indirectCallTarget(for: value)
        }
        let instructions = function.instructions.map { insn -> Instruction in
            guard insn.branchTarget == nil,
                  insn.controlFlow == .call || insn.controlFlow == .branch,
                  let value = targets[insn.address],
                  let resolved = resolve(value)
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
        // A type whose SIMPLE name collided was dropped from the map by the
        // collision guard, but its QUALIFIED key survives — so a self type counts
        // as resolved when either key reaches a layout. The SIMPLE name is what is
        // returned: `vtableIndex` is keyed by simple name, and only the field-map
        // lookup prefers the qualified key.
        func resolves(_ simpleName: String) -> Bool {
            selfFieldMap(of: function, simpleName: simpleName, fieldMaps: fieldMaps) != nil
        }
        if let binding = selfIndex.binding(for: function.startAddress) {
            // Authoritative, including when it says no.
            guard binding.isInstance, resolves(binding.selfTypeName) else { return nil }
            return binding.selfTypeName
        }
        guard let fromSymbol = selfTypeFromDemangledName(function.demangledName),
              resolves(fromSymbol)
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
        selfTypeComponents(name).map { $0.parts[$0.typeIndex] }
    }

    /// The FULLY-QUALIFIED self type (`Module.Outer.Type`) — the same components
    /// `selfTypeFromDemangledName` takes the last of. This matches the qualified
    /// keys the field-map builder indexes, so a type whose SIMPLE name collided
    /// (and was dropped by the collision guard) still resolves to its OWN map.
    /// Nil when there is no module prefix to qualify with, so the caller falls
    /// back to the simple name rather than inventing a path.
    static func qualifiedSelfTypeFromDemangledName(_ name: String?) -> String? {
        guard let (parts, typeIndex) = selfTypeComponents(name), typeIndex >= 1 else { return nil }
        return parts[0...typeIndex].joined(separator: ".")
    }

    /// The demangled name's context components plus the index of the self type
    /// among them, or nil when the name does not denote an instance member.
    private static func selfTypeComponents(_ name: String?) -> (parts: [String], typeIndex: Int)? {
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
        return (parts, typeIndex)
    }

    /// The field map for a resolved self type, preferring the QUALIFIED key so a
    /// type whose simple name collided still reaches its OWN layout. The qualified
    /// name must denote the same simple type, so a mismatch can never substitute a
    /// different type's map.
    static func selfFieldMap(
        of function: DisassembledFunction,
        simpleName: String,
        fieldMaps: [String: FieldMap]
    ) -> FieldMap? {
        if let qualified = qualifiedSelfTypeFromDemangledName(function.demangledName),
           qualified.split(separator: ".").last.map(String.init) == simpleName,
           let map = fieldMaps[qualified] {
            return map
        }
        return fieldMaps[simpleName]
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

    /// An `x == 0` / `x != 0` comparison — the truthiness/boolean-test form the
    /// structurer's text path already renders well (a BOOL ivar as `if (self->_f)`,
    /// a `cbz` as `if (!x)`). Baking the value tracer's raw comparison over it
    /// would lose that simplification, so those conditions stay with the text path
    /// and only genuine comparisons (`a >= b`, `x < 0`, `x == 5`) are baked.
    static func isTruthinessTest(_ value: AbstractValue) -> Bool {
        guard case .binary(let op, let lhs, let rhs) = value, op == .equal || op == .notEqual
        else { return false }
        // Equality against 0 or 1 is how a Bool is tested (`_enabled == 1`,
        // `x != 0`); ordering against them (`n > 0`) is a real comparison and is
        // still baked.
        func isBooleanConstant(_ operand: AbstractValue) -> Bool {
            operand == .immediate(0) || operand == .immediate(1)
        }
        // A masked value `(X & 0xff)` is a byte / no-payload-enum-tag extraction,
        // not a Bool: `(tag & 0xff) == 1` is an enum-case check (`d == .green`)
        // that must be baked and named, not deferred to the structurer's raw text
        // path. Only an *unmasked* `X == 0/1` is the Bool truthiness idiom.
        func isMaskedByte(_ operand: AbstractValue) -> Bool {
            if case .binary(.bitAnd, _, .immediate(let mask)) = operand { return mask <= 0xff }
            return false
        }
        if isMaskedByte(lhs) || isMaskedByte(rhs) { return false }
        return isBooleanConstant(lhs) || isBooleanConstant(rhs)
    }

    /// The value register a Swift function returns in.
    enum SwiftReturnRegister { case integer, floating }

    /// The demangled result type of a Swift function or property getter, or nil
    /// when it is `Void`, has no demangled signature, or the signature shape
    /// isn't one a single result type can be read from (a `.modify`/`.read`
    /// coroutine, a `with`/`for`-qualified thunk).
    ///
    /// A function/method spells its result after ` -> `; a property *getter*
    /// demangles as `Type.prop.getter : PropType`.
    static func swiftReturnTypeName(of function: DisassembledFunction) -> String? {
        guard function.objcMethod == nil, let name = function.demangledName else { return nil }
        let returnType: String
        if let arrow = name.range(of: " -> ", options: .backwards) {
            returnType = String(name[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if name.hasSuffix(".getter") == false, name.contains(".getter : "),
                  let colon = name.range(of: " : ", options: .backwards) {
            returnType = String(name[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        guard !returnType.isEmpty, returnType != "()",
              !returnType.contains(" with "), !returnType.contains(" for ")
        else { return nil }
        return returnType
    }

    /// Which single register a Swift function delivers its result in, inferred
    /// from the demangled return type — or nil when the function is `Void`,
    /// returns a value spanning several registers or an indirect buffer
    /// (`String`, tuples, large structs/existentials), or has no demangled
    /// signature. Restricting to single-register returns is what keeps a stale
    /// `x0`/`v0` from being printed as a fabricated return for a type that isn't
    /// actually returned there.
    static func swiftReturnRegister(of function: DisassembledFunction) -> SwiftReturnRegister? {
        guard let returnType = Self.swiftReturnTypeName(of: function) else { return nil }
        // Double/Float come back in v0 (d0/s0), every other single value in x0.
        let floatingTypes: Set<String> = [
            "Swift.Double", "Swift.Float", "Swift.Float16", "Swift.Float32",
            "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat",
        ]
        if floatingTypes.contains(returnType) { return .floating }
        // Multi-register / indirect returns — don't read a single register.
        // `String` is two words; a tuple or a metatype/existential is several.
        if returnType.hasPrefix("("), returnType != "()" { return nil }
        if returnType == "Swift.String" || returnType == "Swift.StaticString" { return nil }
        if returnType.contains(" -> ") { return nil } // returns a closure
        return .integer
    }

    /// The register→source-argument-index map to seed for a Swift free function
    /// or static method whose every parameter is a single-register scalar. In the
    /// Swift calling convention integer/pointer parameters fill x0… and
    /// floating-point ones fill v0… by independent counters, so the two are
    /// tracked separately. Nil for any signature with an aggregate, generic,
    /// `inout`, `String`, or otherwise multi-register parameter (or none), so a
    /// register is never mislabeled `arg k` when the real layout differs.
    static func swiftScalarArgumentRegisters(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> [String: Int]? {
        guard function.objcMethod == nil, let name = function.demangledName,
              Self.isSwiftMangled(function.symbol),
              // A getter/setter/accessor or a name without a call signature has no
              // ordinary parameter list to seed.
              let arrow = name.range(of: " -> ", options: .backwards)
        else { return nil }
        let signature = name[..<arrow.lowerBound]
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: String(signature))
        else { return nil }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        guard !parameters.isEmpty else { return nil }

        var registers: [String: Int] = [:]
        var integerIndex = 0, floatIndex = 0
        for (index, parameter) in parameters.enumerated() {
            switch Self.scalarParameterClass(parameter, enumCaseIndex: enumCaseIndex,
                                             classTypeIndex: classTypeIndex) {
            case .integer:
                guard integerIndex < 8 else { return nil }
                registers["x\(integerIndex)"] = index
                integerIndex += 1
            case .floating:
                guard floatIndex < 8 else { return nil }
                registers["v\(floatIndex)"] = index
                floatIndex += 1
            case nil:
                return nil // not provably single-register — seed nothing
            }
        }
        return registers
    }

    /// Maps each source-parameter index that is a no-payload enum to that enum's
    /// demangled type name, keyed the same way `.argument(index)` is numbered.
    /// This is what lets a `c == .case` comparison over an enum parameter name
    /// the compared tag: the parameter list carries the type, the index carries
    /// the register binding. Empty when the function has no enum parameters or no
    /// demangled signature.
    static func swiftEnumArgumentTypes(
        of function: DisassembledFunction, enumCaseIndex: EnumCaseIndex
    ) -> [Int: String] {
        guard function.objcMethod == nil, let name = function.demangledName,
              Self.isSwiftMangled(function.symbol),
              let arrow = name.range(of: " -> ", options: .backwards)
        else { return [:] }
        let signature = name[..<arrow.lowerBound]
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: String(signature))
        else { return [:] }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        var types: [Int: String] = [:]
        for (index, parameter) in parameters.enumerated() {
            var type = parameter
            if let colon = type.range(of: ": ", options: .backwards) {
                type = String(type[colon.upperBound...])
            }
            type = type.trimmingCharacters(in: .whitespaces)
            if enumCaseIndex.isNoPayloadEnum(type) { types[index] = type }
        }
        return types
    }

    /// The source-parameter indices that are `Swift.Bool`, keyed like
    /// `.argument(index)`. A Bool argument is a 0/1 value, so recognizing it
    /// lets `!b` (lowered `(arg ^ 1) & 1`) fold to `!arg` and `b == true`/`b`
    /// used in a condition read cleanly rather than as a masked integer test.
    static func swiftBoolArgumentIndices(of function: DisassembledFunction) -> Set<Int> {
        guard function.objcMethod == nil, let name = function.demangledName,
              Self.isSwiftMangled(function.symbol),
              let arrow = name.range(of: " -> ", options: .backwards)
        else { return [] }
        let signature = name[..<arrow.lowerBound]
        guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: String(signature))
        else { return [] }
        let parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        var indices: Set<Int> = []
        for (index, parameter) in parameters.enumerated() {
            var type = parameter
            if let colon = type.range(of: ": ", options: .backwards) {
                type = String(type[colon.upperBound...])
            }
            if type.trimmingCharacters(in: .whitespaces) == "Swift.Bool" { indices.insert(index) }
        }
        return indices
    }

    /// The source-parameter indices that are floating-point, plus whether the
    /// function's float type is double-precision. A float immediate is stored as
    /// an IEEE bit pattern; recognizing a float-valued expression (one reaching a
    /// float parameter) lets a literal operand in it render as `3.14` instead of
    /// `0x40091eb851eb851f`. Nil when the function has no floating-point in its
    /// signature, so a non-float body never reinterprets an integer as a float.
    static func swiftFloatArgumentInfo(
        of function: DisassembledFunction
    ) -> (indices: Set<Int>, isDouble: Bool)? {
        guard function.objcMethod == nil, let name = function.demangledName,
              Self.isSwiftMangled(function.symbol),
              let arrow = name.range(of: " -> ", options: .backwards)
        else { return nil }
        let doubles: Set<String> = [
            "Swift.Double", "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat",
        ]
        let floats: Set<String> = ["Swift.Float", "Swift.Float32", "Swift.Float16"]
        func normalize(_ raw: Substring) -> String {
            var type = String(raw)
            if let colon = type.range(of: ": ", options: .backwards) {
                type = String(type[colon.upperBound...])
            }
            return type.trimmingCharacters(in: .whitespaces)
        }
        var indices: Set<Int> = []
        var sawDouble = false, sawFloat = false
        let signature = name[..<arrow.lowerBound]
        if let paramsRange = DisassembledFunction.outermostArgumentListRange(of: String(signature)) {
            for (index, parameter) in DisassembledFunction.splitTopLevelArguments(signature[paramsRange]).enumerated() {
                let type = normalize(parameter[...])
                if doubles.contains(type) { indices.insert(index); sawDouble = true }
                else if floats.contains(type) { indices.insert(index); sawFloat = true }
            }
        }
        let returnType = name[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        if doubles.contains(returnType) { sawDouble = true }
        else if floats.contains(returnType) { sawFloat = true }
        guard sawDouble || sawFloat else { return nil }
        return (indices, sawDouble)
    }

    /// The enum type owning a `…__derived_enum_equals` callee (the compiler's
    /// synthesized enum `Equatable.==`), or nil when the callee isn't that
    /// method. `static Module.Color.__derived_enum_equals` → `Module.Color`.
    static func derivedEnumEqualsType(_ callee: String) -> String? {
        guard let range = callee.range(of: ".__derived_enum_equals") else { return nil }
        var name = String(callee[..<range.lowerBound])
        if let arrow = name.range(of: "→ ", options: .backwards) {
            name = String(name[arrow.upperBound...])
        }
        if name.hasPrefix("static ") { name = String(name.dropFirst("static ".count)) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Render an integer immediate for pseudocode. Small non-negatives print as
    /// decimal; a small negative — the two's-complement bit pattern of a signed
    /// value, e.g. `0xffffffffffffffff` for `-1` — prints as a signed decimal so
    /// a negative literal reads as `-1` rather than a 16-digit hex; everything
    /// else (large positives, bit masks, addresses, hashes) prints as hex, where
    /// the bit pattern is what a reader needs.
    ///
    /// The negative window is deliberately narrow (down to `-0x10000`): a genuine
    /// large *unsigned* value near `UInt64.max` must never be relabelled negative,
    /// and real negative literals are overwhelmingly small in magnitude.
    static func renderImmediate(_ v: UInt64) -> String {
        if v < 4096 { return String(v) }
        let signed = Int64(bitPattern: v)
        if signed < 0, signed >= -0x1_0000 { return String(signed) }
        return "0x" + String(v, radix: 16)
    }

    /// Name a loop-carried induction variable by id — `i`, `j`, `k`, then `i3`, …
    /// (skips `l`/`m`/`n`, which read poorly next to `1` and common loop bounds).
    static func inductionVariableName(_ id: Int) -> String {
        ["i", "j", "k"].indices.contains(id) ? ["i", "j", "k"][id] : "i\(id)"
    }

    /// A constant rendered per its declared type: a `Bool` as `true`/`false`, a
    /// floating-point value as its decimal. A float immediate holds the IEEE-754
    /// bit pattern, which as raw hex (`0x400921f9f01b866e`) reads like a garbage
    /// address; interpreting the bits per the type recovers `3.14159`. Nil when
    /// the type isn't one whose constants need a typed reading — the caller then
    /// falls back to the plain integer rendering.
    static func renderTypedConstant(bits: UInt64, type: String) -> String? {
        switch type {
        case "Swift.Bool":
            if bits == 0 { return "false" }
            if bits == 1 { return "true" }
            return nil
        case "Swift.Double", "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat":
            return String(Double(bitPattern: bits))
        case "Swift.Float", "Swift.Float32":
            return String(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
        default:
            return nil
        }
    }

    /// For a nonmutating instance method of a small HFA-float struct, the SIMD
    /// register → `self` field-offset map to seed (plus the resolved self type
    /// and its field map, so the fields name). `self` arrives decomposed across
    /// `d0…` in that ABI; this is what lets `Vec2.magnitude()` read `self.x`.
    ///
    /// Two structural guards keep it from fabricating: the demangled name must be
    /// an instance method (not `static`, not `.init`) of a type whose layout is a
    /// genuine HFA (`FieldMap.homogeneousFloatFieldOffsets`), and the body must
    /// never use `x20` as a memory base — a `[x20, …]` access proves `self` is the
    /// pointer form (a mutating or indirectly-passed struct, or a class), where
    /// decomposing SIMD registers would be wrong.
    static func swiftValueTypeSelfFields(
        of function: DisassembledFunction, fieldMaps: [String: FieldMap]
    ) -> (typeName: String, fieldMap: FieldMap,
          seeded: [String: AbstractValue], argumentFieldMaps: [Int: FieldMap])? {
        guard function.objcMethod == nil, let name = function.demangledName,
              Self.isSwiftMangled(function.symbol), !name.hasPrefix("static ")
        else { return nil }

        // Two shapes: a method (`Type.method(params) -> Ret`) or a computed
        // property's getter (`Type.property.getter : Ret`, which takes no explicit
        // parameters). `.modify`/`.read` accessors are coroutines whose self is
        // the x20 pointer, so they are excluded.
        let selfTypeName: String
        let parameters: [String]
        if let arrow = name.range(of: " -> ", options: .backwards) {
            let signature = String(name[..<arrow.lowerBound])
            guard let paramsRange = DisassembledFunction.outermostArgumentListRange(of: signature)
            else { return nil }
            let qualifiedMethod = signature[..<signature.index(before: paramsRange.lowerBound)]
            guard let dot = qualifiedMethod.lastIndex(of: ".") else { return nil }
            let methodName = qualifiedMethod[qualifiedMethod.index(after: dot)...]
            guard methodName != "init", !methodName.isEmpty else { return nil }
            selfTypeName = String(qualifiedMethod[..<dot])
            parameters = DisassembledFunction.splitTopLevelArguments(signature[paramsRange])
        } else {
            var base = name
            if let colon = base.range(of: " : ") { base = String(base[..<colon.lowerBound]) }
            guard base.hasSuffix(".getter") else { return nil }
            base = String(base.dropLast(".getter".count)) // Type.property
            guard let propertyDot = base.lastIndex(of: "."),
                  case let typePart = String(base[..<propertyDot]), !typePart.isEmpty,
                  base.index(after: propertyDot) < base.endIndex
            else { return nil }
            selfTypeName = typePart
            parameters = []
        }

        // The type must be a register-passed value struct — a float HFA (self in
        // SIMD registers) or a small integer struct (self in x0[/x1]) — and `self`
        // must not be accessed through x20 (which would be the pointer form).
        guard let selfMap = Self.namedFieldMap(selfTypeName, in: fieldMaps),
              !function.instructions.contains(where: { $0.text.contains("[x20") })
        else { return nil }

        // `self`'s fields fill the leading registers of the appropriate bank;
        // parameters follow — integers in the remaining x…, floats/HFAs in the
        // remaining SIMD registers by their own counters. Any non-float-scalar,
        // non-HFA parameter bails the whole decomposition so the register
        // assignment can't drift.
        var seeded: [String: AbstractValue] = [:]
        var floatIndex = 0
        var integerIndex = 0
        if let selfOffsets = selfMap.homogeneousFloatFieldOffsets {
            for (index, offset) in selfOffsets.enumerated() {
                seeded["v\(index)"] = .selfFieldValue(offset: offset)
            }
            floatIndex = selfOffsets.count
        } else if let selfOffsets = selfMap.wordIntegerFieldOffsetsInRegisters, parameters.isEmpty {
            // A small integer struct shares the general-register bank with its
            // parameters, and (unlike a float HFA in its own SIMD bank) `self`
            // there is passed AFTER the formal parameters — so seeding it as x0/x1
            // is only safe when there are none. Restrict to getters; a method with
            // parameters declines rather than mis-assign registers (which would
            // mis-reconstruct a non-commutative body like `a * k + b`).
            for offset in selfOffsets {
                seeded["x\(offset / 8)"] = .selfFieldValue(offset: offset)
            }
            integerIndex = selfOffsets.count
        } else {
            return nil
        }
        var argumentFieldMaps: [Int: FieldMap] = [:]
        for (parameter, index) in zip(parameters, parameters.indices) {
            switch Self.scalarParameterClass(parameter) {
            case .integer:
                guard integerIndex < 8 else { return nil }
                seeded["x\(integerIndex)"] = .argument(index); integerIndex += 1
            case .floating:
                guard floatIndex < 8 else { return nil }
                seeded["v\(floatIndex)"] = .argument(index); floatIndex += 1
            case nil:
                // The only other shape we decompose is an HFA-float struct.
                guard let map = Self.namedFieldMap(Self.parameterType(parameter), in: fieldMaps),
                      let offsets = map.homogeneousFloatFieldOffsets,
                      floatIndex + offsets.count <= 8
                else { return nil }
                for offset in offsets {
                    seeded["v\(floatIndex)"] = .argumentField(argument: index, offset: offset)
                    floatIndex += 1
                }
                argumentFieldMaps[index] = map
            }
        }
        return (selfMap.typeName, selfMap, seeded, argumentFieldMaps)
    }

    /// A demangled parameter's type, with any `label:` prefix removed.
    private static func parameterType(_ parameter: String) -> String {
        if let colon = parameter.range(of: ": ", options: .backwards) {
            return String(parameter[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return parameter.trimmingCharacters(in: .whitespaces)
    }

    /// A field map for a demangled type name, trying the qualified name then its
    /// last (unqualified) component, since `FieldMap` is keyed unqualified.
    private static func namedFieldMap(_ typeName: String, in fieldMaps: [String: FieldMap]) -> FieldMap? {
        fieldMaps[typeName] ?? typeName.split(separator: ".").last.flatMap { fieldMaps[String($0)] }
    }

    private enum ScalarParameterClass { case integer, floating }

    /// The register class of a demangled parameter, or nil when it isn't provably
    /// a single-register scalar. Deliberately an under-approximation: an unlisted
    /// type (a class reference is single-register too, but unidentifiable by name)
    /// blocks seeding, trading missed parameters for never mislabeling one.
    private static func scalarParameterClass(
        _ parameter: String, enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> ScalarParameterClass? {
        // Demangled Swift signatures list bare types with no argument labels, but
        // tolerate a `label: Type` form defensively by taking the type.
        var type = parameter
        if let colon = type.range(of: ": ", options: .backwards) {
            type = String(type[colon.upperBound...])
        }
        type = type.trimmingCharacters(in: .whitespaces)
        let floating: Set<String> = [
            "Swift.Double", "Swift.Float", "Swift.Float16", "Swift.Float32",
            "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat",
        ]
        if floating.contains(type) { return .floating }
        let integers: Set<String> = [
            "Swift.Int", "Swift.UInt", "Swift.Int8", "Swift.Int16", "Swift.Int32",
            "Swift.Int64", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
            "Swift.Bool", "Swift.OpaquePointer", "Swift.UnsafeRawPointer",
            "Swift.UnsafeMutableRawPointer",
        ]
        if integers.contains(type) { return .integer }
        if Self.isSingleRegisterPointer(type) { return .integer }
        // A pointer optional is nil-or-a-pointer in ONE register (nil == 0), so it
        // seeds like a scalar — which is what lets `x ?? f` over a pointer optional
        // reconstruct via the `cbz`/diamond select. A tagged optional (`Int?`,
        // multi-register) is deliberately NOT matched here.
        if type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") {
            let inner = String(type.dropFirst("Swift.Optional<".count).dropLast())
            if Self.isSingleRegisterPointer(inner) { return .integer }
        }
        // A reference (class) optional is also nil-or-a-pointer in ONE register
        // (nil == 0), so it seeds like a scalar — which lets `r != nil` / `r ?? x`
        // reconstruct. A value-typed (tagged) optional is not a class and stays
        // unseeded here.
        if classTypeIndex.referenceOptionalInner(type) != nil { return .integer }
        // A no-payload enum is a trivial integer tag in one register, so it seeds
        // like a scalar — which is what lets `c == .case` over an enum parameter
        // reconstruct. Payload enums are absent from the index and stay unseeded.
        if enumCaseIndex.isNoPayloadEnum(type) { return .integer }
        return nil
    }

    /// A single-register pointer type (nil-representable as 0).
    private static func isSingleRegisterPointer(_ type: String) -> Bool {
        ["Swift.OpaquePointer", "Swift.UnsafeRawPointer", "Swift.UnsafeMutableRawPointer"]
            .contains(type)
            || type.hasPrefix("Swift.UnsafePointer<")
            || type.hasPrefix("Swift.UnsafeMutablePointer<")
    }

    private func enrichCallArguments(
        in function: DisassembledFunction,
        resolver: ReferenceResolver,
        swiftTargets: Set<UInt64>,
        entry: MethodEntryConvention?,
        fieldMap: FieldMap?,
        objcFieldSyntax: Bool,
        selfTypeName: String? = nil,
        vtableIndex: VTableIndex = VTableIndex(),
        argumentFieldMaps: [Int: FieldMap] = [:],
        enumCaseIndex: EnumCaseIndex = EnumCaseIndex(),
        argumentEnumTypes: [Int: String] = [:],
        boolArguments: Set<Int> = [],
        classTypeIndex: ClassTypeIndex = ClassTypeIndex()
    ) -> DisassembledFunction {
        // Floating-point signature info: which arguments are float, and whether
        // the function's float type is double-precision — so a literal operand
        // in a float-valued expression renders as a decimal, not IEEE bits.
        let floatInfo = Self.swiftFloatArgumentInfo(of: function)
        // Per-argument recovered types (Phase-1 lattice), computed once from the
        // signature. The typed source the boolean path consults to decide whether
        // an unsigned machine comparison reads as a signed range check.
        let argumentTypes = TypeInference.argumentTypes(of: function, classTypeIndex: classTypeIndex)

        /// A source-level field path for this method convention.
        func fieldPath(_ name: String) -> String {
            objcFieldSyntax ? "self->\(name)" : "self.\(name)"
        }

        /// Render a by-value struct argument's field — `arg1.y` — from the
        /// parameter's own field map, falling back to a byte offset.
        func argumentFieldName(argument: Int, offset: Int) -> String {
            if case .success(let hit)? = argumentFieldMaps[argument]?.lookup(offset: offset, bytes: 1) {
                switch hit {
                case .whole(let name, _), .part(let name, _, _, _):
                    return "arg\(argument).\(name)"
                case .spans:
                    break
                }
            }
            return "arg\(argument)[0x\(String(offset, radix: 16))]"
        }

        /// Resolve a vtable-dispatch byte offset to the method `self`'s class
        /// calls there — the demangled name of its implementation. Nil when
        /// `self`'s type is unknown or the slot is an inherited (superclass) one
        /// this class's descriptor doesn't list.
        func resolveVTableMethod(_ offset: Int) -> String? {
            guard let selfTypeName,
                  let address = vtableIndex.methodAddress(type: selfTypeName, offset: offset)
            else { return nil }
            return resolver.name(at: address)
        }

        /// `self`'s own getters/setters, keyed by resolved method name, so a
        /// vtable dispatch to one renders as `self.property` (or `self.property =`)
        /// instead of `Type.property.getter(…)` with stale argument registers.
        let selfAccessors: [String: (property: String, isGetter: Bool)] = {
            guard let selfTypeName else { return [:] }
            var map: [String: (String, Bool)] = [:]
            for address in vtableIndex.methodAddresses(type: selfTypeName) {
                guard let name = resolver.name(at: address),
                      let access = DisassembledFunction.swiftAccessorProperty(name)
                else { continue }
                map[name] = access
            }
            return map
        }()

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
            case .unary(let op, let operand):
                let operand = sanitizeValue(operand)
                return operand == .unknown ? .unknown : .unary(op, operand)
            case .select(let condition, let whenTrue, let whenFalse):
                let c = sanitizeValue(condition)
                let t = sanitizeValue(whenTrue)
                let f = sanitizeValue(whenFalse)
                guard c != .unknown, t != .unknown, f != .unknown else { return .unknown }
                return .select(condition: c, whenTrue: t, whenFalse: f)
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
            resolver: resolver, selfTypeName: selfTypeName, vtableIndex: vtableIndex
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
        guard !sites.isEmpty || !analysis.selfFieldAccesses.isEmpty
                || !analysis.exitValues.isEmpty || !analysis.exitFloatValues.isEmpty
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

        /// Reconstruct an array literal from the values stored into its allocation.
        /// Only a homogeneous literal — exactly `count` element stores, no boxed
        /// `[Any]` type-metadata interleaved — is rendered `[e0, …]`; anything else
        /// (a boxed existential array, an unrecovered element) stays `[…]`, so the
        /// contents are never fabricated.
        func renderArrayLiteral(site: UInt64, count: Int, depth: Int) -> String {
            let stored = analysis.arrayElements[site] ?? [:]
            guard count > 0, stored.count == count, depth < 5 else { return "[…]" }
            var elements: [String] = []
            for (_, value) in stored.sorted(by: { $0.key < $1.key }) {
                let rendered = renderValue(sanitizeValue(value), depth: depth + 1)
                guard rendered != "?", !DisassembledFunction.isGenericPlumbingArgument(rendered)
                else { return "[…]" }
                elements.append(rendered)
            }
            return "[\(elements.joined(separator: ", "))]"
        }

        /// The enum-case name for a compared operand, when it is a bare tag
        /// immediate of a known no-payload enum — `enumType` from a
        /// `__derived_enum_equals` callee, else inferred from a seeded enum
        /// argument on the other side. Nil declines to the operand's raw form.
        func enumCaseOperand(_ value: AbstractValue, enumType: String?) -> String? {
            guard let enumType, case .immediate(let tag) = sanitizeValue(value),
                  tag <= UInt64(Int.max),
                  let name = enumCaseIndex.caseName(ofEnum: enumType, tag: Int(tag))
            else { return nil }
            return "\(enumType).\(name)"
        }

        /// The enum type of a comparison operand that is a seeded no-payload enum
        /// argument, unwrapping the optimizer's `& 0xFF` tag-extraction mask.
        func enumArgumentType(of value: AbstractValue) -> String? {
            switch value {
            case .argument(let index):
                return argumentEnumTypes[index]
            case .binary(.bitAnd, let inner, .immediate(let mask))
                where mask == 0xFF || mask == 0xFFFF || mask == 0xFFFF_FFFF:
                return enumArgumentType(of: inner)
            default:
                return nil
            }
        }

        /// The operand render for a comparison side: the enum case name when it is
        /// a literal tag, the raw expression (mask stripped for a seeded enum arg)
        /// otherwise.
        func comparisonOperand(_ value: AbstractValue, enumType: String?, depth: Int) -> String {
            if let cased = enumCaseOperand(value, enumType: enumType) { return cased }
            // A seeded enum arg wrapped in `& 0xFF` is just the arg — the mask is
            // the tag extraction, redundant once we know it is an enum.
            if enumArgumentType(of: value) != nil,
               case .binary(.bitAnd, let inner, _) = value {
                return renderValue(inner, depth: depth + 1)
            }
            return renderValue(value, depth: depth + 1)
        }

        /// The inverse comparison operator, or nil when `op` isn't a comparison —
        /// which doubles as the "is this a comparison?" gate (so an arithmetic
        /// `enumArg + 1` never routes through the enum-naming path).
        func invertedComparison(_ op: AbstractBinaryOperator) -> AbstractBinaryOperator? {
            switch op {
            case .equal: return .notEqual
            case .notEqual: return .equal
            case .less: return .greaterEqual
            case .lessEqual: return .greater
            case .greater: return .lessEqual
            case .greaterEqual: return .less
            case .unsignedLess: return .unsignedGreaterEqual
            case .unsignedLessEqual: return .unsignedGreater
            case .unsignedGreater: return .unsignedLessEqual
            case .unsignedGreaterEqual: return .unsignedLess
            default: return nil
            }
        }

        /// The mirrored comparison — `a op b` ⇔ `b mirror(op) a` — for putting a
        /// constant operand on the right (`1 == arg0` → `arg0 == 1`, `0 < arg0` →
        /// `arg0 > 0`), which reads like the Swift source rather than the lowered
        /// `subs`/`cbz` form. Nil for a non-comparison (never reordered).
        func mirroredComparison(_ op: AbstractBinaryOperator) -> AbstractBinaryOperator? {
            switch op {
            case .equal: return .equal
            case .notEqual: return .notEqual
            case .less: return .greater
            case .lessEqual: return .greaterEqual
            case .greater: return .less
            case .greaterEqual: return .lessEqual
            case .unsignedLess: return .unsignedGreater
            case .unsignedLessEqual: return .unsignedGreaterEqual
            case .unsignedGreater: return .unsignedLess
            case .unsignedGreaterEqual: return .unsignedLessEqual
            default: return nil
            }
        }

        /// Whether a value is provably a boolean (0/1) expression: a comparison,
        /// a `Bool` parameter, a synthesized `==`, the `& 1`/`^ 1` normalization
        /// of one, a `0`/`1` literal, or a select both of whose arms are boolean.
        /// This is the gate for reconstructing `&&`/`||` — folding requires the
        /// non-literal arm to be a proven boolean, so a genuine integer ternary
        /// carrying a `0`/`1` is never mislabelled a logical operator.
        func isBooleanValued(_ value: AbstractValue) -> Bool {
            switch value {
            case .binary(let op, let lhs, let rhs):
                if invertedComparison(op) != nil { return true }
                if (op == .bitAnd || op == .bitXor), case .immediate(1) = rhs {
                    return isBooleanValued(lhs)
                }
                return false
            case .argument(let index):
                return boolArguments.contains(index)
            case .immediate(let k):
                return k == 0 || k == 1
            case .callResult(let addr):
                return calleeByAddress[addr].map {
                    $0.contains("__derived_enum_equals") || $0.contains("__derived_struct_equals")
                } ?? false
            case .select(_, let whenTrue, let whenFalse):
                return isBooleanValued(whenTrue) && isBooleanValued(whenFalse)
            default:
                return false
            }
        }

        /// Render a value known to be boolean, negated if asked — preferring
        /// `renderBoolean` (which inverts a comparison cleanly), else the plain
        /// render with a `!(…)` wrap for a needed negation. Nil if not boolean.
        func renderBooleanOperand(_ value: AbstractValue, negated: Bool, depth: Int) -> String? {
            guard isBooleanValued(value) else { return nil }
            if let b = renderBoolean(value, negated: negated, depth: depth) { return b }
            let plain = renderValue(value, depth: depth)
            return negated ? "!(\(plain))" : plain
        }

        /// A boolean-valued select is a short-circuit `&&`/`||`: `C ? T : F` where
        /// one arm is a `false`/`true` literal and the other is a proven boolean.
        /// `C?1:F`=`C||F`, `C?0:F`=`!C&&F`, `C?T:1`=`!C||T`, `C?T:0`=`C&&T`. Nil
        /// (declining to the raw ternary) when the shape isn't one: a genuine
        /// integer ternary, or both arms literal (bool-vs-int ambiguous).
        func renderLogicalSelect(
            _ condition: AbstractValue, _ whenTrue: AbstractValue, _ whenFalse: AbstractValue,
            negated: Bool, depth: Int
        ) -> String? {
            // `(cond ? 1 : 0)` materializes the boolean `cond`; `(cond ? 0 : 1)`
            // materializes `!cond`. A value identity (same 0/1) — safe regardless
            // of the result type — but only when `cond` is a proven boolean, so a
            // genuine integer ternary with 0/1 arms is left alone.
            if case .immediate(let t) = whenTrue, case .immediate(let f) = whenFalse,
               t <= 1, f <= 1, t != f, isBooleanValued(condition) {
                // t==1 ⇒ cond ; t==0 ⇒ !cond ; then compose the outer negation.
                return renderBooleanOperand(condition, negated: (t == 0) != negated, depth: depth + 1)
            }
            var condNegated: Bool
            var isOr: Bool
            let other: AbstractValue
            if case .immediate(1) = whenTrue { condNegated = false; isOr = true; other = whenFalse }
            else if case .immediate(0) = whenTrue { condNegated = true; isOr = false; other = whenFalse }
            else if case .immediate(1) = whenFalse { condNegated = true; isOr = true; other = whenTrue }
            else if case .immediate(0) = whenFalse { condNegated = false; isOr = false; other = whenTrue }
            else { return nil }
            // The other arm must be a real (non-literal) proven boolean — the
            // proof that this select is boolean-valued, not an integer ternary.
            if case .immediate = other { return nil }
            guard isBooleanValued(other) else { return nil }
            // An outer negation distributes by De Morgan: !(a && b) = !a || !b.
            var otherNegated = false
            if negated { condNegated.toggle(); otherNegated = true; isOr.toggle() }
            guard let c = renderBooleanOperand(condition, negated: condNegated, depth: depth + 1),
                  let o = renderBooleanOperand(other, negated: otherNegated, depth: depth + 1)
            else { return nil }
            return "(\(c) \(isOr ? "||" : "&&") \(o))"
        }

        /// The exposed-unsigned operator notation for a comparison we cannot prove
        /// a signed Swift meaning for — a distinct marker so the reader sees it is
        /// an unsigned machine comparison, never a fabricated signed `<`.
        func unsignedSymbol(_ op: AbstractBinaryOperator) -> String {
            switch op {
            case .unsignedLess: return "<\u{1D41}"          // <ᵁ
            case .unsignedLessEqual: return "<=\u{1D41}"
            case .unsignedGreater: return ">\u{1D41}"
            case .unsignedGreaterEqual: return ">=\u{1D41}"
            default: return op.symbol
            }
        }

        /// Render an unsigned machine comparison (ARM64 cc LO/HS/HI/LS) per the
        /// operand's recovered type — the U1 fix. Three outcomes, never a bare
        /// signed comparison:
        ///  · proven `UInt` operand → a plain `<` (correct for unsigned);
        ///  · proven signed operand compared `<`/`<=` against a non-negative
        ///    constant `N` → the proven range idiom `(0 <= x) && (x < N)`
        ///    (`x <ᵤ N ⇔ 0<=x && x<N` for `N < 2^63`);
        ///  · otherwise → the exposed unsigned operation `x <ᵁ y`.
        func renderUnsignedComparison(
            _ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue,
            negated: Bool, depth: Int
        ) -> String {
            let effectiveOp = negated ? invertedComparison(op)! : op
            // Normalize to (variable side, constant?) with the variable on the left.
            let varSide: AbstractValue, other: AbstractValue, viewOp: AbstractBinaryOperator
            var constant: UInt64?
            if case .immediate(let n) = rhs {
                varSide = lhs; other = rhs; viewOp = effectiveOp; constant = n
            } else if case .immediate(let n) = lhs, let mirror = mirroredComparison(effectiveOp) {
                varSide = rhs; other = lhs; viewOp = mirror; constant = n
            } else {
                varSide = lhs; other = rhs; viewOp = effectiveOp
            }
            let varType = TypeInference.typeOf(varSide, arguments: argumentTypes)
            let x = comparisonOperand(varSide, enumType: nil, depth: depth)

            // Proven unsigned (UInt): the unsigned compare IS a plain Swift `<`.
            if varType.isUnsignedInteger {
                return "(\(x) \(viewOp.signedForm.symbol) "
                    + "\(comparisonOperand(other, enumType: nil, depth: depth)))"
            }
            // Proven signed + non-negative constant + `<`/`<=`: the range idiom.
            if varType.isSignedInteger, let n = constant, n <= UInt64(Int64.max),
               viewOp == .unsignedLess || viewOp == .unsignedLessEqual {
                let cmp = viewOp == .unsignedLess ? "<" : "<="
                return "((0 <= \(x)) && (\(x) \(cmp) \(Self.renderImmediate(n))))"
            }
            // Signedness unknown / unprovable shape: expose the unsigned operation.
            return "(\(x) \(unsignedSymbol(viewOp)) "
                + "\(comparisonOperand(other, enumType: nil, depth: depth)))"
        }

        /// Recognizes enum equality (`c == .case` / `!= .case`) and the boolean
        /// noise around it — the redundant `& 1` normalization mask and the
        /// `^ 1` logical-NOT the compiler emits for `!=`. Returns nil (declining
        /// to the raw form) for anything that isn't a boolean expression it can
        /// improve, so ordinary comparisons render through the normal path.
        func renderBoolean(_ value: AbstractValue, negated: Bool, depth: Int) -> String? {
            switch value {
            case .select(let condition, let whenTrue, let whenFalse):
                // A short-circuit `&&`/`||`.
                return renderLogicalSelect(condition, whenTrue, whenFalse, negated: negated, depth: depth)
            case .argument(let index) where boolArguments.contains(index):
                // A Bool parameter is a boolean value (0/1); `!b` and truthiness
                // tests fold against it, and its raw form is just `arg`.
                return negated ? "!arg\(index)" : "arg\(index)"
            case .binary(.bitAnd, let lhs, .immediate(1)):
                // Redundant boolean-normalization mask; unwrap.
                return renderBoolean(lhs, negated: negated, depth: depth)
            case .binary(.bitXor, let lhs, .immediate(1)):
                // `x ^ 1` is logical NOT of a boolean x.
                return renderBoolean(lhs, negated: !negated, depth: depth)
            case .binary(let op, let lhs, let rhs):
                // Only comparisons are boolean; `invertedComparison` returning
                // non-nil is the gate (so `enumArg + 1` never names `1` a case).
                guard invertedComparison(op) != nil else { return nil }
                // An unsigned machine comparison never renders as a bare signed
                // `<` — its Swift meaning depends on the operand's recovered type.
                if op.isUnsignedComparison {
                    return renderUnsignedComparison(op, lhs, rhs, negated: negated, depth: depth)
                }
                // A single-register (reference) optional compared to 0 is a nil
                // check: `r != 0` reads `r != nil`. Only when the operand's
                // recovered type is `.optional`, so an integer `!= 0` is untouched.
                if op == .equal || op == .notEqual {
                    for (opt, zero) in [(lhs, rhs), (rhs, lhs)] {
                        guard case .immediate(0) = zero,
                              TypeInference.typeOf(opt, arguments: argumentTypes).category == .optional
                        else { continue }
                        let effectiveOp = negated ? invertedComparison(op)! : op
                        return "(\(renderValue(opt, depth: depth + 1)) \(effectiveOp.symbol) nil)"
                    }
                }
                // Boolean falsity/truth test: `(bool == 0)` = !bool, `(bool != 0)`
                // = bool, `(bool == 1)` = bool, `(bool != 1)` = !bool — but only
                // when the other operand is itself a recognized boolean, so a
                // genuine zero-test on an integer (`(arg0 & 1) == 0`) is left
                // alone. This peels the double-negation the compiler emits for
                // `if x == .case { … }` (lowered as `(x == .case) == 0 ? … : …`).
                if op == .equal || op == .notEqual {
                    for (boolSide, litSide) in [(lhs, rhs), (rhs, lhs)] {
                        guard case .immediate(let lit) = litSide, lit == 0 || lit == 1
                        else { continue }
                        let negateFold = (op == .equal) == (lit == 0)
                        if let folded = renderBoolean(
                            boolSide, negated: negated != negateFold, depth: depth
                        ) { return folded }
                    }
                }
                let effectiveOp = negated ? invertedComparison(op)! : op
                // Only intervene when there's something to improve: an enum to
                // name (the immediate side is cased using the arg side's type),
                // or a pending negation. Same type to both — only the immediate
                // operand names; the arg operand isn't an immediate so it renders.
                let enumType = enumArgumentType(of: lhs) ?? enumArgumentType(of: rhs)
                guard enumType != nil || negated else { return nil }
                // For a non-enum comparison, put a lone constant operand on the
                // right (source order) just as the plain-render path does; an
                // enum comparison instead positions the tag via the case naming.
                if enumType == nil, case .immediate = lhs, case .immediate = rhs {
                    // const vs const — no reordering
                } else if enumType == nil, case .immediate = lhs,
                          let mirror = mirroredComparison(effectiveOp) {
                    return "(\(comparisonOperand(rhs, enumType: nil, depth: depth))"
                        + " \(mirror.symbol) \(comparisonOperand(lhs, enumType: nil, depth: depth)))"
                }
                let l = comparisonOperand(lhs, enumType: enumType, depth: depth)
                let r = comparisonOperand(rhs, enumType: enumType, depth: depth)
                return "(\(l) \(effectiveOp.symbol) \(r))"
            case .callResult(let addr):
                // `Enum.__derived_enum_equals(a, b)` is the synthesized `==`.
                guard let callee = calleeByAddress[addr],
                      callee.contains("__derived_enum_equals"),
                      let args = argumentsByAddress[addr], args.count == 2
                else { return nil }
                let enumType = Self.derivedEnumEqualsType(callee)
                let op = negated ? "!=" : "=="
                let l = comparisonOperand(args[0], enumType: enumType, depth: depth)
                let r = comparisonOperand(args[1], enumType: enumType, depth: depth)
                return "(\(l) \(op) \(r))"
            default:
                return nil
            }
        }

        /// Whether an expression is float-valued because it reaches a float
        /// parameter — the signal that a bare `.immediate` beside it is an IEEE
        /// bit pattern, not an integer. Only float ARGUMENTS anchor it: a bare
        /// immediate is exactly the ambiguous case being resolved, so it is never
        /// a base case, and an integer body (no float info) never matches.
        func isFloatValued(_ value: AbstractValue) -> Bool {
            switch value {
            case .argument(let index):
                return floatInfo?.indices.contains(index) ?? false
            case .binary(_, let lhs, let rhs):
                return isFloatValued(lhs) || isFloatValued(rhs)
            case .unary(_, let operand):
                return isFloatValued(operand)
            default:
                return false
            }
        }

        func renderValue(_ value: AbstractValue, depth: Int) -> String {
            if depth < 8, let boolean = renderBoolean(value, negated: false, depth: depth) {
                return boolean
            }
            switch value {
            case .unknown:
                return "?"
            case .immediate(let v):
                return Self.renderImmediate(v)
            case .argument(let index):
                return "arg\(index)"
            case .local(let id):
                return Self.inductionVariableName(id)
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
            case .selfVTableMethod(let offset):
                // A bare method pointer (rarely rendered on its own — the call it
                // feeds is named at the dispatch site). Name it when resolvable.
                return resolveVTableMethod(offset).map { "\($0)" } ?? "?"
            case .argumentField(let argument, let offset):
                return argumentFieldName(argument: argument, offset: offset)
            case .arrayLiteral(let site, let count):
                return renderArrayLiteral(site: site, count: count, depth: depth)
            case .select(let condition, let whenTrue, let whenFalse):
                guard depth < 8 else { return "?" }
                let c = renderValue(condition, depth: depth + 1)
                let t = renderValue(whenTrue, depth: depth + 1)
                let f = renderValue(whenFalse, depth: depth + 1)
                return "(\(c) ? \(t) : \(f))"
            case .binary(let op, let lhs, let rhs):
                guard depth < 8 else { return "?" }
                // A single-register optional compared against 0 is a nil check:
                // `r != 0` reads `r != nil`. Only when the other operand's
                // recovered type is `.optional` (a reference optional we seeded),
                // so an ordinary integer `!= 0` is untouched.
                if op == .equal || op == .notEqual {
                    for (opt, zero) in [(lhs, rhs), (rhs, lhs)] {
                        guard case .immediate(0) = zero,
                              TypeInference.typeOf(opt, arguments: argumentTypes).category == .optional
                        else { continue }
                        return "(\(renderValue(opt, depth: depth + 1)) \(op.symbol) nil)"
                    }
                }
                // In a float-valued binary, a bare immediate operand is an IEEE
                // bit pattern — render it as its decimal per the function's
                // precision, not as a 16-digit integer.
                let floatOp = floatInfo != nil && (isFloatValued(lhs) || isFloatValued(rhs))
                func operand(_ value: AbstractValue) -> String {
                    if floatOp, case .immediate(let bits) = value,
                       let decimal = Self.renderTypedConstant(
                           bits: bits, type: floatInfo!.isDouble ? "Swift.Double" : "Swift.Float") {
                        return decimal
                    }
                    return renderValue(value, depth: depth + 1)
                }
                // `0 - x` is unary negation — the shape the compiler emits for a
                // `-x` with no dedicated negate. (`x - 0` never occurs; the tracer
                // folds the identity.)
                if op == .subtract, case .immediate(0) = lhs {
                    return "-\(operand(rhs))"
                }
                // Normalize `const op var` to `var mirror(op) const` so a
                // comparison reads like source; only when the right side isn't
                // itself a constant (so `const op const` is left as-is).
                if case .immediate = lhs, case .immediate = rhs {
                    // both constant — no reordering
                } else if case .immediate = lhs, let mirror = mirroredComparison(op) {
                    return "(\(operand(rhs)) \(mirror.symbol) \(operand(lhs)))"
                }
                return "(\(operand(lhs)) \(op.symbol) \(operand(rhs)))"
            case .unary(let op, let operand):
                guard depth < 8 else { return "?" }
                let inner = renderValue(operand, depth: depth + 1)
                switch op {
                case .negate: return "-\(inner)"
                case .bitwiseNot: return "~\(inner)"
                case .squareRoot: return "sqrt(\(inner))"
                case .absoluteValue: return "abs(\(inner))"
                }
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
                // `_finalizeUninitializedArray(array)` IS the array — render its
                // argument, which carries the recovered elements.
                if callee.contains("_finalizeUninitializedArray"), let first = inner.first {
                    return renderValue(first, depth: depth + 1)
                }
                // Any other array-literal runtime call collapses to `[…]`.
                if let literal = DisassembledFunction.arrayLiteralPlaceholder(callee: callee) {
                    return literal
                }
                // A vtable dispatch to one of `self`'s own getters is the property
                // access it reads — `self.x` — not a method call with stale args.
                if let access = selfAccessors[callee], access.isGetter {
                    return "self.\(access.property)"
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
                let rawArguments: [String] = renderArguments(callValues, depth: depth + 1)
                // A dynamic cast reads its target type from the metadata argument
                // that the plumbing strip would remove, so match it on the raw
                // arguments first — this is what lets `return x as? T` render as a
                // cast rather than the raw `swift_dynamicCast…(…)` call.
                if let cast = DisassembledFunction.swiftCastIdiom(callee: callee, arguments: rawArguments) {
                    return cast
                }
                // Strip the implicit generic plumbing from the rendered arguments
                // here, where they are still a clean per-argument list — the
                // string-level fold can't, because a demangled closure/`throws`
                // type embeds unbalanced parentheses that defeat its parser.
                let arguments = DisassembledFunction.strippingGenericPlumbing(rawArguments)
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

        // The demangled result type, when it names a no-payload enum whose cases
        // this image publishes — so an immediate tag renders as `Type.case`.
        let returnTypeName: String? = Self.swiftReturnTypeName(of: function)

        func renderReturnValue(_ rawValue: AbstractValue, before address: UInt64) -> String {
            let value = sanitizeValue(rawValue)
            // An immediate returned from an enum-typed function is that enum's
            // case tag: name it (`return Color.green`) instead of printing the
            // raw discriminant. Declines — leaving the integer — for payload
            // enums, unknown/ambiguous enums, and out-of-range tags.
            if case .immediate(let tag) = value, let returnTypeName,
               tag <= UInt64(Int.max),
               let caseName = enumCaseIndex.caseName(ofEnum: returnTypeName, tag: Int(tag)) {
                return "\(returnTypeName).\(caseName)"
            }
            // A constant returned from a Bool- or floating-point-typed function
            // reads per its type: `true`/`false`, or the float decimal instead of
            // the raw IEEE-754 bit pattern.
            if case .immediate(let bits) = value, let returnTypeName,
               let typed = Self.renderTypedConstant(bits: bits, type: returnTypeName) {
                return typed
            }
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
            case .arrayLiteral(let site, _):
                // The `_allocateUninitializedArray` at `site` is folded into the
                // literal, so drop its standalone `[…]` statement.
                consumed.insert(site)
            case .binary(_, let lhs, let rhs):
                collectCallResults(in: lhs, into: &consumed)
                collectCallResults(in: rhs, into: &consumed)
            case .unary(_, let operand):
                collectCallResults(in: operand, into: &consumed)
            case .select(let condition, let whenTrue, let whenFalse):
                collectCallResults(in: condition, into: &consumed)
                collectCallResults(in: whenTrue, into: &consumed)
                collectCallResults(in: whenFalse, into: &consumed)
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
            if function.objcMethod.map({ !$0.returnsVoid }) == true,
               let value = analysis.exitValues[insn.address] {
                if insn.controlFlow == .return {
                    collectCallResults(in: value, into: &consumedCallResults)
                } else if insn.controlFlow == .branch,
                          let callee = DisassembledFunction.calleeName(of: insn),
                          passthroughReturnHelpers.contains(where: callee.hasPrefix)
                            || !DisassembledFunction.isRuntimeNoise(callee) {
                    collectCallResults(in: value, into: &consumedCallResults)
                }
            } else if function.objcMethod == nil, insn.controlFlow == .return,
                      let returnRegister = Self.swiftReturnRegister(of: function) {
                // A Swift return that is a call's result consumes it, so the call
                // isn't also printed as its own statement above the `return`.
                let value = returnRegister == .floating
                    ? analysis.exitFloatValues[insn.address]
                    : analysis.exitValues[insn.address]
                if let value { collectCallResults(in: value, into: &consumedCallResults) }
            }
        }

        // The property a `_modify` accessor's ramp exposes, when this function is
        // one. A `yield_once` coroutine returns its yielded value in x1 (the ramp
        // result is `{ continuation, yields… }`, continuation first); for a stored
        // property that value is `&self.field`. The `.resume.N` continuation
        // yields nothing, so it is excluded. Only the ramp of a `_modify` (never a
        // `.read`, whose yield is a borrowed value, not an address) is recognized.
        let modifyProperty: String? = {
            guard let name = function.demangledName, !name.contains(".resume") else { return nil }
            let base = name.range(of: " : ").map { String(name[..<$0.lowerBound]) } ?? name
            guard base.hasSuffix(".modify") else { return nil }
            let property = base.dropLast(".modify".count)
            guard let dot = property.lastIndex(of: "."),
                  case let leaf = String(property[property.index(after: dot)...]), !leaf.isEmpty
            else { return nil }
            return leaf
        }()

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

            // A Swift function surfaces its return value too — the reason a pure
            // leaf like `Point.distance` otherwise shows nothing. Only a real
            // `ret` (a tail-call branch's x0/v0 hold the callee's arguments, not a
            // result) and only return types delivered in one value register, so a
            // stale register is never printed as a fabricated return.
            if function.objcMethod == nil, insn.controlFlow == .return,
               let returnRegister = Self.swiftReturnRegister(of: function) {
                let rawExit = returnRegister == .floating
                    ? analysis.exitFloatValues[insn.address]
                    : analysis.exitValues[insn.address]
                if let rawExit {
                    let exit = sanitizeValue(rawExit)
                    if exit != .unknown {
                        sourceNotes.append("return \(renderReturnValue(exit, before: insn.address))")
                    }
                }
            }

            // A `_modify` accessor's ramp yields `&self.field` (the mutable
            // storage) in x1. Surfacing it completes the get/set/modify trio and
            // replaces the misleading "pure computation" blank. Rendered ONLY when
            // the body-derived field (x1 at the yield) agrees with the accessor's
            // own property name; a mismatch means the field map is not to be
            // trusted here, so decline rather than name the wrong storage.
            if let modifyProperty, insn.controlFlow == .return,
               let rawYield = analysis.exitYieldValues[insn.address] {
                let offset: Int? = switch rawYield {
                case .selfField(let o): o
                case .selfPointer: 0
                default: nil
                }
                if let offset, let field = fieldInfo(at: offset, bytes: 1),
                   field.names == [modifyProperty] {
                    sourceNotes.append("yield &\(fieldPath(modifyProperty))")
                }
            }

            // A flags-based conditional branch whose comparison the value tracer
            // reconstructed with real operands — baked as a `cond:` note the
            // structurer prefers over its raw-register text back-substitution.
            // Only clean comparisons are baked: a call-result operand is left to
            // the structurer's text path, which inlines the send (`[x isKind…]`)
            // more readably than `([x isKind…] != 0)`.
            if insn.controlFlow == .conditionalBranch,
               let raw = analysis.branchConditions[insn.address] {
                let condition = sanitizeValue(raw)
                var callResults = Set<UInt64>()
                collectCallResults(in: condition, into: &callResults)
                if condition != .unknown, callResults.isEmpty,
                   !Self.isTruthinessTest(condition) {
                    sourceNotes.append("cond: \(renderValue(condition, depth: 0))")
                }
            }
            // Proven loop induction body updates (`total += i` | `i += 1`) on the
            // loop header's branch — the structurer appends them, in order, inside
            // a rotated `while (i < n)`. Joined with `|` (no update contains one).
            if let ordered = analysis.loopUpdates[insn.address], !ordered.isEmpty {
                sourceNotes.append("loop-update: \(ordered.joined(separator: " | "))")
            }

            if insn.controlFlow == .branch, let callee,
               let site = sites[insn.address],
               let helper = objcHelperStatement(callee: callee, site: site) {
                sourceNotes.append(helper)
            }

            // A vtable dispatch to one of `self`'s own setters is the assignment
            // it performs — `self.prop = value` — where the new value is the
            // call's first argument. Getters aren't baked here: their result is
            // consumed inline (rendered as `self.prop` where it's used), so a
            // statement note would duplicate them.
            if let callee, let access = selfAccessors[callee], !access.isGetter,
               let value = sites[insn.address]?.arguments.first {
                let rendered = renderValue(sanitizeValue(value), depth: 0)
                if rendered != "?" {
                    sourceNotes.append("self.\(access.property) = \(rendered)")
                }
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
    ///
    /// The address column is **right-aligned**, so it carries leading whitespace
    /// whenever the binary's `__text` addresses are shorter than objdump's widest
    /// one: an executable linked at `0x100000000` prints `100000e58:` flush left,
    /// but a dylib based near zero prints `     b60:`. Trimming is therefore
    /// mandatory, not cosmetic — without it every instruction line in such a
    /// binary fails the hex test, `parsed` comes back empty, and the unfiltered
    /// path reports "No functions matched" on a binary that disassembles fine
    /// under `--function`.
    private func parseInstruction(_ line: String) -> (UInt64, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let addrPart = line[line.startIndex..<colon].drop(while: { $0 == " " })
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
