// Fixture for compare-and-branch shapes the structurer reads from text.
// `cmn a, b` sets the flags from `a + b`, so it compares a with -b; `b.mi` /
// `b.pl` test the sign of that sum or difference, not of `a`.
//
// Built by `build.sh` into `libCompares.dylib` (-O).

@inline(never) public func sink(_ x: Int) -> Int { x &* 7 }

@inline(never) public func onMinusOne(_ x: Int) -> Int {
    if x == -1 { return sink(x) }
    return 5
}

@inline(never) public func onMinusTen(_ x: Int) -> Int {
    if x != -10 { return sink(x) }
    return 9
}

@inline(never) public func doubled(_ x: Int) -> Int { x * 2 }

// The tracer leaves a call-result operand to the structurer's text path, so
// this overflow check (`cmn x0, x8; b.mi` after the call) is read from text.
@inline(never) public func doubledSink(_ x: Int) -> Int { sink(x) * 2 }
