// Independent native value/order oracle for a single uniqueness snapshot.
// Capturing the object changes the answer to a later query. Re-evaluating the
// original Bool at a consumer therefore changes the program's result.
public final class UniqueBox {
    public let payload: Int
    public init() { payload = 47 }
}
nonisolated(unsafe) private var captured: UniqueBox?
nonisolated(unsafe) private var marks: Int = 0

@_optimize(none) @inline(never)
public func markUnique() { marks += 1 }

@_optimize(none) @inline(never)
public func captureUniqueBox(_ box: UniqueBox) { captured = box }

@_optimize(none) @inline(never)
public func consumeUniqueSnapshot(_ value: Bool) -> Int { value ? 1 : 0 }

// Two uses, one before and one after an observable strong-reference change.
@inline(never)
public func branchThenCapture(_ box: inout UniqueBox) -> Int {
    let snapshot = isKnownUniquelyReferenced(&box)
    if snapshot { markUnique() }
    captureUniqueBox(box)
    return consumeUniqueSnapshot(snapshot)
}

// A single use also needs its original evaluation before the capture.
@inline(never)
public func captureThenConsume(_ box: inout UniqueBox) -> Int {
    let snapshot = isKnownUniquelyReferenced(&box)
    captureUniqueBox(box)
    return consumeUniqueSnapshot(snapshot)
}

// Observe the payload after a query so the positive native control has a
// material object lifetime even under whole-module optimization.
@_optimize(none) @inline(never)
public func observeUniquePayload(_ box: UniqueBox) -> Int { box.payload - 47 }

// With no intervening effect and only one use, the query may inline once.
@inline(never)
public func immediateSnapshot(_ box: inout UniqueBox) -> Bool {
    isKnownUniquelyReferenced(&box)
}

@_cdecl("uniqueness_branch_oracle")
public func branchOracle() -> Int {
    captured = nil
    marks = 0
    var box = UniqueBox()
    let before = branchThenCapture(&box)
    let after = isKnownUniquelyReferenced(&box)
    let result = before * 100 + marks * 10 + (after ? 1 : 0)
    captured = nil
    return result // 110: the original snapshot is true, the later one false.
}

@_cdecl("uniqueness_single_oracle")
public func singleOracle() -> Int {
    captured = nil
    marks = 0
    var box = UniqueBox()
    let before = captureThenConsume(&box)
    let after = isKnownUniquelyReferenced(&box)
    let result = before * 100 + (after ? 1 : 0)
    captured = nil
    return result // 100: the sole consumer still sees the earlier true.
}

@_cdecl("uniqueness_shared_oracle")
public func sharedOracle() -> Int {
    marks = 0
    var box = UniqueBox()
    captured = box
    let before = branchThenCapture(&box)
    let after = isKnownUniquelyReferenced(&box)
    let result = before * 100 + marks * 10 + (after ? 1 : 0)
    captured = nil
    return result // 0: both snapshots are false for a shared input.
}

@_cdecl("uniqueness_immediate_oracle")
@_optimize(none)
public func immediateOracle() -> Int {
    captured = nil
    var box = UniqueBox()
    let snapshot = immediateSnapshot(&box)
    return (snapshot ? 1 : 0) + observeUniquePayload(box)
}
