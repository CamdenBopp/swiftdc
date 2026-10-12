import Testing
@testable import SwiftDecompilerCore

/// The compiler lowers `x / D` and `x % D` to a multiply-high by a magic
/// reciprocal. Each test replays, through the tracer's own expression builder,
/// the instruction sequence `xcrun swiftc -O` emitted for that divisor
/// (Xcode 26, arm64), and checks the finished sequence folds back to the source
/// operation while a partial one does not. The differential oracle checks the
/// same functions against the compiled binary; this suite pins the shapes,
/// including the unsigned high half the oracle's signed evaluator cannot reach.
@Suite struct MagicDivisionTests {
    private let x = AbstractValue.argument(0)

    /// smulh x8, x0, M; asr x9, x8, #1; add x0, x9, x8, lsr #63
    @Test func signedSeven() {
        let hi = fold(.multiplyHigh, x, .immediate(0x4924_9249_2492_4925))
        let result = fold(.add, fold(.arithmeticShiftRight, hi, .immediate(1)),
                          fold(.shiftRight, hi, .immediate(63)))
        #expect(result == .binary(.divide, x, .immediate(7)))
    }

    /// smulh x8, x0, M; add x0, x8, x8, lsr #63 (no post-shift)
    @Test func signedThree() {
        let hi = fold(.multiplyHigh, x, .immediate(0x5555_5555_5555_5556))
        let result = fold(.add, hi, fold(.shiftRight, hi, .immediate(63)))
        #expect(result == .binary(.divide, x, .immediate(3)))
    }

    /// smulh x8, x0, M; add x8, x8, x0; asr x9, x8, #3; add x0, x9, x8, lsr #63
    /// (add-back: M is negative as a signed value, and the sign comes from hi + x)
    @Test func signedFifteenAddBack() {
        let hi = fold(.multiplyHigh, x, .immediate(0x8888_8888_8888_8889))
        let sum = fold(.add, hi, x)
        let result = fold(.add, fold(.arithmeticShiftRight, sum, .immediate(3)),
                          fold(.shiftRight, sum, .immediate(63)))
        #expect(result == .binary(.divide, x, .immediate(15)))
    }

    /// x / -7: same shape as x / 7, with the negated reciprocal.
    @Test func signedMinusSeven() {
        let hi = fold(.multiplyHigh, x, .immediate(0xB6DB_6DB6_DB6D_B6DB))
        let result = fold(.add, fold(.arithmeticShiftRight, hi, .immediate(1)),
                          fold(.shiftRight, hi, .immediate(63)))
        #expect(result == .binary(.divide, x, .immediate(UInt64(bitPattern: -7))))
    }

    /// umulh x8, x0, M; lsr x0, x8, #3
    @Test func unsignedTen() {
        let hi = fold(.unsignedMultiplyHigh, x, .immediate(0xCCCC_CCCC_CCCC_CCCD))
        #expect(fold(.shiftRight, hi, .immediate(3)) == .binary(.divide, x, .immediate(10)))
    }

    /// umulh x8, x0, M; sub x9, x0, x8; add x8, x8, x9, lsr #1; lsr x0, x8, #2
    @Test func unsignedSevenFixUp() {
        let hi = fold(.unsignedMultiplyHigh, x, .immediate(0x2492_4924_9249_2493))
        let half = fold(.shiftRight, fold(.subtract, x, hi), .immediate(1))
        let result = fold(.shiftRight, fold(.add, hi, half), .immediate(2))
        #expect(result == .binary(.divide, x, .immediate(7)))
    }

    /// lsr x8, x0, #3; umulh x8, x8, M; lsr x0, x8, #4 (pre-shift)
    @Test func unsignedThousandPreShift() {
        let hi = fold(.unsignedMultiplyHigh, fold(.shiftRight, x, .immediate(3)),
                      .immediate(0x20C4_9BA5_E353_F7CF))
        #expect(fold(.shiftRight, hi, .immediate(4)) == .binary(.divide, x, .immediate(1000)))
    }

    /// The x / 7 sequence, then sub x8, x8, x8, lsl #3; add x0, x0, x8:
    /// x + (q - 8q) is x - 7q, which is x % 7.
    @Test func signedRemainderSeven() {
        let hi = fold(.multiplyHigh, x, .immediate(0x4924_9249_2492_4925))
        let q = fold(.add, fold(.arithmeticShiftRight, hi, .immediate(1)),
                     fold(.shiftRight, hi, .immediate(63)))
        let scaled = fold(.subtract, q, fold(.shiftLeft, q, .immediate(3)))
        #expect(fold(.add, x, scaled) == .binary(.remainder, x, .immediate(7)))
    }

    /// Before the sign correction, `asr(smulh(x, M), 1)` floors rather than
    /// truncates, so it is not x / 7 at a negative x and must not fold.
    @Test func partialSignedSequenceStaysSymbolic() {
        let hi = fold(.multiplyHigh, x, .immediate(0x4924_9249_2492_4925))
        let partial = fold(.arithmeticShiftRight, hi, .immediate(1))
        #expect(partial == .binary(.arithmeticShiftRight, hi, .immediate(1)))
    }

    /// A constant that is no divisor's reciprocal must not fold.
    @Test func unrecognizedMagicStaysSymbolic() {
        let hi = fold(.unsignedMultiplyHigh, x, .immediate(0xDEAD_BEEF_DEAD_BEEF))
        let result = fold(.shiftRight, hi, .immediate(3))
        #expect(result == .binary(.shiftRight, hi, .immediate(3)))
    }

    /// A plain shift is a shift, not a division by a power of two.
    @Test func plainShiftIsNotADivision() {
        #expect(fold(.arithmeticShiftRight, x, .immediate(3)) == .binary(.arithmeticShiftRight, x, .immediate(3)))
    }

    /// Two operands (the checked-multiply overflow test is `smulh a, b`) are
    /// not a division by a constant.
    @Test func twoUnknownsStaySymbolic() {
        let hi = fold(.multiplyHigh, x, .argument(1))
        let result = fold(.add, hi, fold(.shiftRight, hi, .immediate(63)))
        if case .binary(.divide, _, _) = result { Issue.record("folded \(result)") }
    }

    @Test func immediatesConstantFold() {
        #expect(fold(.multiplyHigh, .immediate(UInt64(bitPattern: -1)), .immediate(5)) == .immediate(UInt64.max))
        #expect(fold(.unsignedMultiplyHigh, .immediate(1 << 63), .immediate(4)) == .immediate(2))
    }

    private func fold(
        _ op: AbstractBinaryOperator, _ lhs: AbstractValue, _ rhs: AbstractValue
    ) -> AbstractValue {
        ValueTracer().testExpression(op, lhs, rhs)
    }
}
