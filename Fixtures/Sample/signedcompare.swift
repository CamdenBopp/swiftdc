// Comparisons whose machine signedness differs from the operands' Swift
// types (-O). A plain `<` on UInt operands reads as unsigned in Swift, so
// a signed `cset lt` there must say signed:
//   ubitLt:      `cmp x0, x1; cset lt`   true for a = UInt.max, b = 0
//   ubitSel:     `cmp; csel gt`          signed max of the bit patterns
//   uSignedZero: `subs; cinc ge` style   sign of a &- b
//   mixS:        UInt vs Int, `cset lt`  signed
//   mixU:        UInt vs Int, `cset lo`  unsigned: 0 < -1 is true
// Controls, already right: ultBool (`cset lo` on UInt) and umax (`csel hi`).
@inline(never) public func ubitLt(_ a: UInt, _ b: UInt) -> Bool { Int(bitPattern: a) < Int(bitPattern: b) }
@inline(never) public func ubitSel(_ a: UInt, _ b: UInt) -> UInt { Int(bitPattern: a) > Int(bitPattern: b) ? a : b }
@inline(never) public func uSignedZero(_ a: UInt, _ b: UInt) -> Int { Int(bitPattern: a &- b) < 0 ? 1 : 2 }
@inline(never) public func mixS(_ a: UInt, _ b: Int) -> Bool { Int(bitPattern: a) < b }
@inline(never) public func mixU(_ a: UInt, _ b: Int) -> Bool { a < UInt(bitPattern: b) }
@inline(never) public func ultBool(_ a: UInt, _ b: UInt) -> Bool { a < b }
@inline(never) public func umax(_ a: UInt, _ b: UInt) -> UInt { max(a, b) }
