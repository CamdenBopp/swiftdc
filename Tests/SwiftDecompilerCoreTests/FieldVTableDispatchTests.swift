import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let fieldVTableFixtures = [
    "Fixtures/Sample/libFieldVTable.dylib",
    "Fixtures/Sample/libFieldVTable.Onone.dylib",
]

/// The oracle: `Car(Turbo()).go()` runs Turbo's override through the slot
/// Engine.start() declares, `park(9)` returns its argument, and Garage's
/// field of the other module's Engine runs that module's `coast()`.
@Test func fieldVTableCallsRunAsDocumentedIfPresent() throws {
    for path in fieldVTableFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL), Comment(rawValue: String(cString: dlerror())))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int
        for (name, expected) in [("field_vtable_go_turbo", 3), ("field_vtable_park", 9), ("field_vtable_garage", 7),
                                 ("field_vtable_run_turbo", 3), ("field_vtable_run_other", 7), ("field_vtable_borrow", 4),
                                 ("field_vtable_drive_held", 3)] {
            let entry = try #require(dlsym(library, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
    }
}

/// A call through a vtable slot of an object held in a field of self is
/// named for the field's declared class (`FieldVTable.Engine.start`). A
/// field of another module's class with the same simple name is not: its
/// slot 0x68 is `coast()` there, and this image's Engine has its `rpm`
/// modify accessor at 0x68.
@Test func aVTableCallOnAFieldIsNamedForTheFieldsClassIfPresent() async throws {
    for path in fieldVTableFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func views(_ member: String) throws -> [String] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("FieldVTable.\(member)(") }, "\(member)")
            return [function.renderPseudo(), function.renderStructured()]
        }
        for (member, callee) in [("Car.go", "FieldVTable.Engine.start("), ("Car.park", "FieldVTable.Engine.stop(after:)("),
                                 ("Car.goSpare", "FieldVTable.Engine.start(")] {
            for text in try views(member) {
                #expect(text.contains(callee), "\(path) \(member): \(text)")
                #expect(!text.contains("unresolved call"), "\(path) \(member): \(text)")
            }
        }
        if path == fieldVTableFixtures[0] {
            for text in try views("Car.go") {
                #expect(text.contains("return FieldVTable.Engine.start(self: self.engine)"), Comment(rawValue: text))
            }
        }
        for text in try views("Garage.run") {
            #expect(!text.contains("FieldVTable.Engine"), "\(path): \(text)")
            #expect(text.contains("unresolved call"), "\(path): \(text)")
        }
    }
}

/// A free function's class parameter is typed by its signature: `runEngine(_
/// engine: Engine)` calls Engine.start() through its argument's vtable. The
/// other module's Engine has no layout in this image, so `runOther` stays
/// unresolved rather than taking this module's same-named class.
@Test func aVTableCallOnAClassArgumentIsNamedForItsTypeIfPresent() async throws {
    for path in fieldVTableFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        func views(_ member: String) throws -> [String] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("FieldVTable.\(member)(") }, "\(member)")
            return [function.renderPseudo(), function.renderStructured()]
        }
        for text in try views("runEngine") {
            #expect(text.contains("return FieldVTable.Engine.start(self: arg0)"), "\(path): \(text)")
        }
        for text in try views("runOther") {
            #expect(!text.contains("FieldVTable.Engine"), "\(path): \(text)")
            #expect(text.contains("unresolved call"), "\(path): \(text)")
        }
    }
}

/// An object held in a field of a free function's class argument is typed by
/// that class's field record: `car.engine.start()` in `driveHeld(_ car: Car)`.
@Test func aVTableCallOnAClassArgumentsFieldIsNamedIfPresent() async throws {
    for path in fieldVTableFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for member in ["driveHeld", "driveSpare"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("FieldVTable.\(member)(") }, "\(member)")
            for text in [function.renderPseudo(), function.renderStructured()] {
                #expect(text.contains("FieldVTable.Engine.start("), "\(path) \(member): \(text)")
                #expect(!text.contains("unresolved call"), "\(path) \(member): \(text)")
            }
        }
        if path == fieldVTableFixtures[0] {
            let held = try #require(functions.first { $0.displayName.hasPrefix("FieldVTable.driveHeld(") })
            #expect(held.renderPseudo().contains("return FieldVTable.Engine.start(self: arg0.engine)"))
        }
    }
}
