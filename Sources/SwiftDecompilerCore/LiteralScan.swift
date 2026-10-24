/// Whether a scan of rendered text is inside a string literal, so a scanner
/// for brackets or operators skips what a literal holds.
///
/// A literal's escaped quote (`\"`) does not end it. A scanner that toggled at
/// every `"` left `"a\""` open, so it read the rest of the text as literal:
/// `((arg0 == "a\"") || (arg1 < 1))` inverted to
/// `!(arg0 == "a\"") || (arg1 < 1)`, because the `||` after the literal was
/// hidden from it.
struct LiteralScan {
    private(set) var inLiteral = false
    private var escaped = false

    /// Steps over one character, and says whether it belongs to a literal,
    /// the quotes that open and close it included.
    mutating func step(_ character: Character) -> Bool {
        if escaped {
            escaped = false
            return true
        }
        if character == "\"" {
            inLiteral.toggle()
            return true
        }
        if inLiteral, character == "\\" { escaped = true }
        return inLiteral
    }
}
