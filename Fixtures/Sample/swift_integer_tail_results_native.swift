// Separately compiled native caller: compare each library result with source arithmetic.
import SwiftTailResults
var observations = 0
do {
 let values: [Int8] = Array(Int8.min...Int8.max)
 for x in values {
  let actual = unsigned8Tail(x)
  let expected = UInt8(truncatingIfNeeded: x &+ 1)
  precondition(actual == expected, "unsigned8Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in values {
  let actual = signed8Tail(x)
  let expected = Int8(truncatingIfNeeded: x &+ 2)
  precondition(actual == expected, "signed8Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32766, 32767]
 for x in values {
  let actual = unsigned16Tail(x)
  let expected = UInt16(truncatingIfNeeded: x &+ 3)
  precondition(actual == expected, "unsigned16Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65534, 65535]
 for x in values {
  let actual = signed16Tail(x)
  let expected = Int16(truncatingIfNeeded: x &+ 4)
  precondition(actual == expected, "signed16Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let actual = unsigned32Tail(x)
  let expected = UInt32(truncatingIfNeeded: x &+ 5)
  precondition(actual == expected, "unsigned32Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let actual = signed32Tail(x)
  let expected = Int32(truncatingIfNeeded: x &+ 6)
  precondition(actual == expected, "signed32Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32766, 32767]
 for x in values {
  let actual = unsigned8From16Tail(x)
  let expected = UInt8(truncatingIfNeeded: x &+ 7)
  precondition(actual == expected, "unsigned8From16Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65534, 65535]
 for x in values {
  let actual = signed8From16Tail(x)
  let expected = Int8(truncatingIfNeeded: x &+ 8)
  precondition(actual == expected, "signed8From16Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let actual = unsigned16From32Tail(x)
  let expected = UInt16(truncatingIfNeeded: x &+ 9)
  precondition(actual == expected, "unsigned16From32Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let actual = signed16From32Tail(x)
  let expected = Int16(truncatingIfNeeded: x &+ 10)
  precondition(actual == expected, "signed16From32Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int64] = [-9223372036854775808, -9223372036854775807, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 9223372036854775806, 9223372036854775807]
 for x in values {
  let actual = unsigned32From64Tail(x)
  let expected = UInt32(truncatingIfNeeded: x &+ 11)
  precondition(actual == expected, "unsigned32From64Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt64] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 18446744073709551614, 18446744073709551615]
 for x in values {
  let actual = signed32From64Tail(x)
  let expected = Int32(truncatingIfNeeded: x &+ 12)
  precondition(actual == expected, "signed32From64Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int64] = [-9223372036854775808, -9223372036854775807, -65537, -65536, -32769, -32768, -257, -256, -129, -128, -1, 0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 9223372036854775806, 9223372036854775807]
 for x in values {
  let actual = unsigned8From64Tail(x)
  let expected = UInt8(truncatingIfNeeded: x &+ 13)
  precondition(actual == expected, "unsigned8From64Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt64] = [0, 1, 127, 128, 255, 256, 257, 32767, 32768, 65535, 65536, 18446744073709551614, 18446744073709551615]
 for x in values {
  let actual = signed8From64Tail(x)
  let expected = Int8(truncatingIfNeeded: x &+ 14)
  precondition(actual == expected, "signed8From64Tail: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
print("PASS native tail conversions: \(observations) observations")
