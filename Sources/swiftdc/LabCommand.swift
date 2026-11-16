import ArgumentParser
import Foundation
import SwiftDecompilerCore

/// One function's analysis facts, instruction by instruction: the entry
/// convention and its seeded registers, the registers reaching each call,
/// each call's argument layout, branch conditions and exit registers. For
/// finding out why a render says what it says without reading the render.
struct LabCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lab",
        abstract: "Show what the analysis concluded at each instruction of the matching functions.")
    @Argument(help: "Mach-O binary.") var path: String
    @Option(name: [.short, .long], help: "Functions whose symbol or demangled name contains this text.")
    var function: String
    @Option(help: "Architecture slice of a fat binary.") var arch: String?

    func validate() throws { try validateFunctionFilter(function) }

    func run() async throws {
        do {
            print(try await LabReport.report(path: path, architecture: arch, function: function), terminator: "")
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            throw ExitCode(2)
        }
    }
}
