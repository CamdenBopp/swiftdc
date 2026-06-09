import Foundation
import MachOKit

/// A human-readable error surfaced to the CLI.
public struct BinaryLoadError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Loads a `MachOFile` from a path, transparently selecting a slice out of a
/// fat/universal binary.
public enum BinaryLoader {
    /// Load a single-architecture Mach-O.
    ///
    /// - Parameters:
    ///   - path: Filesystem path to a Mach-O or fat binary.
    ///   - architecture: For fat binaries, the slice to select ("arm64",
    ///     "arm64e", "x86_64"). Ignored for thin binaries.
    public static func load(path: String, architecture: String? = nil) throws -> MachOFile {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BinaryLoadError("File not found: \(path)")
        }

        let file: File
        do {
            file = try MachOKit.loadFromFile(url: url)
        } catch {
            throw BinaryLoadError("Not a Mach-O file: \(path) (\(error))")
        }

        switch file {
        case .machO(let machO):
            return machO

        case .fat(let fat):
            let slices = try fat.machOFiles()
            guard !slices.isEmpty else {
                throw BinaryLoadError("Fat binary contains no Mach-O slices")
            }
            let available = slices.map(archName).joined(separator: ", ")
            guard let architecture else {
                throw BinaryLoadError(
                    "Fat binary — pass --arch to choose a slice. Available: \(available)"
                )
            }
            guard let match = slices.first(where: { archName($0) == architecture }) else {
                throw BinaryLoadError(
                    "Architecture '\(architecture)' not found. Available: \(available)"
                )
            }
            return match
        }
    }

    /// Best-effort architecture name for a thin Mach-O slice.
    public static func archName(_ machO: MachOFile) -> String {
        let cpu = machO.header.cpu
        guard let type = cpu.type else { return "unknown" }
        switch type {
        case .arm64:
            if case .arm64(.arm64e)? = cpu.subtype { return "arm64e" }
            return "arm64"
        case .x86_64:
            return "x86_64"
        default:
            return "\(type)"
        }
    }
}
