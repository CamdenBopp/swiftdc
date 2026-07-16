import Foundation
import MachOKit

/// Selector names, indexed by both of the ways a call site can reference one.
struct SelectorTable {
    /// `__objc_selrefs` slot → selector. A standalone binary's call sites load
    /// the selector *from* one of these slots.
    var bySelref: [UInt64: String] = [:]
    /// Selector string address → selector. The shared cache uniques selectors at
    /// build time and rewrites each `adrp`+`ldr` of a selref into an `adrp`+`add`
    /// forming the string's address directly — so a cache image's call sites
    /// reference these, and its selrefs go unused.
    var byStringAddress: [UInt64: String] = [:]
}

/// Recovers Objective-C selector names from a binary's ObjC metadata, so that
/// message sends read as `[receiver doThing:]` instead of a bare branch to an
/// unnamed address.
enum ObjCSelectors {
    /// `__objc_selrefs` slot address → selector name.
    ///
    /// Each slot holds a pointer to the selector string. Under chained fixups
    /// the on-disk eight bytes are a fixup encoding, not a usable pointer, so
    /// the rebase has to be resolved rather than read straight out of the file.
    ///
    /// Works for both binary shapes:
    ///
    /// - **Standalone**: the string is in this image's `__objc_methname`, and
    ///   requiring the target to land in that section is a strong check.
    /// - **Shared cache**: the builder zeroes each image's `__objc_methname` and
    ///   coalesces every selector into one cache-global region, so the target
    ///   lands far outside the image and there's no section to check it against —
    ///   validation falls back to the string having selector shape. The slots
    ///   usually live in a different subcache than the header, so both the rebase
    ///   and the string read must go through the full cache.
    static func selectorTable(in machO: MachOFile) -> SelectorTable {
        guard let selrefs = sectionBounds(named: "__objc_selrefs", in: machO) else { return SelectorTable() }
        let methnameRange = sectionBounds(named: "__objc_methname", in: machO)
            .map { $0.address ..< ($0.address + UInt64($0.size)) }
        let cacheReader = machO.fullCache.map { CacheReader(full: $0) }
        let pointerSize = MemoryLayout<UInt64>.size
        var table = SelectorTable()

        for slot in stride(from: selrefs.address,
                           to: selrefs.address + UInt64(selrefs.size),
                           by: pointerSize) {
            guard let target = pointerTarget(at: slot, in: machO, cacheReader: cacheReader) else { continue }
            if let methnameRange, !methnameRange.contains(target) { continue }
            guard let name = selectorText(at: target, in: machO, cacheReader: cacheReader),
                  isSelectorShaped(name)
            else { continue }
            table.bySelref[slot] = name
            table.byStringAddress[target] = name
        }
        return table
    }

    /// The VM address a rebased pointer slot points to. Under chained fixups the
    /// on-disk eight bytes are a fixup encoding, not a usable pointer, so the
    /// rebase must be resolved rather than read straight out of the file.
    ///
    /// The two resolvers do *not* agree: `FullDyldCache.resolveRebase` returns
    /// the target VM address outright, while `MachOFile.resolveRebase` returns an
    /// image-relative offset that must be added to the image base.
    private static func pointerTarget(
        at slot: UInt64,
        in machO: MachOFile,
        cacheReader: CacheReader?
    ) -> UInt64? {
        if let cacheReader { return cacheReader.pointer(at: slot) }
        guard let fileOffset = machO.fileOffset(of: slot),
              let runtimeOffset = machO.resolveRebase(at: UInt64(fileOffset))
        else { return nil }
        return machO.address(forOffset: 0) &+ runtimeOffset
    }

    /// Selectors are identifiers with `:` separators. Requiring that shape is
    /// what keeps a misread pointer from being published as a method name once
    /// the cache path loses the `__objc_methname` bounds check.
    private static func isSelectorShaped(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == ":" }
    }

    /// `__objc_stubs` stub address → `objc_msgSend$<selector>`.
    ///
    /// Since Xcode 14 the compiler emits a per-selector stub rather than
    /// materialising the selector at every call site, so a message send compiles
    /// to a bare `bl <stub>` with no selector anywhere in the caller. Each stub
    /// opens by loading its own selector:
    ///
    ///     adrp x1, <selrefs page>
    ///     ldr  x1, [x1, #<slot>]
    ///     ... tail-call to objc_msgSend ...
    ///
    /// Naming the stub is all that's needed: the existing call-target annotation
    /// then names every site that branches to it, for free.
    ///
    /// The stub's entry point is the `adrp` that begins that load — which is
    /// exactly the address call sites target — so stubs are found by shape
    /// rather than by assuming a fixed stride.
    static func stubNames(
        in machO: MachOFile,
        selectors: [UInt64: String],
        decode: (UInt64, Int) -> [Instruction]
    ) -> [UInt64: String] {
        // A cache image has no `__objc_stubs` — the builder elides them, since
        // it pre-binds every call. This is a no-op there.
        guard !selectors.isEmpty,
              let stubs = sectionBounds(named: "__objc_stubs", in: machO)
        else { return [:] }

        let instructions = decode(stubs.address, stubs.size)
        guard !instructions.isEmpty else { return [:] }

        let tracer = ValueTracer()
        var result: [UInt64: String] = [:]
        for (index, insn) in instructions.enumerated() {
            guard let (mnemonic, register) = ValueTracer.destination(of: insn),
                  mnemonic == "adrp", register == "x1"
            else { continue }
            let window = Array(instructions[index ..< min(index + 2, instructions.count)])
            guard case .loaded(let slot)? = tracer.finalState(of: window)["x1"],
                  let selector = selectors[slot]
            else { continue }
            result[insn.address] = "objc_msgSend$\(selector)"
        }
        return result
    }

    private static func selectorText(
        at address: UInt64,
        in machO: MachOFile,
        cacheReader: CacheReader?
    ) -> String? {
        let text: String?
        if let cacheReader {
            text = cacheReader.cString(at: address)
        } else {
            text = machO.fileOffset(of: address).flatMap { try? machO.readString(offset: Int($0)) }
        }
        guard let text, !text.isEmpty, text.count <= 200 else { return nil }
        return text
    }

    private static func sectionBounds(named name: String, in machO: MachOFile) -> (address: UInt64, size: Int)? {
        guard let section = machO.sections.first(where: { $0.sectionName == name && $0.size > 0 })
        else { return nil }
        return (UInt64(section.address), section.size)
    }
}
