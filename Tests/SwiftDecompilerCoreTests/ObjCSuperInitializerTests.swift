import Ccapstone
import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

@Test(arguments: [
    "Fixtures/Sample/libObjCSuperInitializer.O0.dylib",
    "Fixtures/Sample/libObjCSuperInitializer.dylib",
    "Fixtures/Sample/libObjCSuperInitializer.Os.dylib",
])
func superMessagesOnlyAdoptAProvenReplacementReceiverIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let optimized = !path.hasSuffix(".O0.dylib")
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .simplified).disassemble(path: path, functionFilter: "SDSuperInitializer")
    }

    func method(_ selector: String) throws -> DisassembledFunction {
        try #require(functions.first {
            $0.objcMethod?.className == "SDSuperInitializer" && $0.objcMethod?.selector == selector
        })
    }

    func assignments(_ function: DisassembledFunction) -> [String] {
        function.instructions.compactMap {
            guard case .selfInitialization(let expression)? = $0.facts.statement else { return nil }
            return expression
        }
    }

    let forwarded = try method("init")
    #expect(assignments(forwarded).isEmpty)
    let ordinarySend = try #require(forwarded.instructions.first {
        DisassembledFunction.calleeName(of: $0) == "objc_msgSendSuper2"
    })
    let firstConsumer = try #require(forwarded.instructions.first {
        DisassembledFunction.calleeName(of: $0)?.hasSuffix("consumeSuperValue") == true
    })
    let forwardedTrace = ValueTracer().analyze(forwarded, entry: .objectiveCInitializer(argumentCount: 0))
    #expect(forwardedTrace.callSites[firstConsumer.address]?.arguments.first == .callResult(ordinarySend.address))
    for text in [forwarded.renderStructured(), forwarded.renderPseudo()] {
        #expect(text.contains("[super description]"), Comment(rawValue: text))
        #expect(text.contains("[super init]"), Comment(rawValue: text))
        if optimized {
            #expect(text.contains("return [super init]"), Comment(rawValue: text))
        }
    }

    let opaque = try method("initWithToken:")
    // The opaque C consumer can read an old objc_super receiver word through
    // the incoming stack even after the tracer loses its exact slot value.
    #expect(assignments(opaque).isEmpty)
    for text in [opaque.renderStructured(), opaque.renderPseudo()] {
        #expect(text.contains("[super initDecorative]"), Comment(rawValue: text))
        #expect(text.contains("[super description]"), Comment(rawValue: text))
    }
    let opaqueTrace = ValueTracer().analyze(opaque, entry: .objectiveCInitializer(argumentCount: 1))
    let opaqueSends = opaque.instructions.filter {
        DisassembledFunction.calleeName(of: $0) == "objc_msgSendSuper2"
    }
    let opaqueConsumers = opaque.instructions.filter {
        DisassembledFunction.calleeName(of: $0)?.hasSuffix("consumeSuperValue") == true
    }
    try #require(opaqueSends.count == 3 && opaqueConsumers.count == 2)
    #expect(opaqueTrace.callSites[opaqueConsumers[0].address]?.arguments.first == .callResult(opaqueSends[0].address))
    #expect(opaqueTrace.callSites[opaqueConsumers[1].address]?.arguments.first == .callResult(opaqueSends[2].address))

    let adopted = try method("initWritingToken:")
    if optimized {
        #expect(assignments(adopted) == ["[super initWithToken:arg0]"])
    } else {
        // -O0 updates a spilled self local and cleans it up through ARC
        // calls. The register/forwarding proof conservatively declines.
        #expect(assignments(adopted).isEmpty)
    }
    for text in [adopted.renderStructured(), adopted.renderPseudo()] {
        if optimized {
            #expect(text.contains("self->_token = arg0"), Comment(rawValue: text))
            #expect(text.contains("return self"), Comment(rawValue: text))
        }
    }

    let originalStillUsed = try method("initKeepingOriginal:")
    #expect(assignments(originalStillUsed).isEmpty)
    let oldReceiverConsumer = try #require(originalStillUsed.instructions.first {
        DisassembledFunction.calleeName(of: $0)?.hasSuffix("consumeSuperValue") == true
    })
    let originalTrace = ValueTracer().analyze(originalStillUsed, entry: .objectiveCInitializer(argumentCount: 1))
    if optimized {
        #expect(originalTrace.callSites[oldReceiverConsumer.address]?.arguments.first == .selfPointer)
    }
    for text in [originalStillUsed.renderStructured(), originalStillUsed.renderPseudo()] {
        #expect(text.contains("[super initWithToken:"), Comment(rawValue: text))
        #expect(text.contains("consumeSuperValue("), Comment(rawValue: text))
    }
}

@Test func superReplacementTrustsOnlyCompleteBoundNullaryStubsIfPresent() async throws {
    let path = "Fixtures/Sample/libSample.stripped.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    func initializer(_ path: String) async throws -> DisassembledFunction {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .simplified).disassemble(path: path, functionFilter: "initWithName:count:")
        }
        return try #require(functions.first {
            $0.objcMethod?.className == "SDObjCCounter"
        })
    }
    func adoptsSelf(_ function: DisassembledFunction) -> Bool {
        function.instructions.contains {
            if case .selfInitialization? = $0.facts.statement { return true }
            return false
        }
    }

    let original = try await initializer(path)
    #expect(adoptsSelf(original))
    let copyCall = try #require(original.instructions.first {
        DisassembledFunction.calleeName(of: $0) == "objc_msgSend$copy"
    })
    let entry = try #require(copyCall.branchTarget)
    let image = try BinaryLoader.load(path: path)
    let ranges = try #require(FileBackedRanges(standalone: image))
    let file = try #require(ranges.fileBytes(at: entry))
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    try #require(file.available >= 20 && file.offset >= 0 && file.offset <= bytes.count - 20)
    let engine = try #require(CapstoneEngine())
    let island = engine.disassemble(bytes.subdata(in: file.offset..<file.offset + 20), address: entry)
    try #require(island.count == 5)
    let branch = try #require(island[4].detail)
    try #require(branch.id == AARCH64_INS_BR && branch.operands.count == 1)
    try #require(branch.operands.first?.operand.register?.key == "x16")
    let instructions = island.prefix(4).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow, detail: $0.detail)
    }
    let sent = ValueTracer().finalState(of: instructions)
    guard case .loaded(let originalSelref)? = sent["x1"], case .loaded(let originalGot)? = sent["x16"] else {
        Issue.record("The compiler fixture did not emit the expected two-load selector island")
        return
    }
    let selectors = ObjCSelectors.selectorTable(in: image).bySelref
    try #require(selectors[originalSelref] == "copy")
    let fixups = Disassembler.ChainedFixupTable()
    let gotOffset = try #require(ranges.fileBytes(at: originalGot)?.offset)
    let binding = try #require(fixups.validatedFunctionReference(at: UInt64(gotOffset), in: image))
    try #require(binding.permitsNamedABI(named: "objc_msgSend"))

    // Retarget the unsigned scaled ldr within its decoded adrp page.
    func loadWord(register: UInt32, index: Int, old: UInt64, new: UInt64) throws -> UInt32 {
        let detail = try #require(island[index].detail)
        try #require(detail.operands.count == 2)
        guard case .memory(_, nil, let displacement) = detail.operands[1].operand,
              displacement >= 0, old >= UInt64(displacement) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let page = old - UInt64(displacement)
        try #require(new >= page && (new - page).isMultiple(of: 8) && (new - page) / 8 < 4096)
        return 0xf9400000 | UInt32((new - page) / 8) << 10 | register << 5 | register
    }
    let keyword = try #require(selectors.keys.sorted().first {
        $0 >> 12 == originalSelref >> 12 && selectors[$0]?.contains(":") == true
    })
    let got = try #require(image.sections.first { $0.sectionName == "__got" })
    let differentImport = try #require(stride(from: UInt64(got.address),
        to: UInt64(got.address) + UInt64(got.size), by: 8).first { slot in
        guard slot >> 12 == originalGot >> 12, slot != originalGot,
              let offset = ranges.fileBytes(at: slot)?.offset,
              let candidate = fixups.validatedFunctionReference(at: UInt64(offset), in: image)
        else { return false }
        return candidate.symbolName != "objc_msgSend"
    })

    let variants: [(String, Int, UInt32)] = [
        ("branch-register", 4, 0xd61f0220), // br x17
        ("wrong-provider-slot", 3, try loadWord(register: 16, index: 3, old: originalGot, new: differentImport)),
        ("keyword-selector", 1, try loadWord(register: 1, index: 1, old: originalSelref, new: keyword)),
    ]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("objc-super-stubs-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (label, wordIndex, replacement) in variants {
        var mutant = bytes
        let offset = file.offset + 4 * wordIndex
        mutant.replaceSubrange(offset..<offset + 4, with: (0..<4).map {
            UInt8(truncatingIfNeeded: replacement >> ($0 * 8))
        })
        let url = directory.appendingPathComponent(label + ".dylib")
        try mutant.write(to: url)
        let recovered = try await initializer(url.path)
        #expect(!adoptsSelf(recovered), Comment(rawValue: label))
        #expect(recovered.renderStructured().contains("[super init]"), Comment(rawValue: label))
    }
}

@Test func superReplacementRequiresProductionSelectorAndOwnerIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCSuperInitializer.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    func initializer(_ imagePath: String) async throws -> DisassembledFunction {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .simplified).disassemble(path: imagePath, functionFilter: "initWritingToken:")
        }
        return try #require(functions.first {
            $0.objcMethod?.className == "SDSuperInitializer" && $0.objcMethod?.selector == "initWritingToken:"
        })
    }
    func adoption(_ function: DisassembledFunction) -> Bool {
        function.instructions.contains {
            if case .selfInitialization? = $0.facts.statement { return true }
            return false
        }
    }

    let image = try BinaryLoader.load(path: path)
    let ranges = try #require(FileBackedRanges(standalone: image))
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    let original = try await initializer(path)
    try #require(adoption(original))
    let callIndex = try #require(original.instructions.firstIndex {
        DisassembledFunction.calleeName(of: $0) == "objc_msgSendSuper2"
    })
    let superCall = original.instructions[callIndex]
    try #require(superCall.facts.namedABIContract)

    let selectors = ObjCSelectors.selectorTable(in: image).bySelref
    let initialSelector = try #require(selectors.first { $0.value == "initWithToken:" }?.key)
    let ordinarySelector = try #require(selectors.first { $0.value == "description" }?.key)
    let superRefs = try #require(image.sections.first { $0.sectionName == "__objc_superrefs" })
    let classObjects = ObjCMetadataIndex.build(in: image).classObjectNames
    let fixups = Disassembler.ChainedFixupTable()
    func searchSlot(for owner: String) throws -> UInt64 {
        try #require(stride(from: UInt64(superRefs.address),
                            to: UInt64(superRefs.address) + UInt64(superRefs.size), by: 8).first { slot in
            guard let file = ranges.fileBytes(at: slot),
                  let target = fixups.rebaseTarget(at: UInt64(file.offset), in: image) else { return false }
            return classObjects[image.address(forOffset: 0) + target] == owner
        })
    }
    let initialClass = try searchSlot(for: "SDSuperInitializer")
    let foreignClass = try searchSlot(for: "SDSuperInitializerBase")

    // Find the original ADRP/LDR by the address it actually reads. Preserve
    // every instruction bit except the unsigned scaled displacement.
    func retargetLoad(from old: UInt64, to new: UInt64) throws -> (offset: Int, word: UInt32) {
        try #require(old != new && old >> 12 == new >> 12)
        let index = try #require((1..<callIndex).first { index in
            let pair = Array(original.instructions[(index - 1)...index])
            guard pair[0].detail?.id == AARCH64_INS_ADRP, pair[1].detail?.id == AARCH64_INS_LDR,
                  let register = pair[1].detail?.operands.first?.operand.register
            else { return false }
            return ValueTracer().finalState(of: pair)[register.key] == .loaded(old)
        })
        let load = original.instructions[index]
        let detail = try #require(load.detail)
        try #require(detail.operands.count == 2)
        guard case .memory(_, nil, let displacement) = detail.operands[1].operand,
              displacement >= 0, old >= UInt64(displacement), new >= old - UInt64(displacement)
        else { throw CocoaError(.fileReadCorruptFile) }
        let offset = try #require(ranges.fileBytes(at: load.address)?.offset)
        try #require(offset >= 0 && offset <= bytes.count - 4)
        let newDisplacement = new - (old - UInt64(displacement))
        try #require(newDisplacement.isMultiple(of: 8) && newDisplacement / 8 < 4096)
        let raw = bytes[offset..<offset + 4].enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << (8 * $1.offset))
        }
        try #require(raw & 0xffc00000 == 0xf9400000)
        return (offset, (raw & ~UInt32(0x003ffc00)) | UInt32(newDisplacement / 8) << 10)
    }

    let mutations = [
        ("ordinary-selector", try retargetLoad(from: initialSelector, to: ordinarySelector)),
        ("foreign-search-class", try retargetLoad(from: initialClass, to: foreignClass)),
    ]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("objc-super-adopter-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (label, change) in mutations {
        var mutant = bytes
        mutant.replaceSubrange(change.offset..<change.offset + 4, with: (0..<4).map {
            UInt8(truncatingIfNeeded: change.word >> ($0 * 8))
        })
        let url = directory.appendingPathComponent(label + ".dylib")
        try mutant.write(to: url)
        let recovered = try await initializer(url.path)
        #expect(!adoption(recovered), Comment(rawValue: label))
        // The retained result-driven store/return make this an actual
        // negative for the production gate, not an ordinary send that
        // could never pass the subsequent adoption checks.
        let trace = ValueTracer().analyze(recovered, entry: .objectiveCInitializer(argumentCount: 1))
        let producer = AbstractValue.callResult(superCall.address)
        #expect(trace.memoryWrites.values.contains { $0.base == producer }, Comment(rawValue: label))
        #expect(trace.exitValues.values.contains(producer), Comment(rawValue: label))
    }
}

@Test func superInitializerRequiresExactCallAndReplacementEvidence() throws {
    // A decoded objc_super setup with two saved copies of the original
    // receiver. The call rebinds x19, while x21 remains dead after the call.
    let words: [UInt32] = [
        0xd10083ff, 0xaa0003f3, 0xaa0003f5,              // sub sp; mov x19,x0; mov x21,x0
        0xf0000008, 0xf9403108, 0xa90023e0,              // ldr class at 0x4060; stp x0,x8,[sp]
        0xf0000028, 0xf940a501, 0x910003e0,              // ldr selector at 0x8148; mov x0,sp
        0x94000040, 0xaa0003f3, 0xd503201f,              // bl; mov x19,x0; nop
        0xf900041f, 0xd503201f, 0xaa1303e0,              // store via result; nop; mov x0,x19
        0x910083ff, 0xd65f03c0,                          // add sp; ret
    ]
    let base: UInt64 = 0x1000
    let engine = try #require(CapstoneEngine())
    let cases: [(label: String, provider: Bool, change: (Int, UInt32)?, candidate: Bool, adoption: Bool)] = [
        ("complete", true, nil, true, true),
        ("unbound messenger", false, nil, false, false),
        ("foreign receiver", true, (5, 0xa90023e2), false, false),
        ("different search class slot", true, (4, 0xf9402d08), false, false),
        ("different selector slot", true, (7, 0xf940a901), false, false),
        ("old receiver read", true, (11, 0xaa1503e8), true, false), // mov x8,x21
        ("control flow loops", true, (11, 0xb5000002), true, false), // cbnz x2, self
        ("incomplete decoding", true, nil, true, false),
        ("opaque consumer of forgotten super header", true, (13, 0x94000040), true, false),
        ("known no-stack call", true, (13, 0x94000040), true, true),
        ("implicit retain of original x21", true, (13, 0x94000040), true, false),
        ("unknown base can read escaped header", true, (13, 0xf9400128), true, false), // ldr x8,[x9]
        ("one branch publishes a frame address", true, nil, true, false),
        ("external store publishes a frame address", true, nil, true, false),
        ("swpal publishes a frame address", true, nil, true, false),
        ("stxr publishes a frame address", true, nil, true, false),
        ("private frame address copy", true, nil, true, true),
        ("private frame arithmetic", true, nil, true, true),
    ]
    for control in cases {
        var body = words
        if let (index, instruction) = control.change { body[index] = instruction }
        let prefix: [UInt32] = switch control.label {
        case "one branch publishes a frame address":
            // If x2 is nonzero, publish the address of the old receiver's
            // spill and reload x0 from saved incoming self before joining.
            [0xb40000a2, 0xf9000fe0, 0x910063e0, 0x94000040, 0xaa1303e0]
        case "external store publishes a frame address":
            [0xf0000008, 0x910063e9, 0xf9000109] // adrp x8; add x9,sp,#24; str x9,[x8]
        case "swpal publishes a frame address":
            [0xf0000008, 0x910063e9, 0xf8e9810a] // adrp x8; add x9,sp,#24; swpal x9,x10,[x8]
        case "stxr publishes a frame address":
            [0xf0000008, 0x910063e9, 0xc80a7d09] // adrp x8; add x9,sp,#24; stxr w10,x9,[x8]
        case "private frame address copy":
            [0x910063e9, 0xf9000be9] // add x9,sp,#24; str x9,[sp,#16]
        case "private frame arithmetic":
            [0x910063e9, 0x9100212a] // add x9,sp,#24; add x10,x9,#8
        default:
            []
        }
        body.insert(contentsOf: prefix, at: 3)
        let call = base + UInt64(9 + prefix.count) * 4
        let afterField = base + UInt64(13 + prefix.count) * 4
        let bytes = body.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: base)
        try #require(decoded.count == body.count)
        if control.label.hasPrefix("swpal") {
            #expect(decoded[5].detail?.id == AARCH64_INS_SWPAL)
        }
        if control.label.hasPrefix("stxr") {
            #expect(decoded[5].detail?.id == AARCH64_INS_STXR)
        }
        let instructions = decoded.map { item in
            var facts = Instruction.Facts()
            let fixed = control.label == "known no-stack call" && item.address == afterField
            let retain = control.label == "implicit retain of original x21" && item.address == afterField
            facts.arcIdentityContract = retain
            facts.namedABIContract = (item.address == call && control.provider) || fixed
            return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
                branchTarget: item.branchTarget,
                detail: control.label == "incomplete decoding" && item.address == base + 11 * 4 ? nil : item.detail,
                callee: .kept(item.address == call ? "objc_msgSendSuper2" : fixed ? "getpid"
                    : retain ? "objc_retain_x21" : nil), facts: facts)
        }
        let function = DisassembledFunction(symbol: "-[Probe initWithValue:]", demangledName: nil, startAddress: base,
            instructions: instructions, source: .symbol)
        var tracer = ValueTracer()
        tracer.objcInitializerSelectors = [0x8148: "init"]
        tracer.provesObjCSuperInitializer = { selector, searchClass in
            selector == 0x8148 && searchClass == .loaded(0x4060)
        }
        let cfg = FunctionCFG(function)
        let trace = tracer.analyze(function, entry: .objectiveCInitializer(argumentCount: 1), cfg: cfg)
        #expect(trace.callSites[call]?.isObjCSuperInitCandidate == control.candidate, Comment(rawValue: control.label))
        if control.label.contains("publishes") {
            #expect(trace.objcFrameAddressMayHaveEscaped, Comment(rawValue: control.label))
        }
        if control.label == "private frame address copy" {
            #expect(trace.objcPrivateFrameAddressSpilled && !trace.objcFrameAddressMayHaveEscaped)
        }
        if control.label == "private frame arithmetic" {
            #expect(!trace.objcPrivateFrameAddressSpilled && !trace.objcFrameAddressMayHaveEscaped)
        }
        #expect(Disassembler.forwardsObjCSuperResultAsSelf(at: call, in: function, cfg: cfg, analysis: trace)
            == control.adoption, Comment(rawValue: control.label))
        let exit = try #require(instructions.last?.address)
        if control.label == "incomplete decoding" {
            #expect(trace.exitValues[exit] == nil)
            // The CFG proof must reject missing detail independently of
            // whether an exit-value analysis happens to retain the producer.
            var optimistic = trace
            optimistic.exitValues[exit] = .callResult(call)
            #expect(!Disassembler.forwardsObjCSuperResultAsSelf(at: call, in: function, cfg: cfg, analysis: optimistic))
        } else {
            #expect(trace.exitValues[exit] == AbstractValue.callResult(call), Comment(rawValue: control.label))
        }
    }
}

@Test func superReplacementProofSeesOverlappingAndStaleStackReceiverReads() throws {
    // The first lane is zero; the second lane and an unaligned four-byte
    // load both reach incoming self. The getpid call clears the outgoing
    // markers without overwriting the stack word. The following opaque call
    // can still read the word as an incoming stack argument.
    let words: [UInt32] = [
        0xd10083ff, 0xa90103ff, 0xa94127e8, 0xb841b3e8, 0xaa1f03e0,
        0x94000040, 0x94000040, 0x9100013f, 0xf94003e8, 0xd65f03c0, // mov sp,x9; ldr x8,[sp]
    ]
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let engine = try #require(CapstoneEngine())
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "-[Probe init]", demangledName: nil, startAddress: 0x1000,
        instructions: decoded.map {
            let bound = $0.address == 0x1014
            var facts = Instruction.Facts()
            facts.namedABIContract = bound
            return Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail,
                callee: .kept(bound ? "getpid" : nil), facts: facts)
        }, source: .symbol)
    var tracer = ValueTracer()
    tracer.provesObjCSuperInitializer = { _, _ in false }
    let trace = tracer.analyze(function, entry: .objectiveCInitializer(argumentCount: 0))
    func canReadOriginal(at address: UInt64) -> Bool {
        guard let read = trace.objcFrameReadEffects[address] else { return false }
        return trace.objcOriginalSelfFrame.contains(where: read.mayInvalidate)
    }
    #expect(canReadOriginal(at: 0x1008))
    #expect(canReadOriginal(at: 0x100c))
    #expect(!canReadOriginal(at: 0x1014))
    #expect(canReadOriginal(at: 0x1018))
    #expect(trace.objcFrameReadEffects[0x1020]?.isWholeFrame == true)
}

@Test func superReplacementRequiresOneExactSearchClassObject() {
    #expect(Disassembler.uniqueObjCClassObject(named: "Owner", in: [0x1000: "Owner", 0x2000: "Other"]) == 0x1000)
    #expect(Disassembler.uniqueObjCClassObject(named: "Owner", in: [0x1000: "Owner", 0x2000: "Owner"]) == nil)
    #expect(Disassembler.uniqueObjCClassObject(named: "Owner", in: [0x2000: "Other"]) == nil)
}
