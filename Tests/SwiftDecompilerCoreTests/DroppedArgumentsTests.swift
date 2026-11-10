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

private func proven(_ signature: String, isComplete: Bool = true) -> SpecializationClause {
    .proven(SpecializedLayout(signature: "DroppedArgs." + signature, isComplete: isComplete))
}

private extension SpecializationClause {
    var asStatic: SpecializationClause {
        guard case .proven(let layout) = self else { return self }
        return .proven(SpecializedLayout(signature: "static " + layout.signature, isComplete: layout.isComplete))
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

/// A hand-built function: what the clause says, without a binary around it.
private func function(_ symbol: String) throws -> DisassembledFunction {
    DisassembledFunction(symbol: "_" + symbol, demangledName: try demangleAsNode(symbol).print(using: .default),
                         startAddress: 0x1000, instructions: [], source: .symbol)
}

/// `ignores<A>(A, Swift.Int, Swift.Int) -> Holder` with its unused value
/// gone: the printed list seeds x1 and x2, which hold nothing of the kind.
@Test func aDeclinedClauseSeedsNothing() throws {
    let declined = try function("$s11DroppedArgs7ignoresyAA6HolderVx_S2itlFSS_Ttg5")
    #expect(declined.specializationClause == .declined)
    #expect(Disassembler.swiftScalarArgumentRegisters(of: declined) == nil)
}

/// The printed list's Double is its second parameter, and the real list's first.
@Test func aFloatArgumentIsCountedInTheRealList() throws {
    let float = try function("$s11DroppedArgs5floatySdxm_SdSitlFs4Int8V_Ttg5")
    #expect(Disassembler.swiftFloatArgumentInfo(of: float)?.indices == [0])
}

@Test func anUndroppedSpecializationKeepsWhatItPrinted() throws {
    // A buffer stays in x0, with or without a dropped argument.
    #expect(try clause("$s11DroppedArgs4pairyx_xtxlFSi_Tg5") == .absent)
    // The same clause with nothing dropped reads as it always did.
    #expect(try clause("$s15Specializations4bumpyxxSjRzlFSd_Tg5")
        == .proven(SpecializedLayout(signature: "Specializations.bump(Swift.Double) -> Swift.Double", isComplete: true)))
    // A member type needs a conformance to resolve, so the printed name stands.
    #expect(try clause("$s15Specializations10firstCounty7ElementQzSgxSlRzlFSaySiG_Tg5") == .absent)
    // Not a specialization.
    #expect(DisassembledFunction.specializationClause(symbol: "_$s1M1fyS2iF", printedName: "M.f(Swift.Int) -> Swift.Int") == .absent)
}

@Test func aPropagatedClosureGoesAndItsCapturesFollowTheSurvivors() throws {
    #expect(try clause("$s11DroppedArgs5applyySixm_S3iXEtlFSi_Ttg504$s11A26Args8useApplyyS2iFS2iXEfU_SiTf1nc_n")
        == proven("apply(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(try clause("$s11DroppedArgs5applyySixm_S3iXEtlFSS_Ttg504$s11A36Args17useApplyNoCaptureyS2iFS2iXEfU_Tf1nc_n")
        == proven("apply(Swift.Int) -> Swift.Int"))
    // Every survivor comes first, then each closure's captures in clause order.
    #expect(try clause("$s11DroppedArgs11twoClosuresySdS2iXE_SdS2iXESitF04$s11a26Args14useTwoClosuresySdSi_jI12SitFS2iXEfU_Si0eafghij1_jiklM3U0_SiTf1cncn_n")
        == proven("twoClosures(Swift.Double, Swift.Int, Swift.Int, Swift.Int) -> Swift.Double"))
    #expect(try clause("$s11DroppedArgs8oneOfTwoyS3iXE_S2iXESitF04$s11a12Args11useOneD23TwoyS2i_S3iXEtFS2iXEfU_SiTf1cnn_n")
        == proven("oneOfTwo((Swift.Int) -> Swift.Int, Swift.Int, Swift.Int) -> Swift.Int"))
    // A dropped metatype and a substituted survivor, under the closure clause.
    #expect(try clause("$s11DroppedArgs12genericValueySixm_xSixXEtlFSd_Ttg504$s11a33Args15useGenericValueySiSd_SitFSiJ5XEfU_SiTf1nc_n")
        == proven("genericValue(Swift.Double, Swift.Int) -> Swift.Int"))
    // The `@out T` became a direct result, so the clause has three entries.
    #expect(try clause("$s11DroppedArgs6foldedyxx_Sixx_SitXEtlFSd_Tg504$s11a27Args9useFoldedyS2d_SitFS2d_H5XEfU_SiTf1nnc_n")
        == proven("folded(Swift.Double, Swift.Int, Swift.Int) -> Swift.Double"))
    // An escaping closure, and the same closure as an earlier argument.
    #expect(try clause("$s11DroppedArgs9sameTwiceyS3iXE_S2iXESitF04$s11A34Args12useSameTwiceyS2i_SitFS2icfU_SiTf1EC0n_n")
        == proven("sameTwice(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(try clause("$s11DroppedArgs3runyS2i_S2iXEtF04$s11A44Args12captureClassyS2i_AA7CounterCtFS2iXEfU_AA0I0CTf1nc_n")
        == proven("run(Swift.Int, DroppedArgs.Counter) -> Swift.Int"))
}

/// A clause lists SIL value types, so these two print the same capture and
/// take it in different banks: `(i64, double)` and `(i64, ptr)`. A String's
/// two words may be one address. What follows such a capture has no proven
/// register, but the survivors before it do.
@Test func aCaptureOfAnUnplacedTypeEndsTheListWithoutEndingTheSurvivors() throws {
    let survivor = proven("run(Swift.Int) -> Swift.Int", isComplete: false)
    #expect(try clause("$s11DroppedArgs3runyS2i_S2iXEtF04$s11A36Args13captureDoubleyS2i_SdtFS2iXEfU_SdTf1nc_n") == survivor)
    #expect(try clause("$s11DroppedArgs3runyS2i_S2iXEtF04$s11A35Args16captureDoubleVaryS2iFS2iXEfU_SdTf1nc_n") == survivor)
    #expect(try clause("$s11DroppedArgs3runyS2i_S2iXEtF04$s11A38Args13captureStringyS2i_SSSitFS2iXEfU_SSSiTf1nc_n") == survivor)
    // A call passes the capture too, so no call is laid out from that list.
    #expect(DisassembledFunction.specializedSignature(
        symbol: "$s11DroppedArgs3runyS2i_S2iXEtF04$s11A36Args13captureDoubleyS2i_SdtFS2iXEfU_SdTf1nc_n",
        printedName: try demangleAsNode("$s11DroppedArgs3runyS2i_S2iXEtF04$s11A36Args13captureDoubleyS2i_SdtFS2iXEfU_SdTf1nc_n")
            .print(using: .default)) == nil)
}

/// The clause has an entry per SIL argument, which `self` is one of: three
/// entries against two formals is a list this does not hold.
@Test func aClosureClauseWhoseEntriesDisagreeWithTheParametersIsLeftToTheName() throws {
    #expect(try clause("$s11DroppedArgs6RunnerV3runyS2i_S2iXEtF04$s11A36Args9useRunnerySiAA0D0V_SitFS2iXEfU_SiTf1ncn_n") == .absent)
    // One entry too few for `run`'s two formals.
    #expect(try clause("$s11DroppedArgs3runyS2i_S2iXEtF04$s11A36Args13captureDoubleyS2i_SdtFS2iXEfU_SdTf1c_n") == .absent)
    // An async closure specialization is not measured.
    #expect(try clause("$s1A2acyS2i_S2iXEtYaF29$s1A5useACyS2i_SitYaFS2iXEfU_SiTf1nc_n") == .absent)
    // `Arg[0] = Dead` stays declined by the printed name.
    #expect(try clause("$s9CallArity3genyS2i_xtlFSi_Tg5Tf4nd_n") == .absent)
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
func aDroppedArgumentSpecializationIsSeededFromItsRealRegistersIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    #expect(try body(functions, "meta", "Swift.Int8").contains("return (arg0 + 1)"))
    let last = try body(functions, "last<")
    #expect(last.contains("arg0") && last.contains("arg1") && !last.contains("return ?"), Comment(rawValue: last))
    #expect(try body(functions, "two<").contains("((arg0 - arg1) + 3)"))
    // arg1 is the Int, and the printed list's second parameter is a Double.
    #expect(try body(functions, "float<").contains("Double(arg1)"))
    // A result the name spells `A` is the Double in d0.
    #expect(try body(functions, "genericResult<").contains("return arg1"))
}

/// Each query that indexes a parameter reads the real list: in each of these
/// the printed list's first parameter is a metatype.
@Test(arguments: optimizedBuilds)
func aParameterQueryIndexesTheRealListIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    #expect(try body(functions, "chosen<").contains("(arg0 ? arg1 : 1)"))
    // A typed UInt needs no unsigned mark.
    #expect(try body(functions, "below<").contains("return (arg0 < arg1)"))
    #expect(try body(functions, "moded<").contains("(arg0 != DroppedArgs.Mode.second)"))
}

/// A static's own metatype leaves its formals in place, rebuilt or not.
@Test(arguments: optimizedBuilds)
func aDroppedSelfMetatypeKeepsTheFormalsIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.contains("of static DroppedArgs.\(name)") }).renderStructured()
    }
    let combine = try text("Pack.combine")
    #expect(combine.contains("arg1") && !combine.contains("return ?"), Comment(rawValue: combine))
    let of = try text("Scale.of")
    #expect(of.contains("arg1") && !of.contains("return ?"), Comment(rawValue: of))
}

/// A specialization that tail-calls for its result returns it.
@Test(arguments: optimizedBuilds)
func aSpecializationsOwnTailCallIsAReturnIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    let text = try body(functions, "tails<")
    #expect(text.contains("return DroppedArgs.helper("), Comment(rawValue: text))
}

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

/// A tail call to a specialization for the same result is a return.
@Test(arguments: optimizedBuilds)
func aSpecializationTailCallIsAReturnIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    #expect(try caller(functions, "useMetaTail").contains("return generic specialization <Swift.Int16> of DroppedArgs.meta<A>(arg0)"))
    #expect(try caller(functions, "useLast").contains("return generic specialization <Swift.Int16> of DroppedArgs.last<A>(arg0, arg1)"))
}

/// `pair` keeps a buffer in x0, so its x0 is no parameter.
@Test(arguments: optimizedBuilds)
func aBufferInX0IsNoParameterIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    #expect(try !body(functions, "pair<").contains("arg0"))
}

@Test(arguments: optimizedBuilds)
func aClosurePropagatedBodyNamesItsSurvivorsAndCapturesIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    // y * x + 8.
    #expect(try body(functions, "apply", "useApplyyS2iF").contains("return (8 + (arg1 * arg0))"))
    // x + 18.
    #expect(try body(functions, "apply", "useApplyNoCapture").contains("return (arg0 + 18)"))
    // (z + a) * 2: the second parameter is the capture.
    #expect(try body(functions, "sameTwice").contains("((arg1 + arg0) << 1)"))
    // x + Double(z * a + z + b): survivors first, then each capture.
    let two = try body(functions, "twoClosures")
    #expect(two.contains("(arg2 * arg1)") && two.contains("(arg3 + arg1)"), Comment(rawValue: two))
    // v + Double(n + k).
    #expect(try body(functions, "folded<").contains("(arg0 + Double((arg2 + arg1)))"))
    // The survivor is seeded; the capture in x1 or d0 is no parameter.
    let double = try body(functions, "run(", "captureDoubleyS2i_SdtF")
    #expect(double.contains("return ") && !double.contains("arg1"), Comment(rawValue: double))
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

/// A capture no layout proves: the call passes more than the list holds, and
/// shows what the body reads.
@Test(arguments: optimizedBuilds)
func aCallWithAnUnplacedCaptureFollowsTheBodyIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    let string = try caller(functions, "captureString")
    #expect(string.contains("of DroppedArgs.run(arg0, ?, ?, arg2)"), Comment(rawValue: string))
    // x1 is left over from the caller, and the body never reads it.
    let stale = try caller(functions, "captureDoubleThenAdd")
    #expect(!stale.contains("of DroppedArgs.run(arg0, arg1"), Comment(rawValue: stale))
    let double = try caller(functions, "captureDoubleVar")
    #expect(double.contains("of DroppedArgs.run(arg0, local_18)"), Comment(rawValue: double))
}

/// The tail call of a closure-propagated specialization over a generic one
/// is a return, a substituted result included.
@Test(arguments: optimizedBuilds)
func aClosurePropagatedTailCallIsAReturnIfPresent(path: String) async throws {
    guard let functions = try await functions(path) else { return }
    let text = try caller(functions, "useApply")
    #expect(text.contains("    return function signature specialization <"), Comment(rawValue: text))
    let folded = try caller(functions, "useFolded")
    #expect(folded.contains("    return function signature specialization <"), Comment(rawValue: folded))
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
