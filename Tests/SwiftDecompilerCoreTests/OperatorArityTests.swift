import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let operatorArityFixtures = [
    "Fixtures/Sample/libOperatorArity.Onone.dylib",
    "Fixtures/Sample/libOperatorArity.O.dylib",
    "Fixtures/Sample/libOperatorArity.Osize.dylib",
]

@Test func operatorDeclarationsKeepTheirFormalCountWithoutAssumingAnAggregateABI() throws {
    for (name, arity) in [
        ("static M.Token.== infix(M.Token, M.Token) -> Swift.Bool", 2),
        ("M.! prefix(M.Token) -> Swift.Bool", 1),
        ("M.^^^ postfix(M.Token) -> Swift.Int", 1),
    ] {
        let layout: Disassembler.SwiftArgumentLayout = try #require(Disassembler.swiftCallArgumentLayout(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()))
        #expect(layout.slots.isEmpty)
        #expect(layout.unplaced == arity)
    }
    let scalars: Disassembler.SwiftArgumentLayout = try #require(Disassembler.swiftCallArgumentLayout(
        callee: "M.== infix(Swift.Int, Swift.Int) -> Swift.Bool",
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()))
    #expect(scalars.slots.count == 2 && scalars.unplaced == 0)
    let withVoid: Disassembler.SwiftArgumentLayout = try #require(Disassembler.swiftCallArgumentLayout(
        callee: "M.+ infix((), Swift.Int) -> Swift.Int",
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex()))
    #expect(withVoid.slots.map(\.kind) == [.aggregate(integers: 0, floats: 0), .integer])
    #expect(withVoid.unplaced == 0)
    for name in [
        "M.== infix(Swift.Int) -> Swift.Bool",
        "M.! prefix(Swift.Int, Swift.Int) -> Swift.Bool",
        "M.function infix(Swift.Int, Swift.Int) -> Swift.Bool",
        "closure #1 in M.== infix(Swift.Int, Swift.Int) -> Swift.Bool",
        "function signature specialization <Arg[0] = Dead> of M.== infix(Swift.Int, Swift.Int) -> Swift.Bool",
        "protocol witness for static M.Token.== infix(M.Token, M.Token) -> Swift.Bool in conformance M.Token : Swift.Equatable in M",
    ] {
        let layout: Disassembler.SwiftArgumentLayout? = Disassembler.swiftCallArgumentLayout(
            callee: name, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), anyContext: true)
        #expect(layout == nil, Comment(rawValue: name))
    }
}

@Test func opaqueOperatorOperandsHaveIndependentNativeResultsAtAllLevelsIfPresent() throws {
    for fixture in operatorArityFixtures where FileManager.default.fileExists(atPath: fixture) {
        let library = try #require(dlopen(fixture, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for (name, expected): (String, Int64) in [
            ("operator_arity_equal", 1), ("operator_arity_prefix", 0), ("operator_arity_postfix", 42),
        ] {
            let entry = unsafeBitCast(try #require(dlsym(library, name)), to: Entry.self)
            #expect(entry() == expected, Comment(rawValue: fixture + ": " + name))
        }
    }
}

@Test func unknownOperatorOperandsRetainDeclaredArityInEveryPipelineAtAllLevelsIfPresent() async throws {
    for fixture in operatorArityFixtures where FileManager.default.fileExists(atPath: fixture) {
        let image = try BinaryLoader.load(path: fixture)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: fixture) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: fixture, functionFilter: "Opaque")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for group in [listing, array, filtered, streamed, Array(each.values)] {
            for (caller, op, arity) in [("equalOpaque", "== infix", 2), ("prefixOpaque", "! prefix", 1),
                                        ("postfixOpaque", "^^^ postfix", 1)] {
                let function = try #require(group.first { $0.displayName.hasPrefix("OperatorArity.\(caller)(") })
                let calls = function.instructions.filter {
                    ($0.controlFlow == .call || $0.controlFlow == .branch)
                        && DisassembledFunction.calleeName(of: $0)?.contains(op) == true
                }
                // A surviving real operator call is essential: neither an
                // opaque source call nor an optimized constant proves arity.
                let call = try #require(calls.count == 1 ? calls.first : nil)
                #expect(call.callArguments == Array(repeating: "?", count: arity), Comment(rawValue: fixture))
                let operands = Array(repeating: "?", count: arity).joined(separator: ", ")
                for text in [function.renderPseudo(), function.renderStructured()] {
                    #expect(text.contains(op + "(" + operands + ")"), Comment(rawValue: text))
                }
            }
        }
    }
}
