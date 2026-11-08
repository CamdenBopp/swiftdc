// Authored -Onone loop-entry reductions. Each initial value is part of the
// function's behavior, and nested counters restart inside the outer loop.
@inline(never) public func nonzeroStart(_ n: Int) -> Int {
    var i = 3
    var total = 17
    while i < n { total &+= i; i &+= 1 }
    return total
}
@inline(never) public func sequentialSums(_ n: Int) -> Int {
    var i = 3
    var first = 17
    while i < n { first &+= i; i &+= 1 }
    var j = 7
    var second = 41
    while j < n { second &+= j; j &+= 1 }
    return first &+ second
}
@inline(never) public func nestedCounters(_ n: Int) -> Int {
    var i = 3
    var total = 17
    while i < n {
        var j = 7
        while j < n { total &+= j; j &+= 1 }
        i &+= 1
    }
    return total
}
@inline(never) public func unknownStart(_ n: Int, _ start: Int) -> Int {
    var i = start
    while i < n { i &+= 1 }
    return i
}
// Audit the nonrotated, multiple-exit case independently of entry binding.
@inline(never) public func multipleExits(_ n: Int) -> Int {
    var i = 3
    while i < n {
        if i == 7 { return 99 }
        i &+= 1
    }
    return i
}
