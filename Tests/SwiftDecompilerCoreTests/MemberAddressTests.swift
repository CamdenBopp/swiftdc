import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `interface --member-addresses` prints a member's address only when it is
/// that member's code. A stripped image keeps no symbol for a witness of a
/// conformance to another image's protocol, and the printer used to report
/// the slot its requirement's bind fills instead: `sample.stripped` printed
/// `0x1000084B0`, a `__DATA_CONST,__const` address, for both `Point ==` and
/// `Direction ==`.
struct MemberAddressTests {
    /// Every printed address, keyed by the block it is in, the member's
    /// declaration line and the comment's label. A key printed more than once
    /// keeps every value, so a caller can skip it.
    static func addresses(in interface: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var header = ""
        var pending: [(label: String, value: String)] = []
        for line in interface.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            if !line.hasPrefix(" ") { header = String(line); pending = []; continue }
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("// Address") {
                guard let colon = trimmed.range(of: ": ", options: .backwards) else { continue }
                let label = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: "// Address".count) ..< colon.lowerBound])
                pending.append((label, String(trimmed[colon.upperBound...])))
            } else if trimmed.hasPrefix("//") || trimmed.isEmpty {
                continue
            } else {
                for (label, value) in pending {
                    result["\(header) | \(trimmed) |\(label)", default: []].append(value)
                }
                pending = []
            }
        }
        return result
    }

    private static func interface(_ path: String) async throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let machO = try BinaryLoader.load(path: path)
        return try await withStableDependencies {
            try await InterfaceReconstructor(options: .init(memberAddresses: true)).reconstruct(machO)
        }
    }

    /// Every stripped fixture with its unstripped original, by build.sh's
    /// naming: `X.stripped` from `X.release`, `libX.stripped.dylib` from
    /// `libX.dylib`.
    static func strippedPairs() -> [(stripped: String, unstripped: String)] {
        let directory = "Fixtures/Sample"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.sorted().compactMap { name in
            let original: String
            if name.hasSuffix(".stripped.dylib") {
                original = String(name.dropLast(".stripped.dylib".count)) + ".dylib"
            } else if name.hasSuffix(".stripped") {
                original = String(name.dropLast(".stripped".count)) + ".release"
            } else {
                return nil
            }
            guard names.contains(original) else { return nil }
            return ("\(directory)/\(name)", "\(directory)/\(original)")
        }
    }

    /// The oracle: the unstripped image's symbol table names each member's
    /// code, so a member the stripped interface prints an address for must
    /// print the same address unstripped. Checked over every stripped
    /// fixture that has an unstripped original.
    @Test func everyStrippedMemberAddressIsTheUnstrippedOneIfPresent() async throws {
        let pairs = Self.strippedPairs()
        guard !pairs.isEmpty else { return }
        var compared = 0
        for pair in pairs {
            guard let strippedText = try await Self.interface(pair.stripped),
                  let unstrippedText = try await Self.interface(pair.unstripped)
            else { continue }
            let stripped = Self.addresses(in: strippedText)
            let unstripped = Self.addresses(in: unstrippedText)
            for (key, values) in stripped.sorted(by: { $0.key < $1.key }) {
                guard values.count == 1, let value = values.first, value != "?",
                      let truth = unstripped[key], truth.count == 1
                else { continue }
                compared += 1
                #expect(value == truth[0], "\(pair.stripped): \(key) printed \(value), unstripped \(truth[0])")
            }
        }
        #expect(compared > 0, "no member address was compared, so the oracle is vacuous")
    }

    /// The reported defect: both `==` witnesses printed the one
    /// requirement slot. Each now prints its own witness, as the
    /// unstripped image names it, and so do the `Hashable` and
    /// `RawRepresentable` witnesses that printed slots beside it.
    @Test func strippedWitnessesPrintTheirImplementationsIfPresent() async throws {
        guard let strippedText = try await Self.interface("Fixtures/Sample/sample.stripped"),
              let unstrippedText = try await Self.interface("Fixtures/Sample/sample.release")
        else { return }
        let stripped = Self.addresses(in: strippedText)
        let unstripped = Self.addresses(in: unstrippedText)
        let equals = "static func == (_: Self, _: Self) -> Swift.Bool |"
        #expect(stripped["extension sample.Point: Swift.Equatable { | \(equals)"] == ["0x100001164"])
        #expect(stripped["extension sample.Direction: Swift.Equatable { | \(equals)"] == ["0x100001508"])
        let witnesses = stripped.filter { $0.key.hasPrefix("extension sample.Direction: Swift.") }
        #expect(witnesses.count == 6, "\(witnesses)")
        for (key, value) in witnesses {
            #expect(value == unstripped[key], "\(key)")
        }
        #expect(!strippedText.contains("0x1000084"), Comment(rawValue: strippedText))
    }

    /// An address that is neither a function start nor a witness the
    /// conformance can name is declined, and a function start is kept.
    @Test func anAddressThatIsNotAFunctionStartIsDeclinedIfPresent() throws {
        let path = "Fixtures/Sample/sample.stripped"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let audit = MemberAddressAudit(try BinaryLoader.load(path: path))
        let text = """
        struct X {
            // Address: 0x1000084B0
            func data()
            // Address (getter): 0x100001164
            var code: Swift.Int
        }
        """
        let (audited, counts) = audit.audit(text)
        #expect(audited.contains("    // Address: ?\n    func data()"), Comment(rawValue: audited))
        #expect(audited.contains("    // Address (getter): 0x100001164\n"), Comment(rawValue: audited))
        #expect(counts == .init(kept: 1, recovered: 0, declined: 1))
    }

    /// The slot is shared by every conformance to `Equatable`, so only the
    /// enclosing `extension T: P` says which witness it stands for. Outside
    /// a block that names exactly one conformance it is declined.
    @Test func aRequirementSlotIsResolvedOnlyInsideItsConformanceIfPresent() throws {
        let path = "Fixtures/Sample/sample.stripped"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let audit = MemberAddressAudit(try BinaryLoader.load(path: path))
        #expect(audit.witness(at: 0x1000084B0, type: "sample.Point", protocol: "Swift.Equatable") == 0x100001164)
        #expect(audit.witness(at: 0x1000084B0, type: "sample.Direction", protocol: "Swift.Equatable") == 0x100001508)
        #expect(audit.witness(at: 0x1000084B0, type: "sample.Direction", protocol: "Swift.Hashable") == nil)
        #expect(audit.witness(at: 0x1000084B0, type: "sample.Circle", protocol: "Swift.Equatable") == nil)
        let text = "extension sample.Point: Swift.Hashable {\n    // Address: 0x1000084B0\n    func f()\n}"
        #expect(audit.audit(text).text.contains("// Address: ?"))
    }

    /// A protocol requirement has no code. The printer showed its method
    /// descriptor (`$s6Sample5ShapeP4areaSdvgTq`, `__constg_swiftt`) as
    /// its address; it now shows none, unstripped or not, where a `?`
    /// would say code exists that was not found.
    @Test func aProtocolRequirementPrintsNoAddressIfPresent() async throws {
        guard let text = try await Self.interface("Fixtures/Sample/libSample.dylib") else { return }
        #expect(text.contains("protocol Shape {\n    var area: Swift.Double {"), Comment(rawValue: text))
        #expect(text.contains("    }\n\n    func describe() -> Swift.String\n}"), Comment(rawValue: text))
        #expect(!text.contains("0x408C") && !text.contains("0x4094"), Comment(rawValue: text))
    }

    /// An async witness's symbol at the conformance's implementation is its
    /// async function pointer record (`…TWTu`, `__TEXT,__const`), and the
    /// printer showed that. The record leads to the witness's code, which the
    /// symbol table names `…TW`; that is what prints now. Stripped, the
    /// record has no symbol to say what it is, and the address is declined.
    @Test func anAsyncWitnessPrintsItsCodeNotItsRecordIfPresent() async throws {
        let path = "Fixtures/Sample/libAsyncWitness.dylib"
        guard let text = try await Self.interface(path),
              let strippedText = try await Self.interface("Fixtures/Sample/libAsyncWitness.stripped.dylib")
        else { return }
        let machO = try BinaryLoader.load(path: path)
        func code(_ suffix: String) -> String? {
            machO.symbols.first { $0.name.hasSuffix(suffix) }
                .map { "0x" + String(UInt64($0.offset), radix: 16, uppercase: true) }
        }
        let header = "extension AsyncWitness.Countdown: Swift.AsyncIteratorProtocol { | "
        let next = header + "func next() async throws -> Self.Element? |"
        let isolated = header + "func next(isolation: isolated Swift.Actor?) async throws(Self.Failure) -> Self.Element? |"
        let printed = Self.addresses(in: text)
        #expect(printed[next] == code("ScI4next7ElementQzSgyYaKFTW").map { [$0] }, Comment(rawValue: text))
        #expect(printed[isolated] == code("ScI4next9isolation7ElementQzSgScA_pSgYi_tYa7FailureQzYKFTW").map { [$0] })
        let stripped = Self.addresses(in: strippedText)
        #expect(stripped[next] == ["?"] && stripped[isolated] == ["?"], Comment(rawValue: strippedText))
    }

    /// A private type's name cannot be qualified from metadata, so its
    /// conformance is found by the type's own name, and only when that name
    /// is unambiguous (`privatewitness.swift`). `Token` is matched (the
    /// internal `Outer.Token` has a qualified name and is ruled out); the
    /// two private `Badge`s could each be the other, and are declined.
    @Test func aPrivateTypesWitnessIsMatchedByItsOwnNameOnlyWhenUniqueIfPresent() async throws {
        guard let strippedText = try await Self.interface("Fixtures/Sample/libPrivateWitness.stripped.dylib"),
              let unstrippedText = try await Self.interface("Fixtures/Sample/libPrivateWitness.dylib")
        else { return }
        let stripped = Self.addresses(in: strippedText)
        let unstripped = Self.addresses(in: unstrippedText)
        for type in ["PrivateWitness.Token", "PrivateWitness.Outer.Token"] {
            let witnesses = stripped.filter { $0.key.hasPrefix("extension \(type): Swift.") }
            #expect(witnesses.count == 4, "\(type): \(witnesses)")
            for (key, value) in witnesses {
                #expect(value.allSatisfy { $0.hasPrefix("0x") } && value == unstripped[key], "\(key): \(value)")
            }
        }
        let badge = stripped.filter { $0.key.hasPrefix("extension PrivateWitness.Badge: Swift.") }
        #expect(badge.count == 4 && badge.values.allSatisfy { $0 == ["?"] }, "\(badge)")
    }

    /// The name-only tier, on hand-built conformances: a conformance whose
    /// type's name is unknown could be any type, so it rules the tier out
    /// for its protocol, and a conformance with a qualified name is never a
    /// name-only match (it would have matched by that name).
    @Test func theNameOnlyTierDeclinesWhenAnotherTypeCouldBeIt() {
        func make(_ qualified: String?, _ simple: String?, _ proto: String = "Swift.Equatable") -> ResilientWitnessIndex.Conformance {
            .init(typeName: qualified, simpleName: simple, isNonGeneric: true, protocolName: proto, isRetroactive: false, witnesses: [])
        }
        let token = make(nil, "Token")
        func match(_ all: [ResilientWitnessIndex.Conformance]) -> ResilientWitnessIndex.Conformance? {
            MemberAddressAudit.conformance(of: "M.Token", to: "Swift.Equatable", among: all)
        }
        func conformance(_ all: [ResilientWitnessIndex.Conformance]) -> String? { match(all)?.simpleName }
        #expect(conformance([token]) == "Token")
        #expect(conformance([token, make(nil, "Token", "Swift.Hashable")]) == "Token")
        #expect(conformance([token, make(nil, nil)]) == nil, "an unnamed type could be M.Token")
        #expect(conformance([token, make(nil, nil, "Swift.Hashable")]) == "Token")
        #expect(conformance([make("M.Outer.Token", "Token")]) == nil, "a qualified name that differs is another type")
        #expect(conformance([token, make(nil, "Token")]) == nil)
        #expect(match([token, make("M.Token", "Token")])?.typeName == "M.Token")
    }

    /// Only a `…Tu` symbol says its first word leads to code. A method
    /// descriptor, a type descriptor or a C symbol that ends the same way
    /// does not.
    @Test func onlyAnAsyncFunctionPointerSymbolIsFollowed() {
        #expect(MemberAddressAudit.namesAsyncFunctionPointer("_$s12AsyncWitness9CountdownV4nextSiSgyYaFTu"))
        #expect(!MemberAddressAudit.namesAsyncFunctionPointer("_$s6Sample5ShapeP4areaSdvgTq"))
        #expect(!MemberAddressAudit.namesAsyncFunctionPointer("_$s6sample5PointVMn"))
        #expect(!MemberAddressAudit.namesAsyncFunctionPointer("_menuTu"))
    }

    @Test func extensionHeadersAreParsedStrictly() {
        #expect(MemberAddressAudit.extensionHeader("extension a.B: Swift.Equatable {").map { [$0.type, $0.protocol] } == ["a.B", "Swift.Equatable"])
        #expect(MemberAddressAudit.extensionHeader("extension a.B: Swift.Equatable where A: Swift.Equatable {").map { [$0.type, $0.protocol] } == ["a.B", "Swift.Equatable"])
        #expect(MemberAddressAudit.extensionHeader("extension a.B: a.P {}").map { [$0.type, $0.protocol] } == ["a.B", "a.P"])
        #expect(MemberAddressAudit.extensionHeader("extension __C.B: @retroactive Swift.Equatable {").map { [$0.type, $0.protocol] } == ["__C.B", "Swift.Equatable"])
        #expect(MemberAddressAudit.extensionHeader("extension a.B {") == nil)
        #expect(MemberAddressAudit.extensionHeader("extension a.B: a.P, a.Q {") == nil)
        #expect(MemberAddressAudit.extensionHeader("struct a.B: a.P {") == nil)
    }
}
