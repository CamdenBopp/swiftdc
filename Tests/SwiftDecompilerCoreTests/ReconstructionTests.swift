import Testing
import Foundation
@testable import SwiftDecompilerCore

/// End-to-end assertions on the Swift-body pseudocode reconstruction, driven by
/// `Fixtures/Sample/libReconstruction.dylib` (build it with
/// `Fixtures/Sample/build.sh`). Each fixture function isolates one construct so
/// the recovered pseudocode can be asserted verbatim.
///
/// Absent the built fixture these skip, keeping `swift test` green on a clean
/// checkout — the same convention as the other `…IfPresent` tests.
private let reconstructionFixture = "Fixtures/Sample/libReconstruction.dylib"

/// The recovered pseudocode for every function matching `filter` in a fixture
/// variant, or nil when it hasn't been built.
private func reconstructionPseudo(
    _ filter: String, in fixture: String = reconstructionFixture
) async throws -> String? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: fixture, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

/// The recovered *structured* view (if/else/while) for every function matching
/// `filter`, or nil when the fixture hasn't been built.
private func reconstructionStructured(
    _ filter: String, in fixture: String = reconstructionFixture
) async throws -> String? {
    guard FileManager.default.fileExists(atPath: fixture) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default)
            .disassemble(path: fixture, functionFilter: filter)
    }
    return functions.map { $0.renderStructured() }.joined(separator: "\n")
}

// MARK: - Comparisons (NZCV + cset)

@Test func recoversComparisonReturnsIfPresent() async throws {
    // `x > 0` lowers to `0 - x < 0` (constant on the left); operand
    // normalization mirrors it back to the source form `arg0 > 0`.
    guard let positive = try await reconstructionPseudo("isPositive") else { return }
    #expect(positive.contains("return (arg0 > 0)"))

    guard let equal = try await reconstructionPseudo("isEqual") else { return }
    #expect(equal.contains("return (arg0 == arg1)"))

    guard let atLeast = try await reconstructionPseudo("atLeast") else { return }
    #expect(atLeast.contains("return (arg0 >= arg1)"))
}

// MARK: - U1: signed/unsigned comparison distinction (type lattice)

/// A signed range check `x >= 0 && x < N` optimizes to a single UNSIGNED
/// comparison; the type lattice recovers the range idiom rather than a bare
/// signed `(x < N)` (which would be true for negative x, unlike the machine —
/// proven equivalent to the unsigned machine compare by differential test). At
/// `-Onone` the two source comparisons appear directly; at `-O` the unsigned
/// lowering recovers `(0 <= x) && (x < N)`.
@Test func recoversSignedRangeCheckIfPresent() async throws {
    guard let onone = try await reconstructionPseudo("rangeCheck") else { return }
    #expect(onone.contains("(arg0 >= 0)") && onone.contains("(arg0 < 100)"))

    guard let opt = try await reconstructionPseudo(
        "rangeCheck", in: "Fixtures/Sample/libReconstruction.opt.dylib") else { return }
    #expect(opt.contains("return ((0 <= arg0) && (arg0 < 100))"))
    #expect(!opt.contains("return (arg0 < 100)")) // the U1 defect must not reappear

    // A COMPUTED signed value (x + 1) must still recover the range idiom — the
    // constant is signedness-neutral, so structural inference keeps it signed.
    guard let computed = try await reconstructionPseudo(
        "computedRange", in: "Fixtures/Sample/libReconstruction.opt.dylib") else { return }
    #expect(computed.contains("return ((0 <= (arg0 + 1)) && ((arg0 + 1) < 100))"))
    #expect(!computed.contains("<\u{1D41}")) // not exposed-unsigned — the type is known
}

/// Adversarial: a genuine signed comparison stays signed — the fix is scoped to
/// unsigned condition codes and must not disturb ordinary signed `<`.
@Test func keepsSignedComparisonSignedIfPresent() async throws {
    for fixture in [reconstructionFixture, "Fixtures/Sample/libReconstruction.opt.dylib"] {
        guard let s = try await reconstructionPseudo("signedLess", in: fixture) else { continue }
        #expect(s.contains("return (arg0 < 100)"))
    }
}

// MARK: - Argument seeding (integer + floating-point)

@Test func recoversScalarArgumentsIfPresent() async throws {
    guard let addThree = try await reconstructionPseudo("addThree") else { return }
    #expect(addThree.contains("return ((arg0 + arg1) + arg2)"))

    guard let hypot = try await reconstructionPseudo("hypotenuse") else { return }
    #expect(hypot.contains("return sqrt(((arg0 * arg0) + (arg1 * arg1)))"))

    // Mixed: an integer parameter in x0, a floating-point one in v0.
    guard let scaled = try await reconstructionPseudo("scaleInt") else { return }
    #expect(scaled.contains("return (arg0 * arg1)"))

    // A floating-point constant in an expression renders as its decimal, not
    // the raw IEEE-754 bit pattern, because the expression reaches a Double arg.
    guard let poly = try await reconstructionPseudo("polynomial") else { return }
    #expect(poly.contains("return ((arg0 * arg0) + 3.14)"))
    #expect(!poly.contains("0x"))

    // An fmov-encodable constant is decoded from its machine encoding, not a
    // literal-pool load, and renders as its decimal.
    guard let scaled = try await reconstructionPseudo("scaled") else { return }
    #expect(scaled.contains("return (arg0 * 2.5)"))
}

// MARK: - HFA struct decomposition

@Test func decomposesHFAStructSelfAndArgumentsIfPresent() async throws {
    // A computed-property getter: self decomposed into self.x / self.y.
    guard let magnitude = try await reconstructionPseudo("magnitudeSquared") else { return }
    #expect(magnitude.contains("return ((self.x * self.x) + (self.y * self.y))"))

    // A method taking a by-value struct parameter: arg0.x / arg0.y recovered.
    guard let dot = try await reconstructionPseudo("Vec2.dot") else { return }
    #expect(dot.contains("return ((arg0.x * self.x) + (arg0.y * self.y))"))
}

// MARK: - Class vtable property access

@Test func namesVTablePropertyAccessIfPresent() async throws {
    guard let doubled = try await reconstructionPseudo("doubled") else { return }
    #expect(doubled.contains("return (self.value + self.value)"))

    guard let advance = try await reconstructionPseudo("advance") else { return }
    #expect(advance.contains("self.value = (self.value + self.step)"))

    guard let reset = try await reconstructionPseudo("reset") else { return }
    #expect(reset.contains("self.value = 0"))
}

// MARK: - Dynamic casts

@Test func recoversDynamicCastsIfPresent() async throws {
    guard let optional = try await reconstructionPseudo("castOptional") else { return }
    #expect(optional.contains("as? Reconstruction.Dog"))

    guard let forced = try await reconstructionPseudo("castForced") else { return }
    #expect(forced.contains("as! Reconstruction.Dog"))

    guard let string = try await reconstructionPseudo("castToString") else { return }
    #expect(string.contains("as? Swift.String"))
}

// MARK: - Single-register (reference) Optional nil checks (O1, type lattice)

/// A reference (class) optional is one register with `nil == 0`, so its nil
/// check reconstructs as `!= nil` / `== nil`. A value (struct) optional is
/// multi-register (payload + tag) and must decline — never mis-seeded.
@Test func reconstructsReferenceOptionalNilCheckIfPresent() async throws {
    for fixture in [reconstructionFixture, "Fixtures/Sample/libReconstruction.opt.dylib"] {
        guard let has = try await reconstructionPseudo("hasAnimal", in: fixture) else { continue }
        #expect(has.contains("return (arg0 != nil)"))

        guard let isNil = try await reconstructionPseudo("isNilAnimal", in: fixture) else { continue }
        #expect(isNil.contains("return (arg0 == nil)"))
    }

    // Adversarial: a struct optional is multi-register — it must NOT be seeded as
    // a single-register nil check (no `!= nil`, no `!= 0`).
    guard let vec = try await reconstructionPseudo("hasVec") else { return }
    #expect(!vec.contains("!= nil") && !vec.contains("arg0 != 0"))
}

// MARK: - Ternary / select reconstruction (control-flow value merge)

@Test func reconstructsTernarySelectIfPresent() async throws {
    // `-Onone` diamond: two arms store into a merge slot. Semantically
    // equivalent — the compiler tests `x >= 0`, not `x < 0`.
    guard let clamp = try await reconstructionPseudo("clampLow") else { return }
    #expect(clamp.contains("return ((arg0 >= 0) ? arg0 : 0)"))

    guard let maxOf = try await reconstructionPseudo("maxOf") else { return }
    #expect(maxOf.contains(" ? ") && maxOf.contains("arg0") && maxOf.contains("arg1"))

    // The `Bool` parameter `c` arrives as a bit-0 test `(c & 1) == 0`; Bool-arg
    // recognition folds it to `!c`, so the ternary reads like the source
    // `c ? a + 1 : a - 1` (the compiler tested the false arm first).
    guard let pick = try await reconstructionPseudo("pickInc") else { return }
    #expect(pick.contains("return (!arg0 ? (arg1 - 1) : (arg1 + 1))"))
}

/// The optimized build lowers the ternary to a branchless `csel`; it must
/// reconstruct the same select — and survive stripping, since the value tracer
/// needs no symbols for it.
@Test func reconstructsOptimizedTernaryIfPresent() async throws {
    for fixture in ["Fixtures/Sample/libReconstruction.opt.dylib",
                    "Fixtures/Sample/libReconstruction.opt.stripped.dylib"] {
        guard let maxOf = try await reconstructionPseudo("maxOf", in: fixture) else { continue }
        #expect(maxOf.contains("return ((arg1 > arg0) ? arg1 : arg0)"))
    }
}

/// Adversarial: a three-way merge is not a clean 2-arm diamond, so the tool must
/// decline to reconstruct a select rather than fabricate one.
@Test func declinesToGuessNonDiamondSelectIfPresent() async throws {
    guard let threeWay = try await reconstructionPseudo("threeWay") else { return }
    #expect(!threeWay.contains(" ? ")) // no fabricated select
}

/// Pointer-optional nil-coalescing: one register (nil == 0), so at -O it
/// reconstructs as a select — semantically `arg0 ?? arg1`.
@Test func reconstructsPointerNilCoalescingIfPresent() async throws {
    guard let ptr = try await reconstructionPseudo(
        "ptrOrElse", in: "Fixtures/Sample/libReconstruction.opt.dylib") else { return }
    #expect(ptr.contains("return ((arg0 == 0) ? arg1 : arg0)"))
}

/// Adversarial: a TAGGED optional (`Int?`, payload + tag byte in separate
/// registers) has no single-register nil check, so nil-coalescing over it must
/// decline rather than guess — in both debug and optimized builds.
@Test func declinesTaggedOptionalNilCoalescingIfPresent() async throws {
    for fixture in [reconstructionFixture, "Fixtures/Sample/libReconstruction.opt.dylib"] {
        guard let opt = try await reconstructionPseudo("intOrDefault", in: fixture) else { continue }
        #expect(!opt.contains(" ? ")) // no fabricated select over the tag
    }
}

// MARK: - Robustness edge cases

@Test func handlesArithmeticEdgeCasesIfPresent() async throws {
    // A constant return.
    guard let constant = try await reconstructionPseudo("constant") else { return }
    #expect(constant.contains("return 42"))

    // A deeply nested expression (exercises the bounded expression tree).
    guard let deep = try await reconstructionPseudo("deepNest") else { return }
    #expect(deep.contains("return (((arg0 + arg1) * (arg2 - arg3)) + ((arg0 - arg2) * (arg1 + arg3)))"))

    // All eight integer argument registers.
    guard let eight = try await reconstructionPseudo("eightArgs") else { return }
    #expect(eight.contains("arg7"))

    // Interleaved integer (x0/x1) and floating-point (v0/v1) parameters —
    // the two Doubles are arg1 and arg3.
    guard let mixed = try await reconstructionPseudo("interleaved") else { return }
    #expect(mixed.contains("return (arg1 + arg3)"))
}

// MARK: - Homogeneous array literals

@Test func recoversArrayLiteralsIfPresent() async throws {
    guard let triple = try await reconstructionPseudo("triple") else { return }
    #expect(triple.contains("return [10, 20, 30]"))

    guard let pair = try await reconstructionPseudo("pairOf") else { return }
    #expect(pair.contains("return [arg0, arg1]"))

    // A non-Int element type (Double stride) recovers too.
    guard let doubles = try await reconstructionPseudo("doublesOf") else { return }
    #expect(doubles.contains("return [arg0, arg1]"))
}

// MARK: - Wider arithmetic and layout edge cases

@Test func recoversWiderArithmeticIfPresent() async throws {
    guard let bits = try await reconstructionPseudo("bitOps") else { return }
    #expect(bits.contains("return ((arg0 & arg1) | (arg0 << 2))"))

    // Float parameters seed v-registers just as Double does.
    guard let float = try await reconstructionPseudo("floatMath") else { return }
    #expect(float.contains("return ((arg0 * arg1) + arg0)"))

    // Integer division (sdiv), distinct from the FP divide path.
    guard let div = try await reconstructionPseudo("intDivide") else { return }
    #expect(div.contains("return (arg0 / arg1)"))

    // Remainder — folded from the sdiv/mul/sub the compiler emits.
    guard let rem = try await reconstructionPseudo("remainder") else { return }
    #expect(rem.contains("return (arg0 % arg1)"))

    // Fused multiply-add (madd): `a + b * c`.
    guard let fma = try await reconstructionPseudo("fusedMultiplyAdd") else { return }
    #expect(fma.contains("return (arg0 + (arg1 * arg2))"))

    // A 3-field HFA struct decomposes self across d0, d1, d2.
    guard let luminance = try await reconstructionPseudo("luminance") else { return }
    #expect(luminance.contains("return ((self.r + self.g) + self.b)"))
}

// MARK: - No-payload enum case naming

/// A no-payload enum's returned tag is its declaration index, so it names the
/// case (`.south` is tag 2). The case names live in `__swift5_fieldmd`, which
/// `strip` does not touch — so it holds across debug, optimized, and stripped.
@Test func namesNoPayloadEnumCasesIfPresent() async throws {
    for fixture in [reconstructionFixture,
                    "Fixtures/Sample/libReconstruction.opt.dylib",
                    "Fixtures/Sample/libReconstruction.opt.stripped.dylib"] {
        guard let heading = try await reconstructionPseudo("heading", in: fixture) else { continue }
        #expect(heading.contains("return Reconstruction.Direction.south"))
    }

    // A raw-value enum names by DECLARATION INDEX, not the raw value: `.high`
    // is tag 2 even though its `rawValue` is 12. Asserted only at `-Onone`: at
    // `-O` the linker's identical-code-folding merges `urgency` with any other
    // `mov w0, #2; ret` body (here `heading`), so only one label survives — an
    // inherent property of the binary, not of the reconstruction.
    guard let urgency = try await reconstructionPseudo("urgency") else { return }
    #expect(urgency.contains("return Reconstruction.Priority.high"))
}

/// Adversarial: a PAYLOAD enum's tag does not index its cases in declaration
/// order, so a returned immediate must stay a raw value — never a fabricated
/// `.eof`. Holds under optimization too.
@Test func declinesPayloadEnumCaseNamingIfPresent() async throws {
    for fixture in [reconstructionFixture, "Fixtures/Sample/libReconstruction.opt.dylib"] {
        guard let end = try await reconstructionPseudo("endToken", in: fixture) else { continue }
        #expect(!end.contains(".eof"))   // no fabricated case name
        #expect(end.contains("return 0")) // honest raw fallback
    }
}

// MARK: - Enum equality against a case literal

/// A no-payload enum parameter compared to a case literal reconstructs the
/// comparison and names the case — identically across debug, optimized, and
/// stripped, since both the `__derived_enum_equals` (-Onone) and masked-tag
/// compare (-O) lowerings resolve the tag through `__swift5_fieldmd`.
@Test func reconstructsEnumEqualityIfPresent() async throws {
    for fixture in [reconstructionFixture,
                    "Fixtures/Sample/libReconstruction.opt.dylib",
                    "Fixtures/Sample/libReconstruction.opt.stripped.dylib"] {
        guard let north = try await reconstructionPseudo("isNorth", in: fixture) else { continue }
        #expect(north.contains("return (arg0 == Reconstruction.Direction.north)"))

        // `!=` recovered from the compiler's `^ 1` logical negation.
        guard let west = try await reconstructionPseudo("notWest", in: fixture) else { continue }
        #expect(west.contains("return (arg0 != Reconstruction.Direction.west)"))

        // Two enum values (no case literal): the synthesized `==` folds to a
        // plain equality with nothing to name.
        guard let same = try await reconstructionPseudo("sameHeading", in: fixture) else { continue }
        #expect(same.contains("return (arg0 == arg1)"))
    }
}

/// Adversarial: a PAYLOAD enum's `==` can name no case (its operands pass
/// indirectly and its tags don't index the case list), so the reconstruction
/// must not fabricate `.ping` — it declines to the raw call or nothing.
@Test func declinesPayloadEnumEqualityNamingIfPresent() async throws {
    for fixture in [reconstructionFixture, "Fixtures/Sample/libReconstruction.opt.dylib"] {
        guard let ping = try await reconstructionPseudo("isPing", in: fixture) else { continue }
        #expect(!ping.contains(".ping"))
    }
}

/// An `if` over a no-payload enum: the compiler lowers the guard as a falsity
/// test (`(d == .case) == 0 ? … : …`), which the reconstruction peels so the
/// ternary reads cleanly. Build-agnostic — debug keeps the `!=` arm, `-O` the
/// `==` arm — but neither leaves a `== 0` / `!= 0` boolean double-negation.
@Test func peelsEnumFalsityTestIfPresent() async throws {
    for fixture in [reconstructionFixture,
                    "Fixtures/Sample/libReconstruction.opt.dylib",
                    "Fixtures/Sample/libReconstruction.opt.stripped.dylib"] {
        guard let north = try await reconstructionPseudo("northScore", in: fixture) else { continue }
        #expect(north.contains("Reconstruction.Direction.north"))
        #expect(north.contains(" ? "))               // a ternary was recovered
        #expect(!north.contains("== 0)"))             // no leftover falsity test
        #expect(!north.contains("!= 0)"))
    }
}

// MARK: - Switch over a tag (N-way value merge → nested ternary)

/// A switch over a no-payload enum reconstructs as a nested ternary with every
/// case named and the fall-through as the final else. Asserted at `-Onone`,
/// where the cascade is intact; at `-O` the optimizer collapses this particular
/// switch to arithmetic (`(tag & 0xff) + 1`), which the arithmetic path already
/// recovers — a different but equally faithful form.
@Test func reconstructsEnumSwitchIfPresent() async throws {
    guard let rank = try await reconstructionPseudo("rank") else { return }
    #expect(rank.contains("return ((arg0 == Reconstruction.Direction.north) ? 1 "
        + ": ((arg0 == Reconstruction.Direction.east) ? 2 "
        + ": ((arg0 == Reconstruction.Direction.south) ? 3 : 4)))"))
}

/// A switch over an `Int` uses the `n != k` fall-through lowering rather than
/// the enum's `tag == k` taken edge; the resolver's reaching-condition
/// unification recovers the same nested ternary. Operand normalization mirrors
/// the `subs`-derived constant back to the right (`arg0 == 1`, not `1 == arg0`),
/// so every arm reads consistently.
@Test func reconstructsIntegerSwitchIfPresent() async throws {
    guard let grade = try await reconstructionPseudo("gradeOf") else { return }
    #expect(grade.contains("((arg0 == 0) ? 10 : ((arg0 == 1) ? 20 : ((arg0 == 2) ? 30 : 99)))"))
}

/// Negative integer constants render as signed decimals (`-1`), not the
/// 16-digit two's-complement hex the immediate is stored as; a genuine large
/// unsigned mask stays hex, so the narrow negative window never mislabels one.
@Test func rendersNegativeConstantsIfPresent() async throws {
    guard let polarity = try await reconstructionPseudo("polarity") else { return }
    #expect(polarity.contains("((arg0 == 0) ? -1 : ((arg0 == 1) ? -2 : -3))"))

    guard let mask = try await reconstructionPseudo("highMask") else { return }
    #expect(mask.contains("0xff00000000000000")) // not relabelled negative
    #expect(!mask.contains("return -"))
}

/// A constant returned from a Bool- or floating-point-typed function reads per
/// its declared type: `true`/`false`, and a float decimal rather than the raw
/// IEEE-754 bit pattern the immediate stores.
@Test func rendersTypedReturnConstantsIfPresent() async throws {
    guard let flag = try await reconstructionPseudo("alwaysTrue") else { return }
    #expect(flag.contains("return true"))

    guard let pi = try await reconstructionPseudo("piValue") else { return }
    #expect(pi.contains("return 3.14159"))
    #expect(!pi.contains("0x")) // not the raw bit pattern
}

/// A `Bool` parameter is recognized as a boolean, so `!b` folds to `!arg0`
/// instead of the lowered `(arg0 ^ 1) & 1`.
@Test func foldsBoolArgumentNegationIfPresent() async throws {
    guard let neg = try await reconstructionPseudo("negateFlag") else { return }
    #expect(neg.contains("return !arg0"))
    #expect(!neg.contains("^ 1")) // no leftover masked xor
}

/// Unary negation is emitted as `0 - x` and folds back to `-x`; a genuine
/// subtraction from a constant keeps its `-`.
@Test func foldsUnaryNegationIfPresent() async throws {
    guard let abs = try await reconstructionPseudo("absValue") else { return }
    #expect(abs.contains("return ((arg0 >= 0) ? arg0 : -arg0)"))
    #expect(!abs.contains("(0 - arg0)")) // not the raw subtract-from-zero

    guard let sub = try await reconstructionPseudo("fromHundred") else { return }
    #expect(sub.contains("return (100 - arg0)")) // genuine subtraction untouched
}

/// Short-circuit `&&`/`||` lower to a select with a `false`/`true` literal arm;
/// they reconstruct as the logical operator, with a compound condition nesting.
/// The adversarial ternaries (`clampLow`/`maxOf`/`pickInc`, asserted elsewhere)
/// carry a `0`/`1` but a non-boolean other arm, so they stay plain ternaries.
@Test func reconstructsLogicalOperatorsIfPresent() async throws {
    guard let and = try await reconstructionPseudo("bothTrue") else { return }
    #expect(and.contains("return (arg0 && arg1)"))

    guard let or = try await reconstructionPseudo("eitherTrue") else { return }
    #expect(or.contains("return (arg0 || arg1)"))

    guard let range = try await reconstructionPseudo("withinRange") else { return }
    #expect(range.contains("return ((arg0 >= 0) && (arg0 < 10))"))

    // `x > 1` lowers constant-left (`1 < x`); normalization applies inside the
    // `&&` operand too, so it reads `(arg0 > 1)` not `(1 < arg0)`.
    guard let above = try await reconstructionPseudo("aboveOneBelowTen") else { return }
    #expect(above.contains("return ((arg0 > 1) && (arg0 < 10))"))
}

// MARK: - Checked-arithmetic overflow-trap folding (structured view)

@Test func foldsOverflowTrapsInStructuredViewIfPresent() async throws {
    // A checked `+=` loop: the `while` structure survives, but the two per-`+`
    // overflow guards (`adds; cset vs; tbnz trap`) are folded away — no trap noise.
    if let accumulate = try await reconstructionStructured("accumulate") {
        #expect(accumulate.contains("while"))
        #expect(!accumulate.contains("trap()"))
        // Balanced braces — folding never produces structurally broken output.
        #expect(accumulate.filter { $0 == "{" }.count == accumulate.filter { $0 == "}" }.count)
    }
    // Straight-line checked add: overflow guard folds, leaving no trap in the body.
    if let checked = try await reconstructionStructured("checkedSum") {
        #expect(!checked.contains("trap()"))
    }
}

@Test func keepsGenuineTrapsUnfoldedIfPresent() async throws {
    // Adversarial: a `precondition` is not an overflow check — at -O it lowers to
    // a raw `brk` reached by a signed compare (`b.lt`), which the fold must NOT
    // eat. The trap stays visible.
    let optFixture = "Fixtures/Sample/libReconstruction.opt.dylib"
    if let precond = try await reconstructionStructured("requirePositive", in: optFixture) {
        #expect(precond.contains("trap()"))
    }
    // At -Onone the same precondition is a `_assertionFailure` call — also kept.
    if let precond = try await reconstructionStructured("requirePositive") {
        #expect(precond.contains("trap()") || precond.contains("assertionFailure"))
    }
}
