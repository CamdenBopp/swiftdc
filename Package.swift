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
        // Pinned to 0.19.0 (was 0.12.0). Seven upstream releases moved this engine
        // squarely along swiftdc's own priority ladder, so its fixes are our fixes:
        //   Soundness. 0.16.0 closed four silent wrong-result paths (opaque types
        //   printing illegal Swift, a multi-payload enum cache falling back to a
        //   wrong layout, reference-storage fields sized a word too narrow, first-hit
        //   dyld-cache image matches). 0.19.0 attributes a class vtable slot by its
        //   own method-descriptor symbol instead of the symbols at its implementation
        //   address, which identical code folding makes ambiguous — SwiftUICore's
        //   `Symbol not found` count went 358 to 0 with no line regressing to a
        //   `sub_` address.
        //   Completeness. 0.16.0 makes legacy LC_DYLD_INFO binaries (pre-macOS 12,
        //   no chained fixups) parse at all; SwiftUI on the iOS 15.5 simulator went
        //   from 139 to 81,157 interface lines. Exactly the near-empty-but-plausible
        //   result the empty-result rule exists to catch.
        //   Memory/perf. 0.16.0's NodeStore migration cut steady-state memory from
        //   842 MB to 262 MB across five system images; 0.19.0's task-executor change
        //   makes dump/interface ~15-20% faster.
        // Exact-pinned, matching this project's reproducibility intent. Bumping it is
        // a deliberate change, not a floating one: 0.16.0 is a breaking release, and
        // it raises the swift-demangling floor to 0.6.3 (see below).
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection",
            exact: "0.19.0"
        ),
        // MachOKit is the Mach-O container parser MachOSwiftSection is built on.
        // It is NOT re-exported, so we depend on the same fork/identity directly
        // to name `MachOFile` / `loadFromFile` without a package-identity conflict.
        //
        // Floor raised to 0.52.101 to match what MachOSwiftSection 0.19.0 requires
        // (0.52.101 ..< 0.53.0). The 0.51.x line was already mostly performance work
        // on paths this tool leans on hard — chained-fixup caching (every GOT bind and
        // selref resolution), dyld subcache file-handle reuse, cached cache-mapping
        // lookups — and 0.52.101 adds an ObjC-header-info subcache-lookup fix for split
        // dyld shared caches.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOKit.git",
            from: "0.52.101"
        ),
        // `Semantic` provides SemanticString, the return type of SwiftDump's
        // `.dump(...)`. Moves in lockstep with MachOSwiftSection: 0.15.0 raised its
        // floor to 0.3.0 (the transformer modules were re-homed across the two
        // packages), so a lower pin here fails resolution outright. `from:` rather
        // than `exact:` because MachOObjCSection also depends on it directly and two
        // exact pins on one package deadlock.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-semantic-string",
            from: "0.3.0"
        ),
        // Declared directly so our core can use the `Demangling` product for symbol
        // annotation (Disassembler's `demangleAsNode` + `Node.print(using:)`).
        // Bounded to 0.6.3 ..< 0.7.0: MachOSwiftSection 0.19.0 requires >= 0.6.3, and
        // the 0.5.0 reshape of `NodePrinterTarget` (autoclosure witnesses, no default
        // implementations, `Node` no longer `Codable`) makes an open upper bound
        // unsafe. This is the pin that made a blind `swift package update` dangerous
        // while MachOSwiftSection stayed at 0.12.0; both move together now.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-demangling",
            "0.6.3" ..< "0.7.0"
        ),
        // Objective-C runtime metadata (classes/protocols/categories) for real
        // Swift+ObjC app binaries. Same fork URLs MachOSwiftSection resolves to,
        // so there's no package-identity conflict. ObjCDump renders the
        // `@interface … @end` headers (with decoded type encodings).
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOObjCSection.git",
            from: "0.8.105"
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
                // 0.12.0 modularized MachOSwiftSection; the render configuration
                // moved out of SwiftDump into its own module, which SwiftDump
                // depends on but does not re-export.
                .product(name: "SwiftDeclarationRendering", package: "MachOSwiftSection"),
                // Full Swift-interface reconstruction (`.swiftinterface`-style),
                // higher fidelity than SwiftDump's declaration listing.
                .product(name: "SwiftInterface", package: "MachOSwiftSection"),
                // Static type layout: stored-property names, types, and byte
                // OFFSETS, computed offline from metadata. This is what turns
                // `ldr x8, [x0, #0x10]` into `self.name`, and it is the one
                // capability Ghidra structurally cannot have. 100% public API —
                // no SPI, no `package` walls.
                .product(name: "SwiftLayout", package: "MachOSwiftSection"),
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
                // SmokeTests. As of MachOSwiftSection 0.16.0's self-contained ABI
                // layer, the symbol index is no longer re-exported through the
                // MachOSwiftSection umbrella; `MachOFoundation` is the library
                // product that re-exports MachOSymbols, whose `@_spi(Internals)`
                // surface vends `SymbolIndexStore` and `\.symbolIndexStore`.
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "MachOFoundation", package: "MachOSwiftSection"),
            ]
        ),
    ]
)
