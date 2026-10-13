import ArgumentParser
import Darwin
import Foundation
import SwiftDecompilerCore

struct ScoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "score", abstract: "Score recovered integer returns against an independent oracle.")
    @Argument(help: "Mach-O binary, or a completed JSONL trace with --trace.") var path: String
    @Option(help: "swiftdc-oracle/1 manifest. Exit addresses, argument arrays and 64-bit width are optional for single-exit defaults.") var oracle: String?
    @Flag(help: "Read an existing probe trace instead of analyzing a binary.") var trace = false
    @Flag(help: "Execute the authored 1,174 no-argument UInt64 width-flag fixtures and score raw x0 facts in one run.") var widthFlags = false
    @Flag(help: "Score raw x0 register facts instead of recovered Swift return claims.") var rawRegister = false
    @Flag(help: "Permit incomplete evaluation. Refuted claims always fail.") var allowIncomplete = false
    @Option(name: [.short, .long], help: "Write the JSON report to a file.") var output: String?
    func validate() throws {
        guard widthFlags != (oracle != nil), !widthFlags || !trace else {
            throw ValidationError("supply --oracle, or --width-flags with its authored fixture binary")
        }
    }
    func run() async throws {
        do { try await score() }
        catch let code as ExitCode { throw code }
        catch {
            let message = (error as? ProbeScoreError)?.description
                ?? (error as? ValidationError)?.description ?? error.localizedDescription
            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
            throw ExitCode(2)
        }
    }
    private func score() async throws {
        let manifest: ReturnOracle
        if widthFlags { manifest = try nativeWidthOracle(path: path) }
        else { manifest = try JSONDecoder().decode(ReturnOracle.self, from: Data(contentsOf: URL(fileURLWithPath: oracle!))) }
        let score = try ProbeScore(oracle: manifest, mode: rawRegister || widthFlags ? .rawRegister : .recoveredReturn)
        if trace { try score.readTrace(at: URL(fileURLWithPath: path)) }
        else {
            let machO = try BinaryLoader.loadMachO(path: path)
            await Probe.recording(score.recorder) {
                let _: [Void] = await Disassembler().disassembleStreaming(machO: machO) {
                    if !rawRegister && !widthFlags { _ = $0.renderStructured() }
                }
            }
        }
        let report = try score.report()
        try emit(report.json(), to: output)
        if report.exitCode == 1 || (report.exitCode == 3 && !allowIncomplete) { throw ExitCode(report.exitCode) }
    }
}

/// Only this authored ABI is executable here. Symbol and return addresses are
/// obtained from independent system tools, not the decompiler's segmentation.
private func nativeWidthOracle(path: String) throws -> ReturnOracle {
    #if arch(arm64)
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let symbols = try oracleTool(["nm", "-nm", url.path])
    var starts: [String: UInt64] = [:]
    for line in symbols.split(separator: "\n") {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard let name = tokens.last, name.hasPrefix("_wf_"), Int(name.dropFirst(4)) != nil,
              let first = tokens.first, let address = UInt64(first, radix: 16) else { continue }
        starts[String(name)] = address
    }
    guard starts.count == 1174 else { throw ValidationError("expected the authored 1,174 width-flag functions; found \(starts.count)") }
    let listing = try oracleTool(["llvm-objdump", "--macho", "--disassemble", "--no-show-raw-insn", url.path])
    var returns: [String: [UInt64]] = [:], current: String?
    for line in listing.split(separator: "\n") {
        if !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.hasSuffix(":") {
            let label = String(line.dropLast()); current = starts[label] == nil ? nil : label
        }
        let tokens = line.split(whereSeparator: \.isWhitespace)
        if let current, tokens.count >= 2, tokens[1] == "ret", tokens[0].hasSuffix(":"),
           let address = UInt64(tokens[0].dropLast(), radix: 16) { returns[current, default: []].append(address) }
    }
    let uuidLines = try oracleTool(["dwarfdump", "--uuid", url.path]).split(separator: "\n")
    guard uuidLines.count == 1 else { throw ValidationError("expected one independently read Mach-O UUID") }
    let uuidTokens = uuidLines[0].split(whereSeparator: \.isWhitespace)
    guard uuidTokens.count >= 2, uuidTokens[0] == "UUID:" else { throw ValidationError("missing Mach-O UUID") }
    guard let library = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw ValidationError("cannot load native fixture") }
    defer { dlclose(library) }
    let cases = try starts.sorted { $0.value < $1.value }.map { name, start in
        guard let exits = returns[name], exits.count == 1, let symbol = dlsym(library, String(name.dropFirst())) else {
            throw ValidationError("\(name): expected one return and a callable fixture symbol")
        }
        let native = unsafeBitCast(symbol, to: (@convention(c) () -> UInt64).self)
        return ReturnExpectation(native(), in: start, at: exits[0], id: name)
    }
    return ReturnOracle(cases, binaryUUID: String(uuidTokens[1]))
    #else
    throw ValidationError("native width fixtures require Apple Silicon")
    #endif
}
private func oracleTool(_ arguments: [String]) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); process.arguments = arguments
    process.standardOutput = pipe; process.standardError = FileHandle.standardError
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ValidationError("oracle tool failed: \(arguments[0])") }
    return String(decoding: data, as: UTF8.self)
}
