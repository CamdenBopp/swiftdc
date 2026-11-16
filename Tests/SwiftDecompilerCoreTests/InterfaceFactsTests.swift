import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `interfacefacts.swift` through `interface`: the declarations
/// MachOSwiftSection 0.24.0 printed wrong, as the fork's interface series
/// prints them. A constrained existential is itself, not its arguments; an
/// attribute only a member's name suggests says so; a hand-written `_a`
/// beside `a` is not hidden under a wrapper; an `@objc` thunk marks only its
/// own member; an enum with no field records says how many cases it has; a
/// global is `var` where its section proves it and declines where it does
/// not.
@Test func interfacePrintsWhatTheBinaryProvesIfPresent() throws {
    let path = "Fixtures/Sample/libInterfaceFacts.dylib"
    let cli = URL(fileURLWithPath: ".build/debug/swiftdc")
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: cli.path) else { return }
    let process = Process(), out = Pipe()
    process.executableURL = cli
    process.arguments = ["interface", path]
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    try process.run()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    for expected in [
        "var one: any InterfaceFacts.One<Swift.Int>",
        "var two: any InterfaceFacts.Two<X == Swift.Int, Y == Swift.String>",
        "func takesInverse(_: any ~Swift.Copyable)",
        "var bare: any ~Swift.Copyable",
        "// @resultBuilder inferred from a member's name; the binary does not record it",
        "var _a: InterfaceFacts.NotWrapper<Swift.Int>",
        "init(t: Swift.Int)",
        "// 2 cases: the binary has no field records, so no names",
        "var globalVar: Swift.Int",
        "/* let or var */ globalLazyVar: Swift.Int",
    ] {
        #expect(lines.contains(expected), "\(expected)")
    }
    for wrong in ["var one: Swift.Int", "@objc init(t: Swift.Int)", "enum ObjCEnum {}", "let globalVar: Swift.Int",
                  "@InterfaceFacts.NotWrapper var a: Swift.Int {"] {
        #expect(!lines.contains(wrong), "\(wrong)")
    }
}
