// String-literal ABI probes. Each function calls an opaque sink with a literal
// so the literal's register encoding is visible at the call.
@inline(never) public func sink(_ s: String) { print(s) }
@inline(never) public func sink2(_ a: String, _ b: String) { print(a, b) }

// small ASCII "hello" (5 bytes): x0=0x6f6c6c6568, x1=0xe5<<56
public func smallHello() { sink("hello") }
// exactly 15 bytes small: "abcdefghijklmno"
public func small15() { sink("abcdefghijklmno") }
// 16 bytes: large literal "abcdefghijklmnop"
public func large16() { sink("abcdefghijklmnop") }
// empty string: x0=0, x1=0xe0<<56
public func emptyStr() { sink("") }
// non-ASCII small: "héllo" is 6 UTF-8 bytes, 5 chars; discriminator 0xa6
public func smallNonASCII() { sink("héllo") }
// non-ASCII large: "ünïcödé strîng!!" (more than 15 bytes)
public func largeNonASCII() { sink("ünïcödé strîng!! and more") }
// emoji small: "🙂" 4 bytes
public func smallEmoji() { sink("🙂") }
// escapes small: a"b\c (5 bytes: a " b \ c)
public func smallQuote() { sink("a\"b\\c") }
// newline/tab small: "x\ny\tz"
public func smallNewline() { sink("x\ny\tz") }
// NUL inside small: "a\0b" (3 bytes)
public func smallNUL() { sink("a\0b") }
// NUL inside large: "abcdefgh\0ijklmnopqrs" (20 bytes)
public func largeNUL() { sink("abcdefgh\0ijklmnopqrs") }
// large with quote, backslash, newline
public func largeEscapes() { sink("say \"hi\" to C:\\path\nand go") }
// multiline literal: "line one\nline two" (17 bytes)
public func multiline() {
    sink("""
    line one
    line two
    """)
}
// raw literal: #"a\nb"# is 4 bytes a \ n b
public func rawLit() { sink(#"a\nb"#) }
// two strings: "k" and "value-long-enough-to-be-large"
public func twoStrings() { sink2("k", "value-long-enough-to-be-large") }
// small string of exactly 8 bytes (fills x0, x1 holds only discriminator) "12345678"
public func small8() { sink("12345678") }
// DEL char 0x7f small
public func smallDEL() { sink("a\u{7f}b") }
// combining sequence: "e\u{301}" 3 bytes
public func combining() { sink("e\u{301}") }
// line separator U+2028 small
public func lineSep() { sink("a\u{2028}b") }
