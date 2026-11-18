import NarrowIntegerReturnPaths
let box = NarrowBox()
var count = 0
for x: Int64 in [0, 1, 127, 128, 255, 256, -1, -128, -129, 0x1_0000_0001] {
    precondition(box.storeNarrow(x) == Int8(truncatingIfNeeded: x))
    precondition(box.wide == x)
    precondition(chooseNarrow(x, x &+ 1) == Int8(truncatingIfNeeded: x < 0 ? x : x &+ 1))
    precondition(producerNarrow(x) == Int8(truncatingIfNeeded: x &+ 7))
    count += 4
}
print("PASS \(count) native return-path observations")
