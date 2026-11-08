import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A float's bits read into a general register are an integer. `fmov x8, d0`
/// carried the Double through unchanged, so `floatbits.swift` (-O) rendered
/// `Int(a)`'s finiteness guard as `(arg0 & 0x7fffffffffffffff) >
/// 1.7976931348623157e+308`, a float compare that is false on NaN where the
/// binary traps, and `a.bitPattern > 100` as `(arg0 <=ᵁ 100)`, which reads as
/// a compare of the Double.
@Test func aFloatsBitsMovedToAnIntegerRegisterRenderAsItsBitPatternIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatBits.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatBits.\(name)(") }).renderStructured()
    }
    let guardText = try render("truncatingConversion")
    #expect(guardText.contains("if ((arg0.bitPattern & 0x7fffffffffffffff) > 0x7fefffffffffffff) {"))
    #expect(!guardText.contains("e+308"))
    #expect(try render("lowByte").contains("(((arg0.bitPattern & 255) != 7) ? 2 : 1)"))
    #expect(try render("bitsAbove").contains("((arg0.bitPattern <=ᵁ 100) ? 8 : 7)"))
    #expect(try render("exponentField").contains("(((arg0.bitPattern >>ᵁ 52) != 1023) ? 10 : 9)"))
    #expect(try render("floatLowByte").contains("(((arg0.bitPattern & 255) != 7) ? 12 : 11)"))
    // No operator between the bits and the compare: rendered `(arg0 != nan)`.
    #expect(try render("bitsEqualPayload").contains("((arg0.bitPattern != 0x7ff8000000000001) ? 18 : 17)"))
}

/// A bit-level operator's result is an integer whatever it read. A word
/// moved by `memcpy` has no known register file, so the Double arrives bare:
/// `str d0, [sp, #8]; memcpy(sp, sp + 8, 8); ldrb w8, [sp]; cmp w8, #7`
/// (`floatbitswidth.s`), and the 7 rendered as the Double `3.5e-323`. A byte
/// reversal (`ldr x8, [sp]; rev x8, x8`) is integer-only the same way.
@Test func aConstantBesideABitLevelOperatorOnAFloatIsAnIntegerIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatBitsWidth.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatBitsWidth.\(name)(") }).renderStructured()
    }
    let copied = try render("copied")
    #expect(copied.contains("(arg0 & 255) != 7"), "\(copied)")
    #expect(!copied.contains("e-323"))
    let swapped = try render("swapped")
    #expect(swapped.contains("byteSwap64(arg0) != 7"), "\(swapped)")
    #expect(!swapped.contains("e-323"))
}

/// The tracer's half: `fmov x0, d1` is the bit pattern of d1 at its own
/// width, an immediate stays the immediate, and moving a bit pattern back
/// into a float register of that width is the float again.
@Test func anFmovBetweenRegisterFilesReinterpretsTheBits() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ words: [UInt32]) -> (value: AbstractValue?, float: AbstractValue?) {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let result = ValueTracer().analyze(function, entry: nil)
        return (result.exitValues[body.last!.address], result.exitFloatValues[body.last!.address])
    }
    let double = AbstractValue.unary(.toFloat(bits: 64), .immediate(5))
    // mov w8, #5; scvtf d1, w8; fmov x0, d1; ret
    #expect(trace([0x528000a8, 0x1e620101, 0x9e660020, 0xd65f03c0]).value
        == .unary(.bitPattern(bits: 64), double))
    // mov w8, #5; scvtf d1, w8; fmov x9, d1; fmov d0, x9; ret
    #expect(trace([0x528000a8, 0x1e620101, 0x9e660029, 0x9e670120, 0xd65f03c0]).float == double)
    // mov w8, #5; scvtf s1, w8; fmov w0, s1; ret
    #expect(trace([0x528000a8, 0x1e220101, 0x1e260020, 0xd65f03c0]).value
        == .unary(.bitPattern(bits: 32), .unary(.toFloat(bits: 32), .immediate(5))))
    // mov x9, #0x4059000000000000; fmov d2, x9; fmov x0, d2; ret: the same bits
    #expect(trace([0xd2e80b29, 0x9e670122, 0x9e660040, 0xd65f03c0]).value == .immediate(0x4059000000000000))
}

/// A Float's bits are 32. `fmov w0, s0` is `a.bitPattern`; `fmov x0, d0`
/// reads all of d0, whose upper half the Float does not define, and declines.
/// Before the bit pattern was modelled the first read `(arg0 & 0xffffffff)`
/// and the second `arg0`, the Float itself (`floatbitswidth.s`).
@Test func aFloatsBitsReadAtAnotherWidthDeclineIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatBitsWidth.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatBitsWidth.\(name)(") }).renderStructured()
    }
    #expect(try render("word").contains("return arg0.bitPattern\n"))
    #expect(try render("whole").contains("return ?\n"))
}

/// An integer's bits read as a float are `Double(bitPattern: i)`, not i.
/// `floatreinterpret.swift` (-O) passes `Double(bitPattern: i) * 2.0` as
/// `fmov d0, x0; fadd d0, d0, d0`, which rendered `(arg0 + arg0)`, an integer
/// add of the UInt64.
@Test func anIntegersBitsMovedToAFloatRegisterReadAsThatFloatIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatReinterpret.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatReinterpret.\(name)(") }).renderStructured()
    }
    #expect(try render("doubleFromBits").contains("sd((Double(bitPattern: arg0) + Double(bitPattern: arg0)))"))
    #expect(try render("floatFromBits").contains("sf((Float(bitPattern: arg0) + Float(bitPattern: arg0)))"))
    #expect(try render("castFromInt").contains("sd((Double(bitPattern: arg0) + 1.0))"))
}

/// The tracer's half of the reverse move: `fmov d0, x0` is the float whose
/// bits are x0, a word move drops the zero-extension mask, and moving that
/// float back to a general register is x0 again.
@Test func anFmovFromAGeneralRegisterReinterpretsTheBits() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ words: [UInt32]) -> (value: AbstractValue?, float: AbstractValue?) {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let result = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        return (result.exitValues[body.last!.address], result.exitFloatValues[body.last!.address])
    }
    // fmov d0, x0; ret
    #expect(trace([0x9e670000, 0xd65f03c0]).float == .unary(.floatFromBits(bits: 64), .argument(0)))
    // fmov s0, w0; ret
    #expect(trace([0x1e270000, 0xd65f03c0]).float == .unary(.floatFromBits(bits: 32), .argument(0)))
    // fmov d1, x0; fmov x0, d1; ret
    #expect(trace([0x9e670001, 0x9e660020, 0xd65f03c0]).value == .argument(0))
}

/// A reinterpreted integer is a float of its width, and a float's bits an
/// integer of unknown sign, so neither carries the other's type onward.
@Test func reinterpretedBitsTakeTheTypeTheyAreReadAs() {
    #expect(TypeInference.typeOf(.unary(.floatFromBits(bits: 64), .argument(0)), arguments: [:]) == .floating(64))
    #expect(TypeInference.typeOf(.unary(.floatFromBits(bits: 32), .argument(0)), arguments: [:]) == .floating(32))
    #expect(TypeInference.typeOf(.unary(.bitPattern(bits: 64), .argument(0)), arguments: [:])
        == ValueType(category: .integer, width: 64, signedness: .unknownSign))
}

/// A float spilled and reloaded into a general register is its bit pattern,
/// with no `fmov` to say so. -Onone `unsafeBitCast(a, to: Int.self)` is `str
/// d0, [sp]; ldr x9, [sp]`, and `~bits == 7`, lowered to `0 - x - 1`, rendered
/// `((-arg0 - 5e-324) != 3.5e-323)`. The reverse, `str x0, [sp]; ldr d0, [sp]`,
/// rendered the Int as the Double: `(arg0 + 1.0)`.
@Test func aWordReloadedIntoTheOtherRegisterFileIsReinterpretedIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatReinterpret.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatReinterpret.\(name)(") }).renderStructured()
    }
    #expect(try render("complement").contains("if ((-arg0.bitPattern - 1) != 7) {"))
    #expect(try render("castFromInt").contains("sd((Double(bitPattern: arg0) + 1.0))"))
    let bits = "Fixtures/Sample/libFloatBits.dylib"
    guard FileManager.default.fileExists(atPath: bits) else { return }
    let spilled = try await withStableDependencies { try await Disassembler().disassemble(path: bits) }
    let lowByte = try #require(spilled.first { $0.displayName.hasPrefix("FloatBits.bitCastLowByte(") })
    #expect(lowByte.renderStructured().contains("if ((arg0.bitPattern & 255) != 7) {"))
}

/// -Onone `Double(bitPattern: i)` calls the initializer, and the call named
/// it `Swift.Double.init(arg0)`: the numeric conversion `Double(i)`, a
/// different function. A callee with argument labels keeps them.
@Test func aLabelledInitializerKeepsItsLabelsIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatReinterpret.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func render(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FloatReinterpret.\(name)(") }).renderStructured()
    }
    #expect(try render("doubleFromBits").contains("sd((Swift.Double.init(bitPattern:)(arg0) * 2.0))"))
    #expect(try render("floatFromBits").contains("sf((Swift.Float.init(bitPattern:)(arg0) * 2.0))"))
    #expect(!(try render("doubleFromBits")).contains("Swift.Double.init(arg0)"))
}

/// The name half: labels are kept exactly when one is not `_`.
@Test func strippedCalleeKeepsArgumentLabels() {
    #expect(DisassembledFunction.strippedCallee("Swift.Double.init(bitPattern: Swift.UInt64) -> Swift.Double")
        == "Swift.Double.init(bitPattern:)")
    #expect(DisassembledFunction.strippedCallee("Swift.Int.init(Swift.Double) -> Swift.Int") == "Swift.Int.init")
    #expect(DisassembledFunction.strippedCallee("M.f(Swift.Int, by: Swift.Int)") == "M.f(_:by:)")
    #expect(DisassembledFunction.strippedCallee("M.g(x: (a: Swift.Int, b: Swift.Int)) -> ()") == "M.g(x:)")
}

/// The slot's half: which register file stored a word decides what a reload
/// of it is, and what is not known claims nothing.
@Test func aStackSlotRemembersTheRegisterFileThatStoredIt() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ words: [UInt32], conventions: [UInt64: CalleeResultConvention] = [:])
        -> (value: AbstractValue, float: AbstractValue) {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let result = ValueTracer(calleeConventions: conventions)
            .analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0, "v0": 0, "v1": 0]))
        let exit = body.last!.address
        return (result.exitValues[exit] ?? .unknown, result.exitFloatValues[exit] ?? .unknown)
    }
    let ret: UInt32 = 0xd65f03c0
    let double = AbstractValue.unary(.bitPattern(bits: 64), .argument(0))
    // str d0, [sp, #8]; ldr x0, [sp, #8]
    #expect(trace([0xfd0007e0, 0xf94007e0, ret]).value == double)
    // str d0, [sp, #8]; ldrb w0, [sp, #8]: the low byte of the bits
    #expect(trace([0xfd0007e0, 0x394023e0, ret]).value == .binary(.bitAnd, double, .immediate(0xff)))
    // str s0, [sp, #8]; ldr w0, [sp, #8]
    #expect(trace([0xbd000be0, 0xb9400be0, ret]).value == .unary(.bitPattern(bits: 32), .argument(0)))
    // stp d0, d1, [sp, #16]; ldr x0, [sp, #24]
    #expect(trace([0x6d0107e0, 0xf9400fe0, ret]).value == double)
    // str x0, [sp, #8]; ldr d0, [sp, #8]
    #expect(trace([0xf90007e0, 0xfd4007e0, ret]).float == .unary(.floatFromBits(bits: 64), .argument(0)))
    // str d0, [sp, #8]; ldr d0, [sp, #8]: the same file, the same value
    #expect(trace([0xfd0007e0, 0xfd4007e0, ret]).float == .argument(0))
    // str d0, [sp, #8]; str x0, [sp, #8]; ldr x0, [sp, #8]: the last store's file
    #expect(trace([0xfd0007e0, 0xf90007e0, 0xf94007e0, ret]).value == .argument(0))
    // str d0, [sp, #16]; str q0, [sp, #16]; ldr x0, [sp, #16]: a store of no
    // known file leaves none behind
    #expect(trace([0xfd000be0, 0x3d8007e0, 0xf9400be0, ret]).value == .argument(0))
    // str d0, [sp, #8]; ldr s0, [sp, #8]: a Double's word is no Float
    #expect(trace([0xfd0007e0, 0xbd400be0, ret]).float == .unknown)
    // str x0, [sp, #8]; ldr s0, [sp, #8]: half of a general store
    #expect(trace([0xf90007e0, 0xbd400be0, ret]).float == .unknown)
    // stp x0, x0, [sp, #16]; ldr q0, [sp, #16]: a `q` load gathers its words
    #expect(trace([0xa90103e0, 0x3dc007e0, ret]).float != .unknown)
    // cbz x1, +12; str d0, [sp, #8]; b +8; str x0, [sp, #8]; ldr x0, [sp, #8]:
    // the same value by two files, so the paths disagree on what it is
    #expect(trace([0xb4000061, 0xfd0007e0, 0x14000002, 0xf90007e0, 0xf94007e0, ret]).value == .unknown)
    // str x0, [sp, #8]; add x8, sp, #8; bl; ldr d0, [sp, #8]: the callee's word
    // over the general store is no reinterpreted integer
    #expect(trace([0xf90007e0, 0x910023e8, 0x94000004, 0xfd4007e0, ret],
                  conventions: [0x1008: .indirect(sizeBytes: 8)]).float
        == .indirectCallResultWord(site: 0x1008, offset: 0))
}

/// A Double field read through a general register is that Double, not an
/// integer's bits. -Onone `area` copies `radius` with `ldr x8, [x20, #0x10];
/// str x8, [sp, #0x10]; ldr d1, [sp, #0x10]`, and the slot's register file
/// alone would read `Double(bitPattern: self.radius)`.
@Test func aFloatFieldThroughAGeneralRegisterIsThatFieldIfPresent() async throws {
    let path = "Fixtures/Sample/sample.debug"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "sample.Circle.area")
    }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("return ((static Swift.Double.pi.getter() * self.radius) * self.radius)"), "\(text)")
    let floats = "Fixtures/Sample/libFloatReinterpret.dylib"
    guard FileManager.default.fileExists(atPath: floats) else { return }
    let squared = try await withStableDependencies {
        try await Disassembler().disassemble(path: floats, functionFilter: "FloatReinterpret.Labelled.squared")
    }
    let body = squared.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(body.contains("return (self.scale * self.scale)"), "\(body)")
}
