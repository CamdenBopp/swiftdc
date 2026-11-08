// Floating-point immediates in vector and half-precision registers (-O).
// True behaviour: fill stores SIMD2<Double>(3, 3); fillF stores four 1.5s;
// half(h) returns h * 3.0 + 0.5 in Float16; callHalf passes 1.5 to half.
@inline(never) public func fill(_ p: UnsafeMutablePointer<SIMD2<Double>>) { p.pointee = SIMD2<Double>(repeating: 3) }
@inline(never) public func fillF(_ p: UnsafeMutablePointer<SIMD4<Float>>) { p.pointee = SIMD4<Float>(repeating: 1.5) }
@inline(never) public func half(_ h: Float16) -> Float16 { h * 3 + 0.5 }
@inline(never) public func callHalf() -> Float16 { half(1.5) }
