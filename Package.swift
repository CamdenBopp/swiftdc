// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swiftdc",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SwiftDecompilerCore", targets: ["SwiftDecompilerCore"]),
        .executable(name: "swiftdc", targets: ["swiftdc"]),
    ],
    dependencies: [
        // Pinned to a specific `main` commit, NOT a release tag. The latest tag
        // (0.9.1) does not compile under Swift 6.3: SwiftDump's async dumpers call
        // `Node.print()`, which has both sync and async overloads in
        // swift-demangling >=0.3.0, and Swift prefers the async overload in an
        // async context — so 0.9.1's missing `await` is a hard error. This `main`
        // commit (toward 0.10.0) added the `await`s and is the Swift 6.3-compatible
        // combo with async demangling 0.4.x. Frozen to a revision so `swift package
        // update` can't drift us onto an untested commit.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection",
            revision: "8b34efb02340298e3a2cee69541f99a8e701a719"
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
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0"
        ),
    ],
    targets: [
        .target(
            name: "SwiftDecompilerCore",
            dependencies: [
                .product(name: "MachOKit", package: "MachOKit"),
                .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
                .product(name: "SwiftDump", package: "MachOSwiftSection"),
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "Demangling", package: "swift-demangling"),
            ]
        ),
        .executableTarget(
            name: "swiftdc",
            dependencies: [
                "SwiftDecompilerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SwiftDecompilerCoreTests",
            dependencies: ["SwiftDecompilerCore"]
        ),
    ]
)
