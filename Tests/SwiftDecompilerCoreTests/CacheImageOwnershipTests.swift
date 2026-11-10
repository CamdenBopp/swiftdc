import Testing
import Foundation
import MachOKit
import MachOSwiftSection
@testable import SwiftDecompilerCore

/// A shared cache resolves the binds a file leaves as imports, so a reference
/// out of an image lands in another image's records. libswiftObservation's
/// `__swift5_types` holds indirect records for the prespecialized `Optional`
/// and `Dictionary`: on disk the cell is a bind and reads as nothing, in the
/// cache the image listed both as its own types. Its conformances printed
/// another image's requirement descriptors as `sub_` functions.
private let image = "/usr/lib/swift/libswiftObservation.dylib"

/// The host's cache, then every simulator runtime's. Each that holds the image
/// is checked; a host with none has nothing to prove here.
private func observationImages() -> [MachOFile] {
    let simulators = "/Library/Developer/CoreSimulator/Caches/dyld"
    var caches: [String?] = [nil]
    for build in (try? FileManager.default.contentsOfDirectory(atPath: simulators)) ?? [] {
        for runtime in (try? FileManager.default.contentsOfDirectory(atPath: "\(simulators)/\(build)")) ?? [] {
            let cache = "\(simulators)/\(build)/\(runtime)/dyld_sim_shared_cache_arm64"
            if FileManager.default.fileExists(atPath: cache) { caches.append(cache) }
        }
    }
    return caches.compactMap { try? BinaryLoader.loadFromDyldCache(cachePath: $0, selector: .path(image)) }
}

@Suite struct CacheImageOwnershipTests {
    @Test func anExtentHoldsItsSegmentsAndNothingElse() {
        let extent = ImageExtent(segments: [0x1_8000_0000 ..< 0x1_8000_1000, 0x1_9000_0000 ..< 0x1_9000_0100],
                                 regionStart: 0x1_8000_0000)
        #expect(extent.contains(address: 0x1_8000_0000))
        #expect(extent.contains(address: 0x1_9000_00FF))
        #expect(!extent.contains(address: 0x1_8000_1000))
        #expect(extent.contains(cacheOffset: 0x10))
        #expect(!extent.contains(cacheOffset: 0x1000))
        #expect(!extent.contains(cacheOffset: -1))
    }

    @Test func aStandaloneFileHasNoExtentIfPresent() throws {
        let fixture = "Fixtures/Sample/libStrippedFold.dylib"
        guard FileManager.default.fileExists(atPath: fixture) else { return }
        let machO = try BinaryLoader.load(path: fixture)
        #expect(ImageExtent(cacheImage: machO) == nil)
        // So its own records all stand.
        #expect(UnrecordedTypes.ownRecords(in: machO)?.count == (try machO.swift.types).count)
    }

    @Test func removingABlockTakesItsLinesOnly() {
        let text = "a {\n}\nenum E {\n    case x\n}\nb {\n}\n"
        #expect(InterfaceReconstructor.removing("enum E {\n    case x\n}", from: text) == "a {\n}\nb {\n}\n")
        // Not a whole run of lines: left alone.
        #expect(InterfaceReconstructor.removing("num E {", from: text) == text)
        #expect(InterfaceReconstructor.removing("", from: text) == text)
    }

    @Test func aCacheImageListsOnlyItsOwnTypesIfAvailable() async throws {
        for machO in observationImages() {
            let names = UnrecordedTypes.all(in: machO).map { SwiftDeclarationDumper.displayName(of: $0, in: machO) }
            #expect(!names.isEmpty)
            #expect(!names.contains { $0.hasPrefix("Swift.") }, "\(names)")
            let dump = await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.types]) }
            #expect(!dump.contains("Swift.Optional<A>:") && !dump.contains("struct Swift.Dictionary<A, B>"), Comment(rawValue: String(dump.prefix(800))))
            let maps = try FieldMapBuilder.build(in: machO)
            #expect(!maps.keys.contains { $0 == "Dictionary" || $0 == "Swift.Dictionary" }, "\(maps.keys.sorted())")
        }
    }

    @Test func aCacheImagesInterfaceDeclaresOnlyItsOwnTypesIfAvailable() async throws {
        for machO in observationImages() {
            let text = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(machO) }
            #expect(text.contains("struct ObservationRegistrar"), Comment(rawValue: String(text.prefix(800))))
            #expect(!text.contains("\nenum Optional<A>"), Comment(rawValue: String(text.prefix(800))))
            #expect(!text.contains("\nstruct Dictionary<A, B>"), Comment(rawValue: String(text.prefix(800))))
        }
    }

    /// `associated conformance descriptor` is data in libswiftCore.
    @Test func aRequirementInAnotherImageIsNamedNotPrintedAsAFunctionIfAvailable() async throws {
        for machO in observationImages() {
            let text = await withStableDependencies { await SwiftDeclarationDumper().dump(machO, sections: [.conformances]) }
            guard text.contains("Swift.Identifiable {") else { continue }
            #expect(text.contains("associated conformance descriptor for Swift.Identifiable"), Comment(rawValue: String(text.prefix(1500))))
            #expect(text.contains("associated type descriptor for Swift.Identifiable.ID"), Comment(rawValue: String(text.prefix(1500))))
            #expect(!text.contains("\n    sub_"), Comment(rawValue: String(text.prefix(1500))))
        }
    }
}
