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

/// A paired load recorded one read as wide as both registers, so the value
/// in its first register named the whole field: `differenceOfPair`
/// (`ldp x8, x9, [x20, #0x20]; sub x0, x8, x9`) rendered
/// `return (self.pair - self.pair[8...])`. Each register is now its own
/// word of the field, and the String words `Dog.speak` passes from
/// `self.breed` are `self.breed[0..<8]` and `self.breed[8..<16]`.
@Test func aPairedLoadGivesEachRegisterItsWordIfPresent() async throws {
    let fieldWrites = "Fixtures/Sample/libFieldWrites.dylib"
    let sample = "Fixtures/Sample/libSample.dylib"
    guard FileManager.default.fileExists(atPath: fieldWrites), FileManager.default.fileExists(atPath: sample)
    else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: fieldWrites) }
    let difference = try #require(functions.first {
        $0.displayName == "FieldWrites.FieldWrites.differenceOfPair() -> Swift.Int"
    }).renderPseudo()
    #expect(difference.contains("return (self.pair[0..<8] - self.pair[8..<16])"), Comment(rawValue: difference))
    let dogs = try await withStableDependencies { try await Disassembler().disassemble(path: sample) }
    let speak = try #require(dogs.first { $0.displayName.hasPrefix("Sample.Dog.speak()") }).renderPseudo()
    #expect(speak.contains("self.breed[0..<8], self.breed[8..<16])"), Comment(rawValue: speak))
}

/// A paired store over two ivars that did not render as a tuple of them
/// fell through to the single-value form, which takes the first register:
/// `objc_pair_stores.m`'s `packC:` (`stp x2, x9, [x0, #0x18]`, x9 never
/// written) rendered `self->{_c, _d} = arg0`, as if `_d` took part of a.
/// Such a store shows each register's own value (see
/// `aPairStoreThatIsNoTupleIsWrittenRegisterByRegisterIfPresent`):
/// `(self->_c, self->_d) = (arg0, …)`; `setBoth:d:` keeps its tuple.
@Test func aPairStoreOverTwoFieldsClaimsNoSingleValueIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCPairStores.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }, "no \(name)").renderPseudo()
    }
    let packC = try text("-[SDPairStores packC:]")
    #expect(packC.contains("(self->_c, self->_d) = (arg0, …)"), Comment(rawValue: packC))
    let both = try text("-[SDPairStores setBoth:d:]")
    #expect(both.contains("(self->_c, self->_d) = (arg0, arg1)"), Comment(rawValue: both))
}

/// A paired store rendered as a tuple of the fields it covers whenever it
/// covered whole adjacent fields, whatever the registers' boundaries:
/// `packE:f:` (`stp x2, x3, [x0, #0x8]` over the 12-byte `_e` and the
/// 4-byte `_f`) rendered `(self->_e, self->_f) = (arg0, arg1)`, though x2
/// is only `_e`'s first 8 bytes. Each register must now fill one whole
/// field.
@Test func aPairStoreIsATupleOnlyWhenEachRegisterFillsAFieldIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCPairStores.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let packE = try #require(functions.first { $0.displayName == "-[SDPairStores packE:f:]" }).renderPseudo()
    #expect(packE.contains("self->{_e, _f} = …") && !packE.contains("(self->_e, self->_f)"), Comment(rawValue: packE))
}

/// A paired store that covered no whole field first named nothing, so it
/// was dropped: `SDPairParts setTail:b:` (`stp w2, w3, [x0, #0x10]` over
/// the last four bytes of the 12-byte `_a` and all of `_b`) rendered no
/// statement at all. Such a store is now the tuple of what each register
/// writes, and an unknown register's value is `…`.
@Test func aPairStoreThatIsNoTupleIsWrittenRegisterByRegisterIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCPairStores.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let tail = try #require(functions.first { $0.displayName == "-[SDPairParts setTail:b:]" }).renderPseudo()
    #expect(tail.contains("(self->_a[8..<12], self->_b) = ((arg0 & 0xffffffff), (arg1 & 0xffffffff))"),
            Comment(rawValue: tail))
    // A register holding a value forwarded from a store into part of a
    // field is that part, at the register's width: `FieldWrites.init`
    // stores one zeroed q0 across fields with `stp q0, q0`, and q0 is
    // `self.front[0..<16]` after the store into the 32-byte `front`.
    let writesPath = "Fixtures/Sample/libFieldWrites.dylib"
    guard FileManager.default.fileExists(atPath: writesPath) else { return }
    let writes = try await withStableDependencies { try await Disassembler().disassemble(path: writesPath) }
    let initializer = try #require(writes.first { $0.displayName.hasPrefix("FieldWrites.FieldWrites.init()") }).render()
    #expect(initializer.contains("(self.front[16..<32], self.back[0..<16]) = (self.front[0..<16], self.front[0..<16])"),
            Comment(rawValue: initializer))
}
