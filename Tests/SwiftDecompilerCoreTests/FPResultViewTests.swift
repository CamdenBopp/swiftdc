import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fpResultPath = "Fixtures/Sample/libFPResults.dylib"
private let fpResultOps = ["neg", "abs", "sqrt", "add", "sub", "mul", "div", "nmul", "scvt", "ucvt", "convert", "fixSigned", "fixUnsigned", "nan"]
private func resultType(_ bits: Int) -> String { bits == 64 ? "Double" : bits == 32 ? "Float" : "Float16" }
private func resultCode(_ bits: Int) -> String { bits == 64 ? "Sd" : bits == 32 ? "Sf" : "s7Float16V" }
private func fpResultExpr(_ op: String, _ bits: Int) -> String {
    func literal(_ text: String) -> String { bits == 64 ? text : "\(resultType(bits))(\(text))" }
    switch op {
    case "neg": return "-" + literal("1.0")
    case "nan": return "-\(resultType(bits))(bitPattern: \(bits == 64 ? "0x7ff8000000000001" : bits == 32 ? "0x7fc00001" : "0x7e01"))"
    case "abs": return "abs(\(literal("-1.0")))"
    case "sqrt": return "sqrt(\(literal("4.0")))"
    case "add": return "(\(literal(bits == 16 ? "0.099975586" : "0.1")) + \(literal(bits == 16 ? "0.19995117" : "0.2")))"
    case "sub": return "(\(literal("2.5")) - \(literal("1.0")))"
    case "mul": return "(\(literal("2.0")) * \(literal("2.0")))"
    case "div": return "(\(literal("4.0")) / \(literal("2.0")))"
    case "nmul": return "-(\(literal("2.0")) * \(literal("2.0")))"
    case "convert": return "\(resultType(bits))(\(bits == 32 ? "0.1" : "Float(0.1)"))"
    case "fixSigned", "fixUnsigned": return "(\(resultType(bits))(5) / \(literal("2.0")))"
    default: return "\(resultType(bits))(5)"
    }
}
private func viewedResult(_ expression: String, written: Int, read: Int) -> String {
    guard written != read else { return expression }
    let receiver = expression.hasPrefix("-") ? "(\(expression))" : expression
    let raw = receiver + ".bitPattern"
    let pattern = read > written ? "UInt\(read)(\(raw))"
        : "UInt\(read)(truncatingIfNeeded: (\(raw) & \(read == 16 ? "0xffff" : "0xffffffff")))"
    return "\(resultType(read))(bitPattern: \(pattern))"
}
private func resultBits(_ op: String, _ bits: Int) -> UInt64 {
    let values: [String: [UInt64]] = [
        "neg": [0xbc00, 0xbf800000, 0xbff0000000000000],
        "abs": [0x3c00, 0x3f800000, 0x3ff0000000000000],
        "sqrt": [0x4000, 0x40000000, 0x4000000000000000],
        "add": [0x34cc, 0x3e99999a, 0x3fd3333333333334],
        "sub": [0x3e00, 0x3fc00000, 0x3ff8000000000000],
        "mul": [0x4400, 0x40800000, 0x4010000000000000],
        "div": [0x4000, 0x40000000, 0x4000000000000000],
        "nmul": [0xc400, 0xc0800000, 0xc010000000000000],
        "scvt": [0x4500, 0x40a00000, 0x4014000000000000],
        "ucvt": [0x4500, 0x40a00000, 0x4014000000000000],
        "convert": [0x2e66, 0x3dcccccd, 0x3fb99999a0000000],
        "fixSigned": [0x4100, 0x40200000, 0x4004000000000000],
        "fixUnsigned": [0x4100, 0x40200000, 0x4004000000000000],
        "nan": [0xfe01, 0xffc00001, 0xfff8000000000001],
    ]
    return values[op]![bits == 16 ? 0 : bits == 32 ? 1 : 2]
}

@Test func computedFPMetadataDoesNotConsumeCResultProofDepthIfPresent() async throws {
    let path = "Fixtures/Sample/libGridSampler.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: path, functionFilter: "Sampler.disk") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    // Six arithmetic operations carry six precision markers. Those markers
    // do not make the proof that each C call returns a whole scalar deeper.
    let expected = "fmod(((((((arg0.b * 3.141592653589793) / 180.0) + atan2(?, ?)) * 180.0) / 3.141592653589793) + 540.0), 360.0)"
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        let function = try #require(group.first { $0.displayName.contains("Sampler.disk(") })
        for text in [function.renderPseudo(), function.renderStructured()] {
            #expect(text.contains(expected), Comment(rawValue: text))
        }
    }
}

@Test func computedFPResultsKeepPrecisionAndPhysicalViewsInEveryPipelineIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpResultPath) else { return }
    let image = try BinaryLoader.load(path: fpResultPath)
    let listing = try await withStableDependencies { try await Disassembler().disassemble(path: fpResultPath) }
    let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
    let filtered = try await withStableDependencies { try await Disassembler().disassemble(path: fpResultPath, functionFilter: "FPResults") }
    let streamed = await withStableDependencies { await Disassembler().disassembleStreaming(machO: image, transform: { $0 }) }
    let each = await withStableDependencies {
        await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
    }
    var expected: [String: String] = [:]
    for width in [16, 32, 64] {
        for op in fpResultOps where width != 16 || !op.hasPrefix("fix") {
            for read in [16, 32, 64] { expected["\(op)\(width)to\(read)"] = viewedResult(fpResultExpr(op, width), written: width, read: read) }
        }
    }
    for width in [16, 32] {
        for op in ["neg", "abs", "sqrt", "scvt", "ucvt", "convert"] { expected["dirty\(op)\(width)"] = "?" }
        expected["sameDirty\(width)"] = fpResultExpr("neg", width)
        for op in ["add", "sub", "mul", "div", "nmul"] {
            expected["cleanSource\(op)\(width)"] = viewedResult(fpResultExpr(op, width), written: width, read: 64)
            expected["dirtySource\(op)\(width)"] = "?"
        }
        for name in ["reload", "copy", "gprRoundClears"] { expected["\(name)\(width)"] = viewedResult(fpResultExpr("neg", width), written: width, read: 64) }
        expected["rawScalarCopy\(width)"] = String(Double(bitPattern: width == 16 ? 0x3c00 : 0x3f800000))
    }
    expected["pairFP32"] = viewedResult(fpResultExpr("neg", 32), written: 32, read: 64)
    expected["pairGP32"] = "((-Float(1.0)).bitPattern & 0xffffffff)"
    expected["pairGP64"] = "(-1.0).bitPattern"
    expected["halfGPReload"] = "((-Float16(1.0)).bitPattern & 0xffffffff)"
    for width in [16, 32, 64] {
        let expression = fpResultExpr("neg", width)
        expected["computedMemcpy\(width)"] = "(\(expression)).bitPattern"
    }
    expected["shortComputedCopy64"] = "((0.1 + 0.2).bitPattern & 0xffff)"
    expected["byteComputedCopy64"] = "((0.1 + 0.2).bitPattern & 255)"
    expected["byteGPReload16"] = "((Float16(0.099975586) + Float16(0.19995117)).bitPattern & 255)"
    expected["copiedFPRoundTrip16"] = viewedResult(fpResultExpr("neg", 16), written: 16, read: 64)
    for read in [16, 32, 64] { expected["wholeCopy64to\(read)"] = viewedResult(fpResultExpr("add", 64), written: 64, read: read) }
    expected["call16"] = "FPResults.sink16(\(fpResultExpr("neg", 16)))"
    expected["call64"] = "FPResults.sink64(\(viewedResult(fpResultExpr("neg", 16), written: 16, read: 64)))"
    expected["sink16"] = "arg0.bitPattern"
    expected["sink64"] = "arg0.bitPattern"
    for name in ["nepAvailable", "nepOne", "nepZero", "exchangeFPCR", "exchangeFPSR"] { expected[name] = "?" }
    let negative = viewedResult(fpResultExpr("neg", 16), written: 16, read: 64)
    let positive = viewedResult("abs(Float16(1.0))", written: 16, read: 64)
    expected["join16to64"] = "((arg0 != 0) ? \(positive) : \(negative))"
    expected["rawQSpill64"] = "arg0"
    for width in [16, 32] {
        expected["pool\(width)"] = viewedResult(fpResultExpr("neg", width), written: width, read: 64)
        expected["gpWideRead\(width)"] = "(\(fpResultExpr("neg", width))).bitPattern"
        for name in ["chain", "wholeChain"] {
            expected["\(name)\(width)"] = viewedResult("abs(\(fpResultExpr("neg", width)))", written: width, read: 64)
        }
        expected["narrowCopy64via\(width)"] = "Double(bitPattern: ((0.1 + 0.2).bitPattern & \(width == 16 ? "0xffff" : "0xffffffff")))"
    }
    for width in [16, 32, 64] {
        let literal = width == 64 ? "1.0" : "\(resultType(width))(1.0)"
        var expression = literal
        for _ in 0..<6 { expression = "(\(expression) + \(literal))" }
        expected["deep\(width)"] = expression
    }
    expected["frameBitsToWide16"] = viewedResult("-Float16(bitPattern: UInt16(truncatingIfNeeded: (arg0 & 0xffff)))", written: 16, read: 64)
    expected["joinAgain16to64"] = viewedResult("-((arg0 != 0) ? abs(Float16(1.0)) : -Float16(1.0))", written: 16, read: 64)
    #expect(expected.count == 202)
    for group in [listing, array, filtered, streamed, Array(each.values)] {
        for (name, expression) in expected.sorted(by: { $0.key < $1.key }) {
            let function = try #require(group.first { $0.displayName.hasPrefix("FPResults.\(name)(") })
            for text in [function.renderPseudo(), function.renderStructured()] {
                let returns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("return ") }
                #expect(returns == ["return " + expression], Comment(rawValue: text))
            }
        }
    }
}

#if arch(arm64)
@Test func computedFPResultsNativeOracleChecksArithmeticRawViewsAndMergingControlsIfPresent() throws {
    guard FileManager.default.fileExists(atPath: fpResultPath) else { return }
    let handle = try #require(dlopen(fpResultPath, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(handle) }
    func pointer(_ name: String, _ result: String, argument: String? = nil) throws -> UnsafeMutableRawPointer {
        let input = argument == result ? "AD" : argument ?? "y"
        let symbol = "$s9FPResults\(name.count)\(name)\(argument == nil ? "" : "y")\(result)\(input)F"
        return try #require(dlsym(handle, symbol), Comment(rawValue: symbol))
    }
    let exchangeFPCR = unsafeBitCast(try pointer("exchangeFPCR", "s6UInt64V", argument: "s6UInt64V"), to: (@convention(thin) (UInt64) -> UInt64).self)
    let exchangeFPSR = unsafeBitCast(try pointer("exchangeFPSR", "s6UInt64V", argument: "s6UInt64V"), to: (@convention(thin) (UInt64) -> UInt64).self)
    let fpcr = exchangeFPCR(0), fpsr = exchangeFPSR(0)
    defer { _ = exchangeFPSR(fpsr); _ = exchangeFPCR(fpcr) }
    var observations = 0
    func check(_ actual: UInt64, _ expected: UInt64, _ name: String) {
        #expect(actual == expected, Comment(rawValue: name + ": " + String(actual, radix: 16)))
        observations += 1
    }
    func floating(_ name: String, _ bits: Int) throws -> UInt64 {
        let p = try pointer(name, resultCode(bits))
        switch bits {
        case 64: return unsafeBitCast(p, to: (@convention(thin) () -> Double).self)().bitPattern
        case 32: return UInt64(unsafeBitCast(p, to: (@convention(thin) () -> Float).self)().bitPattern)
        default: return UInt64(unsafeBitCast(p, to: (@convention(thin) () -> Float16).self)().bitPattern)
        }
    }
    func integer(_ name: String, _ bits: Int = 64) throws -> UInt64 {
        let p = try pointer(name, "s6UInt\(bits)V")
        return bits == 64 ? unsafeBitCast(p, to: (@convention(thin) () -> UInt64).self)()
            : UInt64(unsafeBitCast(p, to: (@convention(thin) () -> UInt32).self)())
    }
    for width in [16, 32, 64] {
        for op in fpResultOps where width != 16 || !op.hasPrefix("fix") {
            for read in [16, 32, 64] {
                let name = "\(op)\(width)to\(read)"
                let mask: UInt64 = read == 64 ? .max : (UInt64(1) << read) - 1
                check(try floating(name, read), resultBits(op, width) & mask, name)
            }
        }
    }
    for width in [16, 32] {
        for op in ["neg", "abs", "sqrt", "scvt", "ucvt", "convert"] {
            check(try floating("dirty\(op)\(width)", 64), resultBits(op, width), "dirty\(op)\(width)")
        }
        check(try floating("sameDirty\(width)", width), resultBits("neg", width), "sameDirty\(width)")
        for op in ["add", "sub", "mul", "div", "nmul"] {
            check(try floating("cleanSource\(op)\(width)", 64), resultBits(op, width), "cleanSource\(op)\(width)")
            let dirty: [String: UInt64] = ["add": width == 16 ? 0x3ccd : 0x3f99999a, "sub": 0, "mul": width == 16 ? 0x4000 : 0x40000000,
                                         "div": width == 16 ? 0x3800 : 0x3f000000, "nmul": width == 16 ? 0xc000 : 0xc0000000]
            check(try floating("dirtySource\(op)\(width)", 64), dirty[op]!, "dirtySource\(op)\(width)")
        }
        for name in ["reload", "copy", "gprRoundClears"] { check(try floating("\(name)\(width)", 64), resultBits("neg", width), "\(name)\(width)") }
        check(try floating("rawScalarCopy\(width)", 64), width == 16 ? 0x3c00 : 0x3f800000, "rawScalarCopy\(width)")
    }
    check(try floating("pairFP32", 64), 0xbf800000, "pairFP32")
    check(try integer("pairGP32", 32), 0xbf800000, "pairGP32")
    check(try integer("pairGP64"), 0xbff0000000000000, "pairGP64")
    check(try integer("halfGPReload", 32), 0xbc00, "halfGPReload")
    for width in [16, 32, 64] {
        check(try integer("computedMemcpy\(width)"), resultBits("neg", width), "computedMemcpy\(width)")
    }
    check(try integer("shortComputedCopy64"), 0x3334, "shortComputedCopy64")
    check(try integer("byteComputedCopy64"), 0x34, "byteComputedCopy64")
    check(try integer("byteGPReload16"), 0xcc, "byteGPReload16")
    check(try floating("copiedFPRoundTrip16", 64), 0xbc00, "copiedFPRoundTrip16")
    for read in [16, 32, 64] {
        let mask: UInt64 = read == 64 ? .max : (UInt64(1) << read) - 1
        check(try floating("wholeCopy64to\(read)", read), 0x3fd3333333333334 & mask, "wholeCopy64to\(read)")
    }
    for read in [16, 64] {
        check(try integer("call\(read)"), 0xbc00, "call\(read)")
    }
    let join = unsafeBitCast(try pointer("join16to64", "Sd", argument: "s6UInt64V"), to: (@convention(thin) (UInt64) -> Double).self)
    for value: UInt64 in [0, 1, .max] { check(join(value).bitPattern, value == 0 ? 0xbc00 : 0x3c00, "join16to64") }
    let available = try integer("nepAvailable")
    #expect(available == 0 || available == 4)
    check(try integer("nepZero"), 0xbc00, "nepZero")
    check(try integer("nepOne"), available == 4 ? 0xabcdbc00 : 0xbc00, "nepOne")
    let rawQ = unsafeBitCast(try pointer("rawQSpill64", "s6UInt64V", argument: "s6UInt64V"), to: (@convention(thin) (UInt64) -> UInt64).self)
    for raw: UInt64 in [0, 1, .max, 0x3ff0000000000000, 0x7ff8000000000001, 0x7ff0000000000001, 0x8000000000000000, 0x12340000abcd7e01] {
        check(rawQ(raw), raw, "rawQSpill64")
    }
    for width in [16, 32] {
        check(try floating("pool\(width)", 64), resultBits("neg", width), "pool\(width)")
        check(try integer("gpWideRead\(width)"), resultBits("neg", width), "gpWideRead\(width)")
        for name in ["chain", "wholeChain"] { check(try floating("\(name)\(width)", 64), resultBits("abs", width), "\(name)\(width)") }
        check(try floating("narrowCopy64via\(width)", 64), width == 16 ? 0x3334 : 0x33333334, "narrowCopy64via\(width)")
    }
    for width in [16, 32, 64] {
        check(try floating("deep\(width)", width), width == 16 ? 0x4700 : width == 32 ? 0x40e00000 : 0x401c000000000000, "deep\(width)")
    }
    let frame = unsafeBitCast(try pointer("frameBitsToWide16", "Sd", argument: "s6UInt64V"), to: (@convention(thin) (UInt64) -> Double).self)
    for raw: UInt64 in [0, 0x3c00, 0x7e01, .max, 0x12340000abcd7c01] { check(frame(raw).bitPattern, (raw & 0xffff) ^ 0x8000, "frameBitsToWide16") }
    let joinAgain = unsafeBitCast(try pointer("joinAgain16to64", "Sd", argument: "s6UInt64V"), to: (@convention(thin) (UInt64) -> Double).self)
    for value: UInt64 in [0, 1, .max] { check(joinAgain(value).bitPattern, value == 0 ? 0x3c00 : 0xbc00, "joinAgain16to64") }
    #expect(observations == 212)
}
#endif

@Test func computedFPResultMetadataPreservesPrecisionAndRejectsUnprovenBits() {
    func result(_ bits: Int, _ zero: Bool) -> AbstractValue {
        .unary(.floatResult(bits: bits, upperZero: zero), .unary(.negate, .unary(.floatConstant(bits: bits), .immediate(0))))
    }
    for width in [16, 32, 64] {
        for zero in [false, true] {
            let value = result(width, zero)
            #expect(TypeInference.typeOf(value, arguments: [:]) == .floating(width))
            #expect(ValueTracer.scalarView(value, bits: 64, interpretResult: false) == value)
            for read in [16, 32, 64] {
                let expected: AbstractValue
                if read == width { expected = value }
                else if read > width && !zero { expected = .unknown }
                else {
                    let raw = AbstractValue.unary(.bitPattern(bits: width), value)
                    let projected: AbstractValue = read < width
                        ? .binary(.bitAnd, raw, .immediate((UInt64(1) << read) - 1)) : raw
                    expected = .unary(.floatFromBits(bits: read), projected)
                }
                #expect(ValueTracer.floatOperand(value, bits: read) == expected)
                #expect(ValueTracer.scalarView(value, bits: read) == expected)
            }
            let raw: AbstractValue = width == 64 || zero ? .unary(.bitPattern(bits: width), value) : .unknown
            #expect(ValueTracer.scalarView(value, bits: 128) == .aggregate([raw, .unknown]))
            #expect(ValueTracer.floatOperand(.unary(.bitPattern(bits: width), value), bits: width) == value)
        }
    }
    // A raw constructor already describes physical bits. Project its width
    // before interpreting a different register view, even without arithmetic.
    for width in [16, 32, 64] {
        for read in [16, 32, 64] where read != width {
            let integer = AbstractValue.argument(2)
            let mask = (UInt64(1) << min(width, read)) - 1
            let raw = AbstractValue.binary(.bitAnd, integer, .immediate(mask))
            #expect(ValueTracer.floatOperand(.unary(.floatFromBits(bits: width), integer), bits: read)
                == .unary(.floatFromBits(bits: read), raw))
            let pattern = AbstractValue.unary(.bitPattern(bits: width), result(width, true))
            let projected: AbstractValue = read < width
                ? .binary(.bitAnd, pattern, .immediate(mask)) : pattern
            #expect(ValueTracer.floatOperand(pattern, bits: read) == .unary(.floatFromBits(bits: read), projected))
        }
    }
    for invalid in [-1, 0, 8, 128, Int.max] {
        for read in [16, 32, 64, 128] { #expect(ValueTracer.scalarView(result(invalid, true), bits: read) == .unknown) }
    }
    let condition = AbstractValue.binary(.equal, .argument(0), .immediate(0))
    let selected = AbstractValue.select(condition: condition, whenTrue: result(16, true), whenFalse: result(16, false))
    #expect(ValueTracer.scalarView(selected, bits: 64) == .unknown)
    let literal = AbstractValue.unary(.floatConstant(bits: 16), .immediate(0x3c00))
    var deep = literal
    for _ in 0..<5 { deep = .unary(.floatResult(bits: 16, upperZero: true), .binary(.add, deep, literal)) }
    #expect(ValueTracer.floatOperand(deep, bits: 64) != .unknown)
    deep = .unary(.floatResult(bits: 16, upperZero: true), .binary(.add, deep, literal))
    #expect(ValueTracer.floatOperand(deep, bits: 64) == .unknown)
    // Current dev preserves scalars across a call in a one-lane wrapper.
    // It must compose with written precision and raw whole-register reads.
    let scalar = result(32, true)
    let preserved = ValueTracer.callPreservedVectorValue(scalar)
    #expect(preserved == .aggregate([scalar]))
    #expect(ValueTracer.scalarView(preserved, bits: 32) == scalar)
    #expect(ValueTracer.scalarView(preserved, bits: 64, interpretResult: false) == scalar)
    let raw = AbstractValue.unary(.bitPattern(bits: 32), scalar)
    let whole = ValueTracer.scalarView(preserved, bits: 128)
    #expect(whole == .aggregate([raw]))
    #expect(ValueTracer.scalarView(whole, bits: 16) == ValueTracer.floatOperand(raw, bits: 16))
    #expect(ValueTracer.scalarView(ValueTracer.callPreservedVectorValue(result(32, false)), bits: 64) == .unknown)
    let snapshot = ProbeValue.abstractValue(.unary(.floatResult(bits: 16, upperZero: false), .argument(3)))
    #expect(snapshot == .object(["schema": .label("swiftdc-value/1"), "expression": .object([
        "kind": .label("unary"), "operator": .label("float-result"), "bits": .int(16), "upperZero": .bool(false),
        "operand": .object(["kind": .label("argument"), "index": .int(3)]),
    ])]))
}

@Test func computedFPResultSnapshotsRetainTheirStoredPrecisionIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: fpResultPath) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: fpResultPath, functionFilter: "FPResults") }
    for (name, width, zero) in [("neg16to64", 16, true), ("dirtyneg16", 16, false), ("sameDirty32", 32, false),
                                ("cleanSourceadd16", 16, true), ("dirtySourceadd16", 16, false),
                                ("copy16", 16, true), ("reload32", 32, true), ("pairFP32", 32, true)] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("FPResults.\(name)(") })
        let analysis = ValueTracer().analyze(function, entry: nil)
        let value = try #require(analysis.exitFloatValues[function.instructions.last!.address])
        guard case .unary(.floatResult(let bits, let upper), _) = value else { Issue.record("Missing result precision: \(name)"); continue }
        #expect(bits == width && upper == zero, Comment(rawValue: name))
    }
    for (name, zero) in [("call16", false), ("call64", true)] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("FPResults.\(name)(") })
        let analysis = ValueTracer().analyze(function, entry: nil)
        let call = try #require(analysis.callSites.values.first)
        guard case .unary(.floatResult(let width, let upper), _) = call.floatArguments[0] else { Issue.record("Snapshot projected the ABI too early"); continue }
        #expect(width == 16 && upper == zero)
    }
    let copy = try #require(functions.first { $0.displayName.hasPrefix("FPResults.copy32(") })
    let move = try #require(copy.instructions.last { $0.detail?.operands.count == 2 && $0.detail?.operands.allSatisfy { $0.operand.register?.kind == .vector } == true })
    let once = Array(copy.instructions.dropLast())
    let repeated = once + Array(repeating: move, count: 128)
    #expect(ValueTracer().finalState(of: once)["v0"] == ValueTracer().finalState(of: repeated)["v0"])
    let join = try #require(functions.first { $0.displayName.hasPrefix("FPResults.join16to64(") })
    let joined = ValueTracer().analyze(join, entry: .swiftFunction(scalarArguments: ["x0": 0]))
    let paths = try #require(joined.exitFloatValuesByPredecessor[join.instructions.last!.address])
    #expect(paths.count == 2)
    for value in paths.values {
        guard case .unary(.floatResult(let width, let zero), _) = value else { Issue.record("Predecessor precision was projected away"); continue }
        #expect(width == 16 && zero)
    }
}

@Test func computedFPResultStoresCannotEraseTheirRegisterPrecision() throws {
    let engine = try #require(CapstoneEngine())
    func trace(_ words: [UInt32]) -> AbstractValue? {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                        controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "f", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let analysis = ValueTracer().analyze(function, entry: .swiftInstance(scalarArguments: ["v0": 0]))
        return analysis.exitFloatValues[body.last!.address]
    }
    // fmov h0,h0; fneg h0,h0; str h0,[x20,#16]; ret
    let stored = try #require(trace([0x1ee04000, 0x1ee14000, 0x7d002280, 0xd65f03c0]))
    guard case .unary(.floatResult(let width, let zero), .unary(.negate, _)) = stored else {
        Issue.record("A field alias erased the FP result: \(stored)")
        return
    }
    #expect(width == 16 && zero)
    // A second field write cannot erase a copied FP argument's independent value.
    // fmov h0,h0; str h0,[x20,#16]; fmov h1,#2; str h1,[x20,#16]; ret
    #expect(trace([0x1ee04000, 0x7d002280, 0x1ee01001, 0x7d002281, 0xd65f03c0])
        == .unary(.floatResult(bits: 16, upperZero: true), .argument(0)))
    // Preserve x8, make a dirty half result, store it through the indirect
    // result pointer, then reload H0. The load proves its upper word is zero.
    let reloaded = try #require(trace([0xaa0803ea, 0xd2878008, 0xf2b579a8, 0x9e670100,
                                      0x1eee1001, 0x1ee14020, 0xaa0a03e8, 0x7d000100, 0x7d400100, 0xd65f03c0]))
    guard case .unary(.floatResult(let reloadedWidth, let reloadedZero), _) = reloaded else {
        Issue.record("Result-buffer reload lost its precision")
        return
    }
    #expect(reloadedWidth == 16 && reloadedZero)
    // Packed SIMD words can be read at a smaller FP width; their high
    // bits must be discarded before interpreting the scalar. A wider read
    // than the store established remains unknown.
    func rawRead(_ words: [UInt32]) -> (gpr: AbstractValue?, fp: AbstractValue?) {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        let function = DisassembledFunction(symbol: "raw", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let result = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        return (result.exitValues[body.last!.address], result.exitFloatValues[body.last!.address])
    }
    // sub sp,#16; dup v0.2d,x0; str q0,[sp]; ldr s0,[sp]; fmov w0,s0; add sp,#16; ret
    let word = rawRead([0xd10043ff, 0x4e080c00, 0x3d8003e0, 0xbd4003e0, 0x1e260000, 0x910043ff, 0xd65f03c0])
    let low32 = AbstractValue.binary(.bitAnd, .argument(0), .immediate(0xffffffff))
    #expect(word.gpr == low32)
    #expect(word.fp == .unary(.floatFromBits(bits: 32), .argument(0)))
    #expect(word.fp.map { ValueTracer.scalarView($0, bits: 64) } == .unary(.floatFromBits(bits: 64), low32))
    // A literal's constructor folds to its bits, so load-time truncation must
    // clear the high word before a later D-register read can observe it.
    let literal = rawRead([0xd2800000, 0xf2a7f000, 0xf2cacf00, 0xf2e24680,
        0xd10043ff, 0x4e080c00, 0x3d8003e0, 0xbd4003e0, 0x9e660000, 0x910043ff, 0xd65f03c0])
    #expect(literal.gpr == .immediate(0x3f800000))
    #expect(literal.fp == .immediate(0x3f800000))
    // sub sp,#16; str w0,[sp]; ldr d0,[sp]; fmov x0,d0; add sp,#16; ret
    let overread = rawRead([0xd10043ff, 0xb90003e0, 0xfd4003e0, 0x9e660000, 0x910043ff, 0xd65f03c0])
    #expect(overread.gpr == nil && overread.fp == nil)
    // A byte copy directly into the caller's result buffer has no later
    // register load to supply the raw-bit interpretation or truncate it.
    let scalar = AbstractValue.unary(.floatResult(bits: 64, upperZero: true),
        .unary(.negate, .unary(.floatConstant(bits: 64), .immediate(0x3ff0000000000000))))
    let raw = AbstractValue.unary(.bitPattern(bits: 64), scalar)
    for count in [1, 2, 8] {
        // sub sp,#16; fmov d0,#1; fneg d0,d0; str d0,[sp];
        // mov x0,x8; mov x1,sp; mov x2,#count; bl memcpy; add sp,#16; ret
        let words: [UInt32] = [0xd10043ff, 0x1e6e1000, 0x1e614000, 0xfd0003e0,
            0xaa0803e0, 0x910003e1, 0xd2800002 | UInt32(count << 5), 0x94000800, 0x910043ff, 0xd65f03c0]
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let body = engine.disassemble(Data(bytes), address: 0x1000).map {
            Instruction(address: $0.address, text: $0.text, annotation: nil,
                controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept($0.controlFlow == .call ? "memcpy" : nil))
        }
        let function = DisassembledFunction(symbol: "copy", demangledName: nil, startAddress: 0x1000,
                                            instructions: body, source: .symbol)
        let result = ValueTracer().analyze(function, entry: nil)
        let exit = try #require(result.exitIndirectResults[body.last!.address])
        let expected: AbstractValue = count == 8 ? raw
            : .binary(.bitAnd, raw, .immediate((UInt64(1) << (count * 8)) - 1))
        #expect(!exit.poisoned)
        #expect(exit.stores == [0: IndirectResultExit.Store(bytes: count, value: expected)])
    }
}
