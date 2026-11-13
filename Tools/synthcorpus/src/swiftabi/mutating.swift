// LEVELS: O Osize Onone
// Mutating methods: the inout self arrives as an address in x20.
// TRUE behaviour: useCounter puts a Counter in a stack slot and passes its
// address in x20 to bump, reset(to: 9), bump. At -Onone x20 is set before
// Counter.init, survives it (x20 is callee-saved) and is reloaded from a spill
// before reset and the second bump, so every call has a receiver.
// bump: self.value += self.step. reset(to:): value = arg0, step = 2.
// EXPECT structured * Counter.bump() :: self.value += self.step
// EXPECT structured * Counter.reset(to: :: self.value
// FORBID structured * Counter.reset(to: :: self.step = arg0
// EXPECT structured O,Osize useCounter :: Mutating.Counter.reset(to:)(self: local_30, 9)
// The receiver is never dropped, at any level (fails at -Onone in swiftdc-sa2):
// EXPECT structured * useCounter :: Mutating.Counter.bump(self:
// FORBID structured * useCounter :: re:Counter\.bump\(\)
// FORBID structured * useCounter :: re:reset\(to:\)\(9\)
public struct Counter { public var value: Int; public var step: Int
  public init() { value = 0; step = 1 }
  @inline(never) public mutating func bump() { value &+= step }
  @inline(never) public mutating func reset(to v: Int) { value = v; step = 2 } }
public func useCounter() -> Int { var c = Counter(); c.bump(); c.reset(to: 9); c.bump(); return c.value }
