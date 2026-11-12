import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

/// With its type references damaged (every `__swift5_typeref` word set to
/// 0x7ffffff0), an image's interface printed its free functions alone and
/// its types vanished without a word, where `dump` names each. A type the
/// image records but the interface neither declares nor extends is now
/// named in a closing note; an intact image gets none.
@Test func aTypeTheInterfaceDropsIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let intact = try BinaryLoader.load(path: path)
    let section = try #require(intact.sections64.first { $0.sectionName == "__swift5_typeref" })
    var bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    let start = Int(section.offset), end = start + Int(section.size)
    for word in stride(from: start, to: end - 3, by: 4) {
        for (index, byte) in [UInt8(0xf0), 0xff, 0xff, 0x7f].enumerated() { bytes[word + index] = byte }
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("typeref-\(UUID().uuidString).dylib")
    try bytes.write(to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    let damaged = try BinaryLoader.load(path: copy.path)
    let note = "Recorded in this image's __swift5_types but not declared above"
    let broken = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(damaged) }
    #expect(broken.contains(note), Comment(rawValue: String(broken.suffix(600))))
    let whole = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(intact) }
    #expect(!whole.contains(note), Comment(rawValue: String(whole.suffix(600))))
    // An imported C type (`__C.timespec`) and a type outside the records
    // are not the interface's to declare.
    for control in ["Fixtures/Sample/libCStructField.dylib", "Fixtures/Sample/libUnrecordedType.dylib"]
    where FileManager.default.fileExists(atPath: control) {
        let image = try BinaryLoader.load(path: control)
        let text = try await withStableDependencies { try await InterfaceReconstructor().reconstruct(image) }
        #expect(!text.contains(note), "\(control)\n\(text.suffix(400))")
    }
}
