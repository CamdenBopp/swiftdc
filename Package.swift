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
        // Pinned to 0.24.0 (was 0.22.0, 0.19.0, 0.12.0). Each bump followed
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
        //   0.24.0 prints a protocol requirement's generic right-hand side as
        //   itself (0.22 printed `Element == Self.Payload` for `== Event<Payload>`,
        //   libProtocolRHS), and with MachOObjCSection 0.8.205 reads cache
        //   images' bare-colon Swift selectors (`enumerateRangesIn::`, printed
        //   `enumerateRangesIn:` before).
        //   Completeness. 0.23.0 names a local type by its declaring function when
        //   the binary records it (Apple's cache images), and the ObjC properties
        //   and protocols of cache classes, which 0.22 dropped. 0.16.0 makes legacy LC_DYLD_INFO binaries parse at all;
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
        // MachOKit's to 0.54.101 (see below). 0.24.0 moves to swift-capstone 7.0.0,
        // a rewrite of the Swift wrapper only: the C library under it is still
        // Capstone 6 (6.0.101), whose changes are an x86/Alpha fix, CS_OPT_OFF
        // clearing detail, and cs_disasm_iter flags, none of which swiftdc's
        // cs_disasm decoder reaches (listing and JSON of 192 fixtures:
        // byte-identical).
        // INTERIM FORK: 0.24.0 plus two changes, branch
        // swiftdc-interim/0.24.0-interface (vm-relative, then interface on top).
        // A relative pointer's delta counts in memory, so
        // `MachOContext.advanceAddress` goes file offset -> address -> file
        // offset through each end's own segment, and a target with no file
        // bytes reads as an error; upstream adds the delta to the file offset,
        // which misreads any image whose segments lie at different slides. And
        // six `interface` soundness commits (constrained existentials printed
        // as themselves, inferred attributes marked, a hand-written `_a` not
        // hidden, an `@objc` thunk marking only its own member, a case count
        // where no record names cases, `let`/`var` read off a global's section,
        // a vtable offset under a resilient superclass called relative). Return
        // to an upstream version pin once these ship there; see
        // docs/PRODUCTION-READINESS.md.
        .package(
            url: "https://github.com/CamdenBopp/MachOSwiftSection",
            revision: "6e6db62a9a76b0444a043ac44ef7638d4def7e43"
        ),
        // INTERIM FORK: upstream 1.3.0 plus `MachOSegmentMap`, branch
        // swiftdc-interim/1.3.0-vm-relative. The file-to-memory mapping everything
        // above it resolves through, and `address(forOffset:)` through the segment
        // holding the offset. Declared so this revision overrides the transitive
        // one, and because SwiftDecompilerCore reads the map itself.
        .package(
            url: "https://github.com/CamdenBopp/MachOKitExtensions.git",
            revision: "06195c5f9d6e3a3a5fb109cbfb0b847f66cbf5eb"
        ),
        // MachOKit is the Mach-O container parser MachOSwiftSection is built on.
        // It is NOT re-exported, so we depend on the same identity directly to name
        // `MachOFile` / `loadFromFile` without a package-identity conflict.
        //
        // INTERIM FORK: upstream 0.55.100 plus two changes. Fixup chains are read
        // through the segment that starts at `segment_offset`, an offset in
        // memory, so `pointer.offset` is a file offset in every image, and
        // `fileOffset(of:)` takes a rebase target and refuses zero fill. And a
        // memoized negative
        // result of `MachOFile.cache` (as 4c4738f was on 0.54.101 and 07d7633 on
        // 0.52.102; upstream MxIris-Reverse-Engineering/MachOKit#1 closed
        // unmerged). Without it a standalone binary re-opens and maps itself as
        // a would-be dyld cache on every `cache` access, which the class dumper
        // makes once per relative pointer. Memoized on 0.54.101: layout 69.9s ->
        // 4.4s, dump 168s -> 77s, interface 240s -> 74s. The 64-bit fat header
        // fix the old fork cherry-picked (p-x9 #340) is upstream in 0.55.0,
        // line for line, and FatArch64Tests passes on it.
        // Branch swiftdc-interim/0.55.100-vm-relative, on top of
        // swiftdc-interim/0.55.100-memoize-cache.
        // As the root package this revision overrides the transitive range;
        // return to an upstream version pin once the memo ships.
        .package(
            url: "https://github.com/CamdenBopp/MachOKit.git",
            revision: "c9177864cd57339ddafef4639719f1c5d6369015"
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
            "0.7.2" ..< "0.8.0"
        ),
        // Objective-C runtime metadata (classes/protocols/categories) for real
        // Swift+ObjC app binaries. Same fork URLs MachOSwiftSection resolves to,
        // so there's no package-identity conflict. ObjCDump renders the
        // `@interface … @end` headers (with decoded type encodings). Exact:
        // 0.8.201 and later require MachOKit 0.55.100, and a `from:` range
        // resolved to 0.8.200, which lacks the selector, signed-IMP and
        // relative-method-list fixes.
        // INTERIM FORK of 0.8.205, branch swiftdc-interim/0.8.205-vm-relative: a
        // relative method list's fields through their segments. An exact pin would
        // be the upstream one; see the note above on why it is not.
        .package(
            url: "https://github.com/CamdenBopp/MachOObjCSection.git",
            revision: "3873494bec69946c707bd42847a3085972989335"
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
            from: "6.0.101",
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
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
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
