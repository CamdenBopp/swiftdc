import Ccapstone

/// Machine provenance of the requested size and context register on one
/// direct handoff. This carries no fact about an allocator's actual returned
/// extent, successful execution, context privacy, or memory effects.
struct AsyncDescriptorHandoff: Sendable, Equatable {
    let descriptor: AsyncFunctionDescriptor
    let sizeLoad: UInt64
    let allocationCall: UInt64
    let allocator: RuntimeFunctionReference

    struct Evidence {
        let allocatorAt: (UInt64) -> RuntimeFunctionReference?
        let descriptorAt: (_ address: UInt64, _ directEntry: UInt64) -> AsyncFunctionDescriptor?
    }

    /// Initial scope: a straight-line body with an ADRP/LDR size operand,
    /// a paired header store, direct x22 installation and a standard epilogue.
    /// Other instruction shapes retain ordinary grouping without this fact.
    static func prove(
        _ body: [Instruction], source: UInt64, site: UInt64, resume: UInt64,
        entry: UInt64, outgoingScalarRegister: Int = 0, evidence: Evidence
    ) -> Self? {
        let suffixCount = 13
        guard body.count >= suffixCount, body.first?.address == source,
              body.last?.address == site, body.last?.controlFlow == .branch,
              body.last?.branchTarget == entry,
              body.last?.detail?.id == AARCH64_INS_B, entry != source else { return nil }
        let code = Array(body.suffix(suffixCount))
        for (offset, instruction) in body.enumerated() {
            let (address, overflow) = source.addingReportingOverflow(UInt64(offset) * 4)
            guard !overflow, instruction.address == address, instruction.detail != nil,
                  !instruction.isTrap else { return nil }
            if instruction.address != code[2].address && instruction.address != site {
                guard instruction.controlFlow == .sequential else { return nil }
            }
        }
        func operands(_ index: Int, _ id: aarch64_insn, count: Int) -> [StructuredOperandInfo]? {
            guard let detail = code[index].detail, detail.id == id,
                  detail.operands.count == count, !detail.writeback, !detail.updatesFlags else { return nil }
            return detail.operands
        }
        func isGPR(_ operand: StructuredOperandInfo, _ number: Int, width: Int = 64) -> Bool {
            let register = operand.operand.register
            return register?.kind == .gpr && register?.widthBits == width && register?.number == number
        }
        func memory(_ operand: StructuredOperandInfo, basedOn register: PhysReg) -> Int64? {
            guard case .memory(let base?, nil, let displacement) = operand.operand,
                  base == register else { return nil }
            return displacement
        }
        func address(_ page: Int64, plus delta: Int64) -> UInt64? {
            guard delta >= 0 else { return nil }
            let (address, overflow) = UInt64(bitPattern: page).addingReportingOverflow(UInt64(delta))
            return overflow ? nil : address
        }

        guard let page = operands(0, AARCH64_INS_ADRP, count: 2),
              let base = page[0].operand.register, base.kind == .gpr, base.widthBits == 64,
              let sizeBase = page[1].operand.immediateValue,
              let load = operands(1, AARCH64_INS_LDR, count: 2), isGPR(load[0], 0, width: 32),
              let loadOffset = memory(load[1], basedOn: base),
              let sizeAddress = address(sizeBase, plus: loadOffset), sizeAddress >= 4,
              code[2].controlFlow == .call, code[2].detail?.id == AARCH64_INS_BL,
              let stub = code[2].branchTarget,
              let save = operands(3, AARCH64_INS_STR, count: 2), isGPR(save[0], 0),
              case .memory(let parent?, nil, _) = save[1].operand,
              parent.kind == .gpr, parent.widthBits == 64, parent.number == 22,
              let resumePage = operands(4, AARCH64_INS_ADRP, count: 2),
              let scratch = resumePage[0].operand.register,
              scratch.kind == .gpr, scratch.widthBits == 64, scratch.number != 0, scratch.number != 22,
              let resumeBase = resumePage[1].operand.immediateValue,
              let resumeAdd = operands(5, AARCH64_INS_ADD, count: 3),
              resumeAdd[0].operand.register == scratch, resumeAdd[1].operand.register == scratch,
              let resumeOffset = resumeAdd[2].shiftedImmediate,
              address(resumeBase, plus: resumeOffset) == resume,
              let store = operands(6, AARCH64_INS_STP, count: 3),
              isGPR(store[0], 22), store[1].operand.register == scratch,
              let result = save[0].operand.register, memory(store[2], basedOn: result) == 0,
              let install = operands(7, AARCH64_INS_MOV, count: 2),
              isGPR(install[0], 22), isGPR(install[1], 0),
              let restoreArgument = operands(8, AARCH64_INS_MOV, count: 2),
              isGPR(restoreArgument[0], outgoingScalarRegister),
              let restoreLink = operands(9, AARCH64_INS_LDP, count: 3),
              isGPR(restoreLink[0], 29), isGPR(restoreLink[1], 30),
              case .memory(let stack?, nil, _) = restoreLink[2].operand,
              stack.kind == .stackPointer, stack.widthBits == 64,
              let clearFrameTag = operands(10, AARCH64_INS_AND, count: 3),
              isGPR(clearFrameTag[0], 29), isGPR(clearFrameTag[1], 29),
              clearFrameTag[2].operand.immediateValue != nil,
              let pop = operands(11, AARCH64_INS_ADD, count: 3),
              pop[0].operand.register == stack, pop[1].operand.register == stack,
              pop[2].shiftedImmediate != nil,
              let descriptor = evidence.descriptorAt(sizeAddress - 4, entry),
              descriptor.address == sizeAddress - 4, descriptor.entry == entry,
              descriptor.requiredContextSize >= 16, // caller wrote a two-word header
              let allocator = evidence.allocatorAt(stub), allocator.isAsyncTaskAllocator
        else { return nil }
        return Self(descriptor: descriptor, sizeLoad: code[1].address,
                    allocationCall: code[2].address, allocator: allocator)
    }
}

extension RuntimeFunctionReference {
    var isAsyncTaskAllocator: Bool {
        rawSymbol == "_swift_task_alloc" && libraryName == "/usr/lib/swift/libswift_Concurrency.dylib"
    }
}
