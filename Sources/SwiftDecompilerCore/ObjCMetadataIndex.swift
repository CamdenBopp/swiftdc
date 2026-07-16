import Foundation
import MachOKit
import MachOObjCSection
import ObjCDump

/// A concrete Objective-C method implementation recovered from runtime
/// metadata. Unlike a protocol method description, this has a non-zero IMP and
/// therefore names executable code even after the symbol table is stripped.
public struct ObjCMethodBinding: Sendable, Equatable {
    /// Runtime class receiving the method. Categories keep this separate from
    /// `ownerName` so ivars can still be looked up on the underlying class.
    public let className: String
    public let categoryName: String?
    public let selector: String
    public let typeEncoding: String
    public let isClassMethod: Bool
    /// Header-style declaration decoded from the Objective-C type encoding.
    public let signature: String

    public init(
        className: String,
        categoryName: String? = nil,
        selector: String,
        typeEncoding: String,
        isClassMethod: Bool,
        signature: String
    ) {
        self.className = className
        self.categoryName = categoryName
        self.selector = selector
        self.typeEncoding = typeEncoding
        self.isClassMethod = isClassMethod
        self.signature = signature
    }

    /// `Class(Category)` for a category, otherwise `Class`.
    public var ownerName: String {
        categoryName.map { "\(className)(\($0))" } ?? className
    }

    /// The conventional debugger/class-dump spelling, e.g.
    /// `-[SDWidget setLabel:]` or `+[Factory make]`.
    public var displayName: String {
        "\(isClassMethod ? "+" : "-")[\(ownerName) \(selector)]"
    }

    /// Objective-C's two hidden arguments are `self` and `_cmd`; explicit
    /// arguments are exactly the selector's colon count.
    public var argumentCount: Int { selector.filter { $0 == ":" }.count }

    /// Whether the runtime method encoding declares a void return. Qualifiers
    /// may precede the first type code; stack offsets begin only after it.
    public var returnsVoid: Bool {
        typeEncoding.first { !"rnNoORVA".contains($0) } == "v"
    }

    /// Objective-C initializer families are defined by selector spelling. This
    /// metadata fact is enough to model `self = [super init…]` without relying
    /// on a symbol-table name that stripping removes.
    public var isInitializer: Bool {
        selector == "init" || (selector.hasPrefix("init")
            && selector.dropFirst(4).first.map { !$0.isLowercase } == true)
    }
}

/// Classes/categories parsed once from the runtime sections. Keeping this
/// model separate lets both header emission and code indexing consume the same
/// normalized ObjCDump models.
struct ObjCMetadataSnapshot {
    var classes: [ObjCClassInfo] = []
    var protocols: [ObjCProtocolInfo] = []
    var categories: [ObjCCategoryInfo] = []

    /// Whether reading this class would take MachOObjCSection down its
    /// shared-cache "relative list list" path — which, on a binary that is not a
    /// cache image, traps.
    ///
    /// The low bit of `baseMethods`/`baseProperties`/`baseProtocols` marks a
    /// cache-merged list-of-lists (ObjCClassRODataProtocol.swift:339/370/401:
    /// `guard layout.baseX & 1 == 1`). But those fields hold the RAW on-disk
    /// value, and under chained fixups that is a fixup encoding rather than a
    /// pointer — so outside a shared cache the bit means nothing. When it
    /// happens to be set, the library reads an element count out of a
    /// misinterpreted header and `try!`s the resulting out-of-bounds read
    /// (_FileIOProtocol+.swift:52). That is a fatalError: uncatchable, so the
    /// only way to survive it is not to make the call.
    ///
    /// This is not hypothetical or rare. 39 of the 506 classes in the iOS
    /// simulator's UIKit.axbundle have the bit set spuriously; every one of them
    /// kills the process, and with it a `disasm` run that wanted nothing from
    /// ObjC metadata at all. Stickies has 0, which is why standalone binaries
    /// generally look fine.
    ///
    /// Skipping the class loses its methods and properties. That is a real loss,
    /// and it is the *only* option here — `info(in:)` returns an Optional, so
    /// `compactMap` looks like it provides per-class resilience, but a trap
    /// cannot return nil.
    static func readsCacheOnlyRelativeLists(_ machO: MachOFile, _ classData: ObjCClass64) -> Bool {
        // Inside a real shared cache the marker is meaningful; honour it.
        guard machO.cache == nil, let ro = classData.classROData(in: machO) else { return false }
        func marked(_ pointer: UInt64) -> Bool { pointer > 0 && pointer & 1 == 1 }
        return marked(numericCast(ro.layout.baseMethods))
            || marked(numericCast(ro.layout.baseProperties))
            || marked(numericCast(ro.layout.baseProtocols))
    }

    static func build(
        in machO: MachOFile,
        includeProtocols: Bool = true
    ) -> ObjCMetadataSnapshot {
        let objc = machO.objc
        var snapshot = ObjCMetadataSnapshot()
        if machO.is64Bit {
            snapshot.classes = (objc.classes64 ?? [])
                .filter { !readsCacheOnlyRelativeLists(machO, $0) }
                .compactMap { $0.info(in: machO) }
            if includeProtocols {
                snapshot.protocols = (objc.protocols64 ?? []).compactMap { $0.info(in: machO) }
            }
            snapshot.categories = (objc.categories64 ?? []).compactMap { $0.info(in: machO) }
        } else {
            snapshot.classes = (objc.classes32 ?? []).compactMap { $0.info(in: machO) }
            if includeProtocols {
                snapshot.protocols = (objc.protocols32 ?? []).compactMap { $0.info(in: machO) }
            }
            snapshot.categories = (objc.categories32 ?? []).compactMap { $0.info(in: machO) }
        }
        return snapshot
    }
}

/// IMP address → Objective-C owner/selector/signature, plus per-class ivar
/// layouts. This is the Objective-C counterpart to `SelfTypeIndex`: metadata,
/// rather than symbols, establishes both where a method begins and what `self`
/// means there.
public struct ObjCMetadataIndex: Sendable {
    private let methods: [UInt64: [ObjCMethodBinding]]
    let fieldMaps: [String: FieldMap]

    init(methods: [UInt64: [ObjCMethodBinding]], fieldMaps: [String: FieldMap]) {
        self.methods = methods
        self.fieldMaps = fieldMaps
    }

    /// Primary binding at an implementation address. Multiple selectors may
    /// legally share one IMP; class methods are inserted before category
    /// methods and therefore remain the stable primary name.
    public func binding(for implementationAddress: UInt64) -> ObjCMethodBinding? {
        methods[implementationAddress]?.first
    }

    /// Every selector alias for an IMP.
    public func bindings(for implementationAddress: UInt64) -> [ObjCMethodBinding] {
        methods[implementationAddress] ?? []
    }

    public var count: Int { methods.count }

    public var all: [(address: UInt64, binding: ObjCMethodBinding)] {
        methods.compactMap { address, bindings in
            bindings.first.map { (address, $0) }
        }.sorted { $0.address < $1.address }
    }

    var addresses: Set<UInt64> { Set(methods.keys) }

    /// Build from class and category method lists. Protocol declarations are
    /// intentionally absent: they describe requirements and have no IMP.
    public static func build(in machO: MachOFile) -> ObjCMetadataIndex {
        // Protocol requirements have no IMP. Avoid resolving the whole protocol
        // graph on the disassembly path; header emission still includes it.
        build(snapshot: .build(in: machO, includeProtocols: false), in: machO)
    }

    static func build(snapshot: ObjCMetadataSnapshot, in machO: MachOFile) -> ObjCMetadataIndex {
        guard let text = machO.sections.first(where: {
            $0.segmentName == "__TEXT" && $0.sectionName == "__text" && $0.size > 0
        }) else {
            return ObjCMetadataIndex(methods: [:], fieldMaps: [:])
        }
        let textRange = UInt64(text.address) ..< UInt64(text.address + text.size)
        var methods: [UInt64: [ObjCMethodBinding]] = [:]

        func implementationAddress(_ imp: UInt64) -> UInt64? {
            guard imp > 0 else { return nil }
            // MachOObjCSection normalizes file-backed method IMPs to offsets.
            // Keep the raw-address candidate as a backstop for formats where an
            // already-slid pointer is surfaced instead.
            var candidates = [imp]
            if let offset = Int(exactly: imp) {
                candidates.insert(machO.address(forOffset: offset), at: 0)
            }
            return candidates.first(where: textRange.contains)
        }

        func insert(_ method: ObjCMethodInfo, className: String, categoryName: String? = nil) {
            guard !method.name.isEmpty,
                  let address = implementationAddress(method.imp)
            else { return }
            let binding = ObjCMethodBinding(
                className: className,
                categoryName: categoryName,
                selector: method.name,
                typeEncoding: method.typeEncoding,
                isClassMethod: method.isClassMethod,
                signature: method.headerString
            )
            if methods[address]?.contains(binding) != true {
                methods[address, default: []].append(binding)
            }
        }

        // Classes first: if linker folding makes a category and a class method
        // share one body, the class's own declaration is the primary name.
        for cls in snapshot.classes {
            for method in cls.classMethods { insert(method, className: cls.name) }
            for method in cls.methods { insert(method, className: cls.name) }
        }
        for category in snapshot.categories {
            for method in category.classMethods {
                insert(method, className: category.className, categoryName: category.name)
            }
            for method in category.methods {
                insert(method, className: category.className, categoryName: category.name)
            }
        }

        return ObjCMetadataIndex(
            methods: methods,
            fieldMaps: buildFieldMaps(classes: snapshot.classes)
        )
    }

    /// Build ivar maps with inherited fields when the superclass is present in
    /// the image. Offsets in `ivar_t` are already absolute within the instance,
    /// so an external superclass merely means its names are unavailable; it
    /// does not invalidate the subclass's own offsets.
    private static func buildFieldMaps(classes: [ObjCClassInfo]) -> [String: FieldMap] {
        let classesByName = Dictionary(classes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var ivarCache: [String: [ObjCIvarInfo]] = [:]

        func ivars(of className: String, visiting: Set<String> = []) -> [ObjCIvarInfo] {
            if let cached = ivarCache[className] { return cached }
            guard !visiting.contains(className), let cls = classesByName[className] else { return [] }
            var visiting = visiting
            visiting.insert(className)
            var result = cls.superClassName.map { ivars(of: $0, visiting: visiting) } ?? []
            result.append(contentsOf: cls.ivars)
            // A corrupt image should not create overlapping ranges. Prefer the
            // most-derived declaration at a duplicate absolute offset.
            var byOffset: [Int: ObjCIvarInfo] = [:]
            for ivar in result { byOffset[ivar.offset] = ivar }
            let normalized = byOffset.values.sorted { $0.offset < $1.offset }
            ivarCache[className] = normalized
            return normalized
        }

        var maps: [String: FieldMap] = [:]
        for cls in classes where cls.instanceSize > 0 {
            let fields = ivars(of: cls.name).compactMap { ivar -> (Int, Int, String, String)? in
                guard let layout = ObjCTypeLayoutDecoder.layout(of: ivar.typeEncoding) else { return nil }
                return (ivar.offset, layout.size, ivar.name, ivar.typeEncoding)
            }
            guard !fields.isEmpty else { continue }
            maps[cls.name] = FieldMap(
                typeName: cls.name,
                instanceSize: cls.instanceSize,
                fields: fields
            )
        }
        return maps
    }
}

/// Storage size/alignment for an Objective-C type encoding on 64-bit Apple
/// targets. Method/header decoding is delegated to ObjCDump; this deliberately
/// small ABI decoder exists only so an ivar access can be bounds-checked before
/// attaching a field name to it.
struct ObjCTypeLayout: Sendable, Equatable {
    let size: Int
    let alignment: Int
}

enum ObjCTypeLayoutDecoder {
    static func layout(of encoding: String, pointerSize: Int = 8) -> ObjCTypeLayout? {
        guard !encoding.isEmpty else { return nil }
        var parser = Parser(encoding, pointerSize: pointerSize)
        return parser.parseType()
    }

    private struct Parser {
        let characters: [Character]
        let pointerSize: Int
        var index = 0

        init(_ text: String, pointerSize: Int) {
            self.characters = Array(text)
            self.pointerSize = pointerSize
        }

        var current: Character? { index < characters.count ? characters[index] : nil }

        mutating func advance() { index += 1 }

        mutating func parseType() -> ObjCTypeLayout? {
            // const/in/out/bycopy/byref/oneway/atomic qualifiers do not change
            // storage layout.
            while let c = current, "rnNoORVA".contains(c) { advance() }
            guard let code = current else { return nil }
            advance()

            switch code {
            case "c", "C", "B": return .init(size: 1, alignment: 1)
            case "s", "S": return .init(size: 2, alignment: 2)
            case "i", "I", "f": return .init(size: 4, alignment: 4)
            case "l", "L", "q", "Q", "d", "D": return .init(size: 8, alignment: 8)
            case "t", "T": return .init(size: 16, alignment: 16)
            case "@":
                if current == "?" { advance() } // block
                else { skipQuotedName() }        // @"Class<Protocol>"
                return pointer()
            case "#", ":", "*", "%":
                return pointer()
            case "^":
                // Consume the pointee so nested encodings advance correctly;
                // its own layout cannot change the pointer's storage.
                _ = parseType()
                return pointer()
            case "[": return parseArray()
            case "{": return parseAggregate(end: "}", isUnion: false)
            case "(": return parseAggregate(end: ")", isUnion: true)
            case "b":
                let width = parseNumber()
                guard width > 0 else { return nil }
                return .init(size: (width + 7) / 8, alignment: 1)
            case "j":
                guard let element = parseType() else { return nil }
                return .init(size: element.size * 2, alignment: element.alignment)
            case "v", "?": return nil
            default: return nil
            }
        }

        mutating func parseArray() -> ObjCTypeLayout? {
            let count = parseNumber()
            guard count >= 0, let element = parseType(), current == "]" else { return nil }
            advance()
            return .init(size: element.size * count, alignment: element.alignment)
        }

        mutating func parseAggregate(end: Character, isUnion: Bool) -> ObjCTypeLayout? {
            // Skip the aggregate's tag up to '=' (definition) or the closer
            // (opaque forward declaration).
            while let c = current, c != "=", c != end { advance() }
            guard current == "=" else {
                if current == end { advance() }
                return nil
            }
            advance()

            var size = 0
            var alignment = 1
            var sawField = false
            while let c = current, c != end {
                skipQuotedName() // optional quoted struct field name
                guard current != end, let field = parseType() else { return nil }
                sawField = true
                alignment = max(alignment, field.alignment)
                if isUnion {
                    size = max(size, field.size)
                } else {
                    size = align(size, to: field.alignment) + field.size
                }
            }
            guard current == end, sawField else { return nil }
            advance()
            return .init(size: align(size, to: alignment), alignment: alignment)
        }

        mutating func skipQuotedName() {
            guard current == "\"" else { return }
            advance()
            while let c = current {
                advance()
                if c == "\"" { break }
            }
        }

        mutating func parseNumber() -> Int {
            var value = 0
            var found = false
            while let c = current, let digit = c.wholeNumberValue {
                found = true
                value = value * 10 + digit
                advance()
            }
            return found ? value : -1
        }

        func pointer() -> ObjCTypeLayout {
            .init(size: pointerSize, alignment: pointerSize)
        }

        func align(_ value: Int, to alignment: Int) -> Int {
            guard alignment > 1 else { return value }
            return (value + alignment - 1) & ~(alignment - 1)
        }
    }
}
