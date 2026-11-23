import SwiftArgumentBoundary
var observations = 0
do {
 let values: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in values {
  let input: Int8 = Int8(bitPattern: x)
  let expected = Int64(input) &* 3 &+ 1
  let actual = signed8BitPatternCaller(x)
  let measured = (actual &- 1 &- 0) / 3
  precondition(measured == Int64(input))
  print("OBS\tsigned8BitPatternCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed8BitPatternCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int8] = Array(Int8.min...Int8.max)
 for x in values {
  let input: UInt8 = UInt8(bitPattern: x)
  let expected = Int64(input) &* 5 &+ 2
  let actual = unsigned8BitPatternCaller(x)
  let measured = (actual &- 2 &- 0) / 5
  precondition(measured == Int64(input))
  print("OBS\tunsigned8BitPatternCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned8BitPatternCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int64] = [-9223372036854775808, -9223372036854775807, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967295, 4294967296, 9223372036854775806, 9223372036854775807]
 for x in values {
  let input: Int8 = Int8(truncatingIfNeeded: x)
  let expected = Int64(input) &* 7 &+ 3
  let actual = signed8TruncationCaller(x)
  let measured = (actual &- 3 &- 0) / 7
  precondition(measured == Int64(input))
  print("OBS\tsigned8TruncationCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed8TruncationCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt64] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967295, 4294967296, 18446744073709551614, 18446744073709551615]
 for x in values {
  let input: UInt8 = UInt8(truncatingIfNeeded: x)
  let expected = Int64(input) &* 9 &+ 4
  let actual = unsigned8TruncationCaller(x)
  let measured = (actual &- 4 &- 0) / 9
  precondition(measured == Int64(input))
  print("OBS\tunsigned8TruncationCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned8TruncationCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int8] = Array(Int8.min...Int8.max)
 for x in values {
  let input: Int8 = x
  let expected = Int64(input) &* 11 &+ 5
  let actual = signed8SameCaller(x)
  let measured = (actual &- 5 &- 0) / 11
  precondition(measured == Int64(input))
  print("OBS\tsigned8SameCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed8SameCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in values {
  let input: UInt8 = x
  let expected = Int64(input) &* 13 &+ 6
  let actual = unsigned8SameCaller(x)
  let measured = (actual &- 6 &- 0) / 13
  precondition(measured == Int64(input))
  print("OBS\tunsigned8SameCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned8SameCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in values {
  let input: Int8 = Int8(bitPattern: x)
  let expected = Int64(input) &* 15 &+ 7 &+ 1007
  let actual = signed8NonTailCaller(x)
  let measured = (actual &- 7 &- 1007) / 15
  precondition(measured == Int64(input))
  print("OBS\tsigned8NonTailCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed8NonTailCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int8] = Array(Int8.min...Int8.max)
 for x in values {
  let input: UInt8 = UInt8(bitPattern: x)
  let expected = Int64(input) &* 17 &+ 8 &+ 1008
  let actual = unsigned8NonTailCaller(x)
  let measured = (actual &- 8 &- 1008) / 17
  precondition(measured == Int64(input))
  print("OBS\tunsigned8NonTailCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned8NonTailCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int8] = Array(Int8.min...Int8.max)
 for x in values {
  let input: Int8 = x &+ 26
  let expected = Int64(input) &* 19 &+ 9
  let actual = signed8CallResultCaller(x)
  let measured = (actual &- 9 &- 0) / 19
  precondition(measured == Int64(input))
  print("OBS\tsigned8CallResultCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed8CallResultCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in values {
  let input: UInt8 = x &+ 27
  let expected = Int64(input) &* 21 &+ 10
  let actual = unsigned8CallResultCaller(x)
  let measured = (actual &- 10 &- 0) / 21
  precondition(measured == Int64(input))
  print("OBS\tunsigned8CallResultCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned8CallResultCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65534, 65535]
 for x in values {
  let input: Int16 = Int16(bitPattern: x)
  let expected = Int64(input) &* 23 &+ 11
  let actual = signed16BitPatternCaller(x)
  let measured = (actual &- 11 &- 0) / 23
  precondition(measured == Int64(input))
  print("OBS\tsigned16BitPatternCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed16BitPatternCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32766, 32767]
 for x in values {
  let input: UInt16 = UInt16(bitPattern: x)
  let expected = Int64(input) &* 25 &+ 12
  let actual = unsigned16BitPatternCaller(x)
  let measured = (actual &- 12 &- 0) / 25
  precondition(measured == Int64(input))
  print("OBS\tunsigned16BitPatternCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned16BitPatternCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int64] = [-9223372036854775808, -9223372036854775807, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967295, 4294967296, 9223372036854775806, 9223372036854775807]
 for x in values {
  let input: Int16 = Int16(truncatingIfNeeded: x)
  let expected = Int64(input) &* 27 &+ 13
  let actual = signed16TruncationCaller(x)
  let measured = (actual &- 13 &- 0) / 27
  precondition(measured == Int64(input))
  print("OBS\tsigned16TruncationCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed16TruncationCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt64] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967295, 4294967296, 18446744073709551614, 18446744073709551615]
 for x in values {
  let input: UInt16 = UInt16(truncatingIfNeeded: x)
  let expected = Int64(input) &* 29 &+ 14
  let actual = unsigned16TruncationCaller(x)
  let measured = (actual &- 14 &- 0) / 29
  precondition(measured == Int64(input))
  print("OBS\tunsigned16TruncationCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned16TruncationCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32766, 32767]
 for x in values {
  let input: Int16 = x
  let expected = Int64(input) &* 31 &+ 15
  let actual = signed16SameCaller(x)
  let measured = (actual &- 15 &- 0) / 31
  precondition(measured == Int64(input))
  print("OBS\tsigned16SameCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed16SameCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65534, 65535]
 for x in values {
  let input: UInt16 = x
  let expected = Int64(input) &* 33 &+ 16
  let actual = unsigned16SameCaller(x)
  let measured = (actual &- 16 &- 0) / 33
  precondition(measured == Int64(input))
  print("OBS\tunsigned16SameCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned16SameCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65534, 65535]
 for x in values {
  let input: Int16 = Int16(bitPattern: x)
  let expected = Int64(input) &* 35 &+ 17 &+ 1017
  let actual = signed16NonTailCaller(x)
  let measured = (actual &- 17 &- 1017) / 35
  precondition(measured == Int64(input))
  print("OBS\tsigned16NonTailCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed16NonTailCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32766, 32767]
 for x in values {
  let input: UInt16 = UInt16(bitPattern: x)
  let expected = Int64(input) &* 37 &+ 18 &+ 1018
  let actual = unsigned16NonTailCaller(x)
  let measured = (actual &- 18 &- 1018) / 37
  precondition(measured == Int64(input))
  print("OBS\tunsigned16NonTailCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned16NonTailCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32766, 32767]
 for x in values {
  let input: Int16 = x &+ 36
  let expected = Int64(input) &* 39 &+ 19
  let actual = signed16CallResultCaller(x)
  let measured = (actual &- 19 &- 0) / 39
  precondition(measured == Int64(input))
  print("OBS\tsigned16CallResultCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed16CallResultCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65534, 65535]
 for x in values {
  let input: UInt16 = x &+ 37
  let expected = Int64(input) &* 41 &+ 20
  let actual = unsigned16CallResultCaller(x)
  let measured = (actual &- 20 &- 0) / 41
  precondition(measured == Int64(input))
  print("OBS\tunsigned16CallResultCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned16CallResultCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let input: Int32 = Int32(bitPattern: x)
  let expected = Int64(input) &* 43 &+ 21
  let actual = signed32BitPatternCaller(x)
  let measured = (actual &- 21 &- 0) / 43
  precondition(measured == Int64(input))
  print("OBS\tsigned32BitPatternCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed32BitPatternCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let input: UInt32 = UInt32(bitPattern: x)
  let expected = Int64(input) &* 45 &+ 22
  let actual = unsigned32BitPatternCaller(x)
  let measured = (actual &- 22 &- 0) / 45
  precondition(measured == Int64(input))
  print("OBS\tunsigned32BitPatternCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned32BitPatternCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int64] = [-9223372036854775808, -9223372036854775807, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967295, 4294967296, 9223372036854775806, 9223372036854775807]
 for x in values {
  let input: Int32 = Int32(truncatingIfNeeded: x)
  let expected = Int64(input) &* 47 &+ 23
  let actual = signed32TruncationCaller(x)
  let measured = (actual &- 23 &- 0) / 47
  precondition(measured == Int64(input))
  print("OBS\tsigned32TruncationCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed32TruncationCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt64] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967295, 4294967296, 18446744073709551614, 18446744073709551615]
 for x in values {
  let input: UInt32 = UInt32(truncatingIfNeeded: x)
  let expected = Int64(input) &* 49 &+ 24
  let actual = unsigned32TruncationCaller(x)
  let measured = (actual &- 24 &- 0) / 49
  precondition(measured == Int64(input))
  print("OBS\tunsigned32TruncationCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned32TruncationCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let input: Int32 = x
  let expected = Int64(input) &* 51 &+ 25
  let actual = signed32SameCaller(x)
  let measured = (actual &- 25 &- 0) / 51
  precondition(measured == Int64(input))
  print("OBS\tsigned32SameCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed32SameCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let input: UInt32 = x
  let expected = Int64(input) &* 53 &+ 26
  let actual = unsigned32SameCaller(x)
  let measured = (actual &- 26 &- 0) / 53
  precondition(measured == Int64(input))
  print("OBS\tunsigned32SameCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned32SameCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let input: Int32 = Int32(bitPattern: x)
  let expected = Int64(input) &* 55 &+ 27 &+ 1027
  let actual = signed32NonTailCaller(x)
  let measured = (actual &- 27 &- 1027) / 55
  precondition(measured == Int64(input))
  print("OBS\tsigned32NonTailCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed32NonTailCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let input: UInt32 = UInt32(bitPattern: x)
  let expected = Int64(input) &* 57 &+ 28 &+ 1028
  let actual = unsigned32NonTailCaller(x)
  let measured = (actual &- 28 &- 1028) / 57
  precondition(measured == Int64(input))
  print("OBS\tunsigned32NonTailCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned32NonTailCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let input: Int32 = x &+ 46
  let expected = Int64(input) &* 59 &+ 29
  let actual = signed32CallResultCaller(x)
  let measured = (actual &- 29 &- 0) / 59
  precondition(measured == Int64(input))
  print("OBS\tsigned32CallResultCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "signed32CallResultCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let input: UInt32 = x &+ 47
  let expected = Int64(input) &* 61 &+ 30
  let actual = unsigned32CallResultCaller(x)
  let measured = (actual &- 30 &- 0) / 61
  precondition(measured == Int64(input))
  print("OBS\tunsigned32CallResultCaller\t\(x)\t\(measured)")
  precondition(actual == expected, "unsigned32CallResultCaller: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
print("PASS native Swift argument views: \(observations) observations")
