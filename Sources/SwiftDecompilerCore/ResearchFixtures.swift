import Darwin
import Foundation

/// Independent native expectations for the authored researchinteger.swift
/// corpus only. The declared ARM64 ABI is one UInt64 parameter/result, no
/// receiver, generic context, error result or async continuation.
public enum ResearchFixtures {
    public static let names = ["increment", "mixedBits", "lowWord", "signedShift", "unsignedRange",
                               "signedRange", "choose", "quotient", "residue", "boundedLoop", "wordAdd",
                               "wordArithmeticShift", "signExtendWord", "signExtendByte", "signExtendHalf", "unsignedByte", "wordSelect",
                               "wordNot", "shiftedNot", "orNot", "byteSwap"]
    public static let modules = ["ResearchOnone", "ResearchOptimized", "ResearchSize"]
    public static let edges: [UInt64] = [0, 1, 2, 6, 7, 15, 16, 19, 20, 23, 26, 27, 31, 32, 63, 64,
                                       99, 100, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff,
                                       0x7fffffff, 0x80000000, UInt64(UInt32.max), 1 << 32, (1 << 63) - 1, 1 << 63, .max]

    /// SplitMix64 makes exploratory samples repeatable independently of hash or
    /// process order. The edge corpus is retained even when randomCount is zero.
    public static func inputs(seed: UInt64 = 1, randomCount: Int = 16) -> [UInt64] {
        var state = seed, seen = Set(edges), result = edges
        for _ in 0..<max(0, randomCount) {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            z ^= z >> 31
            if seen.insert(z).inserted { result.append(z) }
        }
        return result
    }

    public static func oracle(path: String, module: String, inputs: [UInt64]) throws -> ReturnOracle {
        #if arch(arm64)
        guard !inputs.isEmpty, module.range(of: #"^Research(Onone|Optimized|Size)(_R[0-9]+)?$"#,
                                           options: .regularExpression) != nil else {
            throw ProbeScoreError.invalid("expected an authored research module and nonempty samples")
        }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let listing = try tool(["nm", "-nm", url.path])
        var symbols: [(raw: String, start: UInt64)] = []
        for line in listing.split(separator: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 3, tokens.contains("external"), let raw = tokens.last,
                  raw.hasPrefix("_$s"), let start = UInt64(tokens[0], radix: 16) else { continue }
            symbols.append((String(raw), start))
        }
        guard !symbols.isEmpty else { throw ProbeScoreError.invalid("research fixture has no exported Swift symbols") }
        let decoded = try tool(["swift-demangle", "--compact"] + symbols.map(\.raw)).split(separator: "\n")
        guard decoded.count == symbols.count else { throw ProbeScoreError.invalid("independent demangler returned an incomplete symbol list") }
        var selected: [String: (raw: String, start: UInt64)] = [:]
        for (symbol, signature) in zip(symbols, decoded) {
            for name in names where signature == "\(module).\(name)(Swift.UInt64) -> Swift.UInt64" {
                guard selected[name] == nil else { throw ProbeScoreError.invalid("duplicate research export: \(name)") }
                selected[name] = symbol
            }
        }
        guard selected.count == names.count else {
            throw ProbeScoreError.invalid("missing declared scalar research exports: \(names.filter { selected[$0] == nil })")
        }
        let uuidLines = try tool(["dwarfdump", "--uuid", url.path]).split(separator: "\n")
        guard uuidLines.count == 1 else { throw ProbeScoreError.invalid("expected one native image UUID") }
        let uuid = uuidLines[0].split(whereSeparator: \.isWhitespace)
        guard uuid.count >= 2, uuid[0] == "UUID:" else { throw ProbeScoreError.invalid("missing native image UUID") }
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw ProbeScoreError.invalid("cannot load research fixture") }
        defer { dlclose(handle) }
        var cases: [ReturnExpectation] = []
        for name in names {
            let symbol = selected[name]!
            guard let pointer = dlsym(handle, String(symbol.raw.dropFirst())) else {
                throw ProbeScoreError.invalid("missing native entry: \(name)")
            }
            var owner = Dl_info()
            guard dladdr(pointer, &owner) != 0, let ownerName = owner.dli_fname,
                  URL(fileURLWithPath: String(cString: ownerName)).resolvingSymlinksInPath().path == url.path else {
                throw ProbeScoreError.invalid("native export resolved into another image: \(name)")
            }
            let native = unsafeBitCast(pointer, to: (@convention(c) (UInt64) -> UInt64).self)
            for input in inputs {
                cases.append(ReturnExpectation(native(input), in: symbol.start, arguments: [input],
                                               id: "\(name)/0x\(String(input, radix: 16))"))
            }
        }
        return ReturnOracle(cases, binaryUUID: String(uuid[1]))
        #else
        throw ProbeScoreError.invalid("native research fixtures require Apple Silicon")
        #endif
    }

    private static func tool(_ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.standardError
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProbeScoreError.invalid("research oracle tool failed: \(arguments[0])") }
        return String(decoding: data, as: UTF8.self)
    }
}
