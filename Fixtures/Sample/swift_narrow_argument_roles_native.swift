import SwiftArgumentRoles
var observations = 0
do {
 let inputs: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in inputs {
  let g: Int64 = 73
  let actual = signed8StackCaller(x, g)
  let expected = Int64(Int8(bitPattern: x))
  let measured = (actual &- (g &* 8 &+ 28) &- 1) / 5
  precondition(measured == expected)
  print("OBSROLE\tstack\tsigned8StackCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [Int8] = [Int8.min, Int8.max, 0, 1]
 for x in inputs {
  let result = signed8InoutCaller(x)
  let expected = Int64(x &+ 1)
  precondition(result == expected)
  print("OBSROLE\tinout\tsigned8InoutCaller\t\(x)\t\(result)")
  observations += 1
 }
}
do {
 let inputs: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in inputs {
  let box = Signed8Box(0)
  signed8SetterCaller(box, x)
  precondition(box.value == Int8(bitPattern: x))
  precondition(box.writeCount == 1)
  print("OBSROLE\tsetter\tsigned8SetterCaller\t\(x)\t\(Int64(box.value))")
  observations += 1
 }
}
do {
 let inputs: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in inputs {
  let actual = signed8MixedCaller(x, 3.5)
  let expected = Int64(Int8(bitPattern: x))
  let measured = (actual &- 3 &- 1) / 5
  precondition(measured == expected)
  print("OBSROLE\tmixed\tsigned8MixedCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [Int8] = Array(Int8.min...Int8.max)
 for x in inputs {
  let g: Int64 = 73
  let actual = unsigned8StackCaller(x, g)
  let expected = Int64(UInt8(bitPattern: x))
  let measured = (actual &- (g &* 8 &+ 28) &- 2) / 7
  precondition(measured == expected)
  print("OBSROLE\tstack\tunsigned8StackCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [UInt8] = [UInt8.min, UInt8.max, 0, 1]
 for x in inputs {
  let result = unsigned8InoutCaller(x)
  let expected = Int64(x &+ 2)
  precondition(result == expected)
  print("OBSROLE\tinout\tunsigned8InoutCaller\t\(x)\t\(result)")
  observations += 1
 }
}
do {
 let inputs: [Int8] = Array(Int8.min...Int8.max)
 for x in inputs {
  let box = Unsigned8Box(0)
  unsigned8SetterCaller(box, x)
  precondition(box.value == UInt8(bitPattern: x))
  precondition(box.writeCount == 2)
  print("OBSROLE\tsetter\tunsigned8SetterCaller\t\(x)\t\(Int64(box.value))")
  observations += 1
 }
}
do {
 let inputs: [Int8] = Array(Int8.min...Int8.max)
 for x in inputs {
  let actual = unsigned8MixedCaller(x, 3.5)
  let expected = Int64(UInt8(bitPattern: x))
  let measured = (actual &- 3 &- 2) / 7
  precondition(measured == expected)
  print("OBSROLE\tmixed\tunsigned8MixedCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [UInt16] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65534, 65535]
 for x in inputs {
  let g: Int64 = 73
  let actual = signed16StackCaller(x, g)
  let expected = Int64(Int16(bitPattern: x))
  let measured = (actual &- (g &* 8 &+ 28) &- 3) / 9
  precondition(measured == expected)
  print("OBSROLE\tstack\tsigned16StackCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [Int16] = [Int16.min, Int16.max, 0, 1]
 for x in inputs {
  let result = signed16InoutCaller(x)
  let expected = Int64(x &+ 3)
  precondition(result == expected)
  print("OBSROLE\tinout\tsigned16InoutCaller\t\(x)\t\(result)")
  observations += 1
 }
}
do {
 let inputs: [UInt16] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65534, 65535]
 for x in inputs {
  let box = Signed16Box(0)
  signed16SetterCaller(box, x)
  precondition(box.value == Int16(bitPattern: x))
  precondition(box.writeCount == 3)
  print("OBSROLE\tsetter\tsigned16SetterCaller\t\(x)\t\(Int64(box.value))")
  observations += 1
 }
}
do {
 let inputs: [UInt16] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65534, 65535]
 for x in inputs {
  let actual = signed16MixedCaller(x, 3.5)
  let expected = Int64(Int16(bitPattern: x))
  let measured = (actual &- 3 &- 3) / 9
  precondition(measured == expected)
  print("OBSROLE\tmixed\tsigned16MixedCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [Int16] = [-32768, -32767, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32766, 32767]
 for x in inputs {
  let g: Int64 = 73
  let actual = unsigned16StackCaller(x, g)
  let expected = Int64(UInt16(bitPattern: x))
  let measured = (actual &- (g &* 8 &+ 28) &- 4) / 11
  precondition(measured == expected)
  print("OBSROLE\tstack\tunsigned16StackCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [UInt16] = [UInt16.min, UInt16.max, 0, 1]
 for x in inputs {
  let result = unsigned16InoutCaller(x)
  let expected = Int64(x &+ 4)
  precondition(result == expected)
  print("OBSROLE\tinout\tunsigned16InoutCaller\t\(x)\t\(result)")
  observations += 1
 }
}
do {
 let inputs: [Int16] = [-32768, -32767, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32766, 32767]
 for x in inputs {
  let box = Unsigned16Box(0)
  unsigned16SetterCaller(box, x)
  precondition(box.value == UInt16(bitPattern: x))
  precondition(box.writeCount == 4)
  print("OBSROLE\tsetter\tunsigned16SetterCaller\t\(x)\t\(Int64(box.value))")
  observations += 1
 }
}
do {
 let inputs: [Int16] = [-32768, -32767, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32766, 32767]
 for x in inputs {
  let actual = unsigned16MixedCaller(x, 3.5)
  let expected = Int64(UInt16(bitPattern: x))
  let measured = (actual &- 3 &- 4) / 11
  precondition(measured == expected)
  print("OBSROLE\tmixed\tunsigned16MixedCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [UInt32] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in inputs {
  let g: Int64 = 73
  let actual = signed32StackCaller(x, g)
  let expected = Int64(Int32(bitPattern: x))
  let measured = (actual &- (g &* 8 &+ 28) &- 5) / 13
  precondition(measured == expected)
  print("OBSROLE\tstack\tsigned32StackCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [Int32] = [Int32.min, Int32.max, 0, 1]
 for x in inputs {
  let result = signed32InoutCaller(x)
  let expected = Int64(x &+ 5)
  precondition(result == expected)
  print("OBSROLE\tinout\tsigned32InoutCaller\t\(x)\t\(result)")
  observations += 1
 }
}
do {
 let inputs: [UInt32] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in inputs {
  let box = Signed32Box(0)
  signed32SetterCaller(box, x)
  precondition(box.value == Int32(bitPattern: x))
  precondition(box.writeCount == 5)
  print("OBSROLE\tsetter\tsigned32SetterCaller\t\(x)\t\(Int64(box.value))")
  observations += 1
 }
}
do {
 let inputs: [UInt32] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in inputs {
  let actual = signed32MixedCaller(x, 3.5)
  let expected = Int64(Int32(bitPattern: x))
  let measured = (actual &- 3 &- 5) / 13
  precondition(measured == expected)
  print("OBSROLE\tmixed\tsigned32MixedCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [Int32] = [-2147483648, -2147483647, -65537, -32769, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in inputs {
  let g: Int64 = 73
  let actual = unsigned32StackCaller(x, g)
  let expected = Int64(UInt32(bitPattern: x))
  let measured = (actual &- (g &* 8 &+ 28) &- 6) / 15
  precondition(measured == expected)
  print("OBSROLE\tstack\tunsigned32StackCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let inputs: [UInt32] = [UInt32.min, UInt32.max, 0, 1]
 for x in inputs {
  let result = unsigned32InoutCaller(x)
  let expected = Int64(x &+ 6)
  precondition(result == expected)
  print("OBSROLE\tinout\tunsigned32InoutCaller\t\(x)\t\(result)")
  observations += 1
 }
}
do {
 let inputs: [Int32] = [-2147483648, -2147483647, -65537, -32769, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in inputs {
  let box = Unsigned32Box(0)
  unsigned32SetterCaller(box, x)
  precondition(box.value == UInt32(bitPattern: x))
  precondition(box.writeCount == 6)
  print("OBSROLE\tsetter\tunsigned32SetterCaller\t\(x)\t\(Int64(box.value))")
  observations += 1
 }
}
do {
 let inputs: [Int32] = [-2147483648, -2147483647, -65537, -32769, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in inputs {
  let actual = unsigned32MixedCaller(x, 3.5)
  let expected = Int64(UInt32(bitPattern: x))
  let measured = (actual &- 3 &- 6) / 15
  precondition(measured == expected)
  print("OBSROLE\tmixed\tunsigned32MixedCaller\t\(x)\t\(measured)")
  observations += 1
 }
}
do {
 let bits: [UInt32] = [0, 0x80000000, 0xbf8000ff, 0x3f800080, 0x80000001, 0x7fc000ff]
 for raw in bits {
  let x = Float(bitPattern: raw)
  let result = floatBitsInt32Caller(x)
  let expected = Int64(Int32(bitPattern: x.bitPattern))
  let measured = (result &- 7) / 19
  precondition(measured == expected)
  print("OBSROLE\tfloatBits\tfloatBitsInt32Caller\t\(raw)\t\(measured)")
  observations += 1
 }
}
do {
 let bits: [UInt32] = [0, 0x80000000, 0xbf8000ff, 0x3f800080, 0x80000001, 0x7fc000ff]
 for raw in bits {
  let x = Float(bitPattern: raw)
  let result = floatBitsUInt8Caller(x)
  let expected = Int64(UInt8(truncatingIfNeeded: x.bitPattern))
  let measured = (result &- 7) / 19
  precondition(measured == expected)
  print("OBSROLE\tfloatBits\tfloatBitsUInt8Caller\t\(raw)\t\(measured)")
  observations += 1
 }
}
print("PASS native argument roles: \(observations) observations")
