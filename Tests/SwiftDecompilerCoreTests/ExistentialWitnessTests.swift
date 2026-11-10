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
                                 ("existential_witness_name", 5), ("existential_witness_name_then", 7)] {
            let entry = try #require(dlsym(handle, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
    }
}

/// An opaque existential parameter is one register, the container's
/// address, and a requirement called through its table is named from the
/// protocol's descriptor: by method under library evolution, by index and
/// kind otherwise. A class-bound existential (two registers) and Error's box
/// are another layout and stay as they were.
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
        for text in try views("unpassed") {
            #expect(text.contains("unresolved call"), "\(path) unpassed: \(text)")
            #expect(!text.contains("witness for arg0"), "\(path) unpassed: \(text)")
        }
        for member in ["callName", "callNameThen"] {
            for text in try views(member) {
                #expect(text.contains("unresolved call"), "\(path) \(member): \(text)")
                #expect(!text.contains("witness for arg0"), "\(path) \(member): \(text)")
                // `k` is x2, after the object and the table: nothing reads
                // x1 as it.
                #expect(!text.contains("arg1"), "\(path) \(member): \(text)")
            }
        }
    }
}
