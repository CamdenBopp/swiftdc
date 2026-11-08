import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDump
@testable import SwiftDecompilerCore

/// The iOS simulator runtime, which ships the binary that exposed this. Guarded
/// like the other host-dependent checks so a machine without it stays green.
private func simulatorAXBundle() -> String? {
    let base = "/Library/Developer/CoreSimulator/Volumes"
    guard let volumes = try? FileManager.default.contentsOfDirectory(atPath: base) else { return nil }
    for volume in volumes.sorted() {
        let runtimes = "\(base)/\(volume)/Library/Developer/CoreSimulator/Profiles/Runtimes"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: runtimes) else { continue }
        for entry in entries where entry.hasSuffix(".simruntime") {
            let path = "\(runtimes)/\(entry)/Contents/Resources/RuntimeRoot"
                + "/System/Library/AccessibilityBundles/UIKit.axbundle/UIKit"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
    }
    return nil
}

/// Building the ObjC index must not take down the process.
///
/// `MachOObjCSection` reads a class's method/property/protocol lists through its
/// shared-cache "relative list list" path whenever the low bit of the
/// corresponding RO pointer is set. Those fields hold the RAW on-disk value, and
/// under chained fixups that is a fixup encoding rather than a pointer — so
/// outside a shared cache the bit is arbitrary. When it is set, the library
/// reads an element count out of a misinterpreted header and `try!`s the
/// resulting out-of-bounds read. That is a fatalError: it cannot be caught, and
/// `info(in:)` returning an Optional gives no protection at all.
///
/// Under MachOObjCSection 0.8.105 the marker was set on a large fraction of
/// this binary's classes, and the guard skipped them: `objc` printed 6 of its
/// 853 classes. The marker was never real. The simulator's frameworks are
/// linked `-interposable`, so every class-list entry that points at an exported
/// class holds a bind to the image itself, and 0.8.105 resolved only rebases,
/// so those classes were read from the wrong place and their "RO data" was
/// whatever bytes happened to be there. MachOObjCSection 0.8.110 resolves the
/// self-bind, every class reads from its real address, and no class carries
/// the marker. The guard stays (a genuine non-cache marker would still be a
/// trap), but on this binary it must now filter nothing, and the index must
/// hold every class the class list declares.
@Test func buildsObjCIndexWithoutTrappingOnSpuriousCacheMarkers() throws {
    guard let path = simulatorAXBundle() else { return }
    // Older simruntimes ship a fat x86_64/arm64 slice; newer ones are thin.
    guard let machO = (try? BinaryLoader.load(path: path))
        ?? (try? BinaryLoader.load(path: path, architecture: "arm64"))
    else { return }

    #expect(machO.cache == nil)
    let classes = machO.objc.classes64 ?? []
    #expect(classes.count > 100, "the axbundle declares hundreds of classes")
    let marked = classes.filter { ObjCMetadataSnapshot.readsCacheOnlyRelativeLists(machO, $0) }
    #expect(marked.isEmpty, "self-bound class slots must read as real classes, not as cache markers")

    // The thing that used to trap.
    let snapshot = ObjCMetadataSnapshot.build(in: machO)
    _ = ObjCMetadataIndex.build(in: machO)

    // Every declared class is in the index: the guard skipped none.
    #expect(snapshot.classes.count == classes.count)
    // Categories still resolve — the guard is targeted, not a blanket bail-out.
    #expect(!snapshot.categories.isEmpty)
}

/// The guard must cost nothing on binaries that already worked: it fires only on
/// the marker, and a well-formed non-cache binary does not set it.
@Test func cacheMarkerGuardDoesNotSkipHealthyClasses() throws {
    for path in [
        "/System/Applications/Stickies.app/Contents/MacOS/Stickies",
        "Fixtures/Sample/libSample.stripped.dylib",
    ] where FileManager.default.fileExists(atPath: path) {
        guard let machO = try? BinaryLoader.load(path: path) else { continue }
        let classes = machO.objc.classes64 ?? []
        guard !classes.isEmpty else { continue }
        let skipped = classes.filter { ObjCMetadataSnapshot.readsCacheOnlyRelativeLists(machO, $0) }
        #expect(skipped.isEmpty, "guard must not skip classes in \(path)")
    }
}

/// Inside a real shared cache the marker is meaningful and must be honoured.
@Test func cacheMarkerGuardIsDisabledForCacheImages() throws {
    guard let machO = try? BinaryLoader.loadMachO(path: nil, image: "CoreLocation") else { return }
    #expect(machO.cache != nil)
    let classes = machO.objc.classes64 ?? []
    guard !classes.isEmpty else { return }
    #expect(classes.allSatisfy { !ObjCMetadataSnapshot.readsCacheOnlyRelativeLists(machO, $0) })
}

/// An ivar whose offset is computed at load time has no offset in the image.
/// ObjCDump reads its zero-fill offset variable anyway, through a `try!`: past
/// the end of the file that trapped (`objc` and `xrefs` on Prime Video), and
/// here, inside the file, it reads padding as offset 0. The snapshot records
/// such an ivar at `runtimeIvarOffset`, which never becomes a field-map entry,
/// and otherwise matches ObjCDump field for field.
@Test func recordsLoadTimeIvarOffsetsAsRuntimeIfPresent() throws {
    let path = "Fixtures/Sample/libRuntimeIvars.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let snapshot = ObjCMetadataSnapshot.build(in: machO)
    func info(_ suffix: String) -> ObjCClassInfo? {
        snapshot.classes.first { $0.name.hasSuffix(suffix) }
    }
    guard let stamped = info("7Stamped"), let plain = info("5Plain") else {
        Issue.record("fixture classes missing: \(snapshot.classes.map(\.name))")
        return
    }
    #expect(stamped.ivars.map(\.name) == ["when", "count", "label"])
    #expect(stamped.ivars.allSatisfy { $0.offset == ObjCMetadataSnapshot.runtimeIvarOffset },
            "\(stamped.ivars.map { ($0.name, $0.offset) })")
    #expect(plain.ivars.map(\.offset) == [16, 24])

    // The rebuilt info is ObjCDump's own except for the offsets it declined.
    let raw = (machO.objc.classes64 ?? []).first { $0.info(in: machO)?.name == stamped.name }
    guard let library = raw?.info(in: machO) else { Issue.record("no library info"); return }
    func withoutOffsets(_ info: ObjCClassInfo) -> ObjCClassInfo {
        ObjCClassInfo(
            name: info.name, version: info.version, imageName: info.imageName,
            instanceSize: info.instanceSize, superClassName: info.superClassName,
            protocols: info.protocols,
            ivars: info.ivars.map { ObjCIvarInfo(name: $0.name, typeEncoding: $0.typeEncoding, offset: 0) },
            classProperties: info.classProperties, properties: info.properties,
            classMethods: info.classMethods, methods: info.methods
        )
    }
    #expect(withoutOffsets(stamped) == withoutOffsets(library))
    #expect(library.ivars.allSatisfy { $0.offset == 0 }, "the library reads zero-fill padding")
}
