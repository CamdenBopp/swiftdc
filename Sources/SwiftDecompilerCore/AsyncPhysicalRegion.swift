import Ccapstone

/// Machine-bound portion of the scalar interval. Runtime actions are requests,
/// never solved effects. An admitted region additionally needs complete
/// enclosing ingress, private task identity and all runtime alternatives.
struct AsyncPhysicalRegion {
    enum RuntimeRole: Equatable {
        case allocateBox
        case createDetachedTask
        case allocateContext
        case releaseContext(pointerRegister: Int)
        case awaitImportedContinuation(descriptorSlot: UInt64, descriptor: RuntimeFunctionReference)
        case switchExecutor
    }

    struct EffectRequest {
        let role: RuntimeRole
        let site: UInt64
        let word: UInt32
        let binding: AsyncCheckedImage.Binding
    }

    enum Step {
        case machine([AsyncClosedCallerSolver.Effect])
        case runtime(EffectRequest)
        case wrappingScalarAdd(source: Int, displacement: Int64, result: Int)
        case runtimeDescriptorSize(AsyncClosedCallerSolver.RuntimeDescriptor, base: Int, result: Int)
        case unresolved
    }

    struct InstructionStep {
        let site: UInt64
        let word: UInt32
        let step: Step
        let flow: ControlFlow
        let physicalSuccessors: [UInt64]
    }

    struct ReturnSupplier {
        let tailSite: UInt64
        let callerGeneration: UInt64
        let childGeneration: UInt64
    }

    /// Linker folding can unify a resume address while the incoming owner
    /// generations differ. This is a supplier inventory, not full ingress.
    let sharedReturns: [UInt64: [ReturnSupplier]]
    let ownerAllocationSite: UInt64
    let childAllocationSite: UInt64
    let savedChildOffset: Int
    let ownerSlot: Int
    let childSavedParentResume: UInt64
    let yieldResume: UInt64
    let yieldAllocationSite: UInt64
    let producerArithmetic: UInt64
    let producerReturn: UInt64
    let switchResume: UInt64
    let sinkCall: UInt64
    let sinkEntry: UInt64
    let increment: Int64
    let steps: [InstructionStep]
    let requests: [EffectRequest]

    static func extract(
        detached: AsyncDetachedIngress,
        bindings: [UInt64: AsyncCheckedImage.Binding],
        body: (UInt64) -> [Instruction]?,
        wordAt: (UInt64) -> UInt32?,
        dataImportAt: (UInt64) -> RuntimeFunctionReference?
    ) -> Self? {
        // The scoped implementation starts with the four direct handoffs in
        // the physical closure-to-await chain. No symbol determines the role.
        guard detached.directTails.count == 4,
              let ownerEntry = detached.directTails.dropLast().last,
              let awaited = detached.directTails.last,
              ownerEntry.handoff.descriptor.entry == awaited.function,
              let ownerCode = body(awaited.function), ownerCode.count >= 13,
              let child = body(awaited.handoff.descriptor.entry),
              let ownerReturn = body(awaited.returnEntry)
        else { return nil }

        func match(_ code: [Instruction], _ words: [UInt32?]) -> Bool {
            code.count == words.count && zip(code, words).allSatisfy { insn, expected in
                expected.map { wordAt(insn.address) == $0 } ?? true
            }
        }

        func request(_ insn: Instruction, _ role: RuntimeRole,
                     symbol: String? = nil, isTail: Bool = false) -> EffectRequest? {
            guard insn.controlFlow == (isTail ? .branch : .call),
                  insn.detail?.id == (isTail ? AARCH64_INS_B : AARCH64_INS_BL),
                  let target = insn.branchTarget, let binding = bindings[target],
                  binding.reference.libraryName == "/usr/lib/swift/libswift_Concurrency.dylib",
                  symbol.map({ binding.reference.rawSymbol == $0 }) ?? true,
                  let word = wordAt(insn.address)
            else { return nil }
            return EffectRequest(role: role, site: insn.address, word: word, binding: binding)
        }

        func materializedAddress(_ page: Instruction, _ add: Instruction, register: Int) -> UInt64? {
            guard let p = page.detail, p.id == AARCH64_INS_ADRP, p.operands.count == 2,
                  let a = add.detail, a.id == AARCH64_INS_ADD, a.operands.count == 3, !a.updatesFlags,
                  let r = p.operands[0].operand.register, r.kind == .gpr, r.number == register,
                  r.widthBits == 64, a.operands[0].operand.register == r, a.operands[1].operand.register == r,
                  let origin = p.operands[1].operand.immediateValue,
                  let delta = a.operands[2].shiftedImmediate, delta >= 0
            else { return nil }
            let (address, overflow) = UInt64(bitPattern: origin).addingReportingOverflow(UInt64(delta))
            return overflow ? nil : address
        }

        // Trailing words deliberately exclude PC-relative fields and bound
        // edges checked below. Fixed words include register widths, store
        // ranges, stack operations and absence of bypass branches.
        let prologue: [UInt32?] = [0xb24403bd, 0xd10083ff, 0xa9017bfd, 0xf90007f6, 0x910043fd]
        guard let savedChildStore = wordAt(ownerCode[ownerCode.count - 10].address),
              savedChildStore == 0xf9000ac0, // str x0,[x22,#16] at the C allocation handoff
              match(child, prologue + [
                0xf9000ac0, nil, nil, 0xb9400500, nil, 0xf9000ec0, nil, nil,
                0xa9002016, 0xaa0003f6, 0xa9417bfd, 0x9243fbbd, 0x910083ff, nil,
              ]),
              child[6].detail?.id == AARCH64_INS_ADRP, child[7].detail?.id == AARCH64_INS_LDR,
              case .loaded(let descriptorSlot)? =
                ValueTracer().finalState(of: Array(child[6...7]))["x8"],
              let descriptorImport = dataImportAt(descriptorSlot),
              let loadGot = wordAt(child[7].address), loadGot & 0xffc003ff == 0xf9400108,
              let yieldCall = request(child[18], .awaitImportedContinuation(
                  descriptorSlot: descriptorSlot, descriptor: descriptorImport), isTail: true),
              descriptorImport.libraryName == yieldCall.binding.reference.libraryName,
              descriptorImport.rawSymbol == yieldCall.binding.reference.rawSymbol + "Tu",
              let yieldAllocation = request(child[9], .allocateContext, symbol: "_swift_task_alloc"),
              let yieldResume = materializedAddress(child[11], child[12], register: 8),
              let childReturn = body(yieldResume),
              match(childReturn, prologue + [
                0xf94002c8, 0xf81f83a8, 0xa9410114, 0xf94002d6, nil,
                0xf94006c1, 0x91000680, 0xa9417bfd, 0x9243fbbd, 0x910083ff, 0xd61f0020,
              ]),
              let releaseYield = request(childReturn[9], .releaseContext(pointerRegister: 0),
                                         symbol: "_swift_task_dealloc"),
              match(ownerReturn, prologue + [
                0xf94002c9, 0xf81f83a9, 0xf9400928, 0xf94002d6, 0xf9000d20, 0xaa0803e0,
                nil, nil, nil, 0xd2800001, 0xd2800002, 0xa9417bfd, 0x9243fbbd, 0x910083ff, nil,
              ]),
              let releaseChild = request(ownerReturn[11], .releaseContext(pointerRegister: 0),
                                         symbol: "_swift_task_dealloc"),
              let hop = request(ownerReturn[19], .switchExecutor, symbol: "_swift_task_switch", isTail: true),
              let switchResume = materializedAddress(ownerReturn[12], ownerReturn[13], register: 0),
              let resumed = body(switchResume), resumed.count >= 11,
              let load = wordAt(resumed[5].address), load == 0xf9400ec8,
              let add = wordAt(resumed[6].address), add & 0xffc003ff == 0x91000100,
              resumed[10].controlFlow == .call, resumed[10].detail?.id == AARCH64_INS_BL,
              let sink = resumed[10].branchTarget, body(sink) != nil,
              match(Array(resumed.prefix(5)), prologue),
              resumed[7...9].allSatisfy({ insn in
                  guard insn.controlFlow == .sequential, let detail = insn.detail, !detail.updatesFlags,
                        [AARCH64_INS_MOV, AARCH64_INS_MOVK].contains(detail.id),
                        detail.operands.count == 2,
                        !detail.operands.contains(where: {
                            if case .memory = $0.operand { return true }
                            return false
                        }),
                        detail.writtenRegisterKeys.isSubset(of: ["x1", "x2"]),
                        let reg = detail.operands.first?.operand.register, reg.kind == .gpr
                  else { return false }
                  return [1, 2].contains(reg.number)
              })
        else { return nil }

        var operations = [yieldAllocation, yieldCall, releaseYield, releaseChild, hop]
        for (site, binding, role) in [
            (detached.boxAllocation.site, detached.boxAllocation.binding, RuntimeRole.allocateBox),
            (detached.create.site, detached.create.binding, RuntimeRole.createDetachedTask),
        ] {
            guard let word = wordAt(site) else { return nil }
            operations.append(.init(role: role, site: site, word: word, binding: binding))
        }
        for tail in detached.relativeTails {
            let alloc = tail.allocation
            guard let word = wordAt(alloc.site) else { return nil }
            operations.append(.init(role: .allocateContext, site: alloc.site, word: word, binding: alloc.binding))
        }
        for tail in detached.directTails {
            guard let code = body(tail.function),
                  let instruction = code.first(where: { $0.address == tail.handoff.allocationCall }),
                  let alloc = request(instruction, .allocateContext, symbol: "_swift_task_alloc")
            else { return nil }
            operations.append(alloc)
        }

        // Translate only modeled value effects. Each instruction without a
        // model is explicitly unresolved, including stack effects and returns.
        // Virtual temporary 32 holds an effective address, never a physical SP.
        guard detached.relativeTails.count == 2,
              let wrapperTail = detached.relativeTails.first, let adapterTail = detached.relativeTails.last,
              let wrapper = body(wrapperTail.function), wrapper.count == 28,
              let adapter = body(adapterTail.function), adapter.count == 25,
              let localDescriptorAdd = wrapper[9].detail?.operands.last?.shiftedImmediate,
              let descriptorDelta = Int(exactly: localDescriptorAdd),
              let capturedEntry = detached.directTails.first,
              let captured = body(capturedEntry.function), captured.count > 5,
              wordAt(captured[5].address) == 0xf9401294
        else { return nil }
        let importedDescriptor = AsyncClosedCallerSolver.RuntimeDescriptor(
            slot: descriptorSlot, reference: descriptorImport)
        func relativeContinuation(_ add: Instruction, entry: UInt64, register: Int)
            -> [AsyncClosedCallerSolver.Effect]? {
            guard let info = add.detail, info.id == AARCH64_INS_ADD,
                  info.operands.count == 3, let target = info.operands[0].operand.register,
                  target.kind == .gpr, target.widthBits == 64, target.number == register,
                  info.operands[1].operand.register == target,
                  let delta = info.operands[2].shiftedImmediate, let immediate = Int(exactly: delta)
            else { return nil }
            return [.continuationFromPage(entry: entry, base: register, delta: immediate, result: register)]
        }
        guard let startYield = relativeContinuation(child[12], entry: yieldResume, register: 8),
              let startSwitch = relativeContinuation(ownerReturn[13], entry: switchResume, register: 0),
              let wrapperReturn = relativeContinuation(wrapper[15], entry: wrapperTail.returnEntry, register: 9),
              let adapterReturn = relativeContinuation(adapter[16], entry: adapterTail.returnEntry, register: 9)
        else { return nil }
        let temp = 32
        var lifted: [UInt64: [AsyncClosedCallerSolver.Effect]] = [
            ownerCode[ownerCode.count - 10].address:
                [.offset(base: 22, by: 16, result: temp), .storeWord(address: temp, source: 0)],
            child[5].address: [.offset(base: 22, by: 16, result: temp), .storeWord(address: temp, source: 0)],
            child[7].address: [.loadRuntimeDescriptor(importedDescriptor, base: 8,
                displacement: Int((loadGot >> 10) & 0xfff) * 8, result: 8)],
            child[10].address: [.offset(base: 22, by: 24, result: temp), .storeWord(address: temp, source: 0)],
            child[12].address: startYield,
            child[13].address: [.storeWord(address: 0, source: 22),
                .offset(base: 0, by: 8, result: temp), .storeWord(address: temp, source: 8)],
            child[14].address: [.copy(from: 0, to: 22)],
            childReturn[5].address: [.loadWord(address: 22, result: 8)],
            childReturn[7].address: [
                .offset(base: 8, by: 16, result: temp), .loadWord(address: temp, result: 20),
                .offset(base: 8, by: 24, result: temp), .loadWord(address: temp, result: 0),
            ],
            childReturn[8].address: [.loadWord(address: 22, result: 22)],
            childReturn[10].address: [.offset(base: 22, by: 8, result: temp), .loadWord(address: temp, result: 1)],
            ownerReturn[5].address: [.loadWord(address: 22, result: 9)],
            ownerReturn[7].address: [.offset(base: 9, by: 16, result: temp), .loadWord(address: temp, result: 8)],
            ownerReturn[8].address: [.loadWord(address: 22, result: 22)],
            ownerReturn[9].address: [.offset(base: 9, by: 24, result: temp), .storeWord(address: temp, source: 0)],
            ownerReturn[10].address: [.copy(from: 8, to: 0)],
            ownerReturn[13].address: startSwitch,
            ownerReturn[14].address: [.immediate(0, result: 1)],
            ownerReturn[15].address: [.immediate(0, result: 2)],
            resumed[5].address: [.offset(base: 22, by: 24, result: temp), .loadWord(address: temp, result: 8)],
        ]
        lifted[wrapper[7].address] = [.readBoxPair(base: 20, descriptor: 21, capture: 20)]
        lifted[wrapper[9].address] = [.materializeLocalDescriptor(expected: wrapperTail.descriptor,
            base: 23, delta: descriptorDelta, result: 23)]
        lifted[wrapper[10].address] = [.descriptorSize(expected: wrapperTail.descriptor, base: 23, result: 0)]
        lifted[wrapper[13].address] = [.offset(base: 22, by: 16, result: temp), .storeWord(address: temp, source: 0)]
        lifted[wrapper[15].address] = wrapperReturn
        lifted[wrapper[16].address] = [.storeWord(address: 0, source: 22),
            .offset(base: 0, by: 8, result: temp), .storeWord(address: temp, source: 9)]
        lifted[wrapper[17].address] = [.descriptorDisplacement(expected: wrapperTail.descriptor, base: 23, result: 9)]
        lifted[wrapper[18].address] = [.resolveDescriptorTarget(descriptor: 23, displacement: 9, result: 3)]
        lifted[wrapperTail.branch] = [.requireRelativeTarget(register: 3, entry: wrapperTail.descriptor.entry)]

        lifted[adapter[8].address] = [.descriptorPair(expected: adapterTail.descriptor, base: 1, relative: 8, size: 0)]
        lifted[adapter[9].address] = [.signExtendDescriptorOffset(register: 8)]
        lifted[adapter[10].address] = [.resolveDescriptorTarget(descriptor: 1, displacement: 8, result: 1)]
        lifted[adapter[14].address] = [.offset(base: 22, by: 16, result: temp), .storeWord(address: temp, source: 0)]
        lifted[adapter[16].address] = adapterReturn
        lifted[adapter[17].address] = [.storeWord(address: 0, source: 22),
            .offset(base: 0, by: 8, result: temp), .storeWord(address: temp, source: 9)]
        lifted[adapterTail.branch] = [.requireRelativeTarget(register: 1, entry: adapterTail.descriptor.entry)]
        lifted[captured[5].address] = [.capturedInteger(base: 20, offset: 32, result: 20)]

        // P saves the input in its live context before allocating its
        // child. This particular 64-bit store is outside the C7 suffix.
        guard let parentTail = detached.directTails.dropLast().last,
              let parent = body(parentTail.function), parent.count > 6,
              wordAt(parent[6].address) == 0xf9000ac0
        else { return nil }
        lifted[parent[6].address] = [.offset(base: 22, by: 16, result: temp), .storeWord(address: temp, source: 0)]

        for tail in detached.directTails {
            guard let code = body(tail.function), code.count >= 13,
                  let scratch = code[code.count - 9].detail?.operands.first?.operand.register?.number,
                  let sizeWord = wordAt(tail.handoff.sizeLoad), sizeWord & 0xffc0001f == 0xb9400000,
                  let saveWord = wordAt(code[code.count - 10].address), saveWord & 0xffc003ff == 0xf90002c0,
                  let resumeOperand = relativeContinuation(code[code.count - 8],
                      entry: tail.returnEntry, register: scratch)
            else { return nil }
            lifted[tail.handoff.sizeLoad] = [.descriptorSizeFromPage(expected: tail.handoff.descriptor,
                base: Int((sizeWord >> 5) & 31), displacement: Int((sizeWord >> 10) & 0xfff) * 4, result: 0)]
            lifted[code[code.count - 10].address] = [.offset(base: 22, by: Int((saveWord >> 10) & 0xfff) * 8, result: temp),
                .storeWord(address: temp, source: 0)]
            lifted[code[code.count - 8].address] = resumeOperand
            lifted[code[code.count - 7].address] = [.storeWord(address: 0, source: 22),
                .offset(base: 0, by: 8, result: temp), .storeWord(address: temp, source: scratch)]
            lifted[code[code.count - 6].address] = [.copy(from: 0, to: 22)]
        }
        let arithmetic: [UInt64: Step] = [
            childReturn[11].address: .wrappingScalarAdd(source: 20, displacement: 1, result: 0),
            resumed[6].address: .wrappingScalarAdd(source: 8, displacement: Int64((add >> 10) & 0xfff), result: 0),
        ]
        var requestsAt: [UInt64: EffectRequest] = [:]
        for operation in operations {
            guard requestsAt.updateValue(operation, forKey: operation.site) == nil else { return nil }
        }
        var steps: [UInt64: InstructionStep] = [:]
        for (site, physical) in detached.sites {
            let step: Step
            if site == child[8].address {
                step = .runtimeDescriptorSize(importedDescriptor, base: 8, result: 0)
            } else {
                step = lifted[site].map(Step.machine) ?? requestsAt[site].map(Step.runtime)
                    ?? AsyncPhysicalInstructionLifter.lift(physical.word, at: site, flow: physical.flow,
                                                           successors: physical.successors).map(Step.machine)
                    ?? .unresolved
            }
            steps[site] = .init(site: site, word: physical.word, step: step, flow: physical.flow,
                                physicalSuccessors: physical.successors)
        }
        for code in [childReturn, ownerReturn, Array(resumed.prefix(11))] {
            for (index, insn) in code.enumerated() {
                guard let word = wordAt(insn.address), let flow = insn.controlFlow else { return nil }
                let next = index + 1 < code.count ? [code[index + 1].address] : []
                let successors: [UInt64]
                switch insn.controlFlow {
                case .sequential?: successors = next
                case .call?: successors = (insn.branchTarget.map { [$0] } ?? []) + next
                case .branch?: successors = insn.branchTarget.map { [$0] } ?? []
                default: return nil
                }
                let step = arithmetic[insn.address] ?? lifted[insn.address].map(Step.machine)
                    ?? requestsAt[insn.address].map(Step.runtime)
                    ?? AsyncPhysicalInstructionLifter.lift(word, at: insn.address, flow: flow,
                                                           successors: successors).map(Step.machine)
                    ?? .unresolved
                steps[insn.address] = .init(site: insn.address, word: word, step: step, flow: flow,
                                           physicalSuccessors: successors)
            }
        }

        var suppliers: [UInt64: [ReturnSupplier]] = [:]
        var callerGeneration = detached.create.site
        for tail in detached.relativeTails {
            let child = tail.allocation.site
            suppliers[tail.returnEntry, default: []].append(.init(
                tailSite: tail.branch, callerGeneration: callerGeneration, childGeneration: child))
            callerGeneration = child
        }
        for tail in detached.directTails {
            let child = tail.handoff.allocationCall
            suppliers[tail.returnEntry, default: []].append(.init(
                tailSite: tail.branch, callerGeneration: callerGeneration, childGeneration: child))
            callerGeneration = child
        }
        return Self(sharedReturns: suppliers.filter { $0.value.count > 1 }, ownerAllocationSite: ownerEntry.handoff.allocationCall,
                    childAllocationSite: awaited.handoff.allocationCall,
                    savedChildOffset: 16, ownerSlot: 24,
                    childSavedParentResume: awaited.returnEntry, yieldResume: yieldResume,
                    yieldAllocationSite: yieldAllocation.site,
                    producerArithmetic: childReturn[11].address, producerReturn: childReturn[15].address,
                    switchResume: switchResume, sinkCall: resumed[10].address, sinkEntry: sink,
                    increment: Int64((add >> 10) & 0xfff),
                    steps: steps.values.sorted { $0.site < $1.site }, requests: operations)
    }
}
