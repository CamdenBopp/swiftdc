import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

private let cNarrowArgumentImages = [
    "Fixtures/Sample/libCNarrowArguments.Onone.dylib",
    "Fixtures/Sample/libCNarrowArguments.O.dylib",
    "Fixtures/Sample/libCNarrowArguments.Osize.dylib",
]

@Test func wideSwiftArgumentsDoNotBecomeWholeCIntArgumentsIfPresent() async throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let upper = path.contains(".Onone.") ? "toupper" : "__toupper"
        for (name, callee) in [("narrowClose", "close"), ("narrowKill", "kill"),
                               ("narrowSleep", "sleep"), ("narrowUpper", upper)] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let context = Comment(rawValue: path + "\n" + text)
                #expect(text.contains(callee + "("), context)
                #expect(!text.contains(callee + "(arg0)"), context)
                #expect(!text.contains(callee + "(arg0,"), context)
                if callee != "sleep" {
                    #expect(!text.contains(callee + "((arg0 & 0xffffffff))"), context)
                    #expect(!text.contains(callee + "((arg0 & 0xffffffff),"), context)
                }
            }
        }
    }
}

@Test func aComputedCIntArgumentKeepsItsSignedInterpretationIfPresent() async throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let function = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.narrowComputedUpper(") })
        for text in [function.renderPseudo(), function.renderStructured()] {
            // For input 0x1fffffffe, the C operand is EOF (-1), not the
            // positive 0xffffffff printed by the old zero-extension alone.
            let context = Comment(rawValue: path + "\n" + text)
            let callee = path.contains(".Onone.") ? "toupper" : "__toupper"
            #expect(text.contains(callee + "("), context)
            #expect(!text.contains("toupper(((arg0 + 1) & 0xffffffff))"), context)
            #expect(!text.contains("__toupper((((arg0 & 0xffffffff) + 1) & 0xffffffff))"), context)
        }
    }
}

@Test func narrowCArgumentConstantsAndTypedControlsStayExactIfPresent() async throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let typed = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.typedKill(") })
        let constant = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.constantClose(") })
        for text in [typed.renderPseudo(), typed.renderStructured()] {
            #expect(text.contains("kill(arg0, 1)"), Comment(rawValue: path + "\n" + text))
        }
        for text in [constant.renderPseudo(), constant.renderStructured()] {
            #expect(text.contains("close(-1)"), Comment(rawValue: path + "\n" + text))
        }
    }
}

@Test func narrowCArgumentFixturesBindToTheRealSystemProviderIfPresent() throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        #expect(image.header.flags.contains(.twolevel))
        #expect(!image.header.flags.contains(.force_flat))
        let libraries = Array(image.dependencies)
        let upper = path.contains(".Onone.") ? "_toupper" : "___toupper"
        for name in ["_close", "_kill", "_sleep", "_open", upper] {
            let symbol = try #require(image.symbols.first { $0.name == name && $0.offset == 0 })
            let description = try #require(symbol.nlist.symbolDescription)
            #expect(description.libraryOrdinalType == nil)
            let index = Int(description.libraryOrdinal) - 1
            try #require(libraries.indices.contains(index))
            #expect(libraries[index].dylib.name == "/usr/lib/libSystem.B.dylib")
        }
    }
}

@Test func narrowCArgumentNativeObservationsPassAtAllSwiftLevelsIfPresent() throws {
    for path in ["Fixtures/Sample/c-narrow-arguments-Onone-oracle",
                 "Fixtures/Sample/c-narrow-arguments-O-oracle",
                 "Fixtures/Sample/c-narrow-arguments-Osize-oracle"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: bytes, as: UTF8.self) == "PASS 19 native C narrow-argument observations\n")
    }
}

@Test func decliningUnprovedCArgumentBitsPreservesTheProducerIfPresent() async throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let function = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.narrowProducer(") })
        for text in [function.renderPseudo(), function.renderStructured()] {
            let context = Comment(rawValue: path + "\n" + text)
            #expect(text.components(separatedBy: "getpid()").count == 2, context)
            #expect(text.contains("kill(?, 0)"), context)
            let producer = try #require(text.range(of: "getpid()"))
            let consumer = try #require(text.range(of: "kill(?, 0)"))
            #expect(producer.lowerBound < consumer.lowerBound, context)
        }
    }
}

private func cNarrowEvaluate(_ value: AbstractValue, argument: UInt64) -> UInt64? {
    switch value {
    case .argument(0), .callResult(0x1000): return argument
    case .immediate(let word): return word
    case .binary(let operation, let left, let right):
        guard let lhs = cNarrowEvaluate(left, argument: argument),
              let rhs = cNarrowEvaluate(right, argument: argument) else { return nil }
        switch operation {
        case .add: return lhs &+ rhs
        case .equal: return lhs == rhs ? 1 : 0
        case .bitAnd: return lhs & rhs
        case .shiftLeft: return lhs &<< rhs
        case .arithmeticShiftRight: return UInt64(bitPattern: Int64(bitPattern: lhs) &>> rhs)
        default: return nil
        }
    default: return nil
    }
}

@Test func narrowCIntegerArgumentsAgreeWithNativeIntegerConversions() {
    // High garbage, either sign, and boundaries for all six C integer codes.
    for word: UInt64 in [0, 1, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000,
                         0xffff, 0x10000, 0x7fff_ffff, 0x8000_0000,
                         0xffff_ffff, 0x1_0000_0001, 0xdead_beef_ffff_ff81, .max] {
        let expected: [(String, UInt64)] = [
            ("Swift.Int8", UInt64(bitPattern: Int64(Int8(truncatingIfNeeded: word)))),
            ("Swift.Int16", UInt64(bitPattern: Int64(Int16(truncatingIfNeeded: word)))),
            ("Swift.Int32", UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: word)))),
            ("Swift.UInt8", UInt64(UInt8(truncatingIfNeeded: word))),
            ("Swift.UInt16", UInt64(UInt16(truncatingIfNeeded: word))),
            ("Swift.UInt32", UInt64(UInt32(truncatingIfNeeded: word))),
        ]
        for (type, expected) in expected {
            let value = Disassembler.cIntegerArgumentValue(.argument(0), type: type,
                                                          arguments: [0: .unsignedInteger(64)])
            #expect(cNarrowEvaluate(value, argument: word) == expected,
                    Comment(rawValue: type + " input " + String(word, radix: 16)))
        }
    }
}

@Test func narrowCArgumentsDoNotInventUnprovedPhysicalBits() {
    let byte: [Int: ValueType] = [0: .unsignedInteger(8)]
    #expect(Disassembler.cIntegerArgumentValue(.argument(0), type: "Swift.Int32", arguments: byte) == .unknown)
    #expect(Disassembler.cIntegerArgumentValue(.callResult(0x1000), type: "Swift.Int32", arguments: [:]) == .unknown)
    #expect(Disassembler.cIntegerArgumentValue(.selfPointer, type: "Swift.Int32", arguments: [:]) == .unknown)
    let masked = AbstractValue.binary(.bitAnd, .argument(0), .immediate(0xff))
    let widened = Disassembler.cIntegerArgumentValue(masked, type: "Swift.Int32", arguments: byte)
    #expect(cNarrowEvaluate(widened, argument: 0xdead_beef_0000_0081) == 129)
    let shifted = AbstractValue.binary(.shiftRight, .argument(0), .immediate(1))
    #expect(Disassembler.cIntegerArgumentValue(shifted, type: "Swift.Int8", arguments: byte) == .unknown)
}

@Test func aVariadicCFixedIntegerParameterKeepsItsWidthIfPresent() async throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let function = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.narrowOpen(") })
        for text in [function.renderPseudo(), function.renderStructured()] {
            let context = Comment(rawValue: path + "\n" + text)
            #expect(text.contains("open(arg0,"), context)
            #expect(text.contains("…"), context)
            #expect(!text.contains("open(arg0, arg1,"), context)
            #expect(!text.contains("open(arg0, arg1)"), context)
            #expect(!text.contains("open(arg0, (arg1 & 0xffffffff),"), context)
        }
    }
}

@Test func computedBooleanWordsRetainTheirCIntegerArgumentsIfPresent() async throws {
    for path in cNarrowArgumentImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for name in ["comparisonUpper", "producerComparisonUpper", "comparisonOffsetUpper"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("CNarrowArguments.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let context = Comment(rawValue: path + "\n" + text)
                #expect(text.contains("toupper("), context)
                #expect(!text.contains("toupper(?)"), context)
                if name == "producerComparisonUpper" {
                    #expect(text.contains("> 0"), context)
                } else {
                    #expect(text.contains("== 1") || text.contains("!= 1"), context)
                }
                if name == "producerComparisonUpper" {
                    #expect(text.components(separatedBy: "getpid()").count == 2, context)
                }
            }
        }
    }
}

@Test func aComputedBooleanWordIsDistinctFromABareBooleanArgument() {
    let comparison = AbstractValue.binary(.equal, .callResult(0x1000), .immediate(1))
    for type in ["Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32"] {
        for input in [comparison, .binary(.bitAnd, comparison, .immediate(1)), .binary(.add, comparison, .immediate(1))] {
            let normalized = Disassembler.cIntegerArgumentValue(input, type: type, arguments: [:])
            for word: UInt64 in [0, 1, 0x1_0000_0001, .max] {
                let offset: UInt64 = input == .binary(.add, comparison, .immediate(1)) ? 1 : 0
                #expect(cNarrowEvaluate(normalized, argument: word) == (word == 1 ? 1 : 0) + offset)
            }
        }
        let maskedArgument = AbstractValue.binary(.bitAnd, .argument(0), .immediate(1))
        let normalized = Disassembler.cIntegerArgumentValue(maskedArgument, type: type, arguments: [0: .boolean])
        for word: UInt64 in [0, 1, 0xdead_beef_ffff_fffe, .max] {
            #expect(cNarrowEvaluate(normalized, argument: word) == word & 1)
        }
    }
    // A source Bool's incoming word need only prove its own bit. It does
    // not have a comparison instruction's guarantee about every upper bit.
    #expect(Disassembler.cIntegerArgumentValue(.argument(0), type: "Swift.UInt32", arguments: [0: .boolean]) == .unknown)
}
