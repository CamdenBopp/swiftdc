import Foundation
import Testing
@testable import SwiftDecompilerCore

/// Calls through a dispatch thunk take `self` in x20 and their formal
/// parameters from x0; a protocol requirement's Self metadata and witness
/// table come after them (`gaugeclient.swift`).
struct DispatchThunkArgumentTests {
    private func function(_ path: String, _ name: String) async throws -> DisassembledFunction? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        return try #require(functions.first { $0.displayName.contains(name) })
    }

    /// `g.scaled(by: f)` with f untracked read `scaled(self: g)`: the
    /// positional layout trims unknown registers to nothing.
    @Test func aRequirementTakesItsFormalParametersIfPresent() async throws {
        guard let readScaled = try await function("Fixtures/Sample/libGaugeClient.dylib", "readScaled") else { return }
        let pseudo = readScaled.renderPseudo()
        #expect(pseudo.contains("GaugeKit.Gauge.scaled(by:)(self: __swift_project_boxed_opaque_existential_1(?, ?), ?)"), Comment(rawValue: pseudo))
    }

    /// A getter that returns a String returns both its words: `name.getter
    /// : Swift.String` has no arrow, so x1 after it was not its high word,
    /// and the String parameter it fills read `count(?)`.
    @Test func aStringGetterResultIsOneArgumentIfPresent() async throws {
        guard let label = try await function("Fixtures/Sample/libGaugeClient.dylib", "GaugeClient.label") else { return }
        let pseudo = label.renderPseudo()
        #expect(pseudo.contains("GaugeClient.count(of:)(dispatch thunk of GaugeKit.Gauge.name.getter(self: "), Comment(rawValue: pseudo))
    }

    /// A requirement's getter takes no formal parameter; x0 and x1 hold the
    /// conformer's metadata and witness table (an app read
    /// `Actor.unownedExecutor.getter(type metadata accessor for
    /// Swift.MainActor(0), …)`).
    @Test func aDispatchThunkGetterTakesNoArguments() {
        let index = ClassTypeIndex()
        #expect(Disassembler.getterTakesNoArguments(
            "dispatch thunk of Swift.Actor.unownedExecutor.getter : Swift.UnownedSerialExecutor", classTypeIndex: index))
        #expect(Disassembler.getterTakesNoArguments(
            "dispatch thunk of GaugeKit.Gauge.level.getter : Swift.Int", classTypeIndex: index))
        #expect(Disassembler.swiftCallArgumentSlots(
            callee: "dispatch thunk of GaugeKit.Gauge.scaled(by: Swift.Int) -> Swift.Int",
            enumCaseIndex: EnumCaseIndex(), classTypeIndex: index)?.count == 1)
    }

    /// A subscript's getter takes its index: `g[i]` read
    /// `Grid.subscript.getter(self: arg0)`.
    @Test func aSubscriptGetterTakesItsIndexIfPresent() async throws {
        guard let read = try await function("Fixtures/Sample/libSubscriptGetter.dylib", "SubscriptGetter.read") else { return }
        let pseudo = read.renderPseudo()
        #expect(pseudo.contains("SubscriptGetter.Grid.subscript.getter(self: arg0, arg1)"), Comment(rawValue: pseudo))
        #expect(!Disassembler.getterTakesNoArguments(
            "SubscriptGetter.Grid.subscript.getter : (Swift.Int) -> Swift.Int", classTypeIndex: ClassTypeIndex()))
    }
}
