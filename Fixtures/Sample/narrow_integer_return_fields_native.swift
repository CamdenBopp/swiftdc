import NarrowIntegerReturnFields

var count = 0
for word: UInt64 in [0, 1, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000,
                    0xffff, 0x10000, 0x7fff_ffff, 0x8000_0000,
                    0xffff_ffff, 0x1_0000_0001, 0xdead_beef_ffff_ff81, .max] {
    let box = FieldBox(word)
    precondition(box.byte == UInt8(truncatingIfNeeded: word))
    precondition(box.signed == Int16(truncatingIfNeeded: word))
    precondition(box.middle == UInt32(truncatingIfNeeded: word))
    precondition(box.narrowedWide() == Int8(truncatingIfNeeded: word))
    let byValue = WordBox(Int(truncatingIfNeeded: word) &- 17)
    precondition(byValue.narrowed() == Int8(truncatingIfNeeded: word))
    count += 5
}
print("PASS \(count) native field return observations")
