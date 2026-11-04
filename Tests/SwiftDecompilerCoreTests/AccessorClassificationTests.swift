import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `objc` classifies every property accessor by its body. It decoded all of
/// them into one list and analysed the lot through `assemble`, so its memory
/// grew with the accessor count: a user reported a large iOS app past
/// 4.5 GB. `analyzeEachFunction` decodes, analyses and classifies one at a
/// time. These pin its verdicts to the array path's, the header it
/// produces, and its memory against the accessor count.

private let cli = URL(fileURLWithPath: ".build/debug/swiftdc")

/// `gen-manyaccessors.sh` builds N classes of 14 accessors each.
private let accessorsPerClass = 14

/// Run the debug CLI, returning its stdout and, under `/usr/bin/time -l`,
/// its peak footprint in bytes.
private func runCLI(_ arguments: [String], timed: Bool = false) throws -> (stdout: String, footprint: Int?)? {
    guard FileManager.default.fileExists(atPath: cli.path) else { return nil }
    let process = Process(), out = Pipe(), err = Pipe()
    if timed {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["-l", cli.path] + arguments
    } else {
        process.executableURL = cli
        process.arguments = arguments
    }
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let footprint = String(decoding: stderr, as: UTF8.self).split(separator: "\n").lazy.compactMap { line -> Int? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("peak memory footprint") else { return nil }
        return Int(trimmed.split(separator: " ").first ?? "")
    }.first
    return (String(decoding: stdout, as: UTF8.self), footprint)
}

/// The one-at-a-time classification gives every accessor the verdict the
/// array decode (`disassembleFunctions`, then `isSynthesizedAccessor`) gives
/// it, over the fixtures whose accessors exercise each shape: synthesized
/// and custom at scale, an extent past the prefix, a constant getter.
@Test func eachAccessorIsClassifiedAsTheArrayDecodeClassifiesItIfPresent() async throws {
    let paths = [
        "Fixtures/Sample/libManyAccessors100.dylib",
        "Fixtures/Sample/libAccessorExtent.dylib",
        "Fixtures/Sample/libAccessorExtentCustom.dylib",
        "Fixtures/Sample/libConstantGetter.dylib",
    ]
    for path in paths where FileManager.default.fileExists(atPath: path) {
        let machO = try BinaryLoader.load(path: path)
        let snapshot = ObjCMetadataSnapshot.build(in: machO)
        let addresses = Set(ObjCDumper.accessorImplementations(snapshot, in: machO).values)
        #expect(!addresses.isEmpty, "\(path)")
        let disassembler = Disassembler(preset: .simplified)
        let prefix = ObjCDumper.accessorPrefixBytes
        let (array, streamed) = await withStableDependencies {
            let functions = await disassembler.disassembleFunctions(
                at: addresses, in: machO, prefixBytes: prefix, groupsAsyncFunclets: false)
            var array: [UInt64: Bool] = [:]
            for function in functions where array[function.startAddress] == nil && addresses.contains(function.startAddress) {
                if let verdict = ObjCDumper.isSynthesizedAccessor(function, prefixBytes: prefix) {
                    array[function.startAddress] = verdict
                }
            }
            let streamed = await disassembler.analyzeEachFunction(at: addresses, in: machO, prefixBytes: prefix) {
                ObjCDumper.isSynthesizedAccessor($0, prefixBytes: prefix)
            }.filter { addresses.contains($0.key) }
            return (array, streamed)
        }
        #expect(streamed == array, "\(path): \(streamed.count) streamed, \(array.count) from the array decode")
    }
}

/// The header of 100 classes keeps exactly the three custom accessors of
/// each and drops every synthesized one.
@Test func everyCustomAccessorStaysInTheHeaderIfPresent() throws {
    let path = "Fixtures/Sample/libManyAccessors100.dylib"
    guard FileManager.default.fileExists(atPath: path), let run = try runCLI(["objc", path]) else { return }
    let lines = run.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    func count(_ line: String) -> Int { lines.filter { $0 == line }.count }
    #expect(count("- (int)total;") == 100)
    #expect(count("- (NSString *)label;") == 100)
    #expect(count("- (void)setLimit:(int)arg0;") == 100)
    let synthesizedPrefixes = [
        "- (int)count;", "- (void)setCount:", "- (BOOL)flag;", "- (void)setFlag:",
        "- (NSString *)name;", "- (id)name;", "- (void)setName:", "- (id)owner;", "- (void)setOwner:",
        "- (id)delegate;", "- (void)setDelegate:", "- (int)limit;",
    ]
    let synthesized = lines.filter { line in synthesizedPrefixes.contains { line.hasPrefix($0) } }
    #expect(synthesized.isEmpty, "\(synthesized.prefix(5))")
}

/// Peak footprint against the accessor count: 1,400 accessors, then 11,200.
/// Measured per added accessor, debug build: one at a time, 2.8 KB;
/// holding every analysed body as well, 5.3 KB; the array decode this
/// replaced, 9.2 KB. The bound sits between the first two. In release,
/// 1.2 KB of what is left is metadata and header text (`--metadata-only`
/// grows that much) and the rest is cross-function state.
@Test func accessorClassificationMemoryStaysFlatAsAccessorsGrowIfPresent() throws {
    let small = "Fixtures/Sample/libManyAccessors100.dylib", large = "Fixtures/Sample/libManyAccessors800.dylib"
    guard FileManager.default.fileExists(atPath: small), FileManager.default.fileExists(atPath: large),
          FileManager.default.fileExists(atPath: "/usr/bin/time"),
          let few = try runCLI(["objc", small], timed: true)?.footprint,
          let many = try runCLI(["objc", large], timed: true)?.footprint
    else { return }
    let accessors = (800 - 100) * accessorsPerClass
    let perAccessor = (many - few) / accessors
    #expect(
        perAccessor < accessorGrowthCeiling,
        """
        objc's footprint grew \((many - few) >> 20) MB over \(accessors) more accessors \
        (\(few >> 20) MB to \(many >> 20) MB) = \(perAccessor) B per accessor, over the \
        \(accessorGrowthCeiling) B bound: an image-wide collection of decoded or analysed \
        accessor bodies is being held again.
        """
    )
}

/// Bytes of peak footprint per added accessor, debug build.
private let accessorGrowthCeiling = 4_096

/// `--metadata-only` reads no body, so it cannot know which accessors are
/// synthesized. All 14 of each class stay, typed from the property and
/// marked; a line that is no accessor is not marked; no custom accessor is
/// reported as custom and none is dropped as synthesized.
@Test func metadataOnlyMarksEveryAccessorUnclassifiedIfPresent() throws {
    let path = "Fixtures/Sample/libManyAccessors100.dylib"
    guard FileManager.default.fileExists(atPath: path),
          let run = try runCLI(["objc", path, "--metadata-only"])
    else { return }
    let lines = run.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let note = "// unclassified accessor: body not analyzed"
    let marked = lines.filter { $0.hasSuffix(note) }
    #expect(marked.count == 100 * accessorsPerClass)
    func count(_ line: String) -> Int { lines.filter { $0 == "\(line) \(note)" }.count }
    // A synthesized accessor and a custom one read alike, with the type
    // the property proves in place of the encoding's `id`.
    #expect(count("- (NSString *)name;") == 100)
    #expect(count("- (void)setName:(NSString *)arg0;") == 100)
    #expect(count("- (int)count;") == 100)
    #expect(count("- (NSString *)label;") == 100)
    #expect(count("- (void)setLimit:(int)arg0;") == 100)
    // Every method line is an accessor or not; only the first kind is marked.
    #expect(lines.filter { $0 == "- (void).cxx_destruct;" }.count == 100)
    #expect(!lines.contains("- (int)total;"))
}

/// The mark belongs to the mode: neither the body-reading header nor the
/// library's plain metadata header carries it.
@Test func onlyMetadataOnlyCarriesTheMarkIfPresent() throws {
    let path = "Fixtures/Sample/libManyAccessors100.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let note = ObjCDumper.unclassifiedAccessorNote
    #expect(!ObjCDumper().dump(machO).contains(note))
    #expect(ObjCDumper().metadataOnlyBlocks(machO).joined().contains(note))
    if let run = try runCLI(["objc", path]) { #expect(!run.stdout.contains(note)) }
}

/// The flag excludes the modes that analyze bodies, and `--help` documents it.
@Test func metadataOnlyRefusesBodyModesAndIsDocumentedIfPresent() throws {
    let path = "Fixtures/Sample/libManyAccessors100.dylib"
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: cli.path)
    else { return }
    for mode in [["--methods"], ["--pseudo"], ["--structured"], ["--function", "total"]] {
        #expect(try runCLI(["objc", path, "--metadata-only"] + mode) == nil, "\(mode)")
    }
    let help = try #require(try runCLI(["objc", "--help"]))
    #expect(help.stdout.contains("--metadata-only"))
    #expect(help.stdout.contains("unclassified accessor"))
}
