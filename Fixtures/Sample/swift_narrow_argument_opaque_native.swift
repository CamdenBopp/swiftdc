import SwiftArgumentOpaque
@_silgen_name("argument_opaque_reset") func reset()
@_silgen_name("argument_opaque_count") func count() -> UInt64
var observations = 0
for seed: UInt64 in [0, 1, 127, 128, 255, 256, UInt64.max, 1 << 63] {
 reset()
 let result = signed8OpaqueCaller(seed)
 let expected = Int64(Int8(truncatingIfNeeded: seed ^ 0x9f123456789abcde))
 let measured = (result &- 8) / 3
 precondition(measured == expected && count() == 1)
 print("OBSOPAQUE\tsigned8OpaqueCaller\t\(seed)\t\(measured)\t\(count())")
 observations += 1
}
for seed: UInt64 in [0, 1, 127, 128, 255, 256, UInt64.max, 1 << 63] {
 reset()
 let result = unsigned8OpaqueCaller(seed)
 let expected = Int64(UInt8(truncatingIfNeeded: seed ^ 0x9f123456789abcde))
 let measured = (result &- 8) / 3
 precondition(measured == expected && count() == 1)
 print("OBSOPAQUE\tunsigned8OpaqueCaller\t\(seed)\t\(measured)\t\(count())")
 observations += 1
}
for seed: UInt64 in [0, 1, 127, 128, 255, 256, UInt64.max, 1 << 63] {
 reset()
 let result = signed16OpaqueCaller(seed)
 let expected = Int64(Int16(truncatingIfNeeded: seed ^ 0x9f123456789abcde))
 let measured = (result &- 16) / 3
 precondition(measured == expected && count() == 1)
 print("OBSOPAQUE\tsigned16OpaqueCaller\t\(seed)\t\(measured)\t\(count())")
 observations += 1
}
for seed: UInt64 in [0, 1, 127, 128, 255, 256, UInt64.max, 1 << 63] {
 reset()
 let result = unsigned16OpaqueCaller(seed)
 let expected = Int64(UInt16(truncatingIfNeeded: seed ^ 0x9f123456789abcde))
 let measured = (result &- 16) / 3
 precondition(measured == expected && count() == 1)
 print("OBSOPAQUE\tunsigned16OpaqueCaller\t\(seed)\t\(measured)\t\(count())")
 observations += 1
}
for seed: UInt64 in [0, 1, 127, 128, 255, 256, UInt64.max, 1 << 63] {
 reset()
 let result = signed32OpaqueCaller(seed)
 let expected = Int64(Int32(truncatingIfNeeded: seed ^ 0x9f123456789abcde))
 let measured = (result &- 32) / 3
 precondition(measured == expected && count() == 1)
 print("OBSOPAQUE\tsigned32OpaqueCaller\t\(seed)\t\(measured)\t\(count())")
 observations += 1
}
for seed: UInt64 in [0, 1, 127, 128, 255, 256, UInt64.max, 1 << 63] {
 reset()
 let result = unsigned32OpaqueCaller(seed)
 let expected = Int64(UInt32(truncatingIfNeeded: seed ^ 0x9f123456789abcde))
 let measured = (result &- 32) / 3
 precondition(measured == expected && count() == 1)
 print("OBSOPAQUE\tunsigned32OpaqueCaller\t\(seed)\t\(measured)\t\(count())")
 observations += 1
}
print("PASS native opaque argument producer: \(observations) observations")
