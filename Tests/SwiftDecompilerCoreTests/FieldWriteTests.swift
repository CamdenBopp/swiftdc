import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A field write rendered the first register a store wrote as the field's
/// value, also when the store covered only part of the field or filled a
/// two-word field with one `stp` (`fieldwrites.swift`, -O): `name = "a  b"`
/// rendered `self.name = 0x62202061`, the String's low word; a large
/// literal rendered its count and flags; and `pair.a = x` rendered
/// `self.pair = arg0`. A part is now written to its byte range, a String's
/// two words are shown only when they spell a literal, and words read from
/// the object's own fields name the range they came from.
@Test func aFieldWriteShowsOnlyWhatTheStoreProvesIfPresent() async throws {
    let path = "Fixtures/Sample/libFieldWrites.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let expected: [String: String] = [
        "FieldWrites.FieldWrites.rename() -> ()": "self.name = \"a  b\"",
        "FieldWrites.FieldWrites.retitle() -> ()": "self.name = \"a literal past fifteen bytes\"",
        "FieldWrites.FieldWrites.relabel(Swift.String) -> ()": "self.name = …",
        "FieldWrites.FieldWrites.setHalf(Swift.Int) -> ()": "self.pair[0..<8] = arg0",
        // Both words read from one field of the same size are that field.
        "FieldWrites.FieldWrites.collapse() -> ()": "self.end = self.start",
        // Copied through a stack temporary in q registers: not followed.
        "FieldWrites.FieldWrites.mirror() -> ()": "self.back = …",
        "FieldWrites.FieldWrites.copyFirst() -> ()": "self.back[0..<8] = self.front[0..<8]",
        // Every byte of the field zeroed.
        "FieldWrites.FieldWrites.clear() -> ()": "self.start = 0",
    ]
    for (name, statement) in expected.sorted(by: { $0.key < $1.key }) {
        let function = try #require(functions.first { $0.displayName == name }, "no \(name)")
        for text in [function.renderPseudo(), function.renderStructured()] {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(lines.contains(statement), "\(name):\n\(text)")
        }
    }
}

/// One 16-byte register copies a struct ivar into another
/// (`objc_field_copy.m`, -O2): the store's one value is both words of
/// `_current`, which names the write.
@Test func aWideRegisterCopyOfAFieldNamesItsSourceIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCFieldCopy.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let function = try #require(functions.first { $0.displayName == "-[SDFieldCopy save]" })
    let lines = function.renderPseudo().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(lines.contains("self->_saved = self->_current"), "\(lines)")
}

/// A load of part of a field named the whole field: `fieldwrites.swift`'s
/// `secondOfPair` (`ldr x0, [x20, #0x28]`, pair.b) rendered `return
/// self.pair`, and Chess's one-byte read deep in a board ivar
/// `self->fCurPos`. The read names its byte range, from the width every load
/// of that offset in the function agrees on; `objc_field_copy.m`'s `mixed`
/// (-O0) loads one offset as a byte and as a word, so the value shows only
/// where it starts, and each load's note shows its own range.
@Test func aPartialFieldReadNamesItsRangeIfPresent() async throws {
    let swiftPath = "Fixtures/Sample/libFieldWrites.dylib"
    let objcPath = "Fixtures/Sample/libObjCFieldCopy.O0.dylib"
    guard FileManager.default.fileExists(atPath: swiftPath), FileManager.default.fileExists(atPath: objcPath)
    else { return }
    let swift = try await withStableDependencies { try await Disassembler().disassemble(path: swiftPath) }
    let second = try #require(swift.first { $0.displayName == "FieldWrites.FieldWrites.secondOfPair() -> Swift.Int" })
    #expect(second.renderPseudo().contains("return self.pair[8..<16]"), Comment(rawValue: second.renderPseudo()))
    let objc = try await withStableDependencies { try await Disassembler().disassemble(path: objcPath) }
    let mixed = try #require(objc.first { $0.displayName == "-[SDFieldCopy mixed]" })
    #expect(mixed.renderPseudo().contains("return ((self->_pair[8...] & 0xffffffff) + self->_pair[8...])"),
            Comment(rawValue: mixed.renderPseudo()))
    let listing = mixed.render()
    #expect(listing.contains("; self->_pair[8..<9]") && listing.contains("; self->_pair[8..<16]"),
            Comment(rawValue: listing))
}
