import Testing
import Foundation
import Demangling
@testable import SwiftDecompilerCore

/// What each mangled clause proves. Every symbol here is from
/// `droppedargs.swift`, and every expected list is that symbol's IR
/// signature under `swiftc -O -emit-ir` (see the fixture's comments).
private func clause(_ symbol: String) throws -> SpecializationClause {
    let name = try demangleAsNode(symbol).print(using: .default)
    return DisassembledFunction.specializationClause(symbol: "_" + symbol, printedName: name)
}

private func proven(_ signature: String) -> SpecializationClause {
    .proven(SpecializedLayout(signature: "DroppedArgs." + signature))
}

private extension SpecializationClause {
    var asStatic: SpecializationClause {
        guard case .proven(let layout) = self else { return self }
        return .proven(SpecializedLayout(signature: "static " + layout.signature))
    }
}

@Test func aDroppedArgumentLeavesTheSignatureWhereverItWas() throws {
    #expect(try clause("$s11DroppedArgs4metaySixm_SitlFs4Int8V_Ttg5") == proven("meta(Swift.Int) -> Swift.Int"))
    #expect(try clause("$s11DroppedArgs4lastyS2i_SixmtlFs5Int16V_Tt1g5")
        == proven("last(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(try clause("$s11DroppedArgs3twoySixm_Siq_mSitr0_lFs4Int8V_s5Int16VTtt1g5")
        == proven("two(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(try clause("$s11DroppedArgs5floatySdxm_SdSitlFs4Int8V_Ttg5")
        == proven("float(Swift.Double, Swift.Int) -> Swift.Double"))
    // The only parameter: the argument list is not a tuple.
    #expect(try clause("$s11DroppedArgs4onlyySixmlFs5Int32V_Ttg5") == proven("only() -> Swift.Int"))
}

/// `Tt` counts SIL arguments, and the `@out T` is the first: index 1 is the
/// metatype, and read as a formal's position it was the Int.
@Test func aDroppedIndexCountsAnIndirectResultFirst() throws {
    #expect(try clause("$s11DroppedArgs13genericResultyxxm_SixtlFSd_Tt0g5")
        == proven("genericResult(Swift.Int, Swift.Double) -> Swift.Double"))
}

/// The label list names the declared formals; left in place it labels the
/// wrong one.
@Test func aDroppedArgumentTakesTheLabelsWithIt() throws {
    #expect(try clause("$s11DroppedArgs7labeled2of5countSixm_SitlFs4Int8V_Ttg5")
        == proven("labeled(Swift.Int) -> Swift.Int"))
}

/// Past the formals is a `self` or a capture, so every formal stays put:
/// `Tt1` is the thin metatype of these statics and allocators, and declined,
/// `Array.==`'s body lost its `arg0 == arg1`.
@Test func aDropPastTheFormalsLeavesThemWhereThePrintedNameSays() throws {
    // A generic static is rebuilt: its `v` is an Int8 now.
    #expect(try clause("$s11DroppedArgs5ScaleO2byyS2i_Sixts17FixedWidthIntegerRzlFZs4Int8V_Tt2g5")
        == proven("Scale.by(Swift.Int, Swift.Int, Swift.Int8) -> Swift.Int").asStatic)
    #expect(try clause("$s11DroppedArgs5ScaleO2ofySixm_S2itlFZs4Int8V_Ttt2g5")
        == proven("Scale.of(Swift.Int, Swift.Int) -> Swift.Int").asStatic)
    // A context's generics and an allocator are not rebuilt: the name stands.
    #expect(try clause("$sSasSQRzlE2eeoiySbSayxG_ABtFZSi_Tt1g5") == .absent)
    #expect(try clause("$s11DroppedArgs4PackV5count5scaleACyxGSi_SitcfCs4Int8V_Tt1g5") == .absent)
    // Were `Holder` an `@out`, index 2 here would be the metatype formal.
    #expect(try clause("$s11DroppedArgs5ScaleO4lastyAA6HolderVSi_xmtlFZs4Int8V_Tt1g5") == .declined)
    // Nothing follows a free function's formals.
    #expect(try clause("$s11DroppedArgs4lastyS2i_SixmtlFs5Int16V_Tt2g5") == .declined)
    // A tuple formal moves where the formals end, as an async or typed-throw
    // function's are not measured, and a tuple result's buffers are uncounted.
    #expect(try clause("$s11DroppedArgs5ScaleO3tupyS2i_Sit_SitlFZs4Int8V_Tt2g5") == .declined)
    #expect(try clause("$s11DroppedArgs5ScaleO2ofySixm_S2itYalFZs4Int8V_Tt2g5") == .declined)
    #expect(try clause("$s1Q5ScaleO3tthySixm_q_Sitq_YKs5ErrorR_r0_lFZs4Int8V_AA5NSErrOTt2g5") == .declined)
    #expect(try clause("$s11DroppedArgs5ScaleO4pairyx_xtSi_xtlFZs4Int8V_Tt2g5") == .declined)
}

@Test func aClauseThatCannotBeFollowedDeclinesEveryParameter() throws {
    // A tuple formal is one SIL argument per element, and the clause counts those.
    #expect(try clause("$s11DroppedArgs6tupledyS2i_Sit_xmSitlFs4Int8V_Tt1g5") == .declined)
    // A buffer stays in x0.
    #expect(try clause("$s11DroppedArgs4pairyx_xtxm_SixtlFSi_Tt1g5") == .declined)
    // An index that lands on a formal the compiler never drops: `Tt0` on a
    // direct result names the Int.
    #expect(try clause("$s11DroppedArgs4metaySixm_SitlFs4Int8V_Tt0g5") == .declined)
    // Past the end, as a `self` would be.
    #expect(try clause("$s11DroppedArgs4metaySixm_SitlFs4Int8V_Tt4g5") == .declined)
    // An indirect typed error is a SIL argument too: index 1 here is the
    // metatype, and the second formal is a value of generic type.
    #expect(try clause("$s1Q3tthySixm_q_Sitq_YKs5ErrorR_r0_lFs4Int8V_AA5NSErrOTt0g5") == .declined)
    // An async specialization is not measured.
    #expect(try clause("$s1A2amySixm_SitYalFs4Int8V_Ttg5") == .declined)
    // `Arg[0] = Dead` over a dropped metatype: the printed list is wrong twice.
    #expect(try clause("$s1Q2rgyxxm_SixtlFSi_Tt0g5Tf4dn_n") == .declined)
}

@Test func anUndroppedSpecializationKeepsWhatItPrinted() throws {
    // A buffer stays in x0, with or without a dropped argument.
    #expect(try clause("$s11DroppedArgs4pairyx_xtxlFSi_Tg5") == .absent)
    // The same clause with nothing dropped reads as it always did.
    #expect(try clause("$s15Specializations4bumpyxxSjRzlFSd_Tg5")
        == .proven(SpecializedLayout(signature: "Specializations.bump(Swift.Double) -> Swift.Double")))
    // A member type needs a conformance to resolve, so the printed name stands.
    #expect(try clause("$s15Specializations10firstCounty7ElementQzSgxSlRzlFSaySiG_Tg5") == .absent)
    // Not a specialization.
    #expect(DisassembledFunction.specializationClause(symbol: "_$s1M1fyS2iF", printedName: "M.f(Swift.Int) -> Swift.Int") == .absent)
}

// MARK: - The fixture

private func functions(_ path: String) async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try await withStableDependencies { try await Disassembler().disassemble(path: path) }
}

/// The body of the one specialization of `base` whose name holds `marker`.
private func body(_ functions: [DisassembledFunction], _ base: String, _ marker: String = "") throws -> String {
    let matches = functions.filter {
        $0.displayName.contains("specialization <") && $0.displayName.contains("of DroppedArgs.\(base)")
            && (marker.isEmpty || $0.displayName.contains(marker))
    }
    #expect(matches.count == 1, "\(base) \(marker): \(matches.map(\.displayName))")
    return try #require(matches.first).renderStructured()
}

private func caller(_ functions: [DisassembledFunction], _ name: String) throws -> String {
    try #require(functions.first { $0.displayName.hasPrefix("DroppedArgs.\(name)(") }).renderStructured()
}

/// -O and -Osize define the same specializations with the same signatures.
private let optimizedBuilds = ["Fixtures/Sample/libDroppedArgs.dylib", "Fixtures/Sample/libDroppedArgs.Osize.dylib"]

@Test(arguments: optimizedBuilds)
func aDroppedArgumentCallPassesTheSurvivorsIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    // The Int in x0 and the Double in d0, by index 1 of the SIL list.
    #expect(try caller(functions, "useGenericResult").contains("genericResult<A>(arg0, arg1)"))
    #expect(try caller(functions, "useFloat").contains("float<A>(arg0, arg1)"))
    // Declined: an unproven generic argument list is opaque, never the
    // printed list (which has a place for the x2 left over from the caller).
    #expect(try caller(functions, "useTupled").contains("tupled<A>(…)"))
    #expect(try caller(functions, "useKeyed").contains("keyed<A>(…)"))
    #expect(try caller(functions, "useKeyedThenAdd").contains("keyed<A>(…)"))
}

/// A closure-propagated clause prints an unclosed `[`, and the signature was
/// left in the call: `… P.apply<A>(A.Type, Swift.Int, (Swift.Int) -> Swift.Int)
/// -> Swift.Int(arg0, arg0)`.
@Test(arguments: optimizedBuilds)
func aClosurePropagatedCallHasNoSignatureInItIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    let text = try caller(functions, "useApply")
    #expect(text.contains("of DroppedArgs.apply<A>(arg0, arg0)"), Comment(rawValue: text))
}

/// Nothing is specialized at -Onone, so each call passes its metatype.
@Test func anUnoptimizedCallKeepsItsMetatypeIfPresent() async throws {
    guard let functions = try await functions("Fixtures/Sample/libDroppedArgs.Onone.dylib") else { return }
    let text = try caller(functions, "useMeta")
    #expect(text.contains("DroppedArgs.meta<A>(type metadata for Swift.Int8, arg0"), Comment(rawValue: text))
}

/// A folded address has no symbol, and a `Tt` clause is then invisible: the
/// name alone decides, as for any name.
@Test func aSpecializationSymbolIsKeptForEveryClauseKind() {
    let symbols = Disassembler.ReferenceResolver.specializationSymbols(
        labels: [1: "_one", 2: "_two"],
        names: [1: "function signature specialization <Arg[1] = [Closure Propagated : x, Argument Types : []> of M.f(Swift.Int) -> Swift.Int",
                2: "generic not re-abstracted specialization <Swift.Int> of M.f<A>(A) -> ()"],
        folded: [:])
    #expect(symbols == [1: "_one", 2: "_two"])
}
