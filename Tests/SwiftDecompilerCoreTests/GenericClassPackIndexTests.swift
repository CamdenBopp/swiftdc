import Ccapstone
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let optimizedGenericClassPacks = "Fixtures/Sample/libGenericClassPacks.dylib"

@Test(arguments: [
    "Fixtures/Sample/libGenericClassPacks.Onone.dylib",
    optimizedGenericClassPacks,
    "Fixtures/Sample/libGenericClassPacks.Osize.dylib",
])
func genericClassPackWordsAreNotIndexedAsScalarMetadataIfPresent(path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(path) before running this test.")
        return
    }
    let machO = try BinaryLoader.load(path: path)
    let classes = UnrecordedTypes.all(in: machO)
    let index = VTableIndex.build(in: machO)

    var checked: Set<String> = []
    for type in classes {
        guard case .class(let model) = type,
              let name = try? model.descriptor.name(in: machO),
              name == "PackBox" || name == "PlainBox"
        else { continue }

        #expect(checked.insert(name).inserted)
        let generic = try #require(model.genericContext)
        try #require(generic.parameters.count == 2)
        try #require(generic.currentParameters.count == generic.parameters.count)
        try #require(generic.parameters.allSatisfy { $0.hasKeyArgument })
        try #require(!model.descriptor.hasResilientSuperclass)
        let first = Int(model.descriptor.nonResilientImmediateMembersOffset) * 8

        if name == "PackBox" {
            #expect(generic.typePackHeader != nil)
            // The first word is the pack length. The next is A's metadata.
            // Neither word has a proven scalar identity in the index.
            #expect(index.genericParameter(type: name, offset: first) == nil)
            #expect(index.genericParameter(type: name, offset: first + 8) == nil)
            #expect(index.genericParameter(type: name, offset: first + 16) == nil)
        } else {
            #expect(generic.typePackHeader == nil)
            #expect(index.genericParameter(type: name, offset: first) == "A")
            #expect(index.genericParameter(type: name, offset: first + 8) == "B")
            #expect(index.genericParameter(type: name, offset: first + 16) == nil)
        }
    }
    #expect(checked == ["PackBox", "PlainBox"])
}

@Test func aPackClassValueWitnessDoesNotUseTheNextParametersNameIfPresent() async throws {
    let path = optimizedGenericClassPacks
    guard FileManager.default.fileExists(atPath: path) else {
        #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(path) before running this test.")
        return
    }

    let image = try BinaryLoader.load(path: path)
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "identityA")
    }
    let array = await withStableDependencies {
        await Disassembler().disassemble(machO: image)
    }
    let streaming = await withStableDependencies {
        await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    let routes = [("filtered", filtered), ("array", array), ("streaming", streaming)]

    for (route, functions) in routes {
        let packed = try #require(functions.first {
            $0.displayName.hasPrefix("GenericClassPacks.PackBox.identityA(")
        }, Comment(rawValue: route))
        let plain = try #require(functions.first {
            $0.displayName.hasPrefix("GenericClassPacks.PlainBox.identityA(")
        }, Comment(rawValue: route))

        let packedTail = try #require(packed.instructions.last, Comment(rawValue: route))
        #expect(packedTail.controlFlow == .branch, Comment(rawValue: route))
        #expect(packedTail.branchTarget == nil, Comment(rawValue: route))
        let branch = try #require(packedTail.detail, Comment(rawValue: route))
        try #require(branch.id == AARCH64_INS_BR && branch.operands.count == 1, Comment(rawValue: route))
        try #require(branch.operands.first?.operand.register?.widthBits == 64, Comment(rawValue: route))
        let unresolved = "/* unresolved indirect branch @ 0x\(String(packedTail.address, radix: 16)) */ indirect_jump(?)"
        for text in [packed.renderStructured(), packed.renderPseudo()] {
            #expect(!text.contains("value witness for B"), Comment(rawValue: "\(route): \(text)"))
            #expect(text.contains(unresolved), Comment(rawValue: "\(route): \(text)"))
        }
        for text in [plain.renderStructured(), plain.renderPseudo()] {
            #expect(text.contains("initializeWithCopy value witness for A("), Comment(rawValue: "\(route): \(text)"))
        }
    }
}
