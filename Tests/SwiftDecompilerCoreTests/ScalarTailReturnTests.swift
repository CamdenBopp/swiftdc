import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

@Test func scalarTailCallsKeepTheirReturnedResultIfPresent() async throws {
    for level in ["Onone", "O", "Osize"] {
        let path = "Fixtures/Sample/libScalarTailReturns.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for name in ["integer", "boolean", "floating"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("ScalarTailReturns.\(name)Tail(") })
            for output in [function.renderPseudo(), function.renderStructured()] {
                if level != "Onone" {
                    #expect(output.contains("return ScalarTailReturns.\(name)Leaf("), "\(level): \(output)")
                } else {
                    #expect(output.contains("ScalarTailReturns.\(name)Leaf(") && output.contains("return "))
                }
            }
            if level != "Onone" {
                let tail = try #require(function.instructions.first { $0.controlFlow == .branch })
                #expect(tail.branchTarget != nil)
            }
        }
        let void = try #require(functions.first { $0.displayName.hasPrefix("ScalarTailReturns.voidTail(") })
        #expect(!void.renderStructured().contains("return ScalarTailReturns.voidLeaf("))
    }
}

@Test func longStringComparisonReturnsItsSlowPathIfPresent() async throws {
    let path = "Fixtures/Sample/libLargeStrings.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "LargeStrings.matches")
    }
    let function = try #require(functions.first)
    #expect(function.renderStructured().contains("return Swift._stringCompareWithSmolCheck("))
    #expect(function.renderPseudo().contains("return Swift._stringCompareWithSmolCheck("))
}

@Test func scalarTailReturnProofRejectsIncompatibleContracts() {
    func sites(caller: String = "Example.tail(Swift.Int) -> Swift.Int",
               callee: String = "Example.leaf(Swift.Int) -> Swift.Int",
               flow: ControlFlow = .branch, internalTarget: Bool = false) -> Set<UInt64> {
        var instructions = [Instruction(address: 0x1000, text: "b", annotation: "→ \(callee)",
                                        controlFlow: flow, branchTarget: 0x2000)]
        if internalTarget { instructions.append(Instruction(address: 0x3000, text: "ret", controlFlow: .return)) }
        let function = DisassembledFunction(symbol: "_tail", demangledName: caller, startAddress: 0x1000,
                                            instructions: instructions, source: .symbol)
        return Disassembler.scalarTailReturnSites(in: function)
    }
    #expect(sites() == [0x1000])
    #expect(sites(flow: .call).isEmpty)
    #expect(sites(internalTarget: true).isEmpty)
    #expect(sites(callee: "Example.leaf(Swift.Int) -> Swift.Bool").isEmpty)
    #expect(sites(caller: "Example.tail(Swift.Int) -> ()", callee: "Example.leaf(Swift.Int) -> ()").isEmpty)
    #expect(sites(caller: "Example.tail(Swift.Int) async -> Swift.Int").isEmpty)
    #expect(sites(callee: "Example.leaf(Swift.Int) async -> Swift.Int").isEmpty)
    #expect(sites(caller: "Example.tail(Swift.Int) throws -> Swift.Int").isEmpty)
    #expect(sites(callee: "Example.leaf(Swift.Int) throws -> Swift.Int").isEmpty)
    #expect(sites(caller: "reabstraction thunk helper from Example.tail(Swift.Int) -> Swift.Int").isEmpty)
    #expect(sites(callee: "generic specialization <Swift.Int> of Example.leaf(Swift.Int) -> Swift.Int").isEmpty)
    #expect(sites(caller: "Example.tail() -> (Swift.Int, Swift.Int)",
                  callee: "Example.leaf() -> (Swift.Int, Swift.Int)").isEmpty)
}

@Test func tailReturnProbesDoNotClaimTheirArgumentRegisterAsResultIfPresent() async throws {
    let path = "Fixtures/Sample/libScalarTailReturns.O.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let recorder = ProbeRecorder()
    let functions = try await withStableDependencies {
        try await Probe.recording(recorder) {
            try await Disassembler().disassemble(path: path, functionFilter: "integerTail")
        }
    }
    let function = try #require(functions.first)
    let tail = try #require(function.instructions.first { $0.controlFlow == .branch })
    #expect(recorder.records.contains { $0.event.id == "render.return-outcome" && $0.address == tail.address && $0["status"] == .label("tail-call") })
    #expect(!recorder.records.contains { $0.address == tail.address && ["render.return-value", "values.exit-registers"].contains($0.event.id) })
}

@Test func authoredScalarTailWrappersAgreeWithNativeCalleesIfPresent() throws {
    for level in ["Onone", "O", "Osize"] {
        let path = "Fixtures/Sample/libScalarTailReturns.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(handle) }
        let symbols = try BinaryLoader.loadMachO(path: path).symbols.map(\.name).filter { $0.hasPrefix("_$s") }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift-demangle", "--compact"] + symbols
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let decoded = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
        process.waitUntilExit()
        #expect(process.terminationStatus == 0 && decoded.count == symbols.count)
        func pointer(_ name: String) throws -> UnsafeMutableRawPointer {
            let symbol = try #require(zip(symbols, decoded).first { $0.1.hasPrefix("ScalarTailReturns.\(name)(") }?.0)
            return try #require(dlsym(handle, String(symbol.dropFirst())))
        }
        let integerTail = unsafeBitCast(try pointer("integerTail"), to: (@convention(thin) (Int) -> Int).self)
        let integerLeaf = unsafeBitCast(try pointer("integerLeaf"), to: (@convention(thin) (Int) -> Int).self)
        let booleanTail = unsafeBitCast(try pointer("booleanTail"), to: (@convention(thin) (UInt64) -> Bool).self)
        let booleanLeaf = unsafeBitCast(try pointer("booleanLeaf"), to: (@convention(thin) (UInt64) -> Bool).self)
        let floatingTail = unsafeBitCast(try pointer("floatingTail"), to: (@convention(thin) (Double) -> Double).self)
        let floatingLeaf = unsafeBitCast(try pointer("floatingLeaf"), to: (@convention(thin) (Double) -> Double).self)
        for input: Int in [.min, -1, 0, 1, .max] { #expect(integerTail(input) == integerLeaf(input)) }
        for input: UInt64 in [0, 1, 1 << 63, .max] { #expect(booleanTail(input) == booleanLeaf(input)) }
        for input: Double in [-3, -0.0, 0, 1, .infinity] { #expect(floatingTail(input).bitPattern == floatingLeaf(input).bitPattern) }
    }
}
