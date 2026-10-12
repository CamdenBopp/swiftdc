@main
struct ABISourceOracle {
    static func main() {
        print(abiOneDoubleFromInt(2).value)
        print(ABIVec2(2, 3).scaled(5))
        print(ABIVec2(2, 3).dot(ABIVec2(5, 7)))
        print(abiMaybeFive(10, true)!.e)
        print(abiMakeRef(10).value)
        print(String(abiMakeSubstring("ABCDE")))
        print("sizes", MemoryLayout<ABIOneWord>.size, MemoryLayout<ABITwoWords>.size,
              MemoryLayout<ABIFiveWords>.size, MemoryLayout<Substring>.size,
              MemoryLayout<Any>.size)
    }
}
