import Testing
@testable import SwiftDecompilerCore

/// Unit tests for the Phase-1 type lattice (`ValueType`) and its inference
/// (`TypeInference`) — the representation that fixes the U1 signed/unsigned
/// defect. These are pure (no binary), so they pin the lattice invariants
/// independently of any lowering.
struct ValueTypeTests {
    // MARK: - meet (the join used at CFG merges and to combine evidence)

    @Test func meetKeepsOnlyAgreedFacts() {
        let i64s = ValueType.signedInteger(64)
        let i32s = ValueType.signedInteger(32)
        // Same category + signedness, different width → width drops to nil.
        #expect(ValueType.meet(i64s, i32s) == ValueType(category: .integer, width: nil, signedness: .signed))
        // Same everything → unchanged (idempotent).
        #expect(ValueType.meet(i64s, i64s) == i64s)
        // Signedness disagreement → unknownSign; width agrees so it survives.
        #expect(ValueType.meet(.signedInteger(64), .unsignedInteger(64))
                == ValueType(category: .integer, width: 64, signedness: .unknownSign))
        // Category disagreement → unknown category, and disagreeing facets drop.
        #expect(ValueType.meet(.signedInteger(64), .boolean).category == .unknown)
    }

    @Test func meetIsCommutativeAndConservative() {
        let a = ValueType.signedInteger(64)
        let b = ValueType.unsignedInteger(32)
        #expect(ValueType.meet(a, b) == ValueType.meet(b, a))
        // meet never ADDS a fact: meeting with unknown cannot yield signed.
        #expect(ValueType.meet(a, .unknown).signedness != .signed || ValueType.meet(a, .unknown).category == .unknown)
        #expect(ValueType.meet(.unknown, .unknown) == .unknown)
    }

    // MARK: - classify (ABI/signature evidence)

    @Test func classifySignednessFromType() {
        #expect(TypeInference.classify("Swift.Int") == .signedInteger(64))
        #expect(TypeInference.classify("Swift.Int32") == .signedInteger(32))
        #expect(TypeInference.classify("Swift.UInt") == .unsignedInteger(64))
        #expect(TypeInference.classify("Swift.UInt8") == .unsignedInteger(8))
        #expect(TypeInference.classify("Swift.Bool") == .boolean)
        #expect(TypeInference.classify("Swift.Double").category == .floatingPoint)
        #expect(TypeInference.classify("Swift.UnsafeRawPointer").category == .pointer)
        // Anything not a concrete scalar is honestly unknown — not a guess.
        #expect(TypeInference.classify("Reconstruction.Color") == .unknown)
        #expect(TypeInference.classify("Swift.String") == .unknown)
    }

    // MARK: - typeOf (structural, the hard "no signedness from register shape" rule)

    @Test func typeOfDoesNotInventSignedness() {
        let args: [Int: ValueType] = [0: .signedInteger(64), 1: .unsignedInteger(64)]
        // A bare immediate is integer but signedness is UNKNOWN — bits prove nothing.
        #expect(TypeInference.typeOf(.immediate(42), arguments: args).signedness == .unknownSign)
        // A typed argument carries its signedness.
        #expect(TypeInference.typeOf(.argument(0), arguments: args).isSignedInteger)
        #expect(TypeInference.typeOf(.argument(1), arguments: args).isUnsignedInteger)
        // A comparison is boolean regardless of operands.
        #expect(TypeInference.typeOf(.binary(.less, .argument(0), .immediate(0)), arguments: args).category == .boolean)
        // `-x` is signed.
        #expect(TypeInference.typeOf(.unary(.negate, .argument(1)), arguments: args).isSignedInteger)
        // A low-byte mask of an unsigned value stays unsigned (truncation, not sign change).
        #expect(TypeInference.typeOf(.binary(.bitAnd, .argument(1), .immediate(0xff)), arguments: args).isUnsignedInteger)
        // A low-byte mask of a SIGNED value is no longer provably signed.
        #expect(TypeInference.typeOf(.binary(.bitAnd, .argument(0), .immediate(0xff)), arguments: args).signedness == .unknownSign)
    }

    // MARK: - operator signedness (instruction evidence travels on the value)

    @Test func unsignedOperatorsAreDistinctComparisons() {
        #expect(AbstractBinaryOperator.unsignedLess.isComparison)
        #expect(AbstractBinaryOperator.unsignedLess.isUnsignedComparison)
        #expect(!AbstractBinaryOperator.less.isUnsignedComparison)
        #expect(AbstractBinaryOperator.unsignedLess.signedForm == .less)
    }
}
