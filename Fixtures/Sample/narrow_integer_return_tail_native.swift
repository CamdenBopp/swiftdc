import NarrowIntegerReturnTail
var count = 0
for original: Int32 in [0, 1, 127, 128, 32767, 32768, .max, .min, -1] {
    var word = original
    precondition(unsignedAtomic(&word) == UInt32(bitPattern: original))
    precondition(word == original)
    count += 2
}
print("PASS \(count) native C atomic return observations")
