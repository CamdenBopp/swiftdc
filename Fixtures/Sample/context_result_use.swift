// Authored native receiver-use accounting reduction.
// No app code, symbols, or literals are copied here.
// The oracles count creation, ordinary/context use, effects, and destruction.
// 1234 (or 134 without an effect) requires exactly one lifetime in order.
// Negative results encode failed independent count/value checks as a bit mask.
// A native test should also inspect SIL/LLVM or assembly to verify that use(_:) 
// consumes its class receiver through the Swift context-self ABI (x20).

nonisolated(unsafe) private var selfUseTrace: Int64 = 0
nonisolated(unsafe) private var selfUseMakeCount: Int64 = 0
nonisolated(unsafe) private var selfUseEffectCount: Int64 = 0
nonisolated(unsafe) private var selfUseTakeCount: Int64 = 0
nonisolated(unsafe) private var selfUseMethodCount: Int64 = 0
nonisolated(unsafe) private var selfUseDeinitCount: Int64 = 0
nonisolated(unsafe) private var selfUseObservedPayload: Int64 = 0
nonisolated(unsafe) private var selfUseObservedArgument: Int64 = 0

@inline(__always)
private func selfUseMark(_ digit: Int64) {
    selfUseTrace = selfUseTrace &* 10 &+ digit
}

public final class SelfUseBox {
    public let payload: Int64

    public init(_ payload: Int64) {
        self.payload = payload
    }

    @inline(never)
    public func use(_ value: Int64) {
        selfUseMethodCount &+= 1
        selfUseObservedPayload = payload
        selfUseObservedArgument = value
        selfUseMark(3)
    }

    deinit {
        selfUseDeinitCount &+= 1
        selfUseMark(4)
    }
}

@inline(never)
public func makeSelfUseBox() -> SelfUseBox {
    selfUseMakeCount &+= 1
    selfUseMark(1)
    return SelfUseBox(47)
}

@inline(never)
public func selfUseEffect() {
    selfUseEffectCount &+= 1
    selfUseMark(2)
}

@inline(never)
public func takeSelfUseBox(_ box: SelfUseBox) {
    selfUseTakeCount &+= 1
    // Read the actual ordinary argument so this is an observable receiver use.
    selfUseObservedPayload = box.payload
    selfUseMark(2)
}

// Shape 1: the factory result appears only as context self. The intervening
// effect must keep one factory evaluation at its original instruction.
@_silgen_name("self_use_context_only_shape")
public func selfUseContextOnlyShape()

// Shape 2: one immediately adjacent ordinary argument use, then context self.
// The second use must be counted even though it is outside ordinary arguments.
@_silgen_name("self_use_mixed_shape")
public func selfUseMixedShape()

@inline(never)
private func resetSelfUseOracle() {
    selfUseTrace = 0
    selfUseMakeCount = 0
    selfUseEffectCount = 0
    selfUseTakeCount = 0
    selfUseMethodCount = 0
    selfUseDeinitCount = 0
    selfUseObservedPayload = 0
    selfUseObservedArgument = 0
}

@inline(never)
private func selfUseOracleResult(expectEffect: Bool, expectTake: Bool, expectedTrace: Int64) -> Int64 {
    var failures: Int64 = 0
    if selfUseMakeCount != 1 { failures |= 1 }
    if selfUseMethodCount != 1 { failures |= 2 }
    if selfUseDeinitCount != 1 { failures |= 4 }
    if selfUseEffectCount != (expectEffect ? 1 : 0) { failures |= 8 }
    if selfUseTakeCount != (expectTake ? 1 : 0) { failures |= 16 }
    if selfUseObservedPayload != 47 { failures |= 32 }
    if selfUseObservedArgument != 9 { failures |= 64 }
    if selfUseTrace != expectedTrace { failures |= 128 }
    return failures == 0 ? selfUseTrace : -failures
}

@_cdecl("self_use_context_only_oracle")
public func selfUseContextOnlyOracle() -> Int64 {
    resetSelfUseOracle()
    // A separate non-inlined shape returns after releasing its local box.
    selfUseContextOnlyShape()
    return selfUseOracleResult(expectEffect: true, expectTake: false, expectedTrace: 1234)
}

@_cdecl("self_use_mixed_oracle")
public func selfUseMixedOracle() -> Int64 {
    resetSelfUseOracle()
    selfUseMixedShape()
    return selfUseOracleResult(expectEffect: false, expectTake: true, expectedTrace: 1234)
}

// No intervening effect: the sole context use may inline once, but must
// consume the original producer statement rather than print a second call.
@_silgen_name("self_use_direct_shape")
public func selfUseDirectShape()
@_cdecl("self_use_direct_oracle")
public func selfUseDirectOracle() -> Int64 {
    resetSelfUseOracle()
    selfUseDirectShape()
    return selfUseOracleResult(expectEffect: false, expectTake: false, expectedTrace: 134)
}


public struct SelfUseHolder {
    public let box: SelfUseBox
    public let a, b, c, d: Int64
}

// Five words require an indirect return; the receiver is the first word.
@inline(never)
public func makeSelfUseHolder() -> SelfUseHolder {
    SelfUseHolder(box: makeSelfUseBox(), a: 1, b: 2, c: 3, d: 4)
}

@_silgen_name("self_use_indirect_shape")
public func selfUseIndirectShape()

@_cdecl("self_use_indirect_oracle")
public func selfUseIndirectOracle() -> Int64 {
    resetSelfUseOracle()
    selfUseIndirectShape()
    return selfUseOracleResult(expectEffect: true, expectTake: false, expectedTrace: 1234)
}
