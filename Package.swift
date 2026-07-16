// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swiftdc",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SwiftDecompilerCore", targets: ["SwiftDecompilerCore"]),
        .library(name: "MobileDevice", targets: ["MobileDevice"]),
        .executable(name: "swiftdc", targets: ["swiftdc"]),
    ],
    dependencies: [
        // Pinned to the 0.12.0-beta.3 tag's commit (da7abcf, 2026-06-03), NOT a
        // release tag via `from:`. History: older tags like 0.9.1 do not compile
        // under Swift 6.3 — SwiftDump's async dumpers call `Node.print()`, which has
        // both sync and async overloads in swift-demangling >=0.3.0, and Swift
        // prefers the async overload in an async context, so 0.9.1's missing `await`
        // is a hard error. beta.3 carries those `await` fixes and pairs with async
        // demangling 0.4.x. It is a content-superset of the previous pin (8b34efb on
        // `main`) plus additive June commits: public SharedCache API, resilient-
        // superclass dumping, associated-type + opaque-type symbolic-ref fixes.
        // Frozen to a revision so `swift package update` can't drift us onto an
        // untested commit; re-verify the build under Swift 6.3 before moving it.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection",
            revision: "da7abcf91fc9a1208f53b7314aad288da3dafb14"
        ),
        // MachOKit is the Mach-O container parser MachOSwiftSection is built on.
        // It is NOT re-exported, so we depend on the same fork/identity directly
        // to name `MachOFile` / `loadFromFile` without a package-identity conflict.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOKit.git",
            from: "0.50.100"
        ),
        // `Semantic` provides SemanticString, the return type of SwiftDump's
        // `.dump(...)`. Pinned to match MachOSwiftSection's exact requirement.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-semantic-string",
            exact: "0.1.1"
        ),
        // Declared directly so our core can use the `Demangling` product for
        // symbol annotation. `from: 0.4.0` provides the async `print` overload
        // that MachOSwiftSection `main` now `await`s.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-demangling",
            from: "0.4.0"
        ),
        // Objective-C runtime metadata (classes/protocols/categories) for real
        // Swift+ObjC app binaries. Same fork URLs MachOSwiftSection resolves to,
        // so there's no package-identity conflict. ObjCDump renders the
        // `@interface … @end` headers (with decoded type encodings).
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOObjCSection.git",
            from: "0.7.103"
        ),
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-objc-dump",
            from: "0.8.101"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0"
        ),
        // Test-only. Lets the test target import `Dependencies` and pre-seed
        // `\.symbolIndexStore` into DependencyValues storage, which makes
        // swift-dependencies return it without building the per-test cache key
        // that segfaults under swift-testing on this toolchain (see SmokeTests).
        // Already resolved transitively via MachOSwiftSection.
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.9.0"
        ),
    ],
    targets: [
        // Homebrew-installed Capstone (`brew install capstone`), surfaced via its
        // pkg-config file. Used for structured in-process ARM64 decoding.
        .systemLibrary(
            name: "CCapstone",
            pkgConfig: "capstone",
            providers: [.brew(["capstone"])]
        ),
        // Homebrew-installed OpenSSL (`brew install openssl@3`), same
        // pkg-config pattern as CCapstone above.
        //
        // Needed because lockdown upgrades a live plaintext socket to TLS
        // mid-stream, presenting a client certificate that exists only as a
        // detached PEM cert+key in the usbmux pair record. Network.framework
        // can't upgrade an existing connection, and SecureTransport needs a
        // `SecIdentity`, which can't be built from a detached cert+key without
        // a keychain round-trip or private API. OpenSSL's SSL_set_fd takes the
        // fd directly — the approach libimobiledevice uses.
        .systemLibrary(
            name: "COpenSSL",
            pkgConfig: "openssl",
            providers: [.brew(["openssl@3"])]
        ),
        // usbmux / lockdown / installation_proxy: talking to physical iOS
        // devices. Deliberately separate from SwiftDecompilerCore so the
        // decompiler itself stays free of an OpenSSL dependency.
        .target(
            name: "MobileDevice",
            dependencies: ["COpenSSL"]
        ),
        .target(
            name: "SwiftDecompilerCore",
            dependencies: [
                "CCapstone",
                .product(name: "MachOKit", package: "MachOKit"),
                .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
                .product(name: "SwiftDump", package: "MachOSwiftSection"),
                // Full Swift-interface reconstruction (`.swiftinterface`-style),
                // higher fidelity than SwiftDump's declaration listing.
                .product(name: "SwiftInterface", package: "MachOSwiftSection"),
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "Demangling", package: "swift-demangling"),
                .product(name: "MachOObjCSection", package: "MachOObjCSection"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
        .executableTarget(
            name: "swiftdc",
            dependencies: [
                "SwiftDecompilerCore",
                "MobileDevice",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SwiftDecompilerCoreTests",
            dependencies: [
                "SwiftDecompilerCore",
                // For the swift-testing dependency-resolution workaround in
                // SmokeTests. MachOSwiftSection re-exports MachOSymbols, whose
                // `@_spi(Internals)` surface vends `SymbolIndexStore`.
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
            ]
        ),
    ]
)
