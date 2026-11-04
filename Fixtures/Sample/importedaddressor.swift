// Imported global variable addressors, bound by their mangled names so one
// dylib shows the call a client of `public var libVar` makes (-O). An
// addressor of a global takes no parameters and no self: x0 and x20 at each
// call hold only what the caller left there. True behaviour of readBoth:
// it calls both addressors and returns (*libConst + k) * j + *libVar.
@_silgen_name("$s3lib0A5ConstSivau") func constAddress() -> UnsafeMutablePointer<Int>
@_silgen_name("$s3lib0A3VarSivau") func varAddress() -> UnsafeMutablePointer<Int>

public func readBoth(_ k: Int, _ j: Int) -> Int {
    let sum = constAddress().pointee &+ k
    return sum &* j &+ varAddress().pointee
}
