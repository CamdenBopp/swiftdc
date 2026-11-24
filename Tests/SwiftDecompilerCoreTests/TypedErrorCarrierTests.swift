import Foundation
import SwiftLayout
import Testing
@testable import SwiftDecompilerCore

/// A typed error is in x0 only when it shares the registers of a direct
/// result. A result returned through memory moves the error to a buffer,
/// and x0 at the throw is undefined. The case was read from x0 unless one
/// exact layout (five `UInt64` fields) vetoed it, so a five-`Int` struct or
/// a generic result with another case's tag left in x0 rendered that case:
/// `throw ErrorCarrier.Fault.mid` for a function that throws `.high`.
/// errorcarrier.swift and errorcarrier.s state each function's true
/// behaviour.
private let carrierImages = [
    "Fixtures/Sample/libErrorCarrier.Onone.dylib",
    "Fixtures/Sample/libErrorCarrier.O.dylib",
    "Fixtures/Sample/libErrorCarrier.Osize.dylib",
]

private let fault = "ErrorCarrier.Fault"

/// The functions of one image whose name holds `prefix`, with the image's
/// own layout evidence: the function itself, and for an async function
/// its resume funclets, which are titled after it. Nil when the image is
/// not built.
private func carrierFunctions(
    _ prefix: String, in path: String
) async throws -> (functions: [DisassembledFunction], maps: [String: FieldMap], cases: EnumCaseIndex)? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let image = try BinaryLoader.load(path: path)
    let maps = try FieldMapBuilder.build(in: image)
    return (functions.filter { $0.displayName.contains(prefix) }, maps, EnumCaseIndex.build(in: image))
}

/// The throw statements of a render, trimmed. The header's `throws` is not
/// one: it follows the name.
private func throwStatements(_ text: String) -> [String] {
    text.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("throw ") }
}

private func provesCarrier(
    _ function: DisassembledFunction, _ maps: [String: FieldMap], _ cases: EnumCaseIndex
) -> Bool {
    Disassembler.provesDirectTypedErrorCarrier(
        function, fieldMaps: maps, enumCaseIndex: cases, classTypeIndex: ClassTypeIndex())
}

/// Both authored functions throw `.high` through the error buffer and
/// leave 1, the tag of `.mid`, in x0. The thrown case is not in a register,
/// so it is not named.
@Test(arguments: ["ErrorCarrier.wide(", "ErrorCarrier.opaque<"])
func aTypedErrorBesideAnIndirectResultIsNotNamedFromX0IfPresent(prefix: String) async throws {
    for path in carrierImages {
        guard let (functions, maps, cases) = try await carrierFunctions(prefix, in: path) else { continue }
        let comment = Comment(rawValue: "\(path) \(prefix)")
        try #require(functions.count == 1, comment)
        let function = functions[0]
        // The tag left in x0 is a real case of the thrown type, and the
        // five-`UInt64` veto does not cover either result.
        try #require(cases.caseName(ofEnum: fault, tag: 1) == "mid", comment)
        try #require(!Disassembler.hasIndirectFiveWordTypedThrowResult(function, fieldMaps: maps), comment)
        #expect(!provesCarrier(function, maps, cases), comment)

        let exits = function.instructions.compactMap { insn -> String? in
            if case .throw(let error)? = insn.exit { return error }
            return nil
        }
        #expect(exits == ["?"], comment)
        for view in [function.renderStructured(), function.renderPseudo()] {
            #expect(throwStatements(view) == ["throw ?"], Comment(rawValue: "\(path)\n\(view)"))
        }
    }
}

/// The controls: a scalar, two tuples and a four-word struct are returned in
/// registers, the error's tag is in x0 at the throw, and each still names
/// the case it throws.
@Test(arguments: ["ErrorCarrier.scalar(", "ErrorCarrier.pair(", "ErrorCarrier.labelled(", "ErrorCarrier.quad("])
func aTypedErrorBesideADirectResultKeepsItsCaseIfPresent(prefix: String) async throws {
    for path in carrierImages {
        guard let (functions, maps, cases) = try await carrierFunctions(prefix, in: path) else { continue }
        let comment = Comment(rawValue: "\(path) \(prefix)")
        try #require(functions.count == 1, comment)
        let function = functions[0]
        #expect(provesCarrier(function, maps, cases), comment)
        #expect(function.instructions.contains { $0.exit == .throw("\(fault).high") }, comment)
        for view in [function.renderStructured(), function.renderPseudo()] {
            let thrown = throwStatements(view)
            #expect(thrown.contains("throw \(fault).high"), Comment(rawValue: "\(path)\n\(view)"))
            // No other case: the tag is 2 and nothing else.
            #expect(!thrown.contains { $0.hasPrefix("throw \(fault).") && $0 != "throw \(fault).high" },
                    Comment(rawValue: "\(path)\n\(view)"))
        }
    }
}

/// The compiler's own indirect throw stores `.high` through the error
/// buffer and leaves x0 alone, and an async function hands its error to a
/// resume function from a funclet: neither carrier is proven, so no case
/// is named whatever x0 holds at the exit.
@Test(arguments: ["ErrorCarrier.quint(", "ErrorCarrier.later("])
func anUnprovenCarrierNamesNoCaseIfPresent(prefix: String) async throws {
    for path in carrierImages {
        guard let (functions, maps, cases) = try await carrierFunctions(prefix, in: path) else { continue }
        let comment = Comment(rawValue: "\(path) \(prefix)")
        try #require(!functions.isEmpty, comment)
        for function in functions {
            #expect(!provesCarrier(function, maps, cases), comment)
            for insn in function.instructions {
                if case .throw(let error)? = insn.exit { #expect(error == "?", comment) }
            }
            for view in [function.renderStructured(), function.renderPseudo()] {
                #expect(throwStatements(view).allSatisfy { $0 == "throw ?" }, Comment(rawValue: "\(path)\n\(view)"))
            }
        }
    }
}

/// The proof, one premise at a time, on names alone: no image is read.
@Test func aDirectTypedErrorCarrierNeedsEveryPremise() throws {
    let word = StaticTypeLayout(size: 8, stride: 8, alignmentMask: 7,
                                extraInhabitantCount: 0, isBitwiseTakable: true)
    func ints(_ type: String, _ names: [String]) -> FieldMap {
        let fields = names.enumerated().map { index, name in
            FieldLayoutEntry(fieldName: name, offset: index * 8, typeMangledName: "Si",
                             layout: word, resolution: .computed)
        }
        var map = FieldMap(typeName: type, layout: AggregateFieldLayout(
            fields: fields, size: names.count * 8, stride: names.count * 8, alignment: 8, extraInhabitantCount: 0))
        map.isStruct = true
        map.isGeneric = false
        return map.withFieldTypeNames(Dictionary(uniqueKeysWithValues: names.map { ($0, "Swift.Int") }))
    }
    let quad = ints("Quad", ["a", "b", "c", "d"])
    let imageMaps = ["ErrorCarrier.Quad": quad, "ErrorCarrier.Quint": ints("Quint", ["a", "b", "c", "d", "e"])]
    let imageCases = EnumCaseIndex(byQualifiedName: [fault: ["low", "mid", "high"], "ErrorCarrier.Lone": ["only"]])
    func proves(
        _ name: String, source: RecoverySource = .symbol,
        maps: [String: FieldMap]? = nil, cases: EnumCaseIndex? = nil
    ) -> Bool {
        let function = DisassembledFunction(symbol: "_carrier", demangledName: name, startAddress: 0x1000,
                                            instructions: [], source: source)
        return Disassembler.provesDirectTypedErrorCarrier(
            function, fieldMaps: maps ?? imageMaps, enumCaseIndex: cases ?? imageCases,
            classTypeIndex: ClassTypeIndex())
    }
    func thrower(_ result: String, effects: String = "throws(\(fault))") -> String {
        "ErrorCarrier.probe(Swift.Int) \(effects) -> \(result)"
    }

    // Direct results of each admitted kind.
    try #require(proves(thrower("Swift.Int")))
    for result in ["()", "Swift.Double", "Swift.String", "(Swift.Double, Swift.UInt64)",
                   "(Swift.Int, Swift.Int, Swift.Int, Swift.Int)", "(count: Swift.Int, scale: Swift.Double)",
                   "ErrorCarrier.Quad"] {
        #expect(proves(thrower(result)), Comment(rawValue: result))
    }
    #expect(proves("static ErrorCarrier.Box.make(Swift.Int) throws(\(fault)) -> Swift.Int"))
    #expect(proves("ErrorCarrier.pick<A>(A, Swift.Int) throws(\(fault)) -> Swift.Int"))

    // A result returned through memory, or not proven otherwise.
    for result in ["ErrorCarrier.Quint", "(Swift.Int, Swift.Int, Swift.Int, Swift.Int, Swift.Int)",
                   "(Swift.String, Swift.String, Swift.String)", "Foreign.Value",
                   "Swift.Optional<ErrorCarrier.Quint>"] {
        #expect(!proves(thrower(result)), Comment(rawValue: result))
    }
    var resilient = quad
    resilient.mayBeResilient = true
    #expect(!proves(thrower("ErrorCarrier.Quad"), maps: ["ErrorCarrier.Quad": resilient]))
    // A generic parameter is no type, even where a map answers to its letter.
    let generic = "ErrorCarrier.opaque<A>(A, Swift.Int) throws(\(fault)) -> A"
    try #require(SwiftLowering.directAggregateRegisters(of: "A", fieldMaps: ["A": quad]) != nil)
    #expect(!proves(generic, maps: ["A": quad]))

    // An async function's error goes to a resume function.
    #expect(!proves(thrower("Swift.Int", effects: "async throws(\(fault))")))

    // An error with no tag in a register, or with no proven layout.
    #expect(!proves(thrower("Swift.Int", effects: "throws")))
    #expect(!proves(thrower("Swift.Int", effects: "throws(ErrorCarrier.Lone)")))
    #expect(!proves(thrower("Swift.Int", effects: "throws(Foreign.Fault)")))
    #expect(!proves(thrower("Swift.Int"), cases: EnumCaseIndex(
        byQualifiedName: [fault: ["low", "mid", "high"]], resilientEnums: [fault])))

    // A name that is not the function's own symbol, or not a plain
    // declaration: its entry may not follow the signature it prints.
    #expect(!proves(thrower("Swift.Int"), source: .metadata))
    for prefix in ["function signature specialization <Arg[0] = Dead> of ", "generic specialization <Swift.Int> of ",
                   "merged ", "protocol witness for "] {
        #expect(!proves(prefix + thrower("Swift.Int")), Comment(rawValue: prefix))
    }
    #expect(!proves("closure #1 (Swift.Int) throws(\(fault)) -> Swift.Int in ErrorCarrier.host() -> ()"))
}
