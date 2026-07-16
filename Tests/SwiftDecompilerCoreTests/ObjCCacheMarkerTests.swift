import Testing
import Foundation
import MachOKit
import MachOObjCSection
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
/// This is a regression test in the strongest sense: if the guard is removed,
/// this does not fail — it kills the test runner.
@Test func buildsObjCIndexWithoutTrappingOnSpuriousCacheMarkers() throws {
    guard let path = simulatorAXBundle() else { return }
    // Older simruntimes ship a fat x86_64/arm64 slice; newer ones are thin.
    guard let machO = (try? BinaryLoader.load(path: path))
        ?? (try? BinaryLoader.load(path: path, architecture: "arm64"))
    else { return }

    // The binary really is the hazard: not a cache image, yet carrying the
    // cache-only marker on a large fraction of its classes.
    #expect(machO.cache == nil)
    let classes = machO.objc.classes64 ?? []
    let marked = classes.filter { ObjCMetadataSnapshot.readsCacheOnlyRelativeLists(machO, $0) }
    #expect(!marked.isEmpty, "expected spurious cache markers in the simulator axbundle")

    // The thing that used to trap.
    let snapshot = ObjCMetadataSnapshot.build(in: machO)
    _ = ObjCMetadataIndex.build(in: machO)

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
