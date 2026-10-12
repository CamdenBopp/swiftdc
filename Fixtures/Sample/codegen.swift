// Fixture for compiler code-generation idioms that need their own image, so
// their bytes never move the hard-coded fuzz offsets into libReconstruction.
// Built by `build.sh` into `libCodegen.opt.dylib` (-O) and a stripped copy.

// Division by a constant. At -O none of these is an sdiv: each lowers to a
// multiply-high by a magic reciprocal, in a different shape per divisor
// (the shapes are listed in MagicDivision.swift).
public func divideBySeven(_ a: Int) -> Int { a / 7 }
public func divideByThree(_ a: Int) -> Int { a / 3 }
public func divideByFifteen(_ a: Int) -> Int { a / 15 }
public func divideByMinusSeven(_ a: Int) -> Int { a / -7 }
public func remainderBySeven(_ a: Int) -> Int { a % 7 }
public func unsignedDivideBySeven(_ a: UInt) -> UInt { a / 7 }
public func unsignedDivideByThousand(_ a: UInt) -> UInt { a / 1000 }

