// Integer arithmetic probes. Each comment states the true behaviour.
@inline(never) public func addTrap(_ a: Int, _ b: Int) -> Int { a + b }          // traps on signed overflow
@inline(never) public func mulTrap(_ a: Int, _ b: Int) -> Int { a * b }          // traps if smulh != asr(mul,63)
@inline(never) public func umulTrap(_ a: UInt, _ b: UInt) -> UInt { a * b }      // traps if umulh != 0
@inline(never) public func addWrap(_ a: Int, _ b: Int) -> Int { a &+ b }
@inline(never) public func mulWrap(_ a: Int, _ b: Int) -> Int { a &* b }
@inline(never) public func shlMask(_ a: Int, _ b: Int) -> Int { a &<< b }        // a << (b & 63)
@inline(never) public func shlSmart(_ a: Int, _ b: Int) -> Int { a << b }        // b<0 -> a >> -b ; b>=64 -> 0
@inline(never) public func shrSmart(_ a: Int, _ b: Int) -> Int { a >> b }        // b>=64 -> a<0 ? -1 : 0
@inline(never) public func ushrSmart(_ a: UInt, _ b: Int) -> UInt { a >> b }
@inline(never) public func i8add(_ a: Int8, _ b: Int8) -> Int8 { a &+ b }
@inline(never) public func i8widen(_ a: Int8) -> Int { Int(a) }                  // sign-extend low byte
@inline(never) public func u8widen(_ a: UInt8) -> Int { Int(a) }                 // zero-extend low byte
@inline(never) public func i16widen(_ a: Int16) -> Int { Int(a) }
@inline(never) public func i32widen(_ a: Int32) -> Int { Int(a) }
@inline(never) public func u32widen(_ a: UInt32) -> UInt { UInt(a) }
@inline(never) public func sdivF(_ a: Int, _ b: Int) -> Int { a / b }            // traps b==0 and a==min,b==-1
@inline(never) public func udivF(_ a: UInt, _ b: UInt) -> UInt { a / b }
@inline(never) public func sremF(_ a: Int, _ b: Int) -> Int { a % b }
@inline(never) public func uremF(_ a: UInt, _ b: UInt) -> UInt { a % b }
@inline(never) public func div7(_ a: Int) -> Int { a / 7 }                      // truncating toward zero
@inline(never) public func udiv7(_ a: UInt) -> UInt { a / 7 }
@inline(never) public func rem8(_ a: Int) -> Int { a % 8 }                      // sign of a
@inline(never) public func div8(_ a: Int) -> Int { a / 8 }                      // trunc toward zero, not asr
@inline(never) public func absF(_ a: Int) -> Int { abs(a) }                      // traps on Int.min
@inline(never) public func minF(_ a: Int, _ b: Int) -> Int { min(a, b) }
@inline(never) public func umaxF(_ a: UInt, _ b: UInt) -> UInt { max(a, b) }      // unsigned compare
@inline(never) public func popc(_ a: UInt) -> Int { a.nonzeroBitCount }
@inline(never) public func lzc(_ a: UInt) -> Int { a.leadingZeroBitCount }
@inline(never) public func tzc(_ a: UInt) -> Int { a.trailingZeroBitCount }
@inline(never) public func bswap(_ a: UInt) -> UInt { a.byteSwapped }
@inline(never) public func bswap32(_ a: UInt32) -> UInt32 { a.byteSwapped }
@inline(never) public func rotl(_ a: UInt, _ n: UInt) -> UInt { (a << (n & 63)) | (a >> ((64 - (n & 63)) & 63)) }
@inline(never) public func rotl13(_ a: UInt) -> UInt { (a &<< 13) | (a &>> 51) }
@inline(never) public func fullHi(_ a: Int, _ b: Int) -> Int { a.multipliedFullWidth(by: b).high }
@inline(never) public func ufullHi(_ a: UInt, _ b: UInt) -> UInt { a.multipliedFullWidth(by: b).high }
@inline(never) public func addOvf(_ a: Int, _ b: Int) -> Bool { a.addingReportingOverflow(b).overflow }
@inline(never) public func ubfx(_ a: UInt) -> UInt { (a >> 5) & 0x3f }
@inline(never) public func sbfx(_ a: Int) -> Int { (a << 52) >> 58 }            // signed field bits 6..11
@inline(never) public func bfi(_ a: UInt, _ b: UInt) -> UInt { (a & ~0xff00) | ((b & 0xff) << 8) }
@inline(never) public func trunc8(_ a: Int) -> UInt8 { UInt8(truncatingIfNeeded: a) }
@inline(never) public func trunc8s(_ a: Int) -> Int8 { Int8(truncatingIfNeeded: a) }
@inline(never) public func exact8(_ a: Int) -> Int8? { Int8(exactly: a) }
@inline(never) public func clamp8(_ a: Int) -> Int8 { Int8(clamping: a) }
@inline(never) public func ltBool(_ a: Int, _ b: Int) -> Bool { a < b }
@inline(never) public func ultBool(_ a: UInt, _ b: UInt) -> Bool { a < b }
@inline(never) public func inRange(_ a: Int) -> Bool { a >= 10 && a < 20 }       // ccmp chain
@inline(never) public func inRangeU(_ a: UInt) -> Bool { a >= 10 && a < 20 }
@inline(never) public func bigConst() -> Int { 0x1234_5678_9abc_def0 }
@inline(never) public func negConst() -> Int { -123456789 }
@inline(never) public func negImm(_ a: Int) -> Int { a &+ -5 }
@inline(never) public func andNeg(_ a: Int) -> Int { a & -16 }
@inline(never) public func narrowRet(_ a: Int) -> Int32 { Int32(truncatingIfNeeded: a &* 3) }
@inline(never) public func u16sum(_ a: UInt16, _ b: UInt16) -> UInt16 { a &+ b }
@inline(never) public func i16cmp(_ a: Int16, _ b: Int16) -> Bool { a < b }
@inline(never) public func u8cmp(_ a: UInt8, _ b: UInt8) -> Bool { a > b }
@inline(never) public func selU(_ a: UInt, _ b: UInt) -> Int { a > b ? 1 : 2 }
