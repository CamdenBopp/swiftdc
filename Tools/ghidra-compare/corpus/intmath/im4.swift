// Mixed-signedness compares. True behaviour is the machine's unsigned/signed compare of the bits.
@inline(never) public func mixU(_ a: UInt, _ b: Int) -> Bool { a < UInt(bitPattern: b) }   // unsigned bits: 0 < -1 is true
@inline(never) public func mixS(_ a: UInt, _ b: Int) -> Bool { Int(bitPattern: a) < b }    // signed bits
@inline(never) public func mixSel(_ a: UInt, _ b: Int) -> Int { a > UInt(bitPattern: b) ? 1 : 2 }
@inline(never) public func uNegConst(_ a: UInt) -> Bool { Int(bitPattern: a) > -6 }       // signed vs -6
@inline(never) public func uSignedZero(_ a: UInt, _ b: UInt) -> Int { Int(bitPattern: a &- b) < 0 ? 1 : 2 }
