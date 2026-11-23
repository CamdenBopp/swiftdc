import SwiftReceiverTypeList
var observations = 0
for x in UInt8.min...UInt8.max {
 let expected = Int64(Int8(bitPattern: x))
 let gp = gpCaller(x, 73) &- 73
 let fp = fpCaller(x, 3.5) &- 3
 let gp2 = gp2Caller(x, 73, 91) &- 164
 precondition(gp == expected && fp == expected && gp2 == expected)
 print("OBS", x, gp, fp, gp2)
 observations += 3
}
for bias: Int64 in [-73, 0, 91] {
 let f = gpFloatCaller(bias)
 let b = gpBoolCaller(bias)
 precondition(f == Float(bias) + 3.5 && b == bias + 17)
 print("CONTROL", bias, f, b)
 observations += 2
}
print("PASS receiver type list: \(observations) observations")
