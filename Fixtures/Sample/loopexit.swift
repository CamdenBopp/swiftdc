// An exit from an inner loop that leaves the outer loop too. At -O the
// inner loop's exit block is the function's epilogue (or the code after
// both loops), where the structurer stops, so the text after the inner
// loop is the rest of the OUTER loop's body. A `break` there ran it:
// `if (ext(?) == 6) { break }` fell into `sink(-i)` and the outer loop's
// test, where the code returns.
//
// True behaviour: stopAll(n) returns at the first i, j with ext(i + j) ==
// 6, calling sink(j) before it and sink(-i) after each finished row.
// breakOuter(n) leaves both loops at the same point and then calls
// sink(100). leaveBoth(n) is breakOuter without the sink after.
@inline(never) public func ext(_ x: Int) -> Int { x &* 3 }
@inline(never) public func sink(_ x: Int) { print(x) }

public func stopAll(_ n: Int) {
    for i in 0..<n { for j in 0..<n { if ext(i &+ j) == 6 { return }; sink(j) }; sink(-i) }
}
public func breakOuter(_ n: Int) {
    outer: for i in 0..<n { for j in 0..<n { if ext(i &+ j) == 6 { break outer }; sink(j) } }
    sink(100)
}
public func leaveBoth(_ n: Int) {
    outer: for i in 0..<n { for j in 0..<n { if ext(i &+ j) == 6 { break outer }; sink(j) } }
}
