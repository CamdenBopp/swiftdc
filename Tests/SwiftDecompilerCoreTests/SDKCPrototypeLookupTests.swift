import Testing
@testable import SwiftDecompilerCore

/// `SDKCPrototypes.entry` binary-searches the table's lines, so they must be
/// sorted bytewise by name with no name twice, and every one must be found.
/// A dictionary of the whole table, built per process, cost about 2.5 MB.
@Test func everySDKPrototypeIsFoundByItsName() {
    let text = SDKCPrototypes.data.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
    let lines = text.split(separator: "\n")
    #expect(lines.count > 20_000)
    var previous: [UInt8] = []
    var missed: [Substring] = []
    for line in lines {
        let space = try! #require(line.firstIndex(of: " "))
        let name = String(line[..<space])
        let bytes = Array(name.utf8)
        #expect(previous.lexicographicallyPrecedes(bytes), "\(name) out of order")
        previous = bytes
        if SDKCPrototypes.entry(name) != String(line[line.index(after: space)...]) { missed.append(line) }
    }
    #expect(missed.isEmpty, "\(missed.prefix(5))")
    // Neither a prefix of a name nor a name extended matches.
    #expect(SDKCPrototypes.entry("ioctl") == "i wi...")
    #expect(SDKCPrototypes.entry("ioct") == nil)
    #expect(SDKCPrototypes.entry("ioctlx") == nil)
    #expect(SDKCPrototypes.entry("") == nil)
}
