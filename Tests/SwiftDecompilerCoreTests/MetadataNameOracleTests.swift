import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A stripped binary's functions are named from Swift metadata alone:
/// `Module.Type.<kind>` from each class's method descriptors and override table,
/// `Type: Protocol.<kind>` from witness tables. The fixtures are stripped copies
/// of builds that keep their symbols, so the unstripped symbol at the same
/// address is ground truth. The demangling comes from `xcrun swift-demangle`,
/// not swiftdc's own demangler, so the check does not grade swiftdc against
/// itself.
///
/// The required names are the ones a text scrape of SwiftDump output used to
/// find and a first descriptor-only rewrite lost: an override of a superclass
/// method (`Dog.speak`, `Dog.init`) and two classes that share a simple name
/// (`BoxA.Holder`, `BoxB.Holder`).
///
/// What metadata cannot see: a fold partner with no metadata record. At -O
/// `Counter.value.getter` shares its body with the accessors of the `final`
/// classes `BoxA.Holder` and `BoxB.Holder`, which have no vtable entries, so the
/// stripped binary keeps no trace of them. The address is named for the one
/// owner metadata knows, a name true of the body, and the test accepts it when
/// it matches one of the symbols there.
private let pairs: [(stripped: String, symbols: String, required: [String])] = [
    ("Fixtures/Sample/sample.stripped", "Fixtures/Sample/sample.release",
     ["sample.Dog.method", "sample.Dog.init", "sample.Animal.method", "sample.Widget.getter"]),
    ("Fixtures/Sample/libSample.stripped.dylib", "Fixtures/Sample/libSample.dylib",
     ["Sample.Dog.method", "Sample.Dog.init"]),
    ("Fixtures/Sample/libReconstruction.opt.stripped.dylib", "Fixtures/Sample/libReconstruction.opt.dylib",
     ["Reconstruction.BoxA.Holder.init", "Reconstruction.BoxB.Holder.init", "Reconstruction.Dog.init"]),
    ("Fixtures/Sample/libSwiftErrorProbe.stripped.dylib", "Fixtures/Sample/libSwiftErrorProbe.dylib",
     ["SwiftErrorProbe.Validator.method"]),
]

@Test func metadataNamesAgreeWithTheUnstrippedSymbolsIfPresent() throws {
    var checked = 0
    for pair in pairs {
        guard FileManager.default.fileExists(atPath: pair.stripped),
              let truth = demangledTextSymbols(pair.symbols)
        else { continue }
        let machO = try BinaryLoader.load(path: pair.stripped)
        let names = MetadataSymbolizer().functionNames(in: machO)

        for (address, name) in names {
            let real = try #require(truth[address], "\(pair.stripped): no symbol at 0x\(String(address, radix: 16)) for \(name)")
            #expect(real.contains { agrees(name, with: $0) },
                    "\(pair.stripped) 0x\(String(address, radix: 16)): named \(name), symbols are \(real)")
            checked += 1
        }
        let produced = Set(names.values)
        for required in pair.required {
            #expect(produced.contains(required), "\(pair.stripped): \(required) not named; got \(produced.sorted())")
        }
    }
    // The empty-result rule: an oracle that compared nothing passes vacuously.
    if FileManager.default.fileExists(atPath: pairs[0].stripped) {
        #expect(checked >= 40, "only \(checked) names compared")
    }
}

/// `Module.Type.kind` against a demangled symbol such as
/// `Module.Type.label.getter : Swift.String` or `Module.Type.ping() -> Swift.Int`.
private func agrees(_ name: String, with symbol: String) -> Bool {
    if let colon = name.range(of: ": ") {
        // A witness: `Type: Protocol.kind`. The symbol names the conforming
        // type's own implementation (or a protocol witness thunk for it).
        let type = String(name[..<colon.lowerBound])
        return symbol.contains(type)
    }
    guard let dot = name.lastIndex(of: ".") else { return false }
    let type = String(name[..<dot])
    let kind = String(name[name.index(after: dot)...])
    guard symbol.hasPrefix(type + ".") else { return false }
    let member = symbol.dropFirst(type.count + 1)
    switch kind {
    case "getter", "setter", "modify", "read": return member.contains(".\(kind)")
    case "init": return member.hasPrefix("__allocating_init(") || member.hasPrefix("init(")
    case "method": return member.contains("(") && !member.hasPrefix("__allocating_init(")
    case "override": return true
    default: return false
    }
}

/// Text-symbol address to every demangled name there, read with `nm` and
/// `swift-demangle`.
private func demangledTextSymbols(_ path: String) -> [UInt64: [String]]? {
    guard FileManager.default.fileExists(atPath: path),
          let listing = run(["nm", path])
    else { return nil }
    var mangled: [(UInt64, String)] = []
    for line in listing.split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count >= 3, parts[1] == "t" || parts[1] == "T",
              let address = UInt64(parts[0], radix: 16)
        else { continue }
        mangled.append((address, String(parts[2])))
    }
    guard let demangled = run(["swift-demangle", "--compact"], input: mangled.map(\.1).joined(separator: "\n"))
    else { return nil }
    let lines = demangled.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= mangled.count else { return nil }
    var map: [UInt64: [String]] = [:]
    for (index, entry) in mangled.enumerated() {
        let name = String(lines[index])
        if map[entry.0]?.contains(name) != true { map[entry.0, default: []].append(name) }
    }
    return map
}

private func run(_ arguments: [String], input: String? = nil) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let stdin = Pipe()
    if input != nil { process.standardInput = stdin }
    guard (try? process.run()) != nil else { return nil }
    // Feed stdin from its own thread: writing it inline deadlocks once both
    // pipes fill, the child blocked on stdout and this thread on stdin.
    if let input {
        let writer = stdin.fileHandleForWriting
        Thread {
            writer.write(Data(input.utf8))
            try? writer.close()
        }.start()
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self)
}
