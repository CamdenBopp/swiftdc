#!/usr/bin/env swift
import CryptoKit
import Darwin
import Foundation

// Whole-binary corpus measurements: reliability (exit, signal, timeout,
// memory kill), consistency (output hashes across separate processes),
// completeness against independent evidence (dyld_info function starts, the
// binary's own sections) and performance (wall, CPU, peak footprint).
//
//   swift Tools/corpus.swift manifest < paths > corpus.tsv
//   swift Tools/corpus.swift run <swiftdc> <corpus.tsv> <outdir> [options]
//   swift Tools/corpus.swift report <outdir>
//   swift Tools/corpus.swift compare <old outdir> <new outdir>
//
// run options: --commands a,b  --repeat N  --jobs J  --kill-mb M  --timeout S
//   --min-text B  --max-text B  --swift-only  --sample N  --seed S
// A run appends to <outdir>/results.jsonl and skips what is already there, so
// an interrupted sweep resumes. The manifest names private apps: keep it and
// the outdir out of the repository.

enum CorpusError: Error { case invalid(String) }

let commandTable: [String: [String]] = [
    "dump": ["dump"], "interface": ["interface"], "layout": ["layout"], "objc": ["objc"],
    "version": ["swift-version"], "xrefs": ["xrefs", "--unreferenced"],
    "structured": ["disasm", "--structured"], "pseudo": ["disasm", "--pseudo"],
    "listing": ["disasm"], "analyze": ["analyze"],
    "objc-methods": ["objc", "--methods", "--structured"],
]

// MARK: Manifest: an independent reading of each Mach-O header.

struct Entry {
    var path: String, sha256: String, arch: String, fat: Bool, fileType: Int
    var textBytes: Int, swift: Bool, objc: Bool
    var tsv: String { [path, sha256, arch, fat ? "1" : "0", "\(fileType)", "\(textBytes)", swift ? "1" : "0", objc ? "1" : "0"].joined(separator: "\t") }
    init?(tsv line: Substring) {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 8, let t = Int(f[4]), let b = Int(f[5]) else { return nil }
        path = f[0]; sha256 = f[1]; arch = f[2]; fat = f[3] == "1"; fileType = t; textBytes = b; swift = f[6] == "1"; objc = f[7] == "1"
    }
    init(path: String, sha256: String, arch: String, fat: Bool, fileType: Int, textBytes: Int, swift: Bool, objc: Bool) {
        self.path = path; self.sha256 = sha256; self.arch = arch; self.fat = fat; self.fileType = fileType
        self.textBytes = textBytes; self.swift = swift; self.objc = objc
    }
}

func readInt<T: FixedWidthInteger>(_ d: Data, _ o: Int, _: T.Type, big: Bool = false) -> T? {
    guard o >= 0, o + MemoryLayout<T>.size <= d.count else { return nil }
    var v: T = 0
    _ = withUnsafeMutableBytes(of: &v) { d.copyBytes(to: $0, from: (d.startIndex + o)..<(d.startIndex + o + MemoryLayout<T>.size)) }
    return big ? T(bigEndian: v) : T(littleEndian: v)
}

func name16(_ d: Data, _ o: Int) -> String {
    guard o + 16 <= d.count else { return "" }
    let bytes = d[(d.startIndex + o)..<(d.startIndex + o + 16)].prefix { $0 != 0 }
    return String(decoding: bytes, as: UTF8.self)
}

func describe(path: String) -> Entry? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 4096), let magic = readInt(head, 0, UInt32.self, big: true) else { return nil }
    var sliceOffset = 0, arch = "", fat = false
    if magic == 0xcafebabe || magic == 0xcafebabf {
        fat = true
        let wide = magic == 0xcafebabf, count = Int(readInt(head, 4, UInt32.self, big: true) ?? 0), stride = wide ? 32 : 20
        var choices: [(String, Int)] = []
        for i in 0..<min(count, 64) {
            let o = 8 + i * stride
            guard let cpu = readInt(head, o, UInt32.self, big: true), let sub = readInt(head, o + 4, UInt32.self, big: true) else { break }
            let offset = wide ? Int(readInt(head, o + 8, UInt64.self, big: true) ?? 0) : Int(readInt(head, o + 8, UInt32.self, big: true) ?? 0)
            // Only the subtypes swiftdc can name: ALL, V8 and E. arm64e.x1 and
            // friends are other slices of the same code.
            guard cpu == 0x0100000c, [0, 1, 2].contains(sub & 0xff) else { continue }
            choices.append(((sub & 0xff) == 2 ? "arm64e" : "arm64", offset))
        }
        guard let pick = choices.first(where: { $0.0 == "arm64" }) ?? choices.first else { return nil }
        arch = pick.0; sliceOffset = pick.1
    } else if magic != 0xcffaedfe {
        return nil
    }
    guard (try? handle.seek(toOffset: UInt64(sliceOffset))) != nil, let header = try? handle.read(upToCount: 32),
          readInt(header, 0, UInt32.self) == 0xfeedfacf, readInt(header, 4, UInt32.self) == 0x0100000c,
          let sub = readInt(header, 8, UInt32.self), let fileType = readInt(header, 12, UInt32.self),
          let sizeOfCommands = readInt(header, 20, UInt32.self), sizeOfCommands < 16 << 20,
          let commands = try? handle.read(upToCount: Int(sizeOfCommands)) else { return nil }
    if arch.isEmpty { arch = (sub & 0xff) == 2 ? "arm64e" : "arm64" }
    var o = 0, text = 0, swift = false, objc = false
    let ncmds = Int(readInt(header, 16, UInt32.self) ?? 0)
    for _ in 0..<ncmds {
        guard let cmd = readInt(commands, o, UInt32.self), let size = readInt(commands, o + 4, UInt32.self), size >= 8 else { break }
        if cmd == 0x19, let nsects = readInt(commands, o + 64, UInt32.self) {
            for s in 0..<Int(min(nsects, 512)) {
                let so = o + 72 + s * 80
                let sect = name16(commands, so), seg = name16(commands, so + 16)
                if seg == "__TEXT" || seg == "__TEXT_EXEC", sect == "__text" { text = Int(readInt(commands, so + 40, UInt64.self) ?? 0) }
                if sect.hasPrefix("__swift5_types") || sect.hasPrefix("__swift5_proto") { swift = true }
                if sect == "__objc_classlist" { objc = true }
            }
        }
        o += Int(size)
    }
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return Entry(path: path, sha256: digest, arch: arch, fat: fat, fileType: Int(fileType), textBytes: text, swift: swift, objc: objc)
}

// MARK: Running one command under a footprint and time guard.

struct Measured {
    var status: Int32 = 0, signal: Int32 = 0, timedOut = false, memoryKilled = false
    var wall = 0.0, user = 0.0, system = 0.0, peakMB = 0.0
    var stdoutHash = "", stdoutBytes = 0, stdoutLines = 0, stderrHash = "", stderrTail = "", stdoutTail = ""
}

let timebase: Double = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return Double(t.numer) / Double(t.denom) / 1e9 }()

func rusage(_ pid: pid_t) -> rusage_info_v4? {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return rc == 0 ? info : nil
}

func hashFile(_ path: String) -> (String, Int, Int) {
    guard let h = FileHandle(forReadingAtPath: path) else { return ("", 0, 0) }
    defer { try? h.close() }
    var hasher = SHA256(), bytes = 0, lines = 0
    while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk); bytes += chunk.count
        lines += chunk.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
    }
    return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), bytes, lines)
}

func measure(_ executable: String, _ arguments: [String], scratch: String, killMB: Double, timeout: Double) throws -> Measured {
    let out = scratch + ".out", err = scratch + ".err"
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions); defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 1, out, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    posix_spawn_file_actions_addopen(&actions, 2, err, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, executable, &actions, nil, argv, environ)
    guard spawned == 0 else { throw CorpusError.invalid("spawn \(executable): \(spawned)") }
    var m = Measured()
    let start = Date()
    var info = siginfo_t()
    while true {
        info = siginfo_t()
        if waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT | WNOHANG) == 0, info.si_pid == pid { break }
        if let r = rusage(pid), Double(r.ri_phys_footprint) / 1_048_576 > killMB, !m.memoryKilled {
            m.memoryKilled = true; kill(pid, SIGKILL)
        }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > timeout, !m.timedOut { m.timedOut = true; kill(pid, SIGKILL) }
        usleep(elapsed < 0.2 ? 2_000 : 50_000)
    }
    // The child is a zombie until reaped, and its usage is still readable.
    if let r = rusage(pid) {
        m.wall = Double(r.ri_proc_exit_abstime &- r.ri_proc_start_abstime) * timebase
        m.user = Double(r.ri_user_time) * timebase; m.system = Double(r.ri_system_time) * timebase
        m.peakMB = Double(r.ri_lifetime_max_phys_footprint) / 1_048_576
    }
    var raw: Int32 = 0
    waitpid(pid, &raw, 0)
    if raw & 0x7f == 0 { m.status = (raw >> 8) & 0xff } else { m.signal = raw & 0x7f }
    (m.stdoutHash, m.stdoutBytes, m.stdoutLines) = hashFile(out)
    if let h = FileHandle(forReadingAtPath: out) {
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 4096 ? size - 4096 : 0)
        m.stdoutTail = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self); try? h.close()
    }
    m.stderrHash = hashFile(err).0
    if let e = FileManager.default.contents(atPath: err) {
        let lines = String(decoding: e.suffix(4096), as: UTF8.self).split(separator: "\n").map(String.init)
        m.stderrTail = String((lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "").prefix(240))
    }
    try? FileManager.default.removeItem(atPath: out); try? FileManager.default.removeItem(atPath: err)
    return m
}

func functionStarts(_ e: Entry) -> Int? {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = ["dyld_info", "-function_starts"] + (e.fat ? ["-arch", e.arch] : []) + [e.path]
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    var starts = Set<Substring>()
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let t = line.drop { $0 == " " }
        if t.hasPrefix("0x"), let a = t.split(separator: " ").first { starts.insert(a) }
    }
    return starts.count
}

// MARK: Records

struct Record: Codable {
    var sha256: String, path: String, command: String, rep: Int
    var textBytes: Int, swift: Bool, objc: Bool, fileType: Int, jobs: Int
    var status: Int32, signal: Int32, timedOut: Bool, memoryKilled: Bool
    var wall: Double, user: Double, system: Double, peakMB: Double
    var stdoutHash: String, stdoutBytes: Int, stdoutLines: Int, stderrHash: String, stderrTail: String
    var functionStarts: Int?, reportedFunctions: Int?
    var outcome: String {
        if memoryKilled { return "memory-kill" }
        if timedOut { return "timeout" }
        if signal != 0 { return "crash" }
        return status == 0 ? "ok" : "error"
    }
}

func loadRecords(_ dir: String) -> [Record] {
    guard let text = try? String(contentsOfFile: dir + "/results.jsonl", encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    return text.split(separator: "\n").compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
}

func loadManifest(_ path: String) throws -> [Entry] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return text.split(separator: "\n").compactMap { Entry(tsv: $0) }
}

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

func option(_ args: [String], _ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func runCorpus(_ args: [String]) throws {
    guard args.count >= 3 else { throw CorpusError.invalid("run <swiftdc> <corpus.tsv> <outdir> [options]") }
    let outdir = args[2]
    let commands = (option(args, "--commands") ?? "dump,interface,layout,objc,version,xrefs").split(separator: ",").map(String.init)
    for c in commands where commandTable[c] == nil { throw CorpusError.invalid("unknown command \(c); known: \(commandTable.keys.sorted())") }
    let repeats = Int(option(args, "--repeat") ?? "1") ?? 1, jobs = Int(option(args, "--jobs") ?? "1") ?? 1
    let killMB = Double(option(args, "--kill-mb") ?? "3000") ?? 3000, timeout = Double(option(args, "--timeout") ?? "600") ?? 600
    let minText = Int(option(args, "--min-text") ?? "0") ?? 0, maxText = Int(option(args, "--max-text") ?? "\(Int.max)") ?? Int.max
    var entries = try loadManifest(args[1]).filter { $0.textBytes >= minText && $0.textBytes <= maxText }
    if args.contains("--swift-only") { entries = entries.filter(\.swift) }
    entries.sort { ($0.textBytes, $0.sha256) < ($1.textBytes, $1.sha256) }
    if let n = option(args, "--sample").flatMap(Int.init), n < entries.count {
        var rng = SeededRandom(state: UInt64(option(args, "--seed") ?? "1") ?? 1)
        for i in 0..<n { entries.swapAt(i, i + rng.next(entries.count - i)) }
        entries = Array(entries.prefix(n)).sorted { ($0.textBytes, $0.sha256) < ($1.textBytes, $1.sha256) }
    }
    try FileManager.default.createDirectory(atPath: outdir + "/scratch", withIntermediateDirectories: true)
    // Run a private copy: replacing the build in place while a sweep
    // launches it gets each later launch killed at exec (SIGKILL, no usage),
    // which once read as 14 crashes. The copy is named by its hash, and a
    // resumed run must use the same build.
    let source = URL(fileURLWithPath: args[0]).standardizedFileURL.path
    guard let build = FileManager.default.contents(atPath: source) else { throw CorpusError.invalid("cannot read \(source)") }
    let buildHash = SHA256.hash(data: build).map { String(format: "%02x", $0) }.joined()
    let stamp = outdir + "/swiftdc.sha256"
    if let previous = try? String(contentsOfFile: stamp, encoding: .utf8), previous != buildHash {
        throw CorpusError.invalid("\(outdir) was run with swiftdc \(previous.prefix(12)), not \(buildHash.prefix(12)); use a new outdir")
    }
    let swiftdc = outdir + "/swiftdc-" + buildHash.prefix(12)
    if !FileManager.default.fileExists(atPath: swiftdc) {
        try FileManager.default.copyItem(atPath: source, toPath: swiftdc)
    }
    try buildHash.write(toFile: stamp, atomically: true, encoding: .utf8)
    let done = Set(loadRecords(outdir).map { "\($0.sha256) \($0.command) \($0.rep)" })
    let resultsPath = outdir + "/results.jsonl"
    if !FileManager.default.fileExists(atPath: resultsPath) { FileManager.default.createFile(atPath: resultsPath, contents: nil) }
    guard let results = FileHandle(forWritingAtPath: resultsPath) else { throw CorpusError.invalid("cannot write \(resultsPath)") }
    results.seekToEndOfFile()
    let lock = NSLock(), encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    var finished = 0
    let total = entries.count, gate = DispatchSemaphore(value: jobs), group = DispatchGroup()
    for (index, entry) in entries.enumerated() {
        gate.wait(); group.enter()
        DispatchQueue.global().async {
            defer { gate.signal(); group.leave() }
            let starts = commands.contains("xrefs") ? functionStarts(entry) : nil
            for command in commands { for rep in 0..<repeats where !done.contains("\(entry.sha256) \(command) \(rep)") {
                let arguments = [commandTable[command]![0], entry.path] + commandTable[command]!.dropFirst()
                    + (entry.fat ? ["--arch", entry.arch] : [])
                guard let m = try? measure(swiftdc, arguments, scratch: "\(outdir)/scratch/\(index)", killMB: killMB, timeout: timeout) else { continue }
                var reported: Int?
                if command == "xrefs" { reported = xrefsFunctionCount(m) }
                let r = Record(sha256: entry.sha256, path: entry.path, command: command, rep: rep, textBytes: entry.textBytes,
                               swift: entry.swift, objc: entry.objc, fileType: entry.fileType, jobs: jobs,
                               status: m.status, signal: m.signal, timedOut: m.timedOut, memoryKilled: m.memoryKilled,
                               wall: m.wall, user: m.user, system: m.system, peakMB: m.peakMB,
                               stdoutHash: m.stdoutHash, stdoutBytes: m.stdoutBytes, stdoutLines: m.stdoutLines,
                               stderrHash: m.stderrHash, stderrTail: m.stderrTail, functionStarts: starts, reportedFunctions: reported)
                lock.lock()
                if let line = try? encoder.encode(r) { results.write(line + Data("\n".utf8)) }
                lock.unlock()
            } }
            lock.lock(); finished += 1
            if finished % 50 == 0 || finished == total { FileHandle.standardError.write(Data("\(finished)/\(total)\n".utf8)) }
            lock.unlock()
        }
    }
    group.wait()
    try? results.close()
}

func xrefsFunctionCount(_ m: Measured) -> Int? {
    guard m.status == 0, let line = m.stdoutTail.split(separator: "\n").last(where: { $0.contains(" functions have no resolved caller") }) else { return nil }
    let words = line.split(separator: " ")
    guard words.count > 3, words[1] == "of" else { return nil }
    return Int(words[2])
}

// MARK: Report

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let s = values.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}

func fmt(_ v: Double, _ digits: Int = 2) -> String { v.isNaN ? "-" : String(format: "%.\(digits)f", v) }

/// Paths, hex addresses and numbers vary per binary; a message class does not.
func messageClass(_ s: String) -> String {
    var t = s
    for pattern in ["/[^ :'\"]+", "0x[0-9a-fA-F]+", "[0-9]+"] {
        t = t.replacingOccurrences(of: pattern, with: "#", options: .regularExpression)
    }
    return String(t.prefix(140))
}

func report(_ dir: String) throws {
    let records = loadRecords(dir)
    guard !records.isEmpty else { throw CorpusError.invalid("no records in \(dir)") }
    let binaries = Dictionary(grouping: records, by: \.sha256)
    let text = binaries.values.reduce(0) { $0 + $1[0].textBytes }
    print("# Corpus report: \(dir)")
    print("\(binaries.count) binaries (\(binaries.values.filter { $0[0].swift }.count) Swift, \(binaries.values.filter { $0[0].objc }.count) Objective-C), \(fmt(Double(text) / 1_048_576, 1)) MB of __text, \(records.count) runs, jobs \(Set(records.map(\.jobs)).sorted())")
    print("\n## Reliability (rep 0)\n")
    print("| command | runs | ok | error | crash | timeout | memory-kill | empty ok output |")
    print("|---|---|---|---|---|---|---|---|")
    let commands = Set(records.map(\.command)).sorted()
    for c in commands {
        let rs = records.filter { $0.command == c && $0.rep == 0 }
        let n = { (o: String) in rs.filter { $0.outcome == o }.count }
        print("| \(c) | \(rs.count) | \(n("ok")) | \(n("error")) | \(n("crash")) | \(n("timeout")) | \(n("memory-kill")) | \(rs.filter { $0.outcome == "ok" && $0.stdoutBytes == 0 }.count) |")
    }
    for c in commands {
        let bad = records.filter { $0.command == c && $0.rep == 0 && $0.outcome != "ok" }
        guard !bad.isEmpty else { continue }
        print("\n### \(c): non-ok by message\n")
        for (k, v) in Dictionary(grouping: bad, by: { "\($0.outcome): \(messageClass($0.stderrTail))" }).sorted(by: { ($0.value.count, $1.key) > ($1.value.count, $0.key) }) {
            print("- \(v.count)× \(k)  e.g. `\(v.map(\.path).sorted()[0])`")
        }
    }
    print("\n## Evidence checks\n")
    for c in commands {
        let ok = records.filter { $0.command == c && $0.rep == 0 && $0.outcome == "ok" }
        let emptySwift = ok.filter { $0.swift && $0.stdoutBytes == 0 && ["dump", "interface", "layout"].contains(c) }
        let emptyObjC = ok.filter { $0.objc && $0.stdoutBytes == 0 && c == "objc" }
        if !(emptySwift + emptyObjC).isEmpty {
            print("- \(c): \(emptySwift.count + emptyObjC.count) empty outputs for a binary whose sections say it has metadata, e.g. `\((emptySwift + emptyObjC)[0].path)`")
        }
    }
    let x = records.filter { $0.command == "xrefs" && $0.rep == 0 && $0.outcome == "ok" }
    let paired = x.filter { $0.functionStarts != nil && $0.reportedFunctions != nil }
    if !paired.isEmpty {
        let below = paired.filter { $0.reportedFunctions! < $0.functionStarts! }
        let half = paired.filter { $0.functionStarts! > 0 && Double($0.reportedFunctions!) < 0.5 * Double($0.functionStarts!) }
        let unreadable = x.filter { $0.reportedFunctions == nil }
        print("- xrefs function count against `dyld_info -function_starts`: \(paired.count) binaries, \(below.count) report fewer functions than the starts, \(half.count) below half; \(unreadable.count) summaries unreadable")
        for r in below.sorted(by: { $0.path < $1.path }).prefix(15) { print("  - `\(r.path)`: \(r.reportedFunctions!) of \(r.functionStarts!) starts") }
        let totals = paired.reduce((0, 0)) { ($0.0 + $1.reportedFunctions!, $0.1 + $1.functionStarts!) }
        print("- totals: \(totals.0) functions reported, \(totals.1) function starts")
        // No starts at all passes the comparison above; a function count far
        // below the code's size does not. Compilers' functions average a few
        // hundred instructions.
        let sparse = x.filter { $0.textBytes >= 1 << 18 && ($0.reportedFunctions ?? 0) > 0
            && $0.textBytes / 4 / $0.reportedFunctions! > 20_000 }
        print("- \(sparse.count) binaries with at least 256 KB of __text average more than 20,000 instructions per reported function")
        for r in sparse.sorted(by: { $0.path < $1.path }).prefix(15) {
            print("  - `\(r.path)`: \(r.reportedFunctions!) functions for \(r.textBytes / 4) instructions, \(r.functionStarts ?? 0) starts")
        }
    }
    print("\n## Consistency across processes\n")
    let groups = Dictionary(grouping: records.filter { $0.outcome == "ok" || $0.outcome == "error" }, by: { "\($0.sha256) \($0.command)" }).values.filter { $0.count > 1 }
    let differ = groups.filter { g in Set(g.map { "\($0.status) \($0.stdoutHash) \($0.stderrHash)" }).count > 1 }
    print("\(groups.count) (binary, command) pairs run more than once, \(groups.reduce(0) { $0 + $1.count }) runs; \(differ.count) differ.")
    for g in differ.sorted(by: { $0[0].path < $1[0].path }).prefix(30) {
        print("- `\(g[0].path)` \(g[0].command): \(Set(g.map(\.stdoutHash)).count) stdout hashes, sizes \(g.map(\.stdoutBytes))")
    }
    print("\n## Performance (ok runs; instructions = __text / 4)\n")
    print("| command | runs | total wall s | median insn/s | p10 insn/s | median KB/insn | p90 KB/insn | max peak MB | slowest |")
    print("|---|---|---|---|---|---|---|---|---|")
    for c in commands {
        let ok = records.filter { $0.command == c && $0.outcome == "ok" && $0.textBytes >= 4096 && $0.wall > 0 }
        guard !ok.isEmpty else { continue }
        let rate = ok.map { Double($0.textBytes / 4) / $0.wall }, kb = ok.map { $0.peakMB * 1024 / Double($0.textBytes / 4) }
        let big = ok.filter { $0.textBytes >= 1 << 20 }.map { $0.peakMB * 1024 / Double($0.textBytes / 4) }
        let slow = ok.max { ($0.wall, $1.path) < ($1.wall, $0.path) }!
        print("| \(c) | \(ok.count) | \(fmt(ok.reduce(0) { $0 + $1.wall }, 1)) | \(fmt(percentile(rate, 0.5), 0)) | \(fmt(percentile(rate, 0.1), 0)) | \(fmt(percentile(big.isEmpty ? kb : big, 0.5))) | \(fmt(percentile(big.isEmpty ? kb : big, 0.9))) | \(fmt(ok.map(\.peakMB).max()!, 0)) | \(fmt(slow.wall, 1)) s, \(fmt(Double(slow.textBytes) / 1_048_576, 1)) MB text |")
    }
    print("\nKB/insn is over binaries with at least 1 MB of __text where any exist; small binaries are dominated by fixed cost.")
}

// MARK: Compare two runs

func compare(_ old: String, _ new: String) throws {
    let a = Dictionary(loadRecords(old).filter { $0.rep == 0 }.map { ("\($0.sha256) \($0.command)", $0) }, uniquingKeysWith: { x, _ in x })
    let b = Dictionary(loadRecords(new).filter { $0.rep == 0 }.map { ("\($0.sha256) \($0.command)", $0) }, uniquingKeysWith: { x, _ in x })
    let shared = Set(a.keys).intersection(b.keys).sorted()
    print("# Compare \(old) → \(new)\n\n\(shared.count) shared (binary, command) runs; \(a.count - shared.count) only in old, \(b.count - shared.count) only in new.\n")
    var outcome: [String] = [], output: [String: Int] = [:], examples: [String: String] = [:]
    var wall: [String: [Double]] = [:], peak: [String: [Double]] = [:]
    for k in shared {
        let x = a[k]!, y = b[k]!
        if x.outcome != y.outcome { outcome.append("- `\(x.path)` \(x.command): \(x.outcome) → \(y.outcome) \(y.stderrTail)") }
        if x.outcome == "ok", y.outcome == "ok" {
            if x.stdoutHash != y.stdoutHash { output[x.command, default: 0] += 1; examples[x.command] = examples[x.command] ?? x.path }
            if x.wall > 0.05 { wall[x.command, default: []].append(y.wall / x.wall) }
            if x.peakMB > 0 { peak[x.command, default: []].append(y.peakMB / x.peakMB) }
        }
    }
    print("## Outcome changes: \(outcome.count)\n"); outcome.prefix(50).forEach { print($0) }
    print("\n## Output changes (ok in both)\n")
    for (c, n) in output.sorted(by: { $0.key < $1.key }) { print("- \(c): \(n) binaries, e.g. `\(examples[c]!)`") }
    print("\n## Ratios new/old (ok in both; wall only where old ≥ 50 ms)\n\n| command | median wall | p90 wall | median peak | p90 peak |\n|---|---|---|---|---|")
    for c in Set(wall.keys).union(peak.keys).sorted() {
        print("| \(c) | \(fmt(percentile(wall[c] ?? [], 0.5), 3)) | \(fmt(percentile(wall[c] ?? [], 0.9), 3)) | \(fmt(percentile(peak[c] ?? [], 0.5), 3)) | \(fmt(percentile(peak[c] ?? [], 0.9), 3)) |")
    }
}

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "manifest":
        var paths: [String] = []
        while let line = readLine() { if !line.isEmpty { paths.append(line) } }
        var rows = [String?](repeating: nil, count: paths.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: paths.count) { i in
            let row = describe(path: paths[i])?.tsv
            lock.lock(); rows[i] = row; lock.unlock()
        }
        var seen = Set<String>()
        for row in rows.compactMap({ $0 }) {
            let sha = row.split(separator: "\t")[1]
            if seen.insert(String(sha)).inserted { print(row) }
        }
    case "run": try runCorpus(Array(args.dropFirst()))
    case "report" where args.count == 2: try report(args[1])
    case "compare" where args.count == 3: try compare(args[1], args[2])
    default: throw CorpusError.invalid("usage: corpus.swift manifest|run|report|compare …")
    }
}

do { try main() } catch { FileHandle.standardError.write(Data("corpus: \(error)\n".utf8)); exit(2) }
