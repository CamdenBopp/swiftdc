import Testing
@testable import SwiftDecompilerCore

/// `sdiv` and `udiv` were one operator, folded as unsigned. Two signed
/// constants folded to the unsigned quotient of their bit patterns, and an
/// unsigned division rendered as the signed `/`. The differential oracle's
/// `unsignedQuotient` / `unsignedRemainderOf` cases check the rendering
/// against the binary; these pin the constant folding.
@Suite struct DivisionSignednessTests {
    private func fold(
        _ op: AbstractBinaryOperator, _ lhs: Int64, _ rhs: Int64
    ) -> AbstractValue {
        ValueTracer().testExpression(
            op, .immediate(UInt64(bitPattern: lhs)), .immediate(UInt64(bitPattern: rhs)))
    }

    @Test func signedConstantsFoldSigned() {
        #expect(fold(.divide, -7, 2) == .immediate(UInt64(bitPattern: -3)))
        #expect(fold(.remainder, -7, 2) == .immediate(UInt64(bitPattern: -1)))
        // sdiv wraps Int.min / -1 to Int.min, remainder 0.
        #expect(fold(.divide, .min, -1) == .immediate(UInt64(bitPattern: .min)))
        #expect(fold(.remainder, .min, -1) == .immediate(0))
    }

    @Test func unsignedConstantsFoldUnsigned() {
        #expect(fold(.unsignedDivide, -8, 3) == .immediate(UInt64(bitPattern: -8) / 3))
        #expect(fold(.unsignedRemainder, -8, 3) == .immediate(UInt64(bitPattern: -8) % 3))
    }

    @Test func divisionByZeroStaysUnknown() {
        #expect(fold(.divide, 7, 0) == .unknown)
        #expect(fold(.unsignedDivide, 7, 0) == .unknown)
    }

    /// `a - (a / b) * b` keeps its division's signedness when it folds to a
    /// remainder.
    @Test func remainderFoldKeepsSignedness() {
        let a = AbstractValue.argument(0), b = AbstractValue.argument(1)
        let tracer = ValueTracer()
        for (division, remainder) in [(AbstractBinaryOperator.divide, AbstractBinaryOperator.remainder),
                                      (.unsignedDivide, .unsignedRemainder)] {
            let q = tracer.testExpression(division, a, b)
            let folded = tracer.testExpression(.subtract, a, tracer.testExpression(.multiply, q, b))
            #expect(folded == .binary(remainder, a, b))
        }
    }
}
