import Foundation

/// Turns a user-supplied input — a Mach-O file, a `.app`/`.framework` bundle, or
/// a `.ipa` archive — into the Mach-O path(s) to analyze. This is what lets you
/// point swiftdc straight at an app instead of first digging out its binary.
extension BinaryLoader {
    /// A Mach-O found inside a bundle or archive.
    public struct BundleBinary: Sendable {
        public enum Kind: String, Sendable {
            case executable   // the bundle's main binary
            case framework    // an embedded .framework / .dylib
            case plugin       // an app extension (.appex) / plugin
        }
        /// Display name, e.g. `MyApp`, `SomeKit`.
        public let name: String
        /// Absolute path to the Mach-O on disk.
        public let path: String
        public let kind: Kind
    }

    /// Resolve `input` to the path of a Mach-O to analyze.
    ///
    /// - A plain Mach-O file resolves to itself.
    /// - A `.app`/`.framework` bundle, or a `.ipa` archive (unzipped to a temp
    ///   dir), resolves to the main executable — unless `binary` names an
    ///   embedded framework/extension to target instead.
    public static func resolveBinaryInput(_ input: String, binary: String? = nil) throws -> String {
        guard let bundleDir = try bundleDirectory(for: input) else {
            if let binary {
                throw BinaryLoadError("--binary '\(binary)' applies to an .app/.framework/.ipa, not a plain Mach-O.")
            }
            return input
        }
        let found = try bundleBinaries(inResolvedBundle: bundleDir)
        if let binary {
            if let match = found.first(where: { $0.name.caseInsensitiveCompare(binary) == .orderedSame }) {
                return match.path
            }
            let available = found.map(\.name).joined(separator: ", ")
            throw BinaryLoadError("Binary '\(binary)' not found in bundle. Available: \(available)")
        }
        guard let main = found.first(where: { $0.kind == .executable }) ?? found.first else {
            throw BinaryLoadError("No Mach-O executable found in \(input).")
        }
        return main.path
    }

    /// Every Mach-O in a bundle/archive (main executable + embedded frameworks
    /// and app extensions). For a plain Mach-O file, just itself. Backs
    /// `--list-binaries`.
    public static func binaries(in input: String) throws -> [BundleBinary] {
        guard let bundleDir = try bundleDirectory(for: input) else {
            return [BundleBinary(name: (input as NSString).lastPathComponent, path: input, kind: .executable)]
        }
        return try bundleBinaries(inResolvedBundle: bundleDir)
    }

    // MARK: - Internals

    /// The bundle directory to inspect: unzips an `.ipa`/`.zip` and returns its
    /// `Payload/<App>.app`, returns a `.app`/`.framework` directory as-is, or
    /// `nil` for a plain file.
    private static func bundleDirectory(for input: String) throws -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: input, isDirectory: &isDir) else {
            throw BinaryLoadError("Not found: \(input)")
        }
        let lower = input.lowercased()

        if !isDir.boolValue, lower.hasSuffix(".ipa") || lower.hasSuffix(".zip") {
            let extracted = try unzip(input)
            let payload = (extracted as NSString).appendingPathComponent("Payload")
            let searchRoot = fm.fileExists(atPath: payload) ? payload : extracted
            guard let app = (try? fm.contentsOfDirectory(atPath: searchRoot))?.sorted()
                .first(where: { $0.hasSuffix(".app") }) else {
                throw BinaryLoadError("No .app bundle found inside \(input).")
            }
            return (searchRoot as NSString).appendingPathComponent(app)
        }

        if isDir.boolValue {
            if lower.hasSuffix(".app") || lower.hasSuffix(".framework") { return input }
            // A directory that carries an Info.plist is still a bundle.
            if infoPlistPath(in: input) != nil { return input }
            throw BinaryLoadError("\(input) is a directory but not an .app/.framework bundle.")
        }
        return nil // plain Mach-O file
    }

    private static func bundleBinaries(inResolvedBundle bundleDir: String) throws -> [BundleBinary] {
        var result: [BundleBinary] = []
        if let main = mainExecutable(in: bundleDir) {
            result.append(main)
        }
        for (sub, kind) in [
            ("Frameworks", BundleBinary.Kind.framework),
            ("Contents/Frameworks", .framework),
            ("PlugIns", .plugin),
            ("Contents/PlugIns", .plugin),
        ] {
            let dir = (bundleDir as NSString).appendingPathComponent(sub)
            for item in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() {
                let itemPath = (dir as NSString).appendingPathComponent(item)
                if item.hasSuffix(".framework"), let bin = frameworkBinary(itemPath) {
                    result.append(BundleBinary(name: bundleName(item), path: bin, kind: kind))
                } else if item.hasSuffix(".appex") || item.hasSuffix(".app"), let exe = mainExecutable(in: itemPath) {
                    result.append(BundleBinary(name: bundleName(item), path: exe.path, kind: .plugin))
                } else if item.hasSuffix(".dylib") {
                    result.append(BundleBinary(name: bundleName(item), path: itemPath, kind: kind))
                }
            }
        }
        return result
    }

    private static func unzip(_ archive: String) throws -> String {
        let dest = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("swiftdc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        let result = try Shell.run("/usr/bin/unzip", ["-q", "-o", archive, "-d", dest])
        guard result.status == 0 else {
            throw BinaryLoadError("Failed to unzip \(archive): \(result.stderr.isEmpty ? result.stdout : result.stderr)")
        }
        return dest
    }

    /// `CFBundleExecutable` from the bundle's `Info.plist`, resolved to the
    /// binary on disk (iOS layout `<bundle>/<exec>`, macOS `Contents/MacOS/<exec>`).
    private static func mainExecutable(in bundleDir: String) -> BundleBinary? {
        guard let plistPath = infoPlistPath(in: bundleDir),
              let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let exec = plist["CFBundleExecutable"] as? String else { return nil }
        for relative in [exec, "Contents/MacOS/\(exec)"] {
            let path = (bundleDir as NSString).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: path) {
                return BundleBinary(name: exec, path: path, kind: .executable)
            }
        }
        return nil
    }

    private static func infoPlistPath(in bundleDir: String) -> String? {
        for relative in ["Info.plist", "Contents/Info.plist"] {
            let path = (bundleDir as NSString).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private static func frameworkBinary(_ frameworkDir: String) -> String? {
        let name = bundleName((frameworkDir as NSString).lastPathComponent)
        for relative in [name, "Versions/Current/\(name)", "Versions/A/\(name)"] {
            let path = (frameworkDir as NSString).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private static func bundleName(_ item: String) -> String {
        ((item as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
