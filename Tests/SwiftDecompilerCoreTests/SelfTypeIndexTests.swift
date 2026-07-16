import Testing
import Foundation
@testable import SwiftDecompilerCore

/// The claim the whole field-naming approach rests on: a class vtable slot binds
/// an implementation address to its `self` type using **metadata**, so it
/// survives stripping — while the mangled symbol that would otherwise carry the
/// same fact does not.
///
/// Runs only when the fixture is built (`Fixtures/Sample/build.sh`), matching the
/// other integration checks here.
@Test func selfBindingsSurviveStripping() throws {
    let release = "Fixtures/Sample/sample.release"
    let stripped = "Fixtures/Sample/sample.stripped"
    guard FileManager.default.fileExists(atPath: release),
          FileManager.default.fileExists(atPath: stripped)
    else { return }

    let unstrippedIndex = SelfTypeIndex.build(in: try BinaryLoader.load(path: release))
    let strippedIndex = SelfTypeIndex.build(in: try BinaryLoader.load(path: stripped))

    // There is something to lose in the first place.
    #expect(unstrippedIndex.count > 0)

    // The fixture's class hierarchy is bound to real addresses.
    let types = Set(unstrippedIndex.all.map { $0.binding.selfTypeName })
    #expect(types.contains("Dog"))
    #expect(types.contains("Animal"))

    // The load-bearing assertion: identical after `strip -x -S`.
    #expect(strippedIndex.count == unstrippedIndex.count)
    let unstrippedPairs = unstrippedIndex.all.map { "\($0.address):\($0.binding.selfTypeName).\($0.binding.kind)" }
    let strippedPairs = strippedIndex.all.map { "\($0.address):\($0.binding.selfTypeName).\($0.binding.kind)" }
    #expect(unstrippedPairs == strippedPairs)
}

/// A binding must distinguish an instance receiver from a metatype one. x20
/// holds a metatype for a static/class method, and an instance field map does
/// not apply to it — naming `self.field` there would be a fabrication.
@Test func distinguishesInstanceFromMetatypeReceivers() throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let index = SelfTypeIndex.build(in: try BinaryLoader.load(path: path))
    guard index.count > 0 else { return }

    // Initializers are allocating entry points: they take the metatype, not an
    // instance. If everything claimed to be an instance method, the flag is not
    // being read.
    let inits = index.all.filter { $0.binding.kind == "init" }
    if !inits.isEmpty {
        #expect(inits.allSatisfy { !$0.binding.isInstance })
    }
    // Property accessors on a class are instance methods.
    let getters = index.all.filter { $0.binding.kind == "getter" && $0.binding.selfTypeName == "Dog" }
    if !getters.isEmpty {
        #expect(getters.allSatisfy { $0.binding.isInstance })
    }
}

/// Every binding resolves to a distinct, plausible code address — a guard
/// against the relative-pointer arithmetic silently producing garbage.
@Test func bindingAddressesAreDistinctAndInText() throws {
    let path = "Fixtures/Sample/sample.release"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let index = SelfTypeIndex.build(in: machO)
    guard index.count > 0 else { return }

    let sections = machO.sections
    guard let text = sections.first(where: {
        $0.segmentName == "__TEXT" && $0.sectionName == "__text"
    }) else { return }
    let range = UInt64(text.address) ..< UInt64(text.address + text.size)

    let addresses = index.all.map { $0.address }
    #expect(Set(addresses).count == addresses.count, "vtable slots must not collide")
    #expect(addresses.allSatisfy { range.contains($0) }, "every implementation must land in __text")
}
