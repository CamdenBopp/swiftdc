import Ccapstone

/// Structural evidence for the compiler's separate detached-task startup.
/// Register/data provenance identifies edges and operands. Runtime effects
/// (including creation of a fresh task, box identity and actual writes) remain
/// obligations of the admitted execution configuration.
struct AsyncDetachedIngress {
    struct Operation {
        let site: UInt64
        let binding: AsyncCheckedImage.Binding
    }

    struct RelativeTail {
        let function: UInt64
        let branch: UInt64
        let returnEntry: UInt64
        let allocation: Operation
        let descriptor: AsyncFunctionDescriptor
    }

    struct DirectTail {
        let function: UInt64
        let branch: UInt64
        let returnEntry: UInt64
        let handoff: AsyncDescriptorHandoff
    }

    /// All physical instruction sites included in the observed path, with
    /// possible successors. Return and runtime targets need separate proof.
    struct Site {
        let word: UInt32
        let flow: ControlFlow
        let successors: [UInt64]
        let importedOperation: AsyncCheckedImage.Binding?
        let unresolvedTransfer: Bool
    }

    let driver: UInt64
    let boxAllocation: Operation
    let boxStore: UInt64
    let closureStoreOffset: Int
    let captureStoreOffset: Int
    let create: Operation
    let startupDescriptor: AsyncFunctionDescriptor
    let closureDescriptor: AsyncFunctionDescriptor
    let relativeTails: [RelativeTail]
    let directTails: [DirectTail]
    let sites: [UInt64: Site]

    static func extract(
        from candidates: [UInt64: [Instruction]],
        startup: AsyncCheckedImage.Startup,
        bindings: [UInt64: AsyncCheckedImage.Binding],
        startupSwitches: [UInt64: AsyncCheckedImage.StartupSwitch],
        body: (UInt64) -> [Instruction]?,
        descriptor: @escaping (UInt64, UInt64?) -> AsyncFunctionDescriptor?,
        metadataOffset: (UInt64) -> Int?,
        wordAt: (UInt64) -> UInt32?
    ) -> Self? {
        struct Create {
            let driver: UInt64
            let box: Operation
            let store: UInt64
            let operation: Operation
            let startup: AsyncFunctionDescriptor
            let closure: AsyncFunctionDescriptor
        }

        func bound(_ instruction: Instruction, symbol: String, concurrency: Bool) -> Operation? {
            guard instruction.controlFlow == .call, instruction.detail?.id == AARCH64_INS_BL,
                  let target = instruction.branchTarget, let binding = bindings[target],
                  binding.reference.rawSymbol == symbol
            else { return nil }
            let provider = binding.reference.libraryName
            guard concurrency ? provider == "/usr/lib/swift/libswift_Concurrency.dylib"
                : ["/usr/lib/swift/libswiftCore.dylib", "@rpath/libswiftCore.dylib"].contains(provider)
            else { return nil }
            return Operation(site: instruction.address, binding: binding)
        }

        func matches(_ body: [Instruction], _ pattern: [UInt32?]) -> Bool {
            body.count == pattern.count && zip(body, pattern).allSatisfy { instruction, expected in
                expected.map { wordAt(instruction.address) == $0 } ?? true
            }
        }

        func address(_ page: Instruction, _ add: Instruction, register: Int) -> UInt64? {
            guard let p = page.detail, p.id == AARCH64_INS_ADRP, !p.writeback, p.operands.count == 2,
                  let a = add.detail, a.id == AARCH64_INS_ADD, !a.writeback, a.operands.count == 3,
                  let reg = p.operands[0].operand.register,
                  reg.kind == .gpr, reg.number == register, reg.widthBits == 64,
                  a.operands[0].operand.register == reg, a.operands[1].operand.register == reg,
                  let base = p.operands[1].operand.immediateValue,
                  let displacement = a.operands[2].shiftedImmediate, displacement >= 0
            else { return nil }
            let (value, overflow) = UInt64(bitPattern: base).addingReportingOverflow(UInt64(displacement))
            return overflow ? nil : value
        }

        // Require exact local predecessor edges at every instruction of the
        // operand-producing region. Other caller ingress is recorded by the
        // independent whole-executable check and is not closed here.
        func localSuffixIsIsolated(_ code: [Instruction], start: Int, end: Int) -> Bool {
            let interior = Set(code[(start + 1)...end].map(\.address))
            return !code.contains { insn in
                guard insn.controlFlow == .branch || insn.controlFlow == .conditionalBranch
                        || insn.controlFlow == .call,
                      let target = insn.branchTarget else { return false }
                return interior.contains(target)
            }
        }

        var creates: [Create] = []
        for (driver, code) in candidates where driver != startup.main {
            for i in code.indices where i >= 24 {
                guard let create = bound(code[i], symbol: "_swift_task_create", concurrency: true),
                      create.binding.stub == startup.create.stub,
                      localSuffixIsIsolated(code, start: i - 17, end: i),
                      let box = bound(code[i - 12], symbol: "_swift_allocObject", concurrency: false),
                      let closureAddress = address(code[i - 10], code[i - 9], register: 8),
                      let entryAddress = address(code[i - 5], code[i - 4], register: 3),
                      let closure = descriptor(closureAddress, nil), let root = descriptor(entryAddress, nil)
                else { continue }
                // Both priority arms define x20 as 0x1000 | low8. Bind the
                // real branch targets independently of the immediate fields.
                // The call itself and effects before this join need admission.
                let a = Array(code[(i - 24)...i])
                guard matches(a, [
                    nil, 0x52820014, nil, 0xf9400ad4, nil, 0x52820014, 0xb3401c14,
                    0xf9400ad3, nil, nil, 0x52800401, 0x528000e2, nil, 0xaa0003e4,
                    nil, nil, 0xa9015408, nil, nil, nil, nil, 0x910022a2, 0xaa1403e0,
                    0xd2800001, nil,
                ]),
                      code[i - 24].controlFlow == .conditionalBranch,
                      code[i - 24].branchTarget == code[i - 21].address,
                      code[i - 22].controlFlow == .branch,
                      code[i - 22].branchTarget == code[i - 17].address,
                      code[i - 20].controlFlow == .call,
                      code[i - 20].branchTarget.flatMap({ bindings[$0] }) != nil,
                      localSuffixIsIsolated(code, start: i - 21, end: i - 18)
                else { continue }
                let metadataPrefix = Array(code[(i - 7)...(i - 6)])
                guard case .loaded(let metadataAddress)? = ValueTracer().finalState(of: metadataPrefix)["x21"],
                      let gotPage = code[i - 7].detail, gotPage.id == AARCH64_INS_ADRP,
                      let gotLoad = code[i - 6].detail, gotLoad.id == AARCH64_INS_LDR,
                      metadataOffset(metadataAddress) == startup.metadataFileOffset
                else { continue }
                creates.append(.init(driver: driver, box: box, store: code[i - 8].address,
                                     operation: create, startup: root, closure: closure))
            }
        }
        guard creates.count == 1, let create = creates.first,
              let root = body(create.startup.entry), root.count == 28,
              let wrapperDescriptorAddress = address(root[8], root[9], register: 23),
              let wrapperResume = address(root[14], root[15], register: 9),
              let wrapperDescriptor = descriptor(wrapperDescriptorAddress, nil),
              let wrapperAlloc = bound(root[11], symbol: "_swift_task_alloc", concurrency: true),
              matches(root, [
                0xb24403bd, 0xf81d0ff7, 0xa900cff5, 0xa9027bfd, 0xf9000ff6, 0x910083fd,
                0xaa0003f3, 0xa9415295, nil, nil, 0xb94006e0, nil, 0xaa0003e8, 0xf9000ac0,
                nil, nil, 0xa9002416, 0xb98002e9, 0x8b170123, 0xaa1303e0, 0xaa0803f6,
                0xaa1503e1, 0xaa1403e2, 0xa9427bfd, 0xa940cff5, 0xf84307f7, 0x9243fbbd, 0xd61f0060,
              ]),
              body(wrapperResume) != nil,
              let reabstract = body(wrapperDescriptor.entry), reabstract.count == 25,
              let reabstractResume = address(reabstract[15], reabstract[16], register: 9),
              let reabstractAlloc = bound(reabstract[12], symbol: "_swift_task_alloc", concurrency: true),
              matches(reabstract, [
                0xb24403bd, 0xd100c3ff, 0xf9000bf3, 0xa9027bfd, 0xf9000ff6, 0x910083fd,
                0xaa0203f4, 0xaa0003f3, 0x29400028, 0x93407d08, 0x8b010101, 0xf90007e1,
                nil, 0xaa0003e8, 0xf9000ac0, nil, nil, 0xa9002416, 0xaa1303e0, 0xaa0803f6,
                0xa940cfe1, 0xa9427bfd, 0x9243fbbd, 0x9100c3ff, 0xd61f0020,
              ]),
              body(reabstractResume) != nil,
              let rootBranch = root.last?.address, let reabstractBranch = reabstract.last?.address
        else { return nil }

        let relative = [
            RelativeTail(function: create.startup.entry, branch: rootBranch, returnEntry: wrapperResume,
                         allocation: wrapperAlloc, descriptor: wrapperDescriptor),
            RelativeTail(function: wrapperDescriptor.entry, branch: reabstractBranch,
                         returnEntry: reabstractResume, allocation: reabstractAlloc, descriptor: create.closure),
        ]
        var direct: [DirectTail] = []
        var seen: Set<UInt64> = []
        var source = create.closure.entry
        while direct.count < 8, seen.insert(source).inserted, let code = body(source),
              code.count >= 13, let branch = code.last, let target = branch.branchTarget,
              let savedReturn = code[code.count - 9].detail?.operands.first?.operand.register,
              let resume = address(code[code.count - 9], code[code.count - 8],
                                   register: savedReturn.number),
              body(resume) != nil,
              let handoff = AsyncDescriptorHandoff.prove(code, source: source, site: branch.address,
                  resume: resume, entry: target, outgoingScalarRegister: direct.isEmpty ? 3 : 0,
                  evidence: .init(allocatorAt: { bindings[$0]?.reference }, descriptorAt: descriptor))
        {
            direct.append(.init(function: source, branch: branch.address,
                                returnEntry: resume, handoff: handoff))
            source = target
        }
        guard !direct.isEmpty else { return nil }

        var sites: [UInt64: Site] = [:]
        let observedStarts = Set([create.driver, create.startup.entry, wrapperDescriptor.entry, source]
            + direct.flatMap { [$0.function, $0.returnEntry] } + relative.map(\.returnEntry)
            + startupSwitches.values.map(\.source))
        guard rootBranch != reabstractBranch else { return nil }
        let relativeTargets = [rootBranch: wrapperDescriptor.entry, reabstractBranch: create.closure.entry]
        for start in observedStarts {
            guard let code = body(start) else { return nil }
            for i in code.indices {
                let insn = code[i]
                guard let word = wordAt(insn.address), let flow = insn.controlFlow,
                      sites[insn.address] == nil else { return nil }
                let next = i + 1 < code.count ? [code[i + 1].address] : []
                let target = (relativeTargets[insn.address] ?? insn.branchTarget).map { [$0] } ?? []
                let hasLocalSuccessor: Bool
                let successors: [UInt64]
                switch insn.controlFlow {
                case .branch?: successors = target; hasLocalSuccessor = !target.isEmpty
                case .conditionalBranch?: successors = target + next; hasLocalSuccessor = !target.isEmpty && !next.isEmpty
                case .call?: successors = target + next; hasLocalSuccessor = false // return/effects require admission
                case .return?: successors = []; hasLocalSuccessor = false
                case .sequential?: successors = insn.isTrap ? [] : next; hasLocalSuccessor = insn.isTrap || !next.isEmpty
                case nil: return nil
                }
                let binding = insn.branchTarget.flatMap { bindings[$0] }
                sites[insn.address] = Site(word: word, flow: flow, successors: successors, importedOperation: binding,
                                           unresolvedTransfer: !hasLocalSuccessor || binding != nil)
            }
        }
        return Self(driver: create.driver, boxAllocation: create.box, boxStore: create.store,
                    closureStoreOffset: 16, captureStoreOffset: 24, create: create.operation,
                    startupDescriptor: create.startup, closureDescriptor: create.closure,
                    relativeTails: relative, directTails: direct, sites: sites)
    }
}
