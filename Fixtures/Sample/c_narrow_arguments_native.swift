import CNarrowArguments

var count = 0
for (input, expected): (Int64, Int32) in [
    (97, 65), (0x1_0000_0061, 65), (0x2_0000_0061, 65),
    (0x1_ffff_ffff, -1), (-1, -1),
] {
    precondition(narrowUpper(input) == expected)
    // The computed wrapper adds one before truncation, including across a
    // 32-bit boundary; subtract with wrapping to preserve its test input.
    precondition(narrowComputedUpper(input &- 1) == expected)
    count += 2
}
for x: Int64 in [0, 1, 0x1_0000_0001, -1] {
    precondition(comparisonUpper(x) == (x == 1 ? 1 : 0))
    precondition(comparisonOffsetUpper(x) == (x == 1 ? 2 : 1))
    count += 2
}
precondition(producerComparisonUpper() == 1)
count += 1
print("PASS \(count) native C narrow-argument observations")
