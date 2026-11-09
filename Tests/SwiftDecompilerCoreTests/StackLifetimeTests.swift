import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let stackLifetimeFixture = "Fixtures/Sample/libStackLifetime.dylib"

@Test func calleeStackReuseHasNativeValueAndBoundaryOraclesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: stackLifetimeFixture) else { return }
    let library = try #require(dlopen(stackLifetimeFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Entry = @convention(c) () -> Int64
    for (name, expected): (String, Int64) in [
        ("reuseUnknown", 99), ("reuseProven", 7), ("reuseExact", 99), ("reuseAbove", 7),
        ("reusePreservation", 99), ("keepPreservation", 7), ("reusePointer", 99),
    ] {
        let symbol = "$s13StackLifetime\(name.count)\(name)SiyF"
        let entry = unsafeBitCast(try #require(dlsym(library, symbol)), to: Entry.self)
        #expect(entry() == expected, Comment(rawValue: name))
    }
    typealias Dynamic = @convention(c) (Int64) -> Int64
    let dynamic = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime12reuseDynamicyS2iF")), to: Dynamic.self)
    #expect(dynamic(0) == 99)
    #expect(dynamic(16) == 7)
    let dynamicAbove = unsafeBitCast(try #require(dlsym(library, "$s13StackLifetime17reuseDynamicAboveyS2iF")), to: Dynamic.self)
    #expect(dynamicAbove(-16) == 99)
    #expect(dynamicAbove(0) == 7)
    #expect(dynamicAbove(16) == 7)
}

@Test func anUnprovedCallCannotKeepAnEarlierCalleesStackWordInAnyPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stackLifetimeFixture) else { return }
    let image = try BinaryLoader.load(path: stackLifetimeFixture)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: stackLifetimeFixture) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: stackLifetimeFixture, functionFilter: "StackLifetime.")
    }
    let streamed = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for name in ["reuseUnknown", "reuseDynamic", "reuseDynamicAbove", "reusePreservation", "reusePointer"] {
            let function = try #require(group.first { $0.displayName.hasPrefix("StackLifetime.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return 7"), Comment(rawValue: text))
            }
        }
        for (name, expected) in [("reuseProven", 7), ("reuseExact", 99), ("reuseAbove", 7), ("keepPreservation", 7)] {
            let function = try #require(group.first { $0.displayName.hasPrefix("StackLifetime.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("return \(expected)"), Comment(rawValue: text))
            }
        }
    }
}

// Analysis-only instructions with an explicit external runtime binding.
// The unknown-sp variant is not invoked as a native callable function.
@Test func anUnknownStackPointerCannotProtectFrameFactsAtAStackProbe() throws {
    let engine = try #require(CapstoneEngine())
    for unknownSP in [false, true] {
        let words: [UInt32] = [
            0xd10083ff, 0xd28000e9, 0xf90007e9, 0x910003f3,
            unknownSP ? 0x9100001f : 0xd503201f,
            0x940003fb, 0x9100027f, 0xf94007e0, 0x910083ff, 0xd65f03c0,
        ]
        let data = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } })
        let decoded = engine.disassemble(data, address: 0x1000)
        try #require(decoded.count == words.count)
        let body = decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? "__chkstk_darwin" : nil))
        }
        let function = DisassembledFunction(symbol: "_stack_probe_lifetime_control", demangledName: nil,
            startAddress: 0x1000, instructions: body, source: .address)
        let result = ValueTracer().analyze(function, entry: nil).exitValues[0x1024]
        if unknownSP { #expect(result != .immediate(7)) }
        else { #expect(result == .immediate(7)) }
    }
}

@Test func preservationUsesTheSameCalleeStackBoundaryAndKeepsLostPointerReach() {
    let initial = Preservation.State(registers: ["sp": .stack(-32)],
        slots: [-40: .entry("x19"), -24: .entry("x20")])
    var known = initial
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &known, clobbersMayAliasStack: false)
    #expect(known.load(at: -40) == .unknown)
    #expect(known.load(at: -24) == .entry("x20"))
    var unknown = initial
    unknown.setRegister("sp", to: .unknown)
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &unknown, clobbersMayAliasStack: false)
    #expect(unknown.load(at: -40) == .unknown)
    #expect(unknown.load(at: -24) == .unknown)
    var complete = initial
    let noWrites = CalleeEffect(memoryEffect: .literalStores([], inputs: []))
    Preservation.applyCall(noWrites, inputs: [], to: &complete, clobbersMayAliasStack: false)
    #expect(complete.load(at: -40) == .entry("x19"))
    #expect(complete.load(at: -24) == .entry("x20"))
    var pointer = Preservation.State(registers: ["sp": .stack(-32)],
        slots: [-40: .stack(-24), -24: .entry("x19")])
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &pointer, clobbersMayAliasStack: false)
    #expect(pointer.load(at: -24) == .unknown)
    #expect(pointer.stackAddressEscaped)
}
