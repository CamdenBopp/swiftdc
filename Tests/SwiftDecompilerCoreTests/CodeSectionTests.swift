import Testing
import Foundation
@testable import SwiftDecompilerCore

/// Functions outside `__TEXT,__text` (`codesections.c`): `rt_scale` in
/// `__TEXT,__realtime`, `cold_fail` in `__TEXT,__text_cold`, both called from
/// `drive` in `__text`. Every path decoded `__text` alone, so the two were
/// missing from every listing and `xrefs`, `disasm -f rt_scale` matched
/// nothing, and `drive`'s direct `bl` rendered as an unresolved indirect call.
/// Found by the corpus sweep: auvaltool, audiomxd and systemsoundserverd
/// (`__realtime`), DumpPanic, and gcc's plugins (`__text_cold`) listed fewer
/// functions than `LC_FUNCTION_STARTS`.
private let path = "Fixtures/Sample/libCodeSections.dylib"

/// `dyld_info -function_starts`, by name: the binary's own table, read by a
/// tool that is not swiftdc.
private func starts() -> [String: UInt64]? {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["dyld_info", "-function_starts", path]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    var result: [String: UInt64] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let fields = line.split(separator: " ")
        guard fields.count == 2, fields[0].hasPrefix("0x"), let address = UInt64(fields[0].dropFirst(2), radix: 16)
        else { continue }
        result[String(fields[1])] = address
    }
    return result.count >= 3 ? result : nil
}

@Test func functionsInOtherCodeSectionsAreDecodedOnEveryPathIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let table = try #require(starts(), "dyld_info should list drive, rt_scale and cold_fail")
    let drive = try #require(table["_drive"]), realtime = try #require(table["_rt_scale"])
    let cold = try #require(table["_cold_fail"])
    let machO = try BinaryLoader.load(path: path)
    let disassembler = Disassembler(preset: .default)

    let listing = try await withStableDependencies { try await disassembler.disassemble(path: path) }
    let inProcess = await withStableDependencies { await disassembler.disassemble(machO: machO) }
    for (name, functions) in [("objdump", listing), ("capstone", inProcess)] {
        #expect(Set(functions.map(\.startAddress)) == Set(table.values), "\(name): \(functions.map(\.startAddress))")
        let byStart = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
        // No function runs into the next section: drive ends at its tail branch.
        #expect(byStart[drive]?.instructions.allSatisfy { $0.address < realtime } == true, "\(name)")
        #expect(byStart[realtime]?.instructions.last?.text.hasPrefix("ret") == true, "\(name)")
        #expect(byStart[cold]?.instructions.last?.text.hasPrefix("ret") == true, "\(name)")
        let call = byStart[drive]?.instructions.first { $0.controlFlow == .call }
        #expect(call?.callee == "rt_scale", "\(name): \(String(describing: call?.annotation))")
    }

    let filtered = try await withStableDependencies {
        try await disassembler.disassemble(path: path, functionFilter: "rt_scale")
    }
    #expect(filtered.map(\.startAddress) == [realtime])

    let sites = await withStableDependencies {
        await disassembler.disassembleStreaming(machO: machO, transform: CallGraph.sites(of:))
    }
    let graph = CallGraph(functions: sites)
    #expect(graph.functionAddresses == Set(table.values))
    #expect(graph.callers(of: realtime).contains { $0.caller == drive })
    #expect(graph.callers(of: cold).contains { $0.caller == drive && $0.isTailCall })
}

/// The parts of a filtered or on-demand decode that read a callee's body,
/// and the fold check, each reach the other sections too.
@Test func otherCodeSectionsReachEveryDecodeHelperIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let table = try #require(starts())
    let realtime = try #require(table["_rt_scale"]), clobber = try #require(table["_rt_clobber"])
    let twin = try #require(table["_rt_twin_a"] ?? table["_rt_twin_b"])
    let machO = try BinaryLoader.load(path: path)
    let disassembler = Disassembler(preset: .default)

    // Decoded on demand (async funclets, filtered matches).
    let body = disassembler.decodeFunction(at: realtime, boundaries: table.values.sorted(), in: machO)
    #expect(body.count == 2 && body.last?.text.hasPrefix("ret") == true, "\(body.map(\.text))")

    // Decoded by address (Objective-C accessor classification).
    let byAddress = await withStableDependencies { await disassembler.disassembleFunctions(at: [realtime], in: machO) }
    #expect(byAddress.map(\.startAddress) == [realtime])

    // Two names on one address decline the heading, as in __text.
    let all = await withStableDependencies { await disassembler.disassemble(machO: machO) }
    let heading = all.first { $0.startAddress == twin }?.symbol
    #expect(heading?.hasPrefix("sub_") == true, "\(String(describing: heading))")

    // A filtered run decodes its callees' bodies for their facts, wherever
    // they are: `keep` calls `rt_clobber` in __realtime.
    let recorder = ProbeRecorder()
    _ = try await Probe.recording(recorder) {
        try await withStableDependencies { try await disassembler.disassemble(path: path, functionFilter: "keep") }
    }
    let analysed = Set(recorder.records.filter { $0.event == .analysisSnapshot }.compactMap { $0.function?.start })
    #expect(analysed.contains(clobber), "\(analysed.sorted())")
}
