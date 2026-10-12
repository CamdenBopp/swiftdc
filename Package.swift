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
        // Pinned to 0.22.0 (was 0.19.0, before that 0.12.0). Each bump followed
        // swiftdc's own priority ladder, so upstream's fixes are our fixes:
        //   Soundness. 0.16.0 closed four silent wrong-result paths (opaque types
        //   printing illegal Swift, a multi-payload enum cache falling back to a
        //   wrong layout, reference-storage fields sized a word too narrow, first-hit
        //   dyld-cache image matches). 0.19.0 attributes a class vtable slot by its
        //   own method-descriptor symbol (SwiftUICore's `Symbol not found` count
        //   went 358 to 0). 0.21.0 names a type declared in another module's
        //   extension through the extended type, and builds class vtable members
        //   from their method descriptors, so a main executable's vtable slots are
        //   named. 0.22.0 reads an optional-returning accessor at the field's own
        //   width and lays out Swift 6.4's raw-layout and Builtin.Borrow storage.
        //   Completeness. 0.16.0 makes legacy LC_DYLD_INFO binaries parse at all;
        //   0.21.0 prints `@objc(Name)` on classes renamed for the ObjC runtime
        //   and recovers their field offsets; 0.22.0 reads the ObjC classes a
        //   simulator runtime binds to itself.
        //   Memory/perf. 0.16.0's NodeStore migration cut steady-state memory from
        //   842 MB to 262 MB across five system images; 0.22.0 opens the system
        //   dyld cache once per process and builds each sub-cache once.
        // Exact-pinned, matching this project's reproducibility intent. Bumping it is
        // a deliberate change, not a floating one: 0.20.0 brought swift-capstone
        // (Capstone 6 built from source) into the graph, which is why swiftdc's own
        // decoder links the same `capstone` package below rather than Homebrew's
        // libcapstone 5; 0.22.0 raised the swift-demangling floor to 0.7.1 and
        // MachOKit's to 0.54.101 (see below).
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection",
            exact: "0.22.0"
        ),
        // MachOKit is the Mach-O container parser MachOSwiftSection is built on.
        // It is NOT re-exported, so we depend on the same identity directly to name
        // `MachOFile` / `loadFromFile` without a package-identity conflict.
        //
        // INTERIM FORK: upstream 0.54.101 plus two changes:
        //   1. Memoized negative result of `MachOFile.cache` (as 07d7633 was on
        //      0.52.102; upstream MxIris-Reverse-Engineering/MachOKit#1 closed
        //      unmerged). Without it a standalone binary re-opens and maps itself
        //      as a would-be dyld cache on every `cache` access, which 0.22's
        //      class dumper makes once per relative pointer. Memoized: layout
        //      69.9s -> 4.4s, dump 168s -> 77s, interface 240s -> 74s.
        //   2. 64-bit fat header support (cherry-picked p-x9 #340): fat_arch_64
        //      entries were read with the 20-byte 32-bit layout, truncating
        //      offsets >= 4 GiB. A two-slice file with arm64 past 4 GiB reported
        //      "Available: x86_64, x86_64".
        // As the root package this revision overrides the transitive range;
        // return to an upstream version pin once both fixes ship.
        .package(
            url: "https://github.com/CamdenBopp/MachOKit.git",
            revision: "4076fdaa526857d62217f28e76f3f2a92eb4b6d6"
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
            "0.7.1" ..< "0.8.0"
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
        // Capstone 6, compiled from source by MxIris's SwiftPM packaging of
        // capstone. This is the same package MachOSwiftSection 0.20+ links through
        // swift-capstone (SwiftDump -> SwiftThunkAnalysis -> Capstone), so the
        // in-process ARM64 decoder uses the one copy the process already carries.
        // It replaced the Homebrew libcapstone 5 system library: two Capstones in
        // one module graph fail to compile (both clang modules define `cs_insn`),
        // and would otherwise link one C symbol table against the other's headers.
        // Only the AARCH64 backend is enabled, matching MachOSwiftSection's trait.
        .package(
            url: "https://github.com/MxIris-Reverse-Engineering/capstone",
            from: "6.0.100",
            traits: [.trait(name: "AARCH64")]
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
        // Homebrew-installed OpenSSL (`brew install openssl@3`), surfaced via its
        // pkg-config file.
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
                .product(name: "Ccapstone", package: "capstone"),
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
                // Payload-enum case projection: `StaticLayoutCalculator`
                // (SwiftLayout) returns an `EnumLayoutCalculator.LayoutResult`
                // whose `EnumCaseProjection` type is vended here. Used to name a
                // returned/compared payload-enum *empty* case ONLY when its byte
                // pattern is statically resolved (`.exactBytes`) — the
                // extra-inhabitant-dependent cases stay declined, since only the
                // in-process runtime projector can resolve those.
                .product(name: "SwiftInspection", package: "MachOSwiftSection"),
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
