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
    let (stdout, stderr) = Shell.drain(out, err)
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

/// One block, no call, a store through self or a load from it: what makes
/// an accessor synthesized is that the value moves unchanged.
@Test func aSynthesizedAccessorMovesItsValueUnchanged() throws {
    let engine = try #require(CapstoneEngine())
    func verdict(_ words: [UInt32], callee: Int? = nil, encoding: String? = nil,
                 arcIdentityContract: Bool = false) -> Bool? {
        var data = Data()
        for word in words + [0xd65f_03c0] { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
        let instructions = engine.disassemble(data, address: 0x1000).enumerated().map { index, decoded in
            let insn = Disassembler.instruction(decoded: decoded)
            guard index == callee else { return insn }
            var facts = insn.facts
            facts.arcIdentityContract = arcIdentityContract
            return Instruction(address: insn.address, text: insn.text, annotation: "→ objc_retain",
                               controlFlow: insn.controlFlow, branchTarget: insn.branchTarget,
                               detail: insn.detail, callee: .kept("objc_retain"), facts: facts)
        }
        let binding = encoding.map {
            ObjCMethodBinding(className: "C", selector: "s", typeEncoding: $0, isClassMethod: false, signature: "")
        }
        return ObjCDumper.isSynthesizedAccessor(DisassembledFunction(
            symbol: "accessor", demangledName: nil, startAddress: 0x1000, instructions: instructions, source: .address,
            objcMethod: binding))
    }
    let storeW2: UInt32 = 0xb900_0c02    // str w2, [x0, #12]
    let storeW8: UInt32 = 0xb900_0808    // str w8, [x0, #8]
    let loadW8: UInt32 = 0xb940_0808     // ldr w8, [x0, #8]
    // Unchanged: a store of the argument, of a copy, of a slot it went
    // through, a BOOL's mask, a narrow extension, a float, a register pair.
    #expect(verdict([storeW2]) == true)
    #expect(verdict([0xaa02_03e8, 0xf900_0408]) == true)            // mov x8, x2; str x8, [x0, #8]
    #expect(verdict([0xb900_0fe2, 0xb940_0fe8, storeW8]) == true)   // str w2, [sp, #12]; ldr w8, [sp, #12]
    #expect(verdict([0x1200_0048, 0x3900_2008]) == true)            // and w8, w2, #1; strb w8, [x0, #8]
    #expect(verdict([0x1300_1c48, storeW8]) == true)                // sxtb w8, w2
    #expect(verdict([0xfd00_0400]) == true)                         // str d0, [x0, #8]
    #expect(verdict([0xa900_8c02]) == true)                         // stp x2, x3, [x0, #8]
    #expect(verdict([0xfd40_0400]) == true)                         // ldr d0, [x0, #8]
    // A field offset read through the isa is address arithmetic.
    #expect(verdict([0xf940_0008, 0xf940_2908, 0xf868_6800]) == true) // ldr x8, [x0]; ldr x8, [x8, #80]; ldr x0, [x0, x8]
    // Computed: a compare and select, arithmetic on the argument, on the
    // ivar, a constant, an ivar stored back, one argument stored twice.
    #expect(verdict([0x5280_0148, 0x7100_285f, 0x1a88_b048, storeW8]) == false)
    #expect(verdict([0x1100_0448, storeW8]) == false)               // add w8, w2, #1
    #expect(verdict([loadW8, 0x1100_0500]) == false)                // add w0, w8, #1
    #expect(verdict([0x5280_0148, storeW8]) == false)               // mov w8, #10
    #expect(verdict([0xb900_081f]) == false)                        // str wzr, [x0, #8]
    #expect(verdict([loadW8, 0xb900_0c08]) == false)                // str w8, [x0, #12]
    #expect(verdict([storeW2, 0xb900_0802]) == false)               // str w2, [x0, #8] as well
    #expect(verdict([0xaa02_03e8, storeW2, 0xf900_0408]) == false)  // the same argument through a copy
    // Memory through the value, and a store that is not self's.
    #expect(verdict([0xf940_0408, 0xf940_0500]) == false)           // ldr x8, [x0, #8]; ldr x0, [x8, #8]
    #expect(verdict([0xb940_0840]) == false)                        // ldr w0, [x2, #8]
    #expect(verdict([storeW2, 0xf900_0422]) == false)               // str x2, [x1, #8]
    // A call ends an argument in x2, not one kept in x19.
    let call: UInt32 = 0x9400_0400
    #expect(verdict([0xaa00_03f3, call, 0xb900_0e62], callee: 1, arcIdentityContract: true) == false) // mov x19, x0; bl; str w2, [x19, #12]
    #expect(verdict([0xaa00_03f4, 0xaa02_03f3, call, 0xf900_0693], callee: 2, arcIdentityContract: true) == true)
    #expect(verdict([0xaa00_03f4, 0xaa02_03f3, call, 0xf900_0693], callee: 2) == false) // mov x20, x0; mov x19, x2; bl; str x19, [x20, #8]
    // A struct moves through x2 and x8 only when the method's type has one.
    let wide = "{Wide=qqqqq}16@0:8"
    let copyIn: [UInt32] = [0xad40_0440, 0xad02_8400]   // ldp q0, q1, [x2]; stp q0, q1, [x0, #80]
    let copyOut: [UInt32] = [0xad43_8400, 0xad00_0500]  // ldp q0, q1, [x0, #112]; stp q0, q1, [x8]
    #expect(verdict(copyIn, encoding: wide) == true)
    #expect(verdict(copyOut, encoding: wide) == true)
    #expect(verdict(copyIn) == false)
    #expect(verdict(copyOut) == false)
    // x8 once overwritten is no result buffer, and only an ivar goes to one.
    #expect(verdict([0xaa01_03e8] + copyOut, encoding: wide) == false) // mov x8, x1
    #expect(verdict([0xb940_0809, 0xf900_0102], encoding: wide) == false) // ldr w9, [x0, #8]; str x2, [x8]
}

/// `accessorshapes.m` at each level: nothing of `Plain` in the header, and
/// exactly the hand-written accessors of `Computed`.
@Test func aComputedAccessorStaysInTheHeaderIfPresent() throws {
    let expected = [
        "- (void)setClamped:(int)arg0;", "- (void)setBumped:(int)arg0;", "- (void)setFixedValue:(int)arg0;",
        "- (void)setTwice:(int)arg0;", "- (int)next;", "- (int)floorValue;", "- (long long)nodeValue;",
        "- (int)ignored;", "- (void)setPatched:(Wide)arg0;",
    ]
    for level in ["O0", "O1", "Os"] {
        let path = "Fixtures/Sample/libAccessorShapes.\(level).dylib"
        guard FileManager.default.fileExists(atPath: path), let run = try runCLI(["objc", path]) else { continue }
        let methods = run.stdout.split(separator: "\n").map(String.init).filter { $0.hasPrefix("- (") }
        // -O0 copies a wide struct with `bl memcpy`, no accessor helper, so
        // those accessors read as custom: a kept line, the safe way round.
        let memcpyCopies = level == "O0" ? ["- (Wide)wide5;", "- (void)setWide5:(Wide)arg0;", "- (Wide)patched;"] : []
        #expect(methods.filter { $0 != "- (void).cxx_destruct;" }.sorted() == (expected + memcpyCopies).sorted(), "\(level)")
    }
}

/// `objc_thunk_return.swift`: the `@objc` getter loads the ivar into x0 and
/// returns it through `objc_retainAutoreleaseReturnValue`, which hands back
/// its argument, so the getter is synthesized and its line is implied.
@Test func aGetterReturningThroughARetainIsSynthesizedIfPresent() throws {
    let path = "Fixtures/Sample/libObjCThunkReturn.dylib"
    guard FileManager.default.fileExists(atPath: path), let run = try runCLI(["objc", path]) else { return }
    let lines = run.stdout.split(separator: "\n").map(String.init)
    #expect(lines.contains { $0.contains("@property") && $0.contains(" label") }, "\(lines)")
    #expect(!lines.contains { $0.hasPrefix("- (NSString *)label") }, "\(lines)")
}

/// With no verdict the default header keeps the accessor and says why, one
/// note per cause; a synthesized control beside them still goes.
@Test func anAccessorWithNoVerdictIsMarkedWithItsCauseIfPresent() throws {
    let path = "Fixtures/Sample/libAccessorDeclined.dylib"
    guard FileManager.default.fileExists(atPath: path), let run = try runCLI(["objc", path]) else { return }
    let lines = run.stdout.split(separator: "\n").map(String.init)
    #expect(lines.contains("- (int)depth; // unclassified accessor: body runs past the 4 KB decode limit"), "\(lines)")
    #expect(lines.contains("- (int)width; // unclassified accessor: no body decoded"), "\(lines)")
    #expect(!lines.contains { $0.hasPrefix("- (int)count") || $0.hasPrefix("- (void)setCount:") }, "\(lines)")
}

/// `objcivartypes.m`: a bitfield's type is not in its encoding, so it
/// renders `?` with its width; a `c` ivar is a `char` and a `C` an
/// `unsigned char`, since arm64's BOOL encodes `B`. Only `_flag` is BOOL.
@Test func ivarsAreTypedFromTheirOwnEncodingIfPresent() throws {
    let path = "Fixtures/Sample/libObjCIvarTypes.dylib"
    guard FileManager.default.fileExists(atPath: path), let run = try runCLI(["objc", path]) else { return }
    let lines = run.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    for expected in ["? _bits : 1;", "? _sbits : 3;", "char _letter;", "unsigned char _byte;", "BOOL _flag;"] {
        #expect(lines.contains(expected), "\(expected) in \(lines)")
    }
    #expect(!lines.contains { $0.hasPrefix("int _bits") || $0 == "BOOL _letter" || $0 == "BOOL _byte" }, "\(lines)")
}
