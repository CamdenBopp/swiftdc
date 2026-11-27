/// Solves one bounded allocation region after a complete executable ingress
/// and runtime-effect admission pass. The graph is analysis input and cannot
/// be constructed from AsyncFuncletIndex: its edges are an incomplete census.
enum AsyncClosedCallerSolver {
    struct Edge: Hashable {
        let source: UInt64
        let branch: UInt64
    }

    struct AwaitIdentity: Equatable {
        enum Carrier: Equatable {
            case normalIntegerX0
            case typedErrorX0
        }

        let callEdge: Edge
        let taskGeneration: UInt64
        let ownerGeneration: UInt64
        let returnEntry: UInt64
        let carrier: Carrier
    }

    enum Value: Equatable {
        case pointer(allocation: UInt64, offset: Int)
        case awaited(AwaitIdentity)
        case immediate(UInt64)
        case integerInput(UInt64)
        case integerSum(origin: UInt64?, delta: UInt64, producerSite: UInt64)
        case continuation(UInt64)
        case machineFrame(Int)
        case descriptor(AsyncFunctionDescriptor)
        case runtimeDescriptor(RuntimeDescriptor)
        case relativeDisplacement(AsyncFunctionDescriptor, signed: Bool)
        case boxedOperation(BoxedOperation)
        case capturedObject(CapturedObject)
    }

    struct ByteRange {
        let allocation: UInt64
        let bytes: Range<Int>
    }

    enum Effect {
        case allocate(site: UInt64, extent: Int, result: Int)
        case copy(from: Int, to: Int)
        case offset(base: Int, by: Int, result: Int)
        case forget(Int)
        case immediate(UInt64, result: Int)
        case continuation(UInt64, result: Int)
        case returnedScalar(AwaitIdentity, result: Int)
        case integerInput(origin: UInt64, result: Int)
        case wrappingScalarAdd(site: UInt64, source: Int, displacement: Int64, result: Int)
        case normalIntegerReturn(NormalReturn)
        case requireLiveContinuation(LiveContinuation)
        case storeWord(address: Int, source: Int)
        case loadWord(address: Int, result: Int)
        case clobber(address: Int, byteCount: Int)
        case publish
        case release(Int)
        case adjustMachineStack(by: Int)
        case formMachineFrame(offset: Int)
        case machineStackWords(MachineStackWords)
        case activateBox(BoxedOperation, register: Int)
        case readBoxPair(base: Int, descriptor: Int, capture: Int)
        case capturedInteger(base: Int, offset: Int, result: Int)
        case continuationFromPage(entry: UInt64, base: Int, delta: Int, result: Int)
        case materializeLocalDescriptor(expected: AsyncFunctionDescriptor, base: Int, delta: Int, result: Int)
        case descriptorSize(expected: AsyncFunctionDescriptor, base: Int, result: Int)
        case descriptorSizeFromPage(expected: AsyncFunctionDescriptor, base: Int, displacement: Int, result: Int)
        case descriptorPair(expected: AsyncFunctionDescriptor, base: Int, relative: Int, size: Int)
        case descriptorDisplacement(expected: AsyncFunctionDescriptor, base: Int, result: Int)
        case signExtendDescriptorOffset(register: Int)
        case resolveDescriptorTarget(descriptor: Int, displacement: Int, result: Int)
        case loadRuntimeDescriptor(RuntimeDescriptor, base: Int, displacement: Int, result: Int)
        case runtimeDescriptorSize(RuntimeDescriptor, base: Int, size: Int, result: Int)
        case requireRelativeTarget(register: Int, entry: UInt64)
        case requireImmediate(value: UInt64, register: Int)
        case insertMachineImmediate(field: UInt64, mask: UInt64, widthMask: UInt64, register: Int)
    }

    struct RuntimeDescriptor: Equatable {
        let slot: UInt64
        let reference: RuntimeFunctionReference
    }

    struct CapturedObject: Equatable {
        let allocation: UInt64
        let extent: Int
        let scalarStore: UInt64
        let scalarOffset: Int
    }

    struct BoxedOperation: Equatable {
        let allocation: UInt64
        let store: UInt64
        let extent: Int
        let descriptor: AsyncFunctionDescriptor
        let capture: CapturedObject
    }

    struct MachineStackWords {
        enum Update: Equatable { case none, preIndex, postIndex }
        let base: Int
        let offset: Int
        let registers: [Int]
        let load: Bool
        let update: Update
    }

    struct LiveContinuation {
        let activeAllocation: UInt64
        let parentAllocation: UInt64
        let continuation: UInt64
    }

    struct NormalReturn {
        let identity: AwaitIdentity
        let childGeneration: UInt64
        let continuationRegister: Int
        let producerSite: UInt64
    }

    struct Hop {
        let edge: Edge
        let resume: UInt64
        let inlinePreserved: ByteRange
        let queuedPreserved: ByteRange
    }

    enum Exit {
        case successors([UInt64])
        case hop(Hop)
    }

    struct Block {
        let effects: [Effect]
        let exit: Exit
    }

    /// The transfer model alone has no physical CFG or runtime certificate.
    struct ModelRegion {
        let entry: UInt64
        let taskGeneration: UInt64
        let blocks: [UInt64: Block]
    }

    struct Solution {
        let resume: UInt64
        let edges: Set<Edge>
        let words: [Int: AwaitIdentity]
    }

    private struct Word: Hashable {
        let allocation: UInt64
        let offset: Int
    }

    private struct Allocation: Equatable {
        let site: UInt64
        let extent: Int
    }

    private struct State {
        var stack: [Allocation] = []
        var registers: [Int: Value] = [:]
        var words: [Word: Value] = [:]
        var nativeSP = 0
        var nativeWords: [Int: Value] = [:]
        // A published address can expose pointers later read from its payload.
        // Reject the entire region and retain this fact even after retirement.
        var mayPublish = false

        mutating func join(_ other: State) -> Bool {
            guard stack == other.stack, nativeSP == other.nativeSP else { return false }
            registers = registers.filter { other.registers[$0.key] == $0.value }
            words = words.filter { other.words[$0.key] == $0.value }
            nativeWords = nativeWords.filter { other.nativeWords[$0.key] == $0.value }
            mayPublish = mayPublish || other.mayPublish
            return true
        }

        func word(at register: Int) -> Word? {
            guard case .pointer(let site, let offset)? = registers[register],
                  let allocation = stack.first(where: { $0.site == site }),
                  offset >= 0, offset.isMultiple(of: 8),
                  offset <= allocation.extent - 8
            else { return nil }
            return Word(allocation: site, offset: offset)
        }

        mutating func adjustMachineStack(by delta: Int) -> Bool {
            let (updated, overflow) = nativeSP.addingReportingOverflow(delta)
            guard !overflow, (-4096...0).contains(updated), updated.isMultiple(of: 16)
            else { return false }
            if updated > nativeSP {
                nativeWords = nativeWords.filter { $0.key >= updated }
                func survives(_ value: Value) -> Bool {
                    if case .machineFrame(let offset) = value { return offset >= updated }
                    return true
                }
                registers = registers.filter { survives($0.value) }
                nativeWords = nativeWords.filter { survives($0.value) }
            }
            nativeSP = updated
            return true
        }

        mutating func transferMachineStack(_ access: MachineStackWords) -> Bool {
            guard (1...2).contains(access.registers.count), Set(access.registers).count == access.registers.count,
                  access.registers.allSatisfy({ (0...30).contains($0) })
            else { return false }
            let base: Int
            if access.base == 31 { base = nativeSP }
            else if access.base == 29, case .machineFrame(let frame)? = registers[29] { base = frame }
            else { return false }
            guard access.update == .none || access.base == 31 else { return false }
            let displacement = access.update == .postIndex ? 0 : access.offset
            let (address, overflow) = base.addingReportingOverflow(displacement)
            guard !overflow, address.isMultiple(of: 8) else { return false }
            if access.update == .preIndex {
                guard adjustMachineStack(by: access.offset) else { return false }
            }
            guard address >= nativeSP, address <= -(8 * access.registers.count)
            else { return false }

            for (index, register) in access.registers.enumerated() {
                let coordinate = address + index * 8
                if access.load { registers[register] = nativeWords[coordinate] }
                else { nativeWords[coordinate] = registers[register] }
            }
            return access.update != .postIndex || adjustMachineStack(by: access.offset)
        }

        mutating func apply(_ effect: Effect, task: UInt64) -> Bool {
            switch effect {
            case .allocate(let site, let extent, let result):
                guard extent >= 0, !stack.contains(where: { $0.site == site }) else { return false }
                stack.append(.init(site: site, extent: extent))
                registers[result] = .pointer(allocation: site, offset: 0)
            case .copy(let source, let result):
                registers[result] = registers[source]
            case .offset(let base, let displacement, let result):
                guard case .pointer(let site, let offset)? = registers[base] else { return false }
                let (sum, overflow) = offset.addingReportingOverflow(displacement)
                guard !overflow else { return false }
                registers[result] = .pointer(allocation: site, offset: sum)
            case .forget(let register):
                registers.removeValue(forKey: register)
            case .immediate(let value, let result):
                registers[result] = .immediate(value)
            case .continuation(let target, let result):
                registers[result] = .continuation(target)
            case .returnedScalar(let identity, let result):
                registers[result] = .awaited(identity)
            case .integerInput(let origin, let result):
                registers[result] = .integerInput(origin)
            case .wrappingScalarAdd(let site, let source, let displacement, let result):
                let delta = UInt64(bitPattern: displacement)
                switch registers[source] {
                case .immediate(let old)?:
                    registers[result] = .integerSum(origin: nil, delta: old &+ delta, producerSite: site)
                case .integerInput(let origin)?:
                    registers[result] = .integerSum(origin: origin, delta: delta, producerSite: site)
                case .integerSum(let origin, let old, _)?:
                    registers[result] = .integerSum(origin: origin, delta: old &+ delta, producerSite: site)
                default: return false
                }
            case .requireLiveContinuation(let link):
                guard nativeSP == 0, stack.last?.site == link.activeAllocation,
                      stack.dropLast().last?.site == link.parentAllocation,
                      registers[22] == .pointer(allocation: link.activeAllocation, offset: 0),
                      words[Word(allocation: link.activeAllocation, offset: 0)]
                          == .pointer(allocation: link.parentAllocation, offset: 0),
                      words[Word(allocation: link.activeAllocation, offset: 8)]
                          == .continuation(link.continuation)
                else { return false }
            case .normalIntegerReturn(let result):
                let identity = result.identity
                guard nativeSP == 0, identity.taskGeneration == task, identity.carrier == .normalIntegerX0,
                      let child = stack.last, child.site == result.childGeneration,
                      stack.dropLast().last?.site == identity.ownerGeneration,
                      registers[22] == .pointer(allocation: child.site, offset: 0),
                      registers[result.continuationRegister] == .continuation(identity.returnEntry),
                      words[Word(allocation: child.site, offset: 8)] == .continuation(identity.returnEntry),
                      words[Word(allocation: child.site, offset: 0)]
                          == .pointer(allocation: identity.ownerGeneration, offset: 0)
                else { return false }
                guard case .integerSum(_, _, let producerSite)? = registers[0],
                      producerSite == result.producerSite else { return false }
                registers[0] = .awaited(identity)
            case .storeWord(let address, let source):
                guard let word = word(at: address) else { return false }
                switch registers[source] {
                case .machineFrame?, .boxedOperation?, .capturedObject?: return false
                case .pointer(let site, _)?: guard stack.contains(where: { $0.site == site }) else { return false }
                default: break
                }
                words[word] = registers[source]
            case .loadWord(let address, let result):
                guard let word = word(at: address) else { return false }
                registers[result] = words[word]
            case .clobber(let address, let byteCount):
                guard case .pointer(let site, let offset)? = registers[address],
                      let allocation = stack.first(where: { $0.site == site }),
                      byteCount > 0, offset >= 0, offset <= allocation.extent,
                      byteCount <= allocation.extent - offset
                else { return false }
                let bytes = offset..<(offset + byteCount)
                words = words.filter {
                    $0.key.allocation != site || !($0.key.offset..<($0.key.offset + 8)).overlaps(bytes)
                }
            case .publish:
                mayPublish = true
            case .adjustMachineStack(let delta):
                return adjustMachineStack(by: delta)
            case .formMachineFrame(let delta):
                let (address, overflow) = nativeSP.addingReportingOverflow(delta)
                guard !overflow, nativeSP <= address, address < 0 else { return false }
                registers[29] = .machineFrame(address)
            case .machineStackWords(let access):
                return transferMachineStack(access)
            case .insertMachineImmediate(let field, let mask, let widthMask, let register):
                if case .immediate(let old)? = registers[register] {
                    registers[register] = .immediate(((old & ~mask) | field) & widthMask)
                } else {
                    registers.removeValue(forKey: register)
                }
            case .activateBox(let box, let register):
                guard box.extent >= 32, box.allocation != box.capture.allocation,
                      box.capture.extent >= 8, box.capture.scalarOffset >= 0,
                      box.capture.scalarOffset <= box.capture.extent - 8
                else { return false }
                registers[register] = .boxedOperation(box)
            case .readBoxPair(let base, let descriptor, let capture):
                guard case .boxedOperation(let box)? = registers[base] else { return false }
                registers[descriptor] = .descriptor(box.descriptor)
                registers[capture] = .capturedObject(box.capture)
            case .capturedInteger(let base, let offset, let result):
                guard case .capturedObject(let object)? = registers[base],
                      offset == object.scalarOffset, offset <= object.extent - 8
                else { return false }
                registers[result] = .integerInput(object.scalarStore)
            case .continuationFromPage(let entry, let base, let delta, let result):
                guard case .immediate(let page)? = registers[base], delta >= 0,
                      case let (address, false) = page.addingReportingOverflow(UInt64(delta)),
                      address == entry
                else { return false }
                registers[result] = .continuation(entry)
            case .materializeLocalDescriptor(let record, let base, let delta, let result):
                guard case .immediate(let page)? = registers[base], delta >= 0,
                      case let (address, false) = page.addingReportingOverflow(UInt64(delta)),
                      address == record.address
                else { return false }
                registers[result] = .descriptor(record)
            case .descriptorSize(let record, let base, let result):
                guard registers[base] == .descriptor(record) else { return false }
                registers[result] = .immediate(UInt64(record.requiredContextSize))
            case .descriptorSizeFromPage(let record, let base, let displacement, let result):
                guard case .immediate(let page)? = registers[base], displacement >= 0,
                      case let (address, false) = page.addingReportingOverflow(UInt64(displacement)),
                      record.address <= UInt64.max - 4, address == record.address + 4
                else { return false }
                registers[result] = .immediate(UInt64(record.requiredContextSize))
            case .descriptorPair(let record, let base, let relative, let size):
                guard registers[base] == .descriptor(record) else { return false }
                registers[relative] = .relativeDisplacement(record, signed: false)
                registers[size] = .immediate(UInt64(record.requiredContextSize))
            case .descriptorDisplacement(let record, let base, let result):
                guard registers[base] == .descriptor(record) else { return false }
                registers[result] = .relativeDisplacement(record, signed: true)
            case .signExtendDescriptorOffset(let register):
                guard case .relativeDisplacement(let record, signed: false)? = registers[register]
                else { return false }
                registers[register] = .relativeDisplacement(record, signed: true)
            case .resolveDescriptorTarget(let descriptor, let displacement, let result):
                guard case .descriptor(let record)? = registers[descriptor],
                      registers[displacement] == .relativeDisplacement(record, signed: true)
                else { return false }
                registers[result] = .continuation(record.entry)
            case .loadRuntimeDescriptor(let descriptor, let base, let displacement, let result):
                guard case .immediate(let page)? = registers[base], displacement >= 0,
                      case let (slot, false) = page.addingReportingOverflow(UInt64(displacement)),
                      slot == descriptor.slot
                else { return false }
                registers[result] = .runtimeDescriptor(descriptor)
            case .runtimeDescriptorSize(let descriptor, let base, let size, let result):
                guard registers[base] == .runtimeDescriptor(descriptor), size >= 0 else { return false }
                registers[result] = .immediate(UInt64(size))
            case .requireRelativeTarget(let register, let entry):
                guard nativeSP == 0, registers[register] == .continuation(entry) else { return false }
            case .requireImmediate(let value, let register):
                guard registers[register] == .immediate(value) else { return false }
            case .release(let operand):
                guard let top = stack.last,
                      registers[operand] == .pointer(allocation: top.site, offset: 0)
                else { return false }
                stack.removeLast()
                func survives(_ value: Value) -> Bool {
                    if case .pointer(let site, _) = value { return site != top.site }
                    return true
                }
                registers = registers.filter { survives($0.value) }
                words = words.filter { $0.key.allocation != top.site && survives($0.value) }
                nativeWords = nativeWords.filter { survives($0.value) }
            }
            return true
        }

        func slots(_ hop: Hop, task: UInt64) -> (UInt64, [Int: AwaitIdentity])? {
            guard !mayPublish, nativeSP == 0, let owner = stack.last,
                  registers[22] == .pointer(allocation: owner.site, offset: 0),
                  registers[0] == .continuation(hop.resume),
                  registers[1] == .immediate(0), registers[2] == .immediate(0),
                  hop.inlinePreserved.allocation == owner.site,
                  hop.queuedPreserved.allocation == owner.site
            else { return nil }
            var slots: [Int: AwaitIdentity] = [:]
            for (word, value) in words where word.allocation == owner.site && word.offset >= 16 {
                guard case .awaited(let identity) = value,
                      identity.taskGeneration == task, identity.ownerGeneration == owner.site,
                      identity.carrier == .normalIntegerX0, identity.returnEntry == hop.edge.source,
                      hop.inlinePreserved.bytes.contains(word.offset),
                      hop.inlinePreserved.bytes.contains(word.offset + 7),
                      hop.queuedPreserved.bytes.contains(word.offset),
                      hop.queuedPreserved.bytes.contains(word.offset + 7)
                else { continue }
                slots[word.offset] = identity
            }
            return (owner.site, slots)
        }
    }

    static func solve(_ region: ModelRegion) -> Solution? {
        // Bound alternate states and reject cyclic allocation lifetimes.
        guard region.blocks.count <= 256, region.blocks[region.entry] != nil else { return nil }
        var incoming = Dictionary(uniqueKeysWithValues: region.blocks.keys.map { ($0, 0) })
        var allocationSites: Set<UInt64> = []
        for block in region.blocks.values {
            guard block.effects.count <= 256 else { return nil }
            for effect in block.effects {
                if case .allocate(let site, _, _) = effect,
                   !allocationSites.insert(site).inserted { return nil }
            }
            if case .successors(let targets) = block.exit {
                guard !targets.isEmpty, Set(targets).count == targets.count else { return nil }
                for target in targets {
                    guard let count = incoming[target] else { return nil }
                    incoming[target] = count + 1
                }
            }
        }
        guard incoming[region.entry] == 0 else { return nil }

        var pending = [region.entry]
        var states: [UInt64: State] = [region.entry: State()]
        var visited = 0
        var destination: UInt64?
        var ownerSite: UInt64?
        var joined: [Int: AwaitIdentity]?
        var edges: Set<Edge> = []
        while let address = pending.popLast() {
            guard let block = region.blocks[address],
                  var state = states.removeValue(forKey: address)
            else { return nil }
            visited += 1
            for effect in block.effects where !state.apply(effect, task: region.taskGeneration) { return nil }
            switch block.exit {
            case .successors(let targets):
                for target in targets {
                    if var prior = states[target] {
                        guard prior.join(state) else { return nil }
                        states[target] = prior
                    } else {
                        states[target] = state
                    }
                    guard let degree = incoming[target], degree > 0 else { return nil }
                    incoming[target] = degree - 1
                    if degree == 1 { pending.append(target) }
                }
            case .hop(let hop):
                guard let (owner, words) = state.slots(hop, task: region.taskGeneration),
                      destination.map({ $0 == hop.resume }) ?? true,
                      ownerSite.map({ $0 == owner }) ?? true,
                      edges.insert(hop.edge).inserted
                else { return nil }
                destination = hop.resume
                ownerSite = owner
                joined = joined.map { $0.filter { words[$0.key] == $0.value } } ?? words
            }
        }
        guard visited == region.blocks.count, let destination, let joined, !joined.isEmpty else { return nil }
        return Solution(resume: destination, edges: edges, words: joined)
    }
}
