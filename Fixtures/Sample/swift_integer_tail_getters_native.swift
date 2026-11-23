// Separately compiled native caller: compare each library result with source arithmetic.
import SwiftTailGetters
var observations = 0
do {
 let values: [Int8] = Array(Int8.min...Int8.max)
 for x in values {
  let actual = Signed8Box(x).view()
  let expected = UInt8(truncatingIfNeeded: x &+ 21)
  precondition(actual == expected, "Signed8Box: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt8] = Array(UInt8.min...UInt8.max)
 for x in values {
  let actual = Unsigned8Box(x).view()
  let expected = Int8(truncatingIfNeeded: x &+ 22)
  precondition(actual == expected, "Unsigned8Box: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int16] = [-32768, -32767, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32766, 32767]
 for x in values {
  let actual = Signed16Box(x).view()
  let expected = UInt16(truncatingIfNeeded: x &+ 23)
  precondition(actual == expected, "Signed16Box: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt16] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65534, 65535]
 for x in values {
  let actual = Unsigned16Box(x).view()
  let expected = Int16(truncatingIfNeeded: x &+ 24)
  precondition(actual == expected, "Unsigned16Box: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [Int32] = [-2147483648, -2147483647, -65537, -32769, -257, -129, -128, -1, 0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 2147483646, 2147483647]
 for x in values {
  let actual = Signed32Box(x).view()
  let expected = UInt32(truncatingIfNeeded: x &+ 25)
  precondition(actual == expected, "Signed32Box: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
do {
 let values: [UInt32] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, 4294967294, 4294967295]
 for x in values {
  let actual = Unsigned32Box(x).view()
  let expected = Int32(truncatingIfNeeded: x &+ 26)
  precondition(actual == expected, "Unsigned32Box: \(x), actual \(actual), expected \(expected)")
  observations += 1
 }
}
print("PASS native tail conversions: \(observations) observations")
