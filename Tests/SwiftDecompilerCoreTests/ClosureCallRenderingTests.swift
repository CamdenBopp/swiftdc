import Darwin
import Foundation
import Demangling
import Testing
@testable import SwiftDecompilerCore

private let closureClause = "function signature specialization <Arg[0] = [Closure Propagated : $s1M1fyS2iFS2iXEfU_, Argument Types : [Swift.Int]> of "

@Test func anUnclosedClosureClauseKeepsItsPrefixWithoutItsSignature() {
    let generic = "generic specialization <Swift.Int> of "
    for prefix in [closureClause, closureClause + generic, closureClause + closureClause] {
        for core in ["M.apply((Swift.Int) -> Swift.Int, Swift.Int) -> Swift.Int",
                     "M.apply((Swift.Int) async throws -> Swift.Int, Swift.Int) async throws(M.Error) -> Swift.Int"] {
            #expect(DisassembledFunction.strippedCallee(prefix + core) == prefix + "M.apply")
        }
    }
}

@Test func aClosureCallKeepsItsCompleteArgumentAndTargetFacts() throws {
    let name = closureClause + "M.apply((Swift.Int) -> Swift.Int, Swift.Int) -> Swift.Int"
    let arguments = ["first_value", "second_value"]
    let call = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
        branchTarget: 0x2000, callArguments: arguments, callSelf: "owner", callee: .kept(name))
    let expected = closureClause + "M.apply(self: owner, first_value, second_value)"
    #expect(DisassembledFunction.callStatement(of: call, hideRuntime: false) == expected)
    #expect(DisassembledFunction.pseudoStatement(of: call, hideRuntime: false) == expected)
    #expect(call.callArguments == arguments)
    #expect(call.callSelf == "owner")
    #expect(call.branchTarget == 0x2000)
    #expect(call.callee == name)
}

@Test func ordinaryCalleeStrippingStillKeepsItsBoundaries() {
    let generic = "generic specialization <Swift.Int> of "
    let balanced = "function signature specialization <Arg[0] = Owned To Guaranteed> of "
    for prefix in ["", generic, balanced] {
        #expect(DisassembledFunction.strippedCallee(prefix + "M.apply((Swift.Int) -> Swift.Int) -> Swift.Int") == prefix + "M.apply")
    }
    #expect(DisassembledFunction.strippedCallee("M.f(Swift.Int) throws(M.Error) -> Swift.Int") == "M.f")
    #expect(DisassembledFunction.strippedCallee("M.raw[unclosed (Swift.Int) -> Swift.Int") == "M.raw[unclosed (Swift.Int) -> Swift.Int")
    #expect(DisassembledFunction.strippedCallee("merged M.Box.f(Swift.Int) -> Swift.Int") == "merged ….f")
}


/// Valid demangled payloads may themselves contain the clause delimiter.
/// Keep the complete name when a printed suffix is still ambiguous.
@Test func aPayloadDelimiterCannotChooseALiteralAsTheCallee() throws {
    let cases = [
        ("_T03foo42payload> of M.fake(Swift.Int) -> Swift.IntAATf3psbpsb_n",
         "function signature specialization <Arg[0] = [Constant Propagated String : u8'payload> of M.fake(Swift.Int) -> Swift.Int'], Arg[1] = [Constant Propagated String : u8'foo']> of foo"),
        ("_T03foo42payload> of M.fake(Swift.Int) -> Swift.IntAATf3cpsb_n",
         "function signature specialization <Arg[0] = [Closure Propagated : payload> of M.fake(Swift.Int) -> Swift.Int, Argument Types : [], Arg[1] = [Constant Propagated String : u8'foo']> of foo"),
        ("_T03foo42payload> of M.fake(Swift.Int) -> Swift.IntAATf3psbc_n",
         "function signature specialization <Arg[0] = [Constant Propagated String : u8'payload> of M.fake(Swift.Int) -> Swift.Int'], Arg[1] = [Closure Propagated : foo, Argument Types : []> of foo"),
        ("_T04main5innerys5Int32Vz_yADctF43closure> of M.fake(Swift.Int) -> Swift.Int[xz_Bi32__lXXTf1nc_n",
         "function signature specialization <Arg[1] = [Closure Propagated : closure> of M.fake(Swift.Int) -> Swift.Int[, Argument Types : [<A> { var A } <Builtin.Int32>]> of main.inner(inout Swift.Int32, (Swift.Int32) -> ()) -> ()"),
    ]
    for (symbol, expectedName) in cases {
        let name = try demangleAsNode(symbol).print(using: .default)
        #expect(name == expectedName)
        #expect(DisassembledFunction.strippedCallee(name) == expectedName)
        let call = Instruction(address: 0x1000, text: "bl 0x2000", controlFlow: .call,
            branchTarget: 0x2000, callArguments: ["first_value", "second_value"], callee: .kept(name))
        #expect(DisassembledFunction.callStatement(of: call, hideRuntime: false) == expectedName + "(first_value, second_value)")
        #expect(call.callee == name && call.branchTarget == 0x2000)
        #expect(call.callArguments == ["first_value", "second_value"])
    }
}

private let optimizedClosureSymbols: Set<String> = [
    "_$s8ClosProp11capturesTwoyS2i_S2itF",
    "_$s8ClosProp14nativeCapturesys5Int64VAD_ADtF",
    "_$s8ClosProp15nativeNoCaptureys5Int64VADF",
    "_$s8ClosProp17nativeCapturesTwoys5Int64VAD_A2DtF",
    "_$s8ClosProp5applyyS3iXE_SitF",
    "_$s8ClosProp5applyyS3iXE_SitF03$s8A27Prop9noCaptureyS2iFS2iXEfU_Tf1cn_n",
    "_$s8ClosProp5applyyS3iXE_SitF03$s8A30Prop8capturesyS2i_SitFS2iXEfU_SiTf1cn_n",
    "_$s8ClosProp5applyyS3iXE_SitF03$s8A35Prop11capturesTwoyS2i_S2itFS2iXEfU_S2iTf1cn_n",
    "_$s8ClosProp8capturesyS2i_SitF",
    "_$s8ClosProp9noCaptureyS2iF",
]

private let unoptimizedClosureSymbols: Set<String> = [
    "_$s8ClosProp11capturesTwoyS2i_S2itF",
    "_$s8ClosProp11capturesTwoyS2i_S2itFS2iXEfU_",
    "_$s8ClosProp11capturesTwoyS2i_S2itFS2iXEfU_TA",
    "_$s8ClosProp14nativeCapturesys5Int64VAD_ADtF",
    "_$s8ClosProp15nativeNoCaptureys5Int64VADF",
    "_$s8ClosProp17nativeCapturesTwoys5Int64VAD_A2DtF",
    "_$s8ClosProp5applyyS3iXE_SitF",
    "_$s8ClosProp8capturesyS2i_SitF",
    "_$s8ClosProp8capturesyS2i_SitFS2iXEfU_",
    "_$s8ClosProp8capturesyS2i_SitFS2iXEfU_TA",
    "_$s8ClosProp9noCaptureyS2iF",
    "_$s8ClosProp9noCaptureyS2iFS2iXEfU_",
]

/// Native values identify the fixture; the assertions on the actual call
/// facts only prove rendering, not the closure capture register layout.
@Test func closureCallNamesRenderCompletelyInEveryAnalysisModeIfPresent() async throws {
    let variants = [("Fixtures/Sample/libClosProp.dylib", 13, optimizedClosureSymbols),
                    ("Fixtures/Sample/libClosProp.Osize.dylib", 13, optimizedClosureSymbols),
                    ("Fixtures/Sample/libClosProp.Onone.dylib", 15, unoptimizedClosureSymbols)]
    for (path, expectedCount, filteredSymbols) in variants {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        let noCapture = unsafeBitCast(try #require(dlsym(library, "closprop_no_capture")), to: (@convention(c) (Int64) -> Int64).self)
        let captures = unsafeBitCast(try #require(dlsym(library, "closprop_captures")), to: (@convention(c) (Int64, Int64) -> Int64).self)
        let two = unsafeBitCast(try #require(dlsym(library, "closprop_captures_two")), to: (@convention(c) (Int64, Int64, Int64) -> Int64).self)
        for (k, m, n) in [(Int64(0), Int64(0), Int64(0)), (2, 5, 7), (-3, 4, -2), (5, -2, 9)] {
            #expect(noCapture(k) == k * 3 + 1)
            #expect(captures(k, m) == k * m + 1)
            #expect(two(k, m, n) == k * m + n + 1)
        }
        let array = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "ClosProp.") }
        let streamed = try await withStableDependencies {
            try await Disassembler().disassembleStreaming(machO: BinaryLoader.load(path: path), transform: { $0 })
        }
        try #require(array.count == expectedCount && streamed.count == expectedCount)
        try #require(Set(filtered.map(\.symbol)) == filteredSymbols)
        try #require(filtered.count == filteredSymbols.count)
        for (mode, functions) in [("array", array), ("filtered", filtered), ("streaming", streamed)] {
            for caller in ["noCapture", "captures", "capturesTwo"] {
                let matches = functions.filter { $0.displayName.hasPrefix("ClosProp.\(caller)(") }
                try #require(matches.count == 1, "\(path) \(mode) \(caller)")
                let function = try #require(matches.first)
                let calls = function.instructions.filter {
                    ($0.controlFlow == .call || $0.controlFlow == .branch)
                        && ($0.callee?.contains("ClosProp.apply(") == true)
                }
                try #require(calls.count == 1, "\(path) \(mode) \(caller)")
                let call = try #require(calls.first)
                let callee = try #require(call.callee)
                let arguments = try #require(call.callArguments)
                let core = "ClosProp.apply((Swift.Int) -> Swift.Int, Swift.Int) -> Swift.Int"
                try #require(callee.hasSuffix(core), "\(callee)")
                let prefix = String(callee.dropLast(core.count))
                let expected = prefix + "ClosProp.apply(" + arguments.joined(separator: ", ") + ")"
                if call.resultConsumed {
                    #expect(DisassembledFunction.callStatement(of: call, hideRuntime: false) == nil)
                    #expect(DisassembledFunction.pseudoStatement(of: call, hideRuntime: false) == nil)
                } else {
                    #expect(DisassembledFunction.callStatement(of: call, hideRuntime: false) == expected, "\(path) \(mode) \(caller)")
                }
                let statement = "return " + expected
                let statements = function.instructions.compactMap { DisassembledFunction.pseudoStatement(of: $0, hideRuntime: false) }
                #expect(statements.filter { $0 == statement }.count == 1, "\(path) \(mode) \(caller): \(statements)")
                #expect(function.renderPseudo(hideRuntime: false).split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == statement })
                #expect(function.renderStructured().contains(statement), "\(path) \(mode) \(caller)")
                if !path.contains("Onone") {
                    #expect(prefix.hasPrefix("function signature specialization <"))
                    #expect(prefix.contains("[Closure Propagated"))
                } else {
                    #expect(prefix.isEmpty)
                }
            }
        }
    }
}
