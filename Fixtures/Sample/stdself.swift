// A frozen standard-library struct's method takes `self` in x20 only by
// address, when it is mutating. `s.utf16.index(i, offsetBy: k & 1)` passes
// the view's words after the formals, so whatever the caller parked in x20
// (here a scalar computed from the index) is not `self`. `mutate`'s
// `s.append` takes the inout String's address in x20, and `local`'s takes
// a frame slot's: both are `self`.
public func off16(_ s: String, _ i: String.Index, _ n: Int) -> String.Index { s.utf16.index(i, offsetBy: n) }
public func loop16(_ s: String, _ n: Int) -> Int {
    var total = 0
    var i = s.utf16.startIndex
    for k in 0..<n { i = s.utf16.index(i, offsetBy: k & 1); total &+= i.utf16Offset(in: s) }
    return total
}
public func count8(_ s: String, _ k: Int) -> Int { s.utf8.count &* k &+ s.unicodeScalars.count }
public func mutate(_ s: inout String, _ k: Int) { s.append(String(k)) }
public func local(_ k: Int) -> String { var s = "a"; s.append(String(k)); return s }
