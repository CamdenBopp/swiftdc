// Bridging and heuristic probes.
import Foundation

// Signatureless external: the analysis knows no types for it.
@_silgen_name("ext_pair") func ext_pair(_ a: UInt64, _ b: UInt64)
// Calls ext_pair(0x1234567890abcd41, 0xE1000000000000FF): two integers, NOT a
// Swift small string (bytes past the count are nonzero).
public func intPairNotString() { ext_pair(0x1234567890abcd41, 0xE1000000000000FF) }
// Calls ext_pair(0x6968, 0xE200000000000000): integers that happen to spell "hi".
public func intPairLooksLikeHi() { ext_pair(0x6968, 0xE200000000000000) }

// "abc" bridged to NSString and passed to an ObjC method: NSString.length
public func bridgedLength() -> Int { ("abc-bridged-long-literal" as NSString).length }
// UserDefaults.standard.string(forKey: "key-name")
public func defaultsKey() -> String? { UserDefaults.standard.string(forKey: "key-name") }
// NSString(string: "small")
public func nsStringInit() -> NSString { NSString(string: "small") }
// Notification name literal
public func postNote() { NotificationCenter.default.post(name: Notification.Name("did-change-note"), object: nil) }
// StaticString with an embedded NUL: "ab\0cd" (5 bytes)
@inline(never) public func sinkS(_ s: StaticString) { print(s) }
public func staticNUL() { sinkS("ab\0cdefghijklmnopq") }
// StaticString non-ASCII "größe-static-string"
public func staticNonASCII() { sinkS("größe-static-string") }
// StaticString with a quote: say "x" here please
public func staticQuote() { sinkS("say \"x\" here please") }
// long literal over 48 chars
@inline(never) public func sink(_ s: String) { print(s) }
public func veryLong() { sink("0123456789012345678901234567890123456789012345678901234567890123456789") }
// fatalError message (StaticString-ish message is a String)
public func fatal(_ b: Bool) { if b { fatalError("boom: fatal message here") } }
// precondition message
public func precond(_ x: Int) { precondition(x > 0, "x must be positive!") }
