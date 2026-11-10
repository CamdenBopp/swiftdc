import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let callerFrameFixtures = [
    "Fixtures/Sample/libCallerFrameAlias.dylib",
    "Fixtures/Sample/libCallerFrameAlias.opt.dylib",
    "Fixtures/Sample/libCallerFrameAlias.size.dylib",
]

@Test func callerOwnedAndPrivateFrameSlotsHaveNativeOraclesIfPresent() throws {
    for path in callerFrameFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for (name, expected) in [
            ("complete_frame_self_alias_oracle", Int64(99)),
            ("complete_frame_self_private_oracle", Int64(799)),
            ("complete_frame_self_lost_reach_oracle", Int64(99)),
            ("complete_mutable_argument_field_oracle", Int64(99)),
            ("complete_mutable_argument_reference_oracle", Int64(99)),
            ("complete_entry_pointer_positive_oracle", Int64(799)),
            ("complete_entry_pointer_reference_oracle", Int64(799)),
            ("complete_entry_pointer_copy_oracle", Int64(799)),
        ] {
            let entry = try #require(dlsym(library, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
    }
}

@Test func entryValueSelfWritesInvalidateCallerOwnedFrameFactsIfPresent() async throws {
    for path in callerFrameFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "FrameSelf.Cell.")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        let helper = try #require(array.first { $0.symbol == "_complete_frame_return_self" })
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            for (member, aliasesCaller) in [("cachedAlias", true), ("privateCache", false), ("lostReach", true)] {
                let function = try #require(functions.first { $0.displayName.hasPrefix("FrameSelf.Cell.\(member)(") })
                let ret = try #require(function.instructions.last { $0.controlFlow == .return })
                #expect(ret.exit?.statement == (aliasesCaller ? "return ?" : "return 7"), "\(path): \(member)")

                // The compiler reference independently establishes pointer
                // mutating-self in x20. Give the raw interpreter that ABI fact
                // to cover selfField writes as well as opaque pointer writes.
                var tracer = ValueTracer()
                tracer.calleeMemoryEffects[helper.startAddress] = CalleeMemoryEffect.discover(in: helper)
                let analysis = tracer.analyze(function, entry: .swiftInstance(scalarArguments: [:]))
                #expect((analysis.exitValues[ret.address] ?? .unknown) == (aliasesCaller ? .unknown : .immediate(7)), "\(path): \(member)")
                let write = try #require(analysis.memoryWrites.values.first {
                    $0.baseRegister == "x0" && $0.values == [.immediate(99)]
                })
                #expect(write.base == .selfPointer)
            }
        }
    }
}

@Test func mutableClassFieldsAndEntryFieldsKeepDifferentFrameProvenanceIfPresent() async throws {
    for path in callerFrameFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let mutable = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "argumentFieldAlias")
        }
        let immutable = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "entry_pointer_")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        let cases: [(symbol: String, fields: [Int: [Int: Int]], entry: MethodEntryConvention,
            expected: AbstractValue, baseRegister: String, base: AbstractValue)] = [
            ("_$s9FrameSelf18argumentFieldAliasySiAA10PointerBoxCF", [0: [16: 8]],
             .swiftFunction(scalarArguments: ["x0": 0]), .unknown, "x1", .argumentField(argument: 0, offset: 16)),
            ("_entry_pointer_probe", [1: [16: 8]],
             .swiftValueInstance(seededRegisters: ["x0": .argumentField(argument: 0, offset: 0), "x1": .argument(1)]),
             .immediate(7), "x0", .argumentField(argument: 0, offset: 0)),
            ("_entry_pointer_copy_body", [1: [16: 8]],
             .swiftValueInstance(seededRegisters: ["x0": .argumentField(argument: 0, offset: 0), "x1": .argument(1)]),
             .immediate(7), "x0", .argumentField(argument: 0, offset: 0)),
        ]
        for functions in [listing, array, mutable + immutable, streamed, Array(each.values)] {
            for control in cases {
                let function = try #require(functions.first { $0.symbol == control.symbol })
                let ret = try #require(function.instructions.last { $0.controlFlow == .return })
                var tracer = ValueTracer()
                for callee in array {
                    tracer.calleeMemoryEffects[callee.startAddress] = CalleeMemoryEffect.discover(in: callee)
                }
                tracer.argumentObjectFields = control.fields
                let analysis = tracer.analyze(function, entry: control.entry)
                #expect((analysis.exitValues[ret.address] ?? .unknown) == control.expected,
                    "\(path): \(function.displayName)")
                let write = try #require(analysis.memoryWrites.values.first {
                    $0.baseRegister == control.baseRegister && $0.values == [.immediate(99)]
                })
                #expect(write.base == control.base, "\(path): \(function.displayName)")
            }
        }
    }
}
