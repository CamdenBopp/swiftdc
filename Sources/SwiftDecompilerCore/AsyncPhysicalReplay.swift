import CryptoKit
import Foundation

/// Checks a sealed execution certificate against the executable's physical
/// instruction/effect table, then runs the local allocation/value solver.
enum AsyncPhysicalReplay {
    typealias Solver = AsyncClosedCallerSolver

    struct Transition {
        let word: UInt32
        let action: Action
    }

    enum Action {
        /// Only the physical lifter can supply application effects. The
        /// certificate can confirm the actual edge set but cannot supply effects.
        case application(successors: [UInt64])
        /// Same-task continuation return, independently resolved from the
        /// live child header. The solver checks the actual loaded carriers too.
        case normalReturn(site: UInt64, next: UInt64)
        case runtime(request: AsyncPhysicalRegion.EffectRequest, decision: RuntimeDecision)
    }

    enum RuntimeDecision {
        case allocate(task: UInt64, requested: Int, ownedExtent: Int, next: UInt64)
        case release(task: UInt64, next: UInt64)
        case suspend(early: RuntimeRoute, late: RuntimeRoute)
        case switchExecutor(inline: RuntimeRoute, queued: RuntimeRoute)
    }

    struct RuntimeRoute {
        let taskGeneration: UInt64
        let continuation: UInt64
        let preservedAllocations: [UInt64: Range<Int>]
        let rawWriterReach: RawWriterReach
    }

    enum RawWriterReach: Equatable {
        case excludedByScopedContract
        case mayWrite
        case unknown
    }

    /// Issuance requires an independently closed ingress proof covering every
    /// activation eligible for the renderer's address-keyed seed.
    struct ResumeCoverage {
        let imageDigest: SHA256.Digest
        let resume: UInt64
        let ownerAllocationSite: UInt64

        private init(imageDigest: SHA256.Digest, resume: UInt64, ownerAllocationSite: UInt64) {
            self.imageDigest = imageDigest
            self.resume = resume
            self.ownerAllocationSite = ownerAllocationSite
        }
    }

    /// The supported conditional configuration and all application CFG
    /// evidence must come from one independently validated launch domain.
    /// This type deliberately has no production minting API until the
    /// corresponding admission/extraction supports a real executable.
    struct Admission {
        let imageDigest: SHA256.Digest
        let selectedSwiftRuntime: UUID
        let entry: UInt64
        let detachedTask: UInt64
        let initialContextExtent: Int
        let box: Solver.BoxedOperation
        let startupCreateSite: UInt64
        let transitions: [UInt64: Transition]
        let resumeCoverage: ResumeCoverage

        private init(imageDigest: SHA256.Digest, selectedSwiftRuntime: UUID, entry: UInt64,
                     detachedTask: UInt64, initialContextExtent: Int, box: Solver.BoxedOperation,
                     startupCreateSite: UInt64, transitions: [UInt64: Transition], resumeCoverage: ResumeCoverage) {
            self.imageDigest = imageDigest
            self.selectedSwiftRuntime = selectedSwiftRuntime
            self.entry = entry
            self.detachedTask = detachedTask
            self.initialContextExtent = initialContextExtent
            self.box = box
            self.startupCreateSite = startupCreateSite
            self.transitions = transitions
            self.resumeCoverage = resumeCoverage
        }
    }

    // The initial catalog is scoped to the independently retained 2249
    // image. Its exact default yield descriptor requests 80 bytes.
    // Evidence: runtime-capture-01 and yield-job-operand-byte-proof.json.
    private static let reviewedYieldEntry = "_$sScTss5NeverORszABRs_rlE5yieldyyYaFZ"
    private static let reviewedYieldSize = 80
    private static let reviewedRuntime = UUID(uuidString: "2249664D-2D56-3C9B-A6C9-CD03B6B6A793")

    static func model(
        image: AsyncCheckedImage, admission: Admission
    ) -> Solver.ModelRegion? {
        guard image.sliceDigest == admission.imageDigest, let reviewedRuntime,
              admission.selectedSwiftRuntime == reviewedRuntime,
              let physical = image.physicalRegion, let detached = image.detachedIngress,
              admission.resumeCoverage.imageDigest == image.sliceDigest,
              admission.resumeCoverage.resume == physical.switchResume,
              admission.resumeCoverage.ownerAllocationSite == physical.ownerAllocationSite,
              let awaitEdge = detached.directTails.last,
              let ownerReturn = detached.directTails.last?.returnEntry,
              admission.detachedTask != 0,
              admission.entry == detached.startupDescriptor.entry,
              admission.initialContextExtent >= Int(detached.startupDescriptor.requiredContextSize),
              admission.box.allocation == detached.boxAllocation.site,
              admission.box.store == detached.boxStore,
              admission.box.descriptor == detached.closureDescriptor,
              admission.box.capture.allocation != detached.boxAllocation.site,
              admission.box.capture.scalarOffset == 32,
              admission.startupCreateSite == detached.create.site,
              let ownerOffset = Int(exactly: physical.ownerSlot), ownerOffset <= Int.max - 8
        else { return nil }

        guard let yield = physical.requests.first(where: {
                  if case .awaitImportedContinuation = $0.role { return true }
                  return false
              }),
              case .awaitImportedContinuation(_, let descriptor) = yield.role,
              yield.binding.reference.rawSymbol == Self.reviewedYieldEntry,
              descriptor.rawSymbol == Self.reviewedYieldEntry + "Tu",
              descriptor.libraryName == yield.binding.reference.libraryName
        else { return nil }

        guard case .awaitImportedContinuation(let descriptorSlot, _) = yield.role else { return nil }
        let reviewedDescriptor = Solver.RuntimeDescriptor(slot: descriptorSlot, reference: descriptor)

        let wordRange = ownerOffset..<(ownerOffset + 8)
        let physicalBySite = Dictionary(grouping: physical.steps, by: \.site)
        guard physicalBySite.values.allSatisfy({ $0.count == 1 }) else { return nil }
        var pending = [admission.entry]
        var seen: Set<UInt64> = []
        var blocks: [UInt64: Solver.Block] = [:]
        while let pc = pending.popLast() {
            guard seen.insert(pc).inserted else { continue }
            guard seen.count <= 256, let checked = physicalBySite[pc]?.first,
                  let admitted = admission.transitions[pc], admitted.word == checked.word,
                  let block = block(
                    physical: physical, detached: detached, checked: checked, admitted: admitted.action,
                    awaited: awaitEdge, ownerReturn: ownerReturn, wordRange: wordRange,
                    reviewedDescriptor: reviewedDescriptor, task: admission.detachedTask)
            else { return nil }
            if pc == admission.entry {
                let activate: Solver.Effect = .allocate(site: admission.startupCreateSite,
                    extent: admission.initialContextExtent, result: 22)
                blocks[pc] = .init(effects: [activate, .activateBox(admission.box, register: 20)] + block.effects, exit: block.exit)
            } else {
                blocks[pc] = block
            }
            if case .successors(let addresses) = block.exit { pending += addresses }
        }
        // An omitted or disconnected scoped transition may conceal alternate
        // ingress. The upstream producer must also close all external routes.
        guard seen == Set(admission.transitions.keys),
              seen.isDisjoint(with: physical.sharedReturns.keys)
        else { return nil }
        let region = Solver.ModelRegion(entry: admission.entry,
                                       taskGeneration: admission.detachedTask, blocks: blocks)
        guard Solver.solve(region)?.words[physical.ownerSlot] != nil else { return nil }
        return region
    }

    private static func block(
        physical: AsyncPhysicalRegion, detached: AsyncDetachedIngress,
        checked: AsyncPhysicalRegion.InstructionStep, admitted: Action,
        awaited: AsyncDetachedIngress.DirectTail, ownerReturn: UInt64,
        wordRange: Range<Int>, reviewedDescriptor: Solver.RuntimeDescriptor, task: UInt64
    ) -> Solver.Block? {
        let site = checked.site
        let physicalTargets = checked.physicalSuccessors
        func block(_ effects: [Solver.Effect], to target: [UInt64]) -> Solver.Block? {
            guard !target.isEmpty, Set(target).count == target.count else { return nil }
            return .init(effects: effects, exit: .successors(target))
        }
        func validRoute(_ route: RuntimeRoute, to destination: UInt64,
                        preserving required: [UInt64: Range<Int>]) -> Bool {
            route.taskGeneration == task && route.continuation == destination
                && route.rawWriterReach == .excludedByScopedContract
                && required.allSatisfy { allocation, bytes in
                    guard let preserved = route.preservedAllocations[allocation] else { return false }
                    return preserved.lowerBound <= bytes.lowerBound && preserved.upperBound >= bytes.upperBound
                }
        }

        switch (checked.step, admitted) {
        case (.machine(let effects), .application(let next)):
            guard next == physicalTargets else { return nil }
            return block(effects, to: next)
        case (.wrappingScalarAdd(let source, let displacement, let result), .application(let next)):
            guard next == physicalTargets else { return nil }
            return block([.wrappingScalarAdd(site: site, source: source,
                                             displacement: displacement, result: result)], to: next)
        case (.runtimeDescriptorSize(let descriptor, let base, let result), .application(let next)):
            guard descriptor == reviewedDescriptor, next == physicalTargets else { return nil }
            return block([.runtimeDescriptorSize(descriptor, base: base, size: Self.reviewedYieldSize,
                                                result: result)], to: next)
        case (.unresolved, .normalReturn(let producerSite, let next)):
            guard site == physical.producerReturn, next == ownerReturn, physicalTargets.isEmpty,
                  producerSite == physical.producerArithmetic
            else { return nil }
            let identity = Solver.AwaitIdentity(callEdge: .init(source: awaited.function, branch: awaited.branch),
                taskGeneration: task, ownerGeneration: physical.ownerAllocationSite,
                returnEntry: ownerReturn, carrier: .normalIntegerX0)
            return block([.normalIntegerReturn(.init(identity: identity,
                childGeneration: physical.childAllocationSite, continuationRegister: 1,
                producerSite: producerSite))], to: [next])
        case (.runtime(let expected), .runtime(let supplied, let decision)):
            guard supplied.role == expected.role, supplied.site == site, supplied.word == checked.word,
                  supplied.binding.stub == expected.binding.stub,
                  supplied.binding.pointerFileOffset == expected.binding.pointerFileOffset,
                  supplied.binding.libraryOrdinal == expected.binding.libraryOrdinal,
                  supplied.binding.reference == expected.binding.reference
            else { return nil }
            switch (expected.role, decision) {
            case (.allocateContext, .allocate(let activeTask, let requested, let extent, let next)):
                let descriptor = detached.relativeTails.first(where: { $0.allocation.site == site })?.descriptor
                    ?? detached.directTails.first(where: { $0.handoff.allocationCall == site })?.handoff.descriptor
                let required: Int
                if let descriptor { required = Int(descriptor.requiredContextSize) }
                else if site == physical.yieldAllocationSite { required = Self.reviewedYieldSize }
                else { return nil }
                guard activeTask == task, physicalTargets == [expected.binding.stub, next],
                      required >= 16, requested == required, extent >= required
                else { return nil }
                return block([.requireImmediate(value: UInt64(requested), register: 0)]
                    + (0...17).map(Solver.Effect.forget)
                    + [.allocate(site: site, extent: requested, result: 0)], to: [next])
            case (.releaseContext(let pointer), .release(let activeTask, let next)):
                guard activeTask == task, pointer == 0,
                      physicalTargets == [expected.binding.stub, next] else { return nil }
                return block([.release(pointer)] + (0...17).map(Solver.Effect.forget), to: [next])
            case (.awaitImportedContinuation, .suspend(let early, let late)):
                // Keep the full live tracked header/data intervals used by
                // the subsequent reloads, including C's saved D pointer.
                let bytes = [
                    physical.ownerAllocationSite: 0..<(physical.ownerSlot + 8),
                    physical.childAllocationSite: 0..<32,
                    physical.yieldAllocationSite: 0..<16,
                ]
                guard physicalTargets == [expected.binding.stub],
                      validRoute(early, to: physical.yieldResume, preserving: bytes),
                      validRoute(late, to: physical.yieldResume, preserving: bytes)
                else { return nil }
                return block([.requireLiveContinuation(.init(
                    activeAllocation: physical.yieldAllocationSite,
                    parentAllocation: physical.childAllocationSite,
                    continuation: physical.yieldResume))]
                    + (0...17).map(Solver.Effect.forget), to: [early.continuation])
            case (.switchExecutor, .switchExecutor(let inline, let queued)):
                let required = [physical.ownerAllocationSite: wordRange]
                guard physicalTargets == [expected.binding.stub],
                      validRoute(inline, to: physical.switchResume, preserving: required),
                      validRoute(queued, to: physical.switchResume, preserving: required),
                      let inlineBytes = inline.preservedAllocations[physical.ownerAllocationSite],
                      let queuedBytes = queued.preservedAllocations[physical.ownerAllocationSite]
                else { return nil }
                let hop = Solver.Hop(edge: .init(source: ownerReturn, branch: site),
                    resume: physical.switchResume,
                    inlinePreserved: .init(allocation: physical.ownerAllocationSite, bytes: inlineBytes),
                    queuedPreserved: .init(allocation: physical.ownerAllocationSite, bytes: queuedBytes))
                return .init(effects: [], exit: .hop(hop))
            default: return nil
            }
        default: return nil
        }
    }
}
