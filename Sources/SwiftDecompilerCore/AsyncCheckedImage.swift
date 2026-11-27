import Foundation
import CryptoKit
import Ccapstone
import MachOKit
import MachOSwiftSection

/// Linked startup facts. These do not establish that the named imported
/// runtime implementations were selected or how their mutable hooks behave.
struct AsyncCheckedImage {
    struct Binding {
        let stub: UInt64
        let pointerFileOffset: UInt64
        let libraryOrdinal: Int
        let reference: RuntimeFunctionReference
    }

    struct Startup {
        let main: UInt64
        let createSite: UInt64
        let create: Binding
        let metadataFileOffset: Int
        let descriptor: AsyncFunctionDescriptor
        let executor: Binding
        let runSite: UInt64
        let run: Binding
        let drain: Binding
    }

    /// The nominal x0 continuation operand passed to the exact imported
    /// switch. Scheduling, ownership and x1/x2 are still unresolved.
    struct StartupSwitch {
        let source: UInt64
        let site: UInt64
        let materialization: UInt64
        let continuation: UInt64
        let binding: Binding
    }

    /// Issued only after replay with a complete matched execution certificate.
    /// There is currently no production issuer for that certificate.
    struct AdmittedRegion {
        let sliceDigest: SHA256.Digest
        let model: AsyncClosedCallerSolver.ModelRegion
        let resume: UInt64

        static func replay(_ image: AsyncCheckedImage, admission: AsyncPhysicalReplay.Admission) -> Self? {
            guard let model = AsyncPhysicalReplay.model(image: image, admission: admission) else { return nil }
            return Self(image: image, model: model, resume: admission.resumeCoverage.resume)
        }

        private init(image: AsyncCheckedImage, model: AsyncClosedCallerSolver.ModelRegion, resume: UInt64) {
            self.sliceDigest = image.sliceDigest
            self.model = model
            self.resume = resume
        }
    }

    enum IngressBlocker: Hashable {
        case exported(UInt64)
        case rebased(UInt64)
        case unsupportedControl(UInt64)
        case importedOperation(UInt64)
    }

    /// Local reach by straight-line, exact decoded direct edges. No implied
    /// incoming closure or authorization to enter through the runtime.
    let startup: Startup
    let sliceDigest: SHA256.Digest
    let bodies: [UInt64: [Instruction]]
    let frontiers: Set<IngressBlocker>
    let detachedIngress: AsyncDetachedIngress?
    let startupSwitches: [UInt64: StartupSwitch]
    let physicalRegion: AsyncPhysicalRegion?

    private init(startup: Startup, sliceDigest: SHA256.Digest,
                 bodies: [UInt64: [Instruction]], frontiers: Set<IngressBlocker>,
                 detachedIngress: AsyncDetachedIngress?, startupSwitches: [UInt64: StartupSwitch],
                 physicalRegion: AsyncPhysicalRegion?) {
        self.startup = startup
        self.sliceDigest = sliceDigest
        self.bodies = bodies
        self.frontiers = frontiers
        self.detachedIngress = detachedIngress
        self.startupSwitches = startupSwitches
        self.physicalRegion = physicalRegion
    }

    static func extract(
        from image: MachOFile,
        bindFunctions: () -> [UInt64: Binding],
        isVoidMetadataSlot: (Int) -> Bool,
        strongImportedDataAt: (Int) -> RuntimeFunctionReference?,
        rebasedTargets: () -> Set<UInt64>,
        decode: (UInt64, [UInt64]) -> [Instruction]
    ) -> Self? {
        // The first domain is one thin native macOS executable. A fat
        // wrapper requires distinct selected-slice extent/identity checking.
        guard image.headerStartOffset == 0, !image.isLoadedFromDyldCache,
              image.is64Bit, !image.isSwapped, image.header.cpuType == .arm64,
              image.header.fileType == .execute, image.header.flags.contains(.twolevel),
              let handle = try? FileHandle(forReadingFrom: image.url)
        else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize <= 4 * 1024 * 1024,
              let size = Int(exactly: fileSize)
        else { return nil }
        let reader = MachOPreflight.ImageReader(handle: handle, base: 0, size: size)
        guard let bytes = reader.read(offset: 0, count: size),
              let rootOffset = checkedEntryOffset(in: bytes),
              let mapped: [UInt8] = try? image.readElements(offset: 0, numberOfElements: size),
              bytes.elementsEqual(mapped),
              (try? MachOPreflight.validate(prefix: bytes, fileSize: size)) != nil
        else { return nil }

        let segments = Array(image.segments64)
        let textOwners = segments.filter { $0.segmentName == "__TEXT" }
        guard textOwners.count == 1, let text = textOwners.first, text.layout.fileoff == 0,
              text.initialProtection.contains(.execute), !text.initialProtection.contains(.write),
              segments.allSatisfy({ segment in
                  let s = segment.layout
                  return s.filesize <= s.vmsize && s.fileoff <= fileSize && s.filesize <= fileSize - s.fileoff
                      && s.vmaddr <= UInt64(Int.max) && s.vmsize <= UInt64(Int.max) - s.vmaddr
              }),
              nonOverlapping(segments.map { $0.layout.vmaddr..<($0.layout.vmaddr + $0.layout.vmsize) }),
              nonOverlapping(segments.map { $0.layout.fileoff..<($0.layout.fileoff + $0.layout.filesize) }),
              image.sections64.allSatisfy({ section in
                  let s = section.layout
                  return s.addr <= UInt64(Int.max) && s.size <= UInt64(Int.max) - s.addr && s.nreloc == 0
              }),
              !image.sections64.contains(where: { section in
                  section.size > 0 && (section.flags.type == .mod_init_func_pointers
                      || section.flags.type == .init_func_offsets
                      || (section.segmentName == "__DATA" && section.sectionName == "__s64async_hook"))
              }),
              (try? MachOPreflight.validateImageContents(prefix: bytes, image: reader, path: image.url.path)) != nil,
              let ranges = FileBackedRanges(standalone: image),
              let main = ranges.address(ofFileOffset: rootOffset), main.isMultiple(of: 4),
              image.imageAddress(ofOffset: rootOffset) == main,
              image.imageOffset(ofAddress: main) == rootOffset,
              case .file(let offset, let available) = ranges.target(at: main),
              offset == rootOffset, available >= 4
        else { return nil }

        let starts = Disassembler.linkerFunctionStarts(of: image)
        let exactStarts = Set(starts)
        guard !starts.isEmpty, starts.count <= 256, starts == exactStarts.sorted(),
              exactStarts.contains(main)
        else { return nil }
        let sections = CodeSection.of(image, functionStarts: starts)
        let textSections = sections.filter { $0.name == "__text" && $0.range.contains(main) }
        guard textSections.count == 1, let owner = textSections.first else { return nil }

        func body(_ start: UInt64) -> [Instruction]? {
            guard exactStarts.contains(start), start.isMultiple(of: 4), owner.range.contains(start) else { return nil }
            let stop = min(starts.first(where: { $0 > start }) ?? owner.range.upperBound, owner.range.upperBound)
            let span = start..<stop
            let executableOwners = segments.filter { segment in
                segment.initialProtection.contains(.execute)
                    && (segment.layout.vmaddr..<(segment.layout.vmaddr + segment.layout.vmsize)).overlaps(span)
            }
            let rawOwners = image.sections64.filter { section in
                (section.layout.addr..<(section.layout.addr + section.layout.size)).overlaps(span)
            }
            guard executableOwners.count == 1, executableOwners.first?.segmentName == "__TEXT",
                  rawOwners.count == 1, rawOwners.first?.sectionName == "__text",
                  rawOwners.first?.segmentName == "__TEXT",
                  span.count <= 8192, span.count.isMultiple(of: 4), !span.isEmpty,
                  case .file(let firstOffset, let firstAvailable) = ranges.target(at: start),
                  firstAvailable >= span.count,
                  case .file(let lastOffset, _) = ranges.target(at: stop - 1),
                  lastOffset == firstOffset + span.count - 1
            else { return nil }
            let code = decode(start, starts)
            guard code.count == span.count / 4, code.first?.isTrap == false,
                  code.enumerated().allSatisfy({ index, instruction in
                      instruction.address == start + UInt64(index * 4) && instruction.detail != nil
                  })
            else { return nil }
            return code
        }

        guard let mainBody = body(main) else { return nil }
        let bindings = bindFunctions()
        guard let startup = recognizeStartup(mainBody, bindings: bindings, metadata: { address in
            guard case .file(let offset, let available) = ranges.target(at: address),
                  available >= 8, isVoidMetadataSlot(offset)
            else { return nil }
            return offset
        }, descriptor: { address in
            AsyncFunctionDescriptor.read(at: address, in: image, ranges: ranges,
                codeSections: sections, functionStarts: exactStarts)
        }), let operation = body(startup.descriptor.entry)
        else { return nil }

        var bodies = [main: mainBody, startup.descriptor.entry: operation]
        var frontiers: Set<IngressBlocker> = []
        var pending = [startup.descriptor.entry]
        var startupSwitches: [UInt64: StartupSwitch] = [:]
        while let start = pending.popLast(), let code = bodies[start] {
            let addresses = Set(code.map(\.address))
            for instruction in code {
                switch instruction.controlFlow {
                case .branch?, .call?, .conditionalBranch?:
                    guard let target = instruction.branchTarget else {
                        frontiers.insert(.unsupportedControl(instruction.address))
                        continue
                    }
                    if addresses.contains(target), instruction.controlFlow != .call { continue }
                    if let binding = bindings[target] {
                        frontiers.insert(.importedOperation(instruction.address))
                        if instruction.address == code.last?.address,
                           let scheduling = recognizeStartupSwitch(code, binding: binding),
                           let continuation = body(scheduling.continuation) {
                            startupSwitches[scheduling.site] = scheduling
                            if bodies[scheduling.continuation] == nil {
                                bodies[scheduling.continuation] = continuation
                                pending.append(scheduling.continuation)
                            }
                        }
                    } else if bodies[target] == nil {
                        if let targetBody = body(target) {
                            bodies[target] = targetBody
                            pending.append(target)
                        } else {
                            frontiers.insert(.unsupportedControl(instruction.address))
                        }
                    }
                case .sequential?, .return?: break
                case nil: frontiers.insert(.unsupportedControl(instruction.address))
                }
            }
        }

        // These are concrete exposure witnesses, not a complete pointer scan.
        // Unclassified ADR/ADRP and descriptor/box owners must be closed by
        // the independent task/effect translation before producing a region.
        for exported in image.exportedSymbols {
            if let offset = exported.offset, let target = ranges.address(ofFileOffset: offset),
               owner.range.contains(target), target != main {
                frontiers.insert(.exported(target))
            }
        }
        for target in rebasedTargets() where owner.range.contains(target) {
            frontiers.insert(.rebased(target))
        }

        func wordAt(_ address: UInt64) -> UInt32? {
            guard case .file(let offset, let available) = ranges.target(at: address), available >= 4
            else { return nil }
            return bytes.u32(at: offset)
        }
        let detached = AsyncDetachedIngress.extract(
            from: bodies, startup: startup, bindings: bindings, startupSwitches: startupSwitches, body: body,
            descriptor: { address, target in
                AsyncFunctionDescriptor.read(at: address, in: image, ranges: ranges,
                    codeSections: sections, functionStarts: exactStarts, expectedEntry: target)
            }, metadataOffset: { address in
                guard case .file(let offset, let available) = ranges.target(at: address),
                      available >= 8, isVoidMetadataSlot(offset) else { return nil }
                return offset
            }, wordAt: wordAt)
        let physicalRegion = detached.flatMap { detached in
            AsyncPhysicalRegion.extract(detached: detached, bindings: bindings, body: body,
                                        wordAt: wordAt, dataImportAt: { address in
                guard case .file(let offset, let available) = ranges.target(at: address), available >= 8
                else { return nil }
                return strongImportedDataAt(offset)
            })
        }
        guard let final: [UInt8] = try? image.readElements(offset: 0, numberOfElements: size),
              bytes.elementsEqual(final) else { return nil }
        return Self(startup: startup, sliceDigest: SHA256.hash(data: bytes),
                    bodies: bodies, frontiers: frontiers, detachedIngress: detached,
                    startupSwitches: startupSwitches, physicalRegion: physicalRegion)
    }

    private static func recognizeStartupSwitch(
        _ code: [Instruction], binding: Binding
    ) -> StartupSwitch? {
        guard binding.reference.rawSymbol == "_swift_task_switch",
              binding.reference.libraryName == "/usr/lib/swift/libswift_Concurrency.dylib",
              let source = code.first?.address, let tail = code.last,
              tail.controlFlow == .branch, tail.detail?.id == AARCH64_INS_B,
              tail.branchTarget == binding.stub
        else { return nil }

        // The observed suffix materializes x0 and then restores other
        // registers. Stay within a branch-free suffix after the last call.
        // Reject instructions which could overwrite the x0 reaching value.
        let prefix = code.dropLast()
        let suffix = Array(prefix.reversed().prefix {
            $0.controlFlow == .sequential && !$0.isTrap
        }.prefix(12).reversed())
        guard let index = suffix.indices.reversed().first(where: { i in
            suffix[i].detail?.id == AARCH64_INS_ADRP
                && suffix[i].detail?.operands.first?.operand.register?.key == "x0"
        }), index + 1 < suffix.count else { return nil }
        let page = suffix[index], add = suffix[index + 1]
        guard let p = page.detail, p.operands.count == 2, !p.writeback,
              let address = p.operands[1].operand.immediateValue,
              let r = p.operands[0].operand.register, r.widthBits == 64,
              let a = add.detail, a.id == AARCH64_INS_ADD, a.operands.count == 3,
              !a.writeback, !a.updatesFlags, a.operands[0].operand.register == r,
              a.operands[1].operand.register == r,
              let displacement = a.operands[2].shiftedImmediate, displacement >= 0
        else { return nil }
        let (target, overflow) = UInt64(bitPattern: address).addingReportingOverflow(UInt64(displacement))
        guard !overflow, target != source,
              suffix.dropFirst(index + 2).allSatisfy({ instruction in
                  guard let d = instruction.detail, !d.updatesFlags else { return false }
                  let count: Int
                  switch d.id {
                  case AARCH64_INS_MOV, AARCH64_INS_AND, AARCH64_INS_LDR: count = 1
                  case AARCH64_INS_LDP: count = 2
                  default: return false
                  }
                  guard d.operands.count > count,
                        d.operands.prefix(count).allSatisfy({
                            guard let dest = $0.operand.register else { return false }
                            return dest.key != "x0"
                        })
                  else { return false }
                  if d.writeback {
                      return d.operands.contains {
                          guard case .memory(let base?, _, _) = $0.operand else { return false }
                          return base.kind == .stackPointer
                      }
                  }
                  return true
              }),
              !code.contains(where: {
                  guard let destination = $0.branchTarget else { return false }
                  return page.address < destination && destination <= tail.address
              })
        else { return nil }
        return StartupSwitch(source: source, site: tail.address, materialization: page.address,
                             continuation: target, binding: binding)
    }

    private static func nonOverlapping(_ ranges: [Range<UInt64>]) -> Bool {
        let nonempty = ranges.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
        return zip(nonempty, nonempty.dropFirst()).allSatisfy { $0.0.upperBound <= $0.1.lowerBound }
    }

    /// Bounds-check LC_MAIN before MachOKit's typed command view is used.
    static func checkedEntryOffset(in bytes: Data) -> Int? {
        guard bytes.u32(at: 0) == 0xfeed_facf, bytes.u32(at: 4) == 0x0100_000c,
              bytes.u32(at: 12) == 2, let count = bytes.u32(at: 16),
              let commandBytes = bytes.u32(at: 20), bytes.count >= 32,
              commandBytes <= bytes.count - 32, count <= commandBytes / 8
        else { return nil }
        let end = 32 + Int(commandBytes)
        var position = 32
        var entry: Int?
        var functionStarts = 0
        var dyld = 0
        var macOS = 0
        for _ in 0..<count {
            guard end - position >= 8, let command = bytes.u32(at: position),
                  let commandLength = bytes.u32(at: position + 4),
                  commandLength >= 8, commandLength.isMultiple(of: 8), commandLength <= end - position
            else { return nil }
            let length = Int(commandLength)
            switch command {
            case 0x8000_0028: // LC_MAIN
                guard length == 24, entry == nil, let offset = bytes.u64(at: position + 8),
                      let candidate = Int(exactly: offset), candidate >= end,
                      candidate.isMultiple(of: 4), candidate <= bytes.count - 4,
                      bytes.u64(at: position + 16) == 0
                else { return nil }
                entry = candidate
            case 0xe: // LC_LOAD_DYLINKER
                guard length >= 16, let nameOffset = bytes.u32(at: position + 8),
                      nameOffset >= 12, nameOffset < length,
                      let terminator = bytes[(position + Int(nameOffset))..<(position + length)].firstIndex(of: 0),
                      bytes[(position + Int(nameOffset))..<terminator].elementsEqual("/usr/lib/dyld".utf8)
                else { return nil }
                dyld += 1
            case 0x32: // LC_BUILD_VERSION, PLATFORM_MACOS
                guard length >= 24, bytes.u32(at: position + 8) == 1 else { return nil }
                macOS += 1
            case 0x26: // LC_FUNCTION_STARTS
                guard length == 16 else { return nil }
                functionStarts += 1
            case 0x19, 0x2, 0xb, 0x1b, 0x2a, 0xc, 0x8000_001c, 0x29, 0x1d, 0x8000_0033, 0x8000_0034:
                // Known commands in the initially admitted loader envelope.
                break
            default: return nil
            }
            position += length
        }
        guard position == end, functionStarts == 1, dyld == 1, macOS == 1 else { return nil }
        return entry
    }

    private static func recognizeStartup(
        _ body: [Instruction], bindings: [UInt64: Binding],
        metadata: (UInt64) -> Int?, descriptor: (UInt64) -> AsyncFunctionDescriptor?
    ) -> Startup? {
        // The accepted main is a straight-line, explicit create/run/drain
        // startup. Check actual machine operands and exact call targets.
        let calls = body.indices.filter { body[$0].controlFlow == .call }
        guard calls.count == 4, let first = body.first,
              calls[0] > 0, calls[1] == calls[0] + 2, calls[2] == calls[1] + 6,
              calls[3] == calls[2] + 1, calls[3] + 1 < body.count,
              body[calls[3] + 1].isTrap,
              body.dropFirst(calls[3] + 1).allSatisfy({ instruction in
                  if instruction.isTrap { return true }
                  guard let detail = instruction.detail, detail.id == AARCH64_INS_HINT,
                        detail.operands.count == 1,
                        case .immediate(0) = detail.operands[0].operand else { return false }
                  return true
              })
        else { return nil }
        let names = ["_swift_task_create", "_swift_task_getMainExecutor", "_swift_job_run",
                     "_swift_task_asyncMainDrainQueue"]
        let operations = zip(calls, names).compactMap { index, name -> Binding? in
            guard body[index].detail?.id == AARCH64_INS_BL, let target = body[index].branchTarget,
                  let binding = bindings[target],
                  binding.reference.rawSymbol == name,
                  binding.reference.libraryName == "/usr/lib/swift/libswift_Concurrency.dylib"
            else { return nil }
            return binding
        }
        guard operations.count == names.count else { return nil }

        let prefix = Array(body[..<calls[0]])
        guard prefix.allSatisfy({ instruction in
            guard !instruction.isTrap, instruction.controlFlow == .sequential,
                  let detail = instruction.detail, !detail.updatesFlags
            else { return false }
            if detail.id == AARCH64_INS_STP {
                guard detail.operands.count == 3,
                      case .memory(let base?, nil, _) = detail.operands[2].operand
                else { return false }
                return base.kind == .stackPointer && base.widthBits == 64
            }
            return !detail.writeback
                && [AARCH64_INS_ADR, AARCH64_INS_ADRP, AARCH64_INS_ADD, AARCH64_INS_LDR, AARCH64_INS_MOV].contains(detail.id)
        }) else { return nil }
        let inputs = ValueTracer().finalState(of: prefix)
        guard inputs["x0"] == .immediate(0x800), inputs["x1"] == .immediate(0),
              inputs["x4"] == .immediate(0),
              case .address(let record)? = inputs["x3"],
              case .binary(.add, .loaded(let metadataSlot), .immediate(8))? = inputs["x2"],
              let metadataFileOffset = metadata(metadataSlot), let function = descriptor(record)
        else { return nil }

        func move(_ index: Int, to: Int, from: Int) -> Bool {
            guard body[index].controlFlow == .sequential, let detail = body[index].detail,
                  detail.id == AARCH64_INS_MOV, detail.operands.count == 2,
                  let destination = detail.operands[0].operand.register, destination.kind == .gpr,
                  let source = detail.operands[1].operand.register, source.kind == .gpr
            else { return false }
            return destination.number == to && source.number == from
                && destination.widthBits == 64 && source.widthBits == 64
        }
        let getter = calls[1]
        guard move(calls[0] + 1, to: 19, from: 0),
              move(getter + 1, to: 2, from: 0), move(getter + 2, to: 3, from: 1),
              move(getter + 3, to: 0, from: 19), move(getter + 4, to: 1, from: 2),
              move(getter + 5, to: 2, from: 3)
        else { return nil }
        return Startup(main: first.address, createSite: body[calls[0]].address,
                       create: operations[0], metadataFileOffset: metadataFileOffset,
                       descriptor: function, executor: operations[1],
                       runSite: body[calls[2]].address, run: operations[2], drain: operations[3])
    }
}
