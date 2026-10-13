#!/usr/bin/env swift
import Darwin
import Foundation

// Bounded, reproducible corruption of Mach-O containers or metadata. Swift v1
// uses SplitMix64, so its seed sequences differ from the former harness.
// Usage: swift Tools/fuzz.swift container|metadata <binary> [mutants] [seed] [build ...]
struct SeededRandom {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return Int((z ^ (z >> 31)) % UInt64(bound))
    }
}
struct Region { let offset: Int; let size: Int; let name: String }
struct Tally { var accepted = 0; var rejected = 0; var crashes: [String] = []; var timeouts = 0 }
enum FuzzError: Error { case invalid(String) }
func run(_ executable: String, _ arguments: [String], timeout: Int = 60) throws -> (Int32, Bool, Bool) {
    let process = Process(), finished = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + .seconds(timeout)) == .timedOut {
        process.terminate()
        if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL); finished.wait() }
        return (process.terminationStatus, process.terminationReason == .uncaughtSignal, true)
    }
    return (process.terminationStatus, process.terminationReason == .uncaughtSignal, false)
}
func metadataRegions(_ path: String) throws -> [Region] {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/otool"); process.arguments = ["-l", path]
    process.standardOutput = pipe; process.standardError = FileHandle.standardError
    try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw FuzzError.invalid("otool failed") }
    var name: String?, size = 0, regions: [Region] = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let t = line.split(whereSeparator: \.isWhitespace)
        guard t.count >= 2 else { continue }
        switch t[0] {
        case "sectname": name = String(t[1]); size = 0
        case "size" where name != nil: size = Int(t[1].dropFirst(2), radix: 16) ?? 0
        case "offset" where name != nil:
            if let name, size > 0, name.contains("swift5") || name.contains("objc"), let offset = Int(t[1]) {
                regions.append(Region(offset: offset, size: size, name: name))
            }
            name = nil
        default: break
        }
    }
    return regions
}
func main() throws -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2, ["container", "metadata"].contains(args[0]) else {
        throw FuzzError.invalid("usage: swift Tools/fuzz.swift container|metadata <binary> [mutants] [seed] [build ...]")
    }
    let container = args[0] == "container", source = args[1]
    let count = args.count > 2 ? Int(args[2]) : (container ? 120 : 40)
    let seed = args.count > 3 ? UInt64(args[3]) : (container ? 7 : 1234)
    guard let count, count >= 0, let seed else { throw FuzzError.invalid("invalid count or seed") }
    let builds = args.count > 4 ? Array(args.dropFirst(4)) : [".build/debug/swiftdc"]
    let base = try Data(contentsOf: URL(fileURLWithPath: source)), regions: [Region]
    if container {
        guard base.count >= 32, Array(base.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe] else {
            throw FuzzError.invalid("requires a little-endian 64-bit Mach-O")
        }
        let size = (0..<4).reduce(0) { $0 | (Int(base[20 + $1]) << ($1 * 8)) }
        regions = [Region(offset: 32, size: size, name: "load-commands")]
    } else { regions = try metadataRegions(source) }
    guard !regions.isEmpty, regions.allSatisfy({ $0.size > 0 && $0.offset >= 0 && $0.offset <= base.count && $0.size <= base.count - $0.offset }) else {
        throw FuzzError.invalid("no valid mutation ranges")
    }
    let commands = container ? [["dump"], ["layout"], ["objc"], ["interface"], ["swift-version"]]
        : [["dump"], ["interface"], ["objc"], ["objc", "--methods"], ["layout"], ["disasm"], ["xrefs", "--unreferenced"], ["analyze"]]
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-fuzz-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    var rng = SeededRandom(state: seed), tallies = Dictionary(uniqueKeysWithValues: builds.map { ($0, Tally()) })
    for index in 0..<count {
        let region = regions[rng.next(regions.count)]
        var mutant = base, edits: [Int] = []
        let number = container ? 1 + rng.next(4) : [1, 1, 2, 4][rng.next(4)]
        for _ in 0..<number {
            let position = region.offset + rng.next(region.size)
            mutant[position] = UInt8(rng.next(256)); edits.append(position)
        }
        let url = scratch.appendingPathComponent("m\(index).dylib"); try mutant.write(to: url)
        for build in builds {
            for command in commands {
                let (code, signalled, timeout) = try run(build, command + [url.path], timeout: container ? 60 : 180)
                if timeout { tallies[build]!.timeouts += 1 }
                else if signalled || code > 1 {
                    tallies[build]!.crashes.append("m\(index) \(region.name) \(command.joined(separator: " ")) rc=\(code) offsets=\(edits)")
                } else if code == 0 { tallies[build]!.accepted += 1 }
                else { tallies[build]!.rejected += 1 }
            }
        }
        try FileManager.default.removeItem(at: url)
    }
    print("rng=splitmix64-swift/1 binary=\(source) mutants=\(count) seed=\(seed) sections=\(regions.count)")
    for build in builds {
        let t = tallies[build]!
        print("\(build): runs=\(count * commands.count) accepted=\(t.accepted) rejected=\(t.rejected) crashes=\(t.crashes.count) timeouts=\(t.timeouts)")
        for sample in t.crashes.prefix(10) { print("  \(sample)") }
    }
    return tallies.values.contains { !$0.crashes.isEmpty || $0.timeouts > 0 } ? 1 : 0
}
do { exit(try main()) }
catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2) }
