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

        // MachOKit traps (`try!`, `precondition`) rather than throwing on
        // malformed input, and a trap in a dependency cannot be caught — so the
        // structure has to be checked before it is handed over. See
        // MachOPreflight.
        try MachOPreflight.validate(url: url)

        let file: File
        do {
            file = try MachOKit.loadFromFile(url: url)
        } catch {
            throw BinaryLoadError("Not a Mach-O file: \(path) (\(error))")
        }

        switch file {
        case .machO(let machO):
            warnIfEncrypted(machO, path: path)
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
            warnIfEncrypted(match, path: path)
            return match
        }
    }

    /// FairPlay-encrypted App Store binaries (`cryptid != 0`) read as garbage —
    /// warn loudly so the user isn't puzzled by nonsense output.
    private static func warnIfEncrypted(_ machO: MachOFile, path: String) {
        guard machO.isEncrypted else { return }
        let name = (path as NSString).lastPathComponent
        FileHandle.standardError.write(Data("""
        warning: '\(name)' is FairPlay-encrypted (cryptid != 0) — its __text and Swift metadata \
        will read as garbage. Analyze a decrypted dump (e.g. from a jailbroken device via \
        frida-ios-dump) or an un-encrypted build instead.

        """.utf8))
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

// MARK: - dyld shared cache

extension BinaryLoader {
    /// Selects a single image inside a dyld shared cache.
    public enum ImageSelector: Sendable {
        /// Match by the binary's file name without extension, e.g. `Foundation`
        /// for `/System/Library/Frameworks/Foundation.framework/Foundation`.
        case name(String)
        /// Match by the full install path recorded in the cache.
        case path(String)
    }

    /// Unified entry point for the CLI: load a standalone Mach-O, or extract an
    /// image from a dyld shared cache when `image` / `imagePath` is given.
    ///
    /// On modern macOS/iOS the system frameworks (Foundation, SwiftUI, …) have
    /// no standalone on-disk binary — they live only in the dyld shared cache,
    /// so this is the only way to reach their metadata.
    public static func loadMachO(
        path: String?,
        architecture: String? = nil,
        image: String? = nil,
        imagePath: String? = nil,
        cachePath: String? = nil,
        binary: String? = nil
    ) throws -> MachOFile {
        if image != nil, imagePath != nil {
            throw BinaryLoadError("Pass only one of --image or --image-path.")
        }
        if let image {
            return try loadFromDyldCache(cachePath: cachePath, selector: .name(image))
        }
        if let imagePath {
            return try loadFromDyldCache(cachePath: cachePath, selector: .path(imagePath))
        }
        if cachePath != nil {
            throw BinaryLoadError("--cache needs --image or --image-path to choose an image from the cache.")
        }
        guard let path else {
            throw BinaryLoadError("Provide a binary path, or --image <name> to read from the dyld shared cache.")
        }
        // Accept a Mach-O, or an .app/.framework/.ipa to dig the binary out of.
        return try load(path: resolveBinaryInput(path, binary: binary), architecture: architecture)
    }

    /// Extract a single image from a dyld shared cache as a cache-aware
    /// `MachOFile` — so Swift-metadata pointers resolve through the cache and
    /// the existing dump pipeline works unchanged.
    ///
    /// - Parameters:
    ///   - cachePath: Path to a `dyld_shared_cache_*` file. `nil` uses the
    ///     running host's cache (`FullDyldCache.host`).
    ///   - selector: Which image to pull out.
    public static func loadFromDyldCache(
        cachePath: String?,
        selector: ImageSelector
    ) throws -> MachOFile {
        let cache = try openDyldCache(cachePath: cachePath)
        let matches: (MachOFile) -> Bool
        switch selector {
        case .name(let name): matches = { imageName(of: $0) == name }
        case .path(let path): matches = { $0.imagePath == path }
        }
        guard let image = cache.machOFiles().first(where: matches) else {
            switch selector {
            case .name(let name):
                throw BinaryLoadError(
                    "Image '\(name)' not found in the dyld shared cache. "
                    + "Use --list-images to see what's available, or --image-path with a full install path."
                )
            case .path(let path):
                throw BinaryLoadError("Image path '\(path)' not found in the dyld shared cache.")
            }
        }
        return image
    }

    /// Install paths of every image in the cache, sorted. Backs `--list-images`.
    public static func dyldCacheImagePaths(cachePath: String?) throws -> [String] {
        try openDyldCache(cachePath: cachePath).machOFiles().map(\.imagePath).sorted()
    }

    private static func openDyldCache(cachePath: String?) throws -> FullDyldCache {
        if let cachePath {
            let url = URL(fileURLWithPath: cachePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BinaryLoadError("Dyld shared cache not found: \(cachePath)")
            }
            do {
                return try FullDyldCache(url: url)
            } catch {
                throw BinaryLoadError("Not a dyld shared cache: \(cachePath) (\(error))")
            }
        }
        guard let host = FullDyldCache.host else {
            throw BinaryLoadError(
                "No host dyld shared cache is available on this system. "
                + "Pass --cache with a path to a dyld_shared_cache_* file."
            )
        }
        return host
    }

    /// Binary file name without extension: `.../Foundation` → `Foundation`,
    /// `.../libswiftCore.dylib` → `libswiftCore`.
    static func imageName(of machO: MachOFile) -> String {
        let last = (machO.imagePath as NSString).lastPathComponent
        return (last as NSString).deletingPathExtension
    }
}
