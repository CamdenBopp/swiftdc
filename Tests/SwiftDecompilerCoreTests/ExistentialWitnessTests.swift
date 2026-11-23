import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let existentialFixtures = [
    "Fixtures/Sample/libExistentialWitness.dylib",
    "Fixtures/Sample/libExistentialWitness.Onone.dylib",
    "Fixtures/Sample/libExistentialWitness.resilient.dylib",
]

/// The oracle, from a second module so the existential functions keep their
/// existential parameters: area 9 (requirement 0), scale 12 (requirement 1),
/// a class-bound name 5, and 5 + 2 for `callNameThen`.
@Test func existentialWitnessCallsRunAsDocumentedIfPresent() throws {
    for (library, oracle) in [("", ""), (".Onone", ".Onone"), (".resilient", ".resilient")] {
        let path = "Fixtures/Sample/libExistentialWitnessOracle\(oracle).dylib"
        guard FileManager.default.fileExists(atPath: "Fixtures/Sample/libExistentialWitness\(library).dylib"),
              FileManager.default.fileExists(atPath: path) else { continue }
        let handle = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL), Comment(rawValue: String(cString: dlerror())))
        defer { dlclose(handle) }
        typealias Entry = @convention(c) () -> Int
        for (name, expected) in [("existential_witness_measure", 9), ("existential_witness_grow", 12),
                                 ("existential_witness_name", 5), ("existential_witness_name_then", 7),
                                 ("existential_witness_lookup", 15), ("existential_witness_copy_out", 16)] {
            let entry = try #require(dlsym(handle, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
    }
}

/// An opaque existential parameter is one register, the container's
/// address, and a requirement called through its table is named from the
/// protocol's descriptor: by method under library evolution, by index and
/// kind otherwise. A class-bound existential is two registers, the object
/// and its table, and is named the same way; Error's box is another layout.
@Test func aRequirementCallOnAnExistentialArgumentIsNamedIfPresent() async throws {
    for path in existentialFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func views(_ member: String) throws -> [String] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("ExistentialWitness.\(member)(") }, "\(member)")
            return [function.renderPseudo(), function.renderStructured()]
        }
        let resilient = path.hasSuffix(".resilient.dylib")
        let area = resilient ? "ExistentialWitness.Shape.area() witness for arg0()"
            : "ExistentialWitness.Shape requirement 0 (method) witness for arg0()"
        let scale = resilient ? "ExistentialWitness.Shape.scale(_:) witness for arg0(arg1)"
            : "ExistentialWitness.Shape requirement 1 (method) witness for arg0(arg1)"
        for text in try views("measure") { #expect(text.contains("return \(area)"), "\(path): \(text)") }
        for text in try views("grow") { #expect(text.contains("return \(scale)"), "\(path): \(text)") }
        // A table word called without the metadata and table a witness
        // takes (existential_unpassed.s) is no proven requirement call.
        for member in ["unpassed", "unpassedNamed", "unpassedTable", "retainedType"] {
            for text in try views(member) {
                #expect(text.contains("unresolved call"), "\(path) \(member): \(text)")
                #expect(!text.contains("witness for arg0"), "\(path) \(member): \(text)")
            }
        }
        // A class-bound existential is the object and its table: the call
        // passes swift_getObjectType(object) and the table, and `k` is x2.
        let name = resilient ? "ExistentialWitness.Named.name() witness for arg0("
            : "ExistentialWitness.Named requirement 0 (method) witness for arg0("
        for text in try views("callName") { #expect(text.contains("return \(name)"), "\(path): \(text)") }
        for text in try views("callNameThen") {
            #expect(text.contains(name) && text.contains(" + arg1)"), "\(path): \(text)")
        }
        // A method's: self in x20, the object and table in x0 and x1.
        for text in try views("Registry.lookup") {
            #expect(text.contains(name) && text.contains("self.base"), "\(path): \(text)")
        }
    }
}

/// Which existential layout a protocol takes is its descriptor's: Shape is
/// opaque (a container), Named class-bound (object and table). Each check
/// refuses the other's protocol.
@Test func anExistentialsLayoutIsReadFromItsProtocolDescriptorIfPresent() throws {
    let path = "Fixtures/Sample/libExistentialWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    var symbols: [UInt64: [String]] = [:]
    for name in ["Shape", "Named"] {
        let symbol = try #require(machO.symbols.first { $0.name == "_$s18ExistentialWitness\(name.count)\(name)Mp" })
        symbols[UInt64(symbol.offset)] = ["protocol descriptor for ExistentialWitness.\(name)"]
    }
    var resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
    resolver.protocolDescriptorSymbols = symbols
    #expect(resolver.opaqueExistentialDescriptor(named: "ExistentialWitness.Shape") != nil)
    #expect(resolver.classBoundExistentialDescriptor(named: "ExistentialWitness.Shape") == nil)
    #expect(resolver.classBoundExistentialDescriptor(named: "ExistentialWitness.Named") != nil)
    #expect(resolver.opaqueExistentialDescriptor(named: "ExistentialWitness.Named") == nil)
}

/// Copying an existential runs its dynamic type's value witness, read
/// through the container's metadata (word 3) and passed that metadata last.
/// No type is known in the outlined helper, so the witness is named for
/// where its metadata was read. A slot called without that metadata
/// (`existential_vw_unpassed`) is not named.
@Test func aValueWitnessOnAnExistentialsMetadataIsNamedIfPresent() async throws {
    for path in existentialFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let copy = try #require(functions.first { $0.displayName == "outlined init with copy of ExistentialWitness.Shape" },
                                "\(path)")
        for text in [copy.renderPseudo(), copy.renderStructured()] {
            #expect(text.contains("initializeBufferWithCopyOfBuffer value witness for the metadata at arg0 + 0x18("),
                    "\(path): \(text)")
        }
        let unpassed = try #require(functions.first { $0.symbol == "_existential_vw_unpassed" }, "\(path)")
        for text in [unpassed.renderPseudo(), unpassed.renderStructured()] {
            #expect(text.contains("unresolved call") && !text.contains("value witness"), "\(path): \(text)")
        }
    }
}
