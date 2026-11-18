import NarrowIntegerReturn

var count = 0
for word: UInt64 in [0, 1, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000,
                    0xffff, 0x10000, 0x7fff_ffff, 0x8000_0000,
                    0xffff_ffff, 0x1_0000_0001, 0xdead_beef_ffff_ff81, .max] {
    let input = NarrowInput(truncatingIfNeeded: word)
    precondition(narrow(input) == NarrowOutput(truncatingIfNeeded: word))
    count += 1
}
print("PASS \(count) isolated integer return observations")
