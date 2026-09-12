import Testing
import Foundation

/// Content assertions for the `layout` and `xrefs` commands, which were only
/// exercised for determinism and not-crashing — never for what they render.
/// Both render in the CLI target (`LayoutCommand` / `XrefsCommand`), not the
/// core, so these drive the built binary the way `DeterminismTests` does. They
/// skip when the CLI or a fixture is absent (build with `swift build` and
/// `Fixtures/Sample/build.sh`).
struct LayoutXrefsContentTests {
    private static let binary = URL(fileURLWithPath: ".build/debug/swiftdc")

    private func run(_ arguments: [String]) throws -> String? {
        guard FileManager.default.fileExists(atPath: Self.binary.path) else { return nil }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func layoutRendersFieldOffsetsIfPresent() throws {
        let fixture = "Fixtures/Sample/libReconstruction.dylib"
        guard FileManager.default.fileExists(atPath: fixture) else { return }
        guard let output = try run(["layout", fixture]) else { return }
        guard !output.isEmpty else {
            Issue.record("layout produced no output"); return
        }
        // Per-type header carries the computed instance size, and each stored
        // property is placed at a byte offset with its size and mangled type.
        #expect(output.contains("IntPair"))
        #expect(output.contains("instance size 16 bytes"))
        #expect(output.contains("a: Si"))   // Swift.Int
        #expect(output.contains("b: Si"))
        #expect(output.contains("+0x8"))    // the second field's offset
    }

    @Test func xrefsResolvesConcreteCallEdgesIfPresent() throws {
        let fixture = "Fixtures/Sample/sample.release"
        guard FileManager.default.fileExists(atPath: fixture) else { return }
        guard let output = try run(["xrefs", "--function", "sum", fixture]) else { return }
        guard !output.isEmpty else {
            Issue.record("xrefs --function produced no output"); return
        }
        // Tree.sum recurses and is called by run(); both are direct calls the
        // graph must resolve (not the unresolved-dispatch bucket).
        #expect(output.contains("sample.Tree.sum() -> Swift.Int"))
        #expect(output.contains("callers ("))
        #expect(output.contains("callees ("))
        #expect(output.contains("sample.run() -> ()"), "a resolved cross-function caller edge should appear")
    }

    @Test func xrefsUnreferencedListsLeafFunctionsIfPresent() throws {
        let fixture = "Fixtures/Sample/libReconstruction.dylib"
        guard FileManager.default.fileExists(atPath: fixture) else { return }
        guard let output = try run(["xrefs", "--unreferenced", fixture]) else { return }
        guard !output.isEmpty else {
            Issue.record("xrefs --unreferenced produced no output"); return
        }
        // The pure leaf predicates have no in-image callers, so they are listed
        // with their address.
        #expect(output.contains("Reconstruction.isEqual"))
        #expect(output.contains("0xb80"))
    }
}
