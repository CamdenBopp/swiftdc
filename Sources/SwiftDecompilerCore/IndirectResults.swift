import Ccapstone
import Foundation

/// Whether a function reads the x8 it was entered with.
///
/// In every ARM64 convention the incoming x8 is the indirect-result address and
/// nothing else, so a body that reads it before writing it returns through a
/// caller-owned buffer. That is the one fact that decides both halves of
/// indirect-result recovery: the callee must not print a stale x0 as its return,
/// and a caller whose x8 pointed into its own frame has had that frame written.
public enum IndirectResultUse: Equatable, Sendable {
    /// Some path reads the incoming x8 before any write to it.
    case reads
    /// Every path writes x8 (or ends) before reading it, and no path leaves the
    /// function by a tail call that would hand x8 on unread.
    case neverReads
    /// Not provable either way: an external tail call (x8 passes through to the
    /// callee unread), an undecodable instruction, or an x8 use the classifier
    /// does not model (an atomic, a branch through it).
    case unknown
}

extension Disassembler {
    /// Classify a function's use of its incoming x8 by walking the CFG from the
    /// entry while x8 is still the entry value. A read on any such path proves
    /// `.reads`; a path can also stop (x8 written, or a call, which clobbers x8)
    /// or make the answer `.unknown` (a tail call out of the function).
    static func indirectResultUse(of function: DisassembledFunction) -> IndirectResultUse {
        let cfg = FunctionCFG(function)
        guard let entry = cfg.entry else { return .unknown }
        var visited = [Bool](repeating: false, count: cfg.blocks.count)
        visited[entry] = true
        var worklist = [entry]
        var unknown = false
        while let id = worklist.popLast() {
            let block = cfg.blocks[id]
            var stillIncoming = true
            for insn in function.instructions[block.range] {
                let access: X8Access
                let isCall: Bool
                if let detail = insn.detail {
                    access = Self.x8Access(of: insn, detail: detail)
                    isCall = insn.controlFlow == .call
                } else {
                    // No structured operands (a text-only listing): the same
                    // operand-role rules read from the mnemonic and operand text.
                    access = Self.x8Access(ofText: insn.text)
                    let mnemonic = insn.text.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                    isCall = insn.controlFlow == .call || mnemonic == "bl" || mnemonic.hasPrefix("blr")
                }
                switch access {
                case .reads:
                    return .reads
                case .writes:
                    stillIncoming = false
                case .unmodelled:
                    unknown = true
                    stillIncoming = false
                case .none:
                    break
                }
                if !stillIncoming { break }
                if isCall {
                    // The callee clobbers x8 (caller-saved) without reading ours.
                    stillIncoming = false
                    break
                }
                if insn.controlFlow == .branch,
                   insn.branchTarget.map({ cfg.block(startingAt: $0) == nil }) ?? true {
                    // A tail call hands the unread x8 to the callee.
                    unknown = true
                    stillIncoming = false
                    break
                }
            }
            guard stillIncoming else { continue }
            for successor in block.successorIDs where !visited[successor] {
                visited[successor] = true
                worklist.append(successor)
            }
        }
        return unknown ? .unknown : .neverReads
    }

    private enum X8Access { case none, reads, writes, unmodelled }

    /// `x8Access(of:detail:)` for an instruction with no structured operands:
    /// the same roles read from the text. Every operand of a store, compare, or
    /// compare-and-branch is a read; a register branch through x8 is unproven;
    /// elsewhere the first operand is the destination and any later x8 (a
    /// memory base included) is a read.
    private static func x8Access(ofText text: String) -> X8Access {
        let parts = text.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2 else { return .none }
        let mnemonic = parts[0].lowercased()
        let operandText = parts[1].split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let operands = operandText.split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " []!"))
        }
        let isX8 = { (operand: String) in operand == "x8" || operand == "w8" }
        guard let first = operands.firstIndex(where: isX8) else { return .none }
        if mnemonic.hasPrefix("br") || mnemonic.hasPrefix("blr") { return .unmodelled }
        let readsAll = mnemonic.hasPrefix("st") || mnemonic.hasPrefix("cb") || mnemonic.hasPrefix("tb")
            || ["cmp", "cmn", "tst", "ccmp", "ccmn"].contains(mnemonic)
        if readsAll || first > 0 || operands.dropFirst().contains(where: isX8) { return .reads }
        return .writes
    }

    /// How one instruction touches x8, from Capstone's structured operands with
    /// the same operand-role rules the value tracker uses (never Capstone's
    /// access flags, which lie for `cmp` and the atomics).
    private static func x8Access(of insn: Instruction, detail: StructuredInsn) -> X8Access {
        func isX8(_ register: PhysReg?) -> Bool {
            guard let register else { return false }
            return register.kind == .gpr && register.number == 8
        }
        let operands = detail.operands
        // A memory operand reads its base and index; writeback also writes the base.
        var reads = false, writes = false
        for operand in operands {
            if case .memory(let base, let index, _) = operand.operand {
                if isX8(base) || isX8(index) { reads = true }
                if isX8(base), detail.writeback { writes = true }
            }
        }
        let registerIndices = operands.indices.filter { operands[$0].operand.register != nil }
        let x8Indices = registerIndices.filter { isX8(operands[$0].operand.register) }
        if x8Indices.isEmpty { return reads ? .reads : (writes ? .writes : .none) }

        if let flow = insn.controlFlow, flow != .sequential {
            // `cbz x8` / `tbz w8` test the value (a read); `br x8` / `blr x8`
            // branch through it, which is not a shape compiled Swift produces for
            // the result pointer, so it is left unproven.
            return flow == .conditionalBranch ? .reads : .unmodelled
        }
        let id = detail.id.rawValue
        let storeIDs: Set<UInt32> = Set([
            AARCH64_INS_STR, AARCH64_INS_STUR, AARCH64_INS_STRB, AARCH64_INS_STURB,
            AARCH64_INS_STRH, AARCH64_INS_STURH, AARCH64_INS_STP, AARCH64_INS_STNP,
            AARCH64_INS_STLR, AARCH64_INS_STLRB, AARCH64_INS_STLRH, AARCH64_INS_STLUR,
        ].map(\.rawValue))
        let compareIDs: Set<UInt32> = Set([
            AARCH64_INS_ALIAS_CMP, AARCH64_INS_ALIAS_CMN, AARCH64_INS_ALIAS_TST, AARCH64_INS_CCMP, AARCH64_INS_CCMN,
        ].map(\.rawValue))
        let pairLoadIDs: Set<UInt32> = Set([
            AARCH64_INS_LDP, AARCH64_INS_LDNP, AARCH64_INS_LDPSW, AARCH64_INS_LDXP, AARCH64_INS_LDAXP,
        ].map(\.rawValue))
        if storeIDs.contains(id) || compareIDs.contains(id) { return .reads }
        if pairLoadIDs.contains(id) { return reads ? .reads : .writes } // destinations 0 and 1
        // Atomics (`ldadd`, `cas`, `swp`) put their destination in operand 1 and
        // Capstone reports no accesses for them: not modelled for x8.
        let mnemonic = insn.text.split(separator: " ").first.map(String.init) ?? ""
        if mnemonic.hasPrefix("ld") && !mnemonic.hasPrefix("ldr") && !mnemonic.hasPrefix("ldu")
            && !mnemonic.hasPrefix("ldp") && !mnemonic.hasPrefix("ldnp") {
            return .unmodelled
        }
        if mnemonic.hasPrefix("cas") || mnemonic.hasPrefix("swp") { return .unmodelled }
        // Everything else writes its first register operand and reads the rest.
        if reads || x8Indices.contains(where: { $0 != registerIndices.first }) { return .reads }
        return .writes
    }

    /// `memcpy`/`memmove`/`memset` and the compiler's outlined `__swift_memcpyN_M`
    /// value-witness copies: the fixed-ABI helpers the value tracker models as
    /// the stores they perform.
    static func isMemoryHelper(_ callee: String) -> Bool {
        let name = String(callee.drop(while: { $0 == "_" }))
        return name == "memcpy" || name == "memmove" || name == "memset" || name.hasPrefix("swift_memcpy")
    }

    /// Runtime and C-library entry points with a fixed public ABI that never
    /// return through x8. Anything in the Swift and Objective-C runtimes returns
    /// at most two words; the libc helpers here return a pointer or an integer.
    static func isKnownDirectReturnCallee(_ callee: String) -> Bool {
        let name = String(callee.drop(while: { $0 == "_" }))
        if name.hasPrefix("swift_") || name.hasPrefix("objc_") { return true }
        let libc: Set<String> = [
            "memcpy", "memmove", "memset", "memcmp", "bzero", "strlen", "strcmp", "strncmp",
            "malloc", "calloc", "realloc", "free", "abort", "exit", "arc4random", "arc4random_uniform",
            "pthread_mutex_lock", "pthread_mutex_unlock", "os_unfair_lock_lock", "os_unfair_lock_unlock",
            "dispatch_once_f", "dispatch_async", "dispatch_sync",
        ]
        return libc.contains(name) || name.hasPrefix("swift_memcpy")
    }

    /// Whether a demangled Swift return type is provably delivered in registers
    /// (so x8 is unused): the scalar and reference types, `String`, the
    /// single-pointer collections, closures, metatypes, and `Optional` of those.
    /// Any struct, enum, generic, existential, or tuple result returns nil
    /// (unproven) rather than claiming direct delivery.
    static func isKnownDirectReturnType(_ type: String, classTypeIndex: ClassTypeIndex) -> Bool {
        var type = type.trimmingCharacters(in: .whitespaces)
        if type == "()" || type == "Swift.Void" || type == "Swift.Never" { return true }
        if type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") {
            type = String(type.dropFirst("Swift.Optional<".count).dropLast())
            // A tagged optional of a scalar is two registers at most; of a
            // reference it is one. Both are direct.
        }
        let scalars: Set<String> = [
            "Swift.Int", "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
            "Swift.UInt", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
            "Swift.Bool", "Swift.Double", "Swift.Float", "Swift.Float16", "Swift.Float32",
            "Swift.Float64", "Swift.CGFloat", "CoreGraphics.CGFloat", "Swift.String",
            "Swift.Substring", "Swift.Character", "Swift.Unicode.Scalar", "Swift.StaticString",
            "Swift.AnyObject", "Swift.Error", "Swift.AnyKeyPath", "Swift.OpaquePointer",
            "Swift.UnsafeRawPointer", "Swift.UnsafeMutableRawPointer",
        ]
        if scalars.contains(type) { return true }
        if type.hasSuffix(".Type") || type.hasSuffix(".Protocol") { return true }
        for prefix in ["Swift.Array<", "Swift.ContiguousArray<", "Swift.Dictionary<", "Swift.Set<",
                       "Swift.UnsafePointer<", "Swift.UnsafeMutablePointer<",
                       "Swift.UnsafeBufferPointer<", "Swift.UnsafeMutableBufferPointer<",
                       "Swift.Unmanaged<"] where type.hasPrefix(prefix) {
            return true
        }
        if type.contains(" -> ") { return true } // a closure: context + function pointer
        return classTypeIndex.isClass(type)
    }

    /// The result type's demangled name from a demangled function name, or nil
    /// (the same parse `swiftReturnTypeName(of:)` applies to a function's own
    /// signature, exposed for a call target's name).
    static func swiftReturnTypeName(ofDemangled fullName: String) -> String? {
        // A protocol witness's name trails the signature with its conformance
        // (`… -> Swift.String in conformance M.Circle : M.Shape in M`); the
        // result type ends where that clause begins. Left attached, the type
        // read as "not `Swift.String`", and a String-returning witness was
        // treated as a single-register return and printed a stale x0.
        let name = fullName.range(of: " in conformance ").map { String(fullName[..<$0.lowerBound]) } ?? fullName
        let returnType: String
        if let signature = DisassembledFunction.splitSignature(name) {
            returnType = signature.result
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

    /// The stored-property layout of a named struct type when it is complete,
    /// so the whole result can be covered field by field. A class (returned by
    /// reference), a type with a collided simple name, or a layout with an
    /// untrusted suffix returns nil.
    static func completeValueLayout(
        of typeName: String, fieldMaps: [String: FieldMap], classTypeIndex: ClassTypeIndex
    ) -> FieldMap? {
        guard !classTypeIndex.isClass(typeName) else { return nil }
        let map = fieldMaps[typeName]
            ?? typeName.split(separator: ".").last.flatMap { fieldMaps[String($0)] }
        guard let map, map.trustLimitReason == nil, !map.fields.isEmpty else { return nil }
        return map
    }

    /// The callee result conventions for every direct call in `function`, from
    /// the callees' own bodies (same image) or their fixed ABI / return type.
    static func calleeResultConventions(
        in function: DisassembledFunction,
        indirectResultUses: [UInt64: IndirectResultUse],
        resolver: ReferenceResolver,
        fieldMaps: [String: FieldMap],
        classTypeIndex: ClassTypeIndex
    ) -> [UInt64: CalleeResultConvention] {
        var conventions: [UInt64: CalleeResultConvention] = [:]
        for insn in function.instructions where insn.controlFlow == .call {
            let callee = DisassembledFunction.calleeName(of: insn)
            if let target = insn.branchTarget, let use = indirectResultUses[target] {
                switch use {
                case .neverReads:
                    conventions[insn.address] = .direct
                case .reads:
                    let size = callee.flatMap(Self.swiftReturnTypeName(ofDemangled:))
                        .flatMap { completeValueLayout(of: $0, fieldMaps: fieldMaps, classTypeIndex: classTypeIndex) }
                        .map(\.instanceSize)
                    conventions[insn.address] = .indirect(sizeBytes: size)
                case .unknown:
                    break
                }
                continue
            }
            guard let callee else { continue }
            if Self.isKnownDirectReturnCallee(callee) {
                conventions[insn.address] = .direct
            } else if let type = Self.swiftReturnTypeName(ofDemangled: callee),
                      Self.isKnownDirectReturnType(type, classTypeIndex: classTypeIndex) {
                conventions[insn.address] = .direct
            } else if callee.hasSuffix(" -> ()") {
                conventions[insn.address] = .direct
            }
        }
        return conventions
    }
}
