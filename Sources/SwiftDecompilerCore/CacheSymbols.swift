import Foundation
import MachOKit

/// Reads bytes at VM addresses out of a dyld shared cache, transparently
/// crossing subcache files.
///
/// A cache image's `__DATA_CONST` (and often its `__text`) lives in a *different*
/// subcache file than its Mach-O header, and `MachOFile`'s own reader only
/// reaches the header's subcache — so `machO.fileOffset(of:)` returns nil for
/// those addresses. Every cache read has to go through the full cache instead.
final class CacheReader {
    private let full: FullDyldCache
    private var handles: [URL: FileHandle] = [:]

    init(full: FullDyldCache) { self.full = full }
    deinit { for handle in handles.values { try? handle.close() } }

    func bytes(at address: UInt64, count: Int) -> Data? {
        guard let fullOffset = full.fileOffset(of: address),
              let subcache = full.cache(forFileOffset: fullOffset),
              let url = full.url(forFileOffset: fullOffset),
              let localOffset = subcache.fileOffset(of: address)
        else { return nil }
        let handle: FileHandle
        if let existing = handles[url] {
            handle = existing
        } else {
            guard let opened = try? FileHandle(forReadingFrom: url) else { return nil }
            handles[url] = opened
            handle = opened
        }
        guard (try? handle.seek(toOffset: localOffset)) != nil else { return nil }
        return try? handle.read(upToCount: count)
    }

    /// A NUL-terminated string at a VM address.
    func cString(at address: UInt64, limit: Int = 256) -> String? {
        guard let data = bytes(at: address, count: limit),
              let end = data.firstIndex(of: 0), end > data.startIndex
        else { return nil }
        return String(decoding: data[data.startIndex..<end], as: UTF8.self)
    }

    /// The VM address a rebased pointer slot holds.
    ///
    /// Note `FullDyldCache.resolveRebase` returns the target VM address outright,
    /// unlike `MachOFile.resolveRebase`, which returns an image-relative offset.
    func pointer(at slot: UInt64) -> UInt64? {
        guard let fileOffset = full.fileOffset(of: slot) else { return nil }
        return full.resolveRebase(at: fileOffset)
    }
}

/// Names call targets that leave a dyld-cache image.
///
/// A cache image's calls into other images don't branch directly. They target a
/// stub island living in a cache region outside every image:
///
///     adrp x17, <page>
///     add  x17, x17, #<off>   ; a pre-bound pointer slot
///     ldr  x16, [x17]
///     braa x16, x17
///
/// Neither the island nor its eventual target is inside the calling image, so
/// the per-image reference index can name neither — which is why roughly 78% of
/// a cache image's calls otherwise disassemble as anonymous addresses. Following
/// the island to its pre-bound destination and looking that up in the owning
/// image's exports recovers the name.
final class CacheSymbolResolver {
    private let reader: CacheReader
    private let engine: CapstoneEngine
    private let tracer = ValueTracer()
    /// Sorted by text range, for a binary search on the call target.
    private var images: [(range: Range<UInt64>, base: UInt64, image: MachOFile)] = []
    private var exportsByImage: [Int: [UInt64: String]] = [:]
    private var resolved: [UInt64: String?] = [:]

    /// Nil unless `machO` is a shared-cache image (there is nothing to resolve
    /// for a standalone binary, whose stubs objdump already names).
    init?(machO: MachOFile) {
        guard let full = machO.fullCache, let engine = CapstoneEngine() else { return nil }
        self.reader = CacheReader(full: full)
        self.engine = engine
        // Text ranges and bases only — cheap. Export tries are read lazily, per
        // image, and only for images something actually calls into.
        for image in full.machOFiles() {
            guard let text = image.sections.first(where: {
                $0.segmentName == "__TEXT" && $0.sectionName == "__text"
            }), text.size > 0,
                  let base = Self.imageBase(of: image)
            else { continue }
            let start = UInt64(text.address)
            images.append((start ..< (start + UInt64(text.size)), base, image))
        }
        images.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// An image's load address: its `__TEXT` segment's vmaddr.
    ///
    /// Emphatically *not* `address(forOffset: 0)` — for a cache image that
    /// returns the whole cache's base (0x180000000), not the image's own, and
    /// export offsets are relative to the image. `segments` is an existential, so
    /// this reads the concrete segment64 load command.
    private static func imageBase(of image: MachOFile) -> UInt64? {
        image.loadCommands
            .infos(of: LoadCommand.segment64)
            .first { $0.segmentName == "__TEXT" }
            .map { UInt64($0.vmaddr) }
    }

    /// A name for a call target, following a stub island when the address isn't
    /// code in any image.
    func name(forCallTarget address: UInt64) -> String? {
        if let cached = resolved[address] { return cached }
        let name = resolve(address)
        resolved[address] = name
        return name
    }

    private func resolve(_ address: UInt64) -> String? {
        if let direct = symbol(at: address) { return direct }
        if let selectorStub = selectorStubName(at: address) { return selectorStub }
        guard let target = stubTarget(at: address) else { return nil }
        return symbol(at: target)
    }

    /// Decode a cache-global Objective-C selector stub.
    ///
    /// The shared-cache builder removes each image's `__objc_stubs` and retargets
    /// calls to a compact selector-stub pool in libobjc:
    ///
    ///     adrp x1, <uniqued selector page>
    ///     add  x1, x1, #<selector offset>
    ///     b    _objc_msgSend
    ///
    /// These entries are code inside an image but are not exports, so the normal
    /// exact export lookup intentionally cannot name them. The shape plus a
    /// verified objc dispatcher target proves both the call family and selector.
    private func selectorStubName(at address: UInt64) -> String? {
        guard let bytes = reader.bytes(at: address, count: 12) else { return nil }
        let decoded = engine.disassemble(bytes, address: address)
        guard decoded.count == 3 else { return nil }
        let instructions = decoded.map {
            Instruction(
                address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail
            )
        }
        return Self.selectorStubName(
            in: instructions,
            selectorText: { self.reader.cString(at: $0, limit: 4096) },
            dispatcherName: { self.symbol(at: $0) }
        )
    }

    /// Pure shape recognizer, split out so selector stubs can be regression
    /// tested without depending on the host machine's cache addresses.
    static func selectorStubName(
        in instructions: [Instruction],
        selectorText: (UInt64) -> String?,
        dispatcherName: (UInt64) -> String?
    ) -> String? {
        guard instructions.count == 3,
              case .address(let selectorAddress)? = ValueTracer()
                .finalState(of: Array(instructions.prefix(2)))["x1"],
              let dispatcherAddress = instructions[2].branchTarget,
              let rawDispatcher = dispatcherName(dispatcherAddress)
        else { return nil }
        let dispatcher = rawDispatcher.hasPrefix("_")
            ? String(rawDispatcher.dropFirst()) : rawDispatcher
        guard dispatcher.hasPrefix("objc_msgSend"),
              let selector = selectorText(selectorAddress),
              selector.count <= 4096, ObjCSelectors.isSelectorShaped(selector)
        else { return nil }
        return "\(dispatcher)$\(selector)"
    }

    /// Follow a stub island to the address its pre-bound slot holds.
    private func stubTarget(at address: UInt64) -> UInt64? {
        guard let bytes = reader.bytes(at: address, count: 16) else { return nil }
        let instructions = engine.disassemble(bytes, address: address).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        guard instructions.count >= 3 else { return nil }
        // x16 holds the loaded pointer in both the arm64 (`br x16`) and arm64e
        // (`braa x16, x17`) stub shapes.
        guard case .loaded(let slot)? = tracer.finalState(of: instructions)["x16"] else { return nil }
        return reader.pointer(at: slot)
    }

    /// Exact export match in whichever image owns `address`.
    ///
    /// Reads the **export trie**, not the symbol table. A cross-image call can
    /// only target an exported symbol, so the trie is the semantically correct
    /// source — and `MachOFile.symbols` is unusable here regardless: a cache
    /// image's `__LINKEDIT` may live in another subcache, so the nlist stream
    /// reads as garbage and MachOKit's iterator traps in `numericCast` on a bogus
    /// `n_value` (a fatalError, so it cannot be caught).
    ///
    /// Exact match is the right test: stub targets are function entry points, and
    /// a nearest-preceding search would happily name an unrelated interior
    /// address.
    private func symbol(at address: UInt64) -> String? {
        guard let index = imageIndex(containing: address) else { return nil }
        if exportsByImage[index] == nil {
            var table: [UInt64: String] = [:]
            let base = images[index].base
            for export in images[index].image.exportedSymbols where !export.name.isEmpty {
                // `offset` is a signed Int and is not always a plain image offset
                // — re-exports and absolute symbols carry values that are huge or
                // negative. `UInt64(negative)` traps, so screen them out rather
                // than converting blind.
                guard let offset = export.offset, offset >= 0 else { continue }
                let exportAddress = base &+ UInt64(offset)
                if table[exportAddress] == nil { table[exportAddress] = export.name }
            }
            exportsByImage[index] = table
        }
        return exportsByImage[index]?[address]
    }

    private func imageIndex(containing address: UInt64) -> Int? {
        var low = 0
        var high = images.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if images[mid].range.contains(address) { return mid }
            if address < images[mid].range.lowerBound { high = mid - 1 } else { low = mid + 1 }
        }
        return nil
    }
}
