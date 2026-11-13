// `scvtf` converts its operand as signed. Each function below lowers at -O
// to one `scvtf` on an argument typed unsigned:
//   si:   `scvtf d0, x0; ret`: true value is Double(Int(bitPattern: x)),
//         so UInt.max gives -1.0, not 1.8e19.
//   si32: `scvtf s0, w0; ret`: Float(Int32(bitPattern: x)).
// `widen` is the control: `scvtf` on a signed argument is plain Double(x)
// (scaled, so -O does not fold it into a tail call to `si`).
public func si(_ x: UInt) -> Double { Double(Int(bitPattern: x)) }
public func si32(_ x: UInt32) -> Float { Float(Int32(bitPattern: x)) }
public func widen(_ x: Int) -> Double { Double(x) * 2.0 }
