import ABISource

@_silgen_name("$s9ABISource17abiMakeAliasedOneyAA10ABIOneWordVSiF")
private func abiMakeAliasedOne(_ seed: Int) -> ABIOneWord

// This is compiled in a separate module so the imported resilient ABI, not
// same-module optimization, determines how the return is passed.
@main
struct ABISourceResilientOracle {
    static func main() {
        print(abiMakeOne(10).a)
        print(abiMakeAliasedOne(10).a)
    }
}
