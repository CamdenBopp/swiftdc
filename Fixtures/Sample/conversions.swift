// Fixture for numeric conversions: each one is part of the value, and the float
// constant beside it is only decodable once the conversion is known. Carried
// through as if absent, `Double(n) * 1.5` rendered `(arg0 * 0x3ff8000000000000)`.
//
// Built by `build.sh` into `libConversions.dylib` (-Onone -g) and
// `libConversions.opt.dylib` (-O). DifferentialOracleTests executes these.

public func intTimesConstant(_ n: Int) -> Double { Double(n) * 1.5 }

public func unsignedTimesConstant(_ n: UInt) -> Double { Double(n) * 0.25 }

public func widenedTimesConstant(_ f: Float) -> Double { Double(f) * 1.5 }

public func narrowedTimesConstant(_ d: Double) -> Float { Float(d) * 0.5 }

public func truncatedScaled(_ x: Double) -> Int { Int(x * 2.5) }

public func intTimesHalfFloat(_ n: Int) -> Float { Float(n) * 0.5 }
