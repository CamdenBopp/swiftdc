import Foundation
import MachOKit
import MachOSwiftSection
import SwiftLayout
import SwiftInspection

/// Names a **payload** enum's case from the bytes a function wrote for it, but
/// only when the encoding is *provable*, never guessed.
///
/// `EnumCaseIndex` deliberately declines payload enums: a bare returned immediate
/// is not a declaration index, so naming a case from it would be a fabrication.
/// That decline is correct as far as it goes. What it lacks is the enum's real
/// encoding, which `SwiftLayout`'s `StaticLayoutCalculator.enumCaseLayoutResult`
/// computes offline through `SwiftInspection.EnumLayoutCalculator` (the audited
/// port of the runtime's `getEnumTag*` formulas). For a *tagged* multi-payload
/// enum like `Token { eof; number(Int); ident(Int) }` it resolves `.eof` to the
/// exact bytes `payload 0, tag byte 2` (`patternResolution == .exactBytes`).
///
/// Two consumers, one rule (an exact match of every fixed byte, or decline):
///
/// - A value returned **directly** (16 bytes or fewer: bytes 0..<8 in x0, 8..<16
///   in x1) names an *empty* case from the two registers. Payload cases are out
///   of scope there: they carry a live associated value, so they are never
///   returned as a bare constant.
/// - A value returned **indirectly** through x8 (more than four scalars) names a
///   case from the stores through x8 that reach the `ret`: an empty case when
///   the stores reproduce its fixed bytes exactly, a payload case when its tag
///   bytes are stored as immediates that match and the payload is a tuple of
///   word-sized scalars whose every word is stored (so the payload's arity is
///   the type's, not a guess from the store count).
///
/// Anything short of a unique exact match declines:
///
///   - a case whose bytes depend on the payload's extra-inhabitant scheme
///     (`.unresolvedExtraInhabitant`), which only the in-process runtime
///     projector can resolve;
///   - a fixed byte no register / store can source, or one whose stored value is
///     not an immediate (a spare-bit tag inside a variable payload word);
///   - more than one case matching the observed bytes;
///   - an enum whose simple name is ambiguous across the image.
public struct PayloadEnumCaseIndex: Sendable {
    /// One statically-resolved case: its source name, whether it carries a
    /// payload, the fixed byte pattern that identifies it (offset → value, with
    /// the fixed-bit mask per byte; an absent mask means every bit is fixed), and
    /// for a payload case the number of consecutive 8-byte words its payload
    /// occupies when that payload is a tuple of word scalars (nil otherwise).
    struct ResolvedCase: Sendable {
        let name: String
        let isPayloadCase: Bool
        let fixedBytes: [Int: UInt8]
        let masks: [Int: UInt8]
        let payloadWords: Int?
    }

    /// One indexed enum: its total size (which decides direct vs indirect
    /// return) and its resolvable cases.
    struct Entry: Sendable {
        let size: Int
        let cases: [ResolvedCase]
    }

    /// A case named from an indirectly returned value's stores.
    public struct IndirectCase: Equatable, Sendable {
        public let name: String
        /// Byte offsets of the payload's words, in tuple order; empty for an
        /// empty case.
        public let payloadWordOffsets: [Int]
    }

    /// Simple name → entry, `nil` when the simple name is ambiguous across the
    /// image (two distinct payload enums, different layouts) so it declines
    /// rather than guessing which one a receiver meant.
    private let byName: [String: Entry?]
    /// Fully-qualified name → entry. Qualified names are unique, so a caller that
    /// knows the qualified return type resolves its own enum even when the simple
    /// name collided and was dropped.
    private let byQualifiedName: [String: Entry]

    init(byName: [String: Entry?] = [:], byQualifiedName: [String: Entry] = [:]) {
        self.byName = byName
        self.byQualifiedName = byQualifiedName
    }

    /// The number of enums indexed, for diagnostics.
    public var count: Int { byName.count }

    /// The empty-case name for a payload enum returned in `x0` (bytes 0..<8) and,
    /// for a value spanning a second register, `x1` (bytes 8..<16) — or `nil`
    /// (decline) when the enum is unknown/ambiguous/oversize, a register cannot
    /// source a fixed byte, or the observed bytes do not match exactly one case.
    public func caseName(ofEnum typeName: String, x0: UInt64, x1: UInt64?) -> String? {
        guard let entry = resolve(typeName), entry.size <= 16 else { return nil }

        // The byte at `offset` of the returned value, sourced from the register it
        // lands in; nil when no register covers it (so the case cannot be verified).
        func byte(at offset: Int) -> UInt8? {
            if offset < 0 { return nil }
            if offset < 8 { return UInt8((x0 >> (offset * 8)) & 0xFF) }
            if offset < 16, let x1 { return UInt8((x1 >> ((offset - 8) * 8)) & 0xFF) }
            return nil
        }

        var matched: [String] = []
        for candidate in entry.cases where !candidate.isPayloadCase {
            var isExactMatch = true
            for (offset, value) in candidate.fixedBytes {
                let mask = candidate.masks[offset] ?? 0xFF
                guard let actual = byte(at: offset), (actual & mask) == (value & mask) else {
                    isExactMatch = false
                    break
                }
            }
            if isExactMatch { matched.append(candidate.name) }
        }
        // A unique exact match only — never a coin-flip between two candidates.
        return matched.count == 1 ? matched[0] : nil
    }

    /// The case an indirectly returned (x8) payload enum holds, from the stores
    /// that reach the `ret`: `stores` maps byte offset → (store width, the
    /// stored value when it is an immediate). Nil (decline) when the enum is
    /// unknown, ambiguous, or small enough to return directly; when a fixed
    /// byte is not stored as a matching immediate; when more than one case
    /// matches; or, for a payload case, when the payload is not a word-scalar
    /// tuple whose every word is stored.
    public func indirectCase(
        ofEnum typeName: String, stores: [Int: (bytes: Int, immediate: UInt64?)]
    ) -> IndirectCase? {
        guard let entry = resolve(typeName), entry.size > 16 else { return nil }

        // The stored byte at `offset`, when a store covers it with an immediate.
        func storedByte(at offset: Int) -> UInt8? {
            for (start, store) in stores where start <= offset && offset < start + store.bytes {
                guard let immediate = store.immediate else { return nil }
                return UInt8((immediate >> ((offset - start) * 8)) & 0xFF)
            }
            return nil
        }

        var matched: [IndirectCase] = []
        for candidate in entry.cases {
            var isExactMatch = !candidate.fixedBytes.isEmpty || !candidate.isPayloadCase
            for (offset, value) in candidate.fixedBytes {
                let mask = candidate.masks[offset] ?? 0xFF
                guard let actual = storedByte(at: offset), (actual & mask) == (value & mask) else {
                    isExactMatch = false
                    break
                }
            }
            guard isExactMatch else { continue }
            if candidate.isPayloadCase {
                // The payload's words come from the type, and each must be stored
                // as a whole word; a byte the tag claims cannot also be payload.
                guard let words = candidate.payloadWords else { continue }
                let offsets = (0..<words).map { $0 * 8 }
                guard offsets.allSatisfy({ stores[$0]?.bytes == 8 }),
                      !candidate.fixedBytes.keys.contains(where: { $0 < words * 8 })
                else { continue }
                matched.append(IndirectCase(name: candidate.name, payloadWordOffsets: offsets))
            } else {
                matched.append(IndirectCase(name: candidate.name, payloadWordOffsets: []))
            }
        }
        return matched.count == 1 ? matched[0] : nil
    }

    private func resolve(_ typeName: String) -> Entry? {
        // The qualified return type can live in a dependency whose enum layout
        // is absent from this image. A local enum with the same simple name is
        // not evidence for that foreign type's case encoding or names.
        // (Recovered from the pre-merge stash 983aa25.)
        if typeName.contains(".") { return byQualifiedName[typeName] }
        return byName[typeName] ?? nil   // may be nil (ambiguous) → decline
    }

    public static func build(in machO: MachOFile) -> PayloadEnumCaseIndex {
        guard let calculator = try? StaticLayoutCalculator(machO: machO) else {
            return PayloadEnumCaseIndex()
        }
        var seen: [String: Entry] = [:]
        var ambiguous: Set<String> = []
        var byQualified: [String: Entry] = [:]
        var ambiguousQualifiedNames: Set<String> = []

        for type in (try? machO.swift.types) ?? [] {
            guard case .enum(let model) = type else { continue }
            let descriptor = model.descriptor
            // Payload enums only: a no-payload enum is `EnumCaseIndex`'s domain
            // (its bare tag IS the declaration index).
            guard descriptor.numberOfPayloadCases > 0 else { continue }
            guard let name = try? descriptor.name(in: machO) else { continue }

            guard let size = (try? calculator.typeLayout(forDescriptor: .enum(descriptor)))?.size,
                  let layout = calculator.enumCaseLayoutResult(forDescriptor: .enum(descriptor))
            else { continue }
            // The payload type of each case, by declared name, so a payload case's
            // word arity comes from the type rather than from the stores.
            let payloadWordsByName = Self.payloadWordCounts(of: descriptor, in: machO)

            let cases: [ResolvedCase] = layout.cases.compactMap { projection in
                guard projection.patternResolution == .exactBytes,
                      let declaredName = projection.declaredName
                else { return nil }
                let masks = Dictionary(uniqueKeysWithValues:
                    projection.memoryChanges.keys.map { ($0, projection.fixedBitMask(atByteOffset: $0)) })
                return ResolvedCase(
                    name: declaredName, isPayloadCase: projection.isPayloadCase,
                    fixedBytes: projection.memoryChanges, masks: masks,
                    payloadWords: projection.isPayloadCase ? payloadWordsByName[declaredName] ?? nil : nil
                )
            }
            guard !cases.isEmpty else { continue }
            let entry = Entry(size: size, cases: cases)

            if let existing = seen[name], !entriesEquivalent(existing, entry) {
                ambiguous.insert(name)
            } else {
                seen[name] = entry
            }
            if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) {
                if let existing = byQualified[qualified], !entriesEquivalent(existing, entry) {
                    ambiguousQualifiedNames.insert(qualified)
                }
                byQualified[qualified] = entry
            }
        }

        var byName: [String: Entry?] = [:]
        for (name, entry) in seen {
            byName[name] = ambiguous.contains(name) ? nil : entry
        }
        for name in ambiguousQualifiedNames { byQualified.removeValue(forKey: name) }
        return PayloadEnumCaseIndex(byName: byName, byQualifiedName: byQualified)
    }

    /// Case name → the number of 8-byte words its payload occupies when the
    /// payload is one word-sized scalar or a tuple of them (`Int`, `UInt`,
    /// `Double`, a raw pointer), laid out contiguously from offset 0; nil for any
    /// other payload (a `String`, a struct, a `Bool`, a class reference), whose
    /// scalar arity the store count cannot prove.
    private static func payloadWordCounts(
        of descriptor: EnumDescriptor, in machO: MachOFile
    ) -> [String: Int?] {
        guard let records = try? descriptor.fieldDescriptor(in: machO).records(in: machO) else { return [:] }
        var counts: [String: Int?] = [:]
        for record in records {
            guard let caseName = try? record.fieldName(in: machO) else { continue }
            // The record's mangled type text, read directly: no demangling, so no
            // symbolic-reference resolution through the image's fixup tables (a
            // shared, lazily built cache that concurrent analyses raced on).
            counts[caseName] = (try? record.mangledTypeName(in: machO)).flatMap { wordScalarTupleArity(mangled: $0.typeString) }
        }
        return counts
    }

    /// The word count of a payload type from its mangled text (the field
    /// record's, read verbatim): `Si` (Int) → 1, `Si_S3it` ((Int, Int, Int,
    /// Int): the first element, `_`, then `S3i` for three more `Si`) → 4;
    /// anything else → nil. Only the standard library's word scalars are
    /// recognised, all spelled with plain ASCII codes; a type with a symbolic
    /// reference (any user type) or any other code is declined, since its
    /// scalar arity is not what the store count says.
    static func wordScalarTupleArity(mangled type: String) -> Int? {
        // Standard-substitution letters for the word scalars: Int, UInt, Double,
        // UnsafeRawPointer, UnsafeMutableRawPointer. `S<n><letter>` repeats one.
        let standardWordLetters: Set<Character> = ["i", "u", "d", "V", "v"]
        let longWordCodes = ["s5Int64V", "s6UInt64V", "s13OpaquePointerV"]
        var rest = Substring(type)
        let isTuple = rest.hasSuffix("t")
        if isTuple { rest = rest.dropLast() }
        var count = 0
        while !rest.isEmpty {
            if rest.hasPrefix("_") {
                // The separator after a tuple's first element.
                guard isTuple, count == 1 else { return nil }
                rest = rest.dropFirst()
                continue
            }
            if let code = longWordCodes.first(where: { rest.hasPrefix($0) }) {
                rest = rest.dropFirst(code.count)
                count += 1
                continue
            }
            guard rest.first == "S" else { return nil }
            rest = rest.dropFirst()
            let digits = rest.prefix(while: { $0.isNumber })
            rest = rest.dropFirst(digits.count)
            guard let letter = rest.first, standardWordLetters.contains(letter) else { return nil }
            rest = rest.dropFirst()
            count += digits.isEmpty ? 1 : (Int(digits) ?? 0)
        }
        guard count > 0, isTuple || count == 1 else { return nil }
        return count
    }

    /// Two entries are equivalent when they name the same cases with the same
    /// patterns — so two same-named enums with identical layouts are not
    /// treated as an ambiguous collision.
    private static func entriesEquivalent(_ a: Entry, _ b: Entry) -> Bool {
        guard a.size == b.size, a.cases.count == b.cases.count else { return false }
        let aByName = Dictionary(a.cases.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for caseB in b.cases {
            guard let caseA = aByName[caseB.name],
                  caseA.isPayloadCase == caseB.isPayloadCase,
                  caseA.fixedBytes == caseB.fixedBytes, caseA.masks == caseB.masks,
                  caseA.payloadWords == caseB.payloadWords
            else { return false }
        }
        return true
    }
}
