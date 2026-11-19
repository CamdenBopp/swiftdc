import Foundation
import Testing
@testable import SwiftDecompilerCore

private func outlinedTailIndex(hop: Bool, hints: Bool, name: String? = nil,
                               prefix: [UInt32]? = nil, depth: Int = 1,
                               poisonLast: Bool = false, cycle: Bool = false,
                               missingStart: Bool = false, returns: Bool = false,
                               interior: Int = 0, unboundTail: Bool = false,
                               waitName: String? = nil, waitRegister: Int = 2, declaredEntry: Bool = false) throws -> AsyncFuncletIndex {
    func branch(_ from: UInt64, _ to: UInt64, link: Bool = false) -> UInt32 {
        (link ? 0x94000000 : 0x14000000)
            | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
    }
    var entry: [UInt32] = [0xd10083ff, 0xa9017bfd, 0x910043fd]
    if !hop { entry.append(branch(0x100c, 0x4000, link: true)) }
    let pc = 0x1000 + UInt64(entry.count * 4), delta = UInt64(0x2000) - pc
    entry.append(0x10000000 | UInt32(hop ? (waitName == nil ? 0 : waitRegister) : 8) | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5)
    if hop { entry += waitName != nil && waitRegister == 2 ? [0xd2800000, 0xd2800001] : [0xd2800001, 0xd2800002] }
    else { entry += [0xa9002016, 0xaa0003f6] }
    entry.append(0xa9417bfd)
    entry.append(branch(0x1000 + UInt64(entry.count * 4), depth == 0 ? 0x5000 : 0x3000))
    var bodies: [UInt64: [UInt32]] = [0x1000: entry, 0x2000: [0xd65f03c0],
                                    0x4000: [0xd65f03c0], 0x5000: [0xd65f03c0]]
    if depth > 0 {
        for i in 0..<depth {
            let start = UInt64(0x3000 + i * 0x40)
            var code = prefix ?? [0x9243fbbd, 0x910083ff]
            if poisonLast && i == depth - 1 { code = [0xaa1f03f6, 0x910083ff] }
            let final: UInt64 = cycle ? 0x3000 : (interior != 0 ? start + UInt64(interior * 4) : (unboundTail ? 0x7000 : 0x5000))
            let target: UInt64 = i == depth - 1 ? final : start + 0x40
            code.append(returns ? 0xd65f03c0 : branch(start + UInt64(code.count * 4), target))
            bodies[start] = code
        }
    }
    let engine = try #require(CapstoneEngine())
    var decoded: [UInt64: [Instruction]] = [:]
    for (start, code) in bodies {
        decoded[start] = engine.disassemble(code.withUnsafeBytes { Data($0) }, address: start).map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                        branchTarget: $0.branchTarget, detail: $0.detail)
        }
        // An invalid instruction may deliberately stop decoding the helper;
        // the entry and every supported prefix must still decode completely.
        if !code.contains(0xffffffff) { try #require(decoded[start]?.count == code.count) }
    }
    var starts = Set(bodies.keys)
    if missingStart { starts.remove(0x3000) }
    return AsyncFuncletIndex.build(
        hints: hints ? .init(entries: declaredEntry ? [0x1000, 0x3000] : [0x1000], awaitReturns: hop ? [] : [0x2000],
                            continuations: hop ? [0x2000] : []) : nil,
        functionStarts: starts, instructions: { decoded[$0] ?? [] },
        nameOf: { address in
            if address >= 0x3000 && address < 0x3800 { return name }
            switch address {
            case 0x4000: return "swift_task_alloc"
            case 0x5000: return waitName ?? (hop ? "swift_task_switch" : "Own.worker() async -> Swift.Int64")
            default: return nil
            }
        })
}

@Test func outlinedTerminalPreservesChildContextAndNamesFinalCallee() throws {
    for hints in [true, false] {
        for name: String? in [nil, "OUTLINED_FUNCTION_2", "ordinaryName"] {
            let index = try outlinedTailIndex(hop: false, hints: hints, name: name)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
            #expect(index.suspension(into: 0x2000)?.suspension.callee == 0x5000)
        }
    }
}

@Test func outlinedTerminalPreservesTaskSwitchResumeArguments() throws {
    for hints in [true, false] {
        for name: String? in [nil, "OUTLINED_FUNCTION_3", "ordinaryName"] {
            let index = try outlinedTailIndex(hop: true, hints: hints, name: name)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
            #expect(index.funclets[0x2000]?.kind == .continuation)
            #expect(index.suspension(into: 0x2000)?.suspension.isExecutorHop == true)
        }
    }
}

@Test func outlinedTerminalDeclinesUnprovedContextAndArgumentEffects() throws {
    let unsafe: [[UInt32]] = [
        [0xaa1f03f6, 0x910083ff], // clears the forwarded context
        [0x9243fbb6, 0x910083ff], // AND writes x22 instead of the frame register
        [0x9243fbbd, 0xf90006df], // overwrites its saved resume pointer
        [0x9243fbbd, 0xaa1f03e0], // clears task_switch's resume argument
        [0x9243fbbd, 0xaa1f03e2], // changes a runtime wait resume argument
        [0x9243fbbd, 0xaa1f03e3], // changes the waitAll resume argument
        [0x9243fbbd, 0x910082df], // sets SP from the context rather than SP
        [0x9243fbbd, 0x110083ff], // truncates SP
        [0x9243fbbd, 0x910083ff, 0xaa1f03f6], // extra hidden context write
    ]
    for hints in [true, false] {
        for hop in [true, false] {
            for name: String? in [nil, "OUTLINED_FUNCTION_2", "ordinaryName"] {
                for prefix in unsafe {
                    let index = try outlinedTailIndex(hop: hop, hints: hints, name: name, prefix: prefix)
                    #expect(index.funclets[0x2000]?.parent == nil)
                    #expect(index.suspension(into: 0x2000) == nil)
                }
            }
        }
    }
}

@Test func outlinedTerminalFollowsEveryPrefixAndDeclinesCyclesOrCaps() throws {
    for hints in [true, false] {
        for hop in [true, false] {
            for depth in [2, 8] {
                let index = try outlinedTailIndex(hop: hop, hints: hints, depth: depth)
                #expect(index.chains[0x1000] == [0x1000, 0x2000])
                if !hop { #expect(index.suspension(into: 0x2000)?.suspension.callee == 0x5000) }
            }
            for (depth, poison, cycle) in [(2, true, false), (2, false, true), (9, false, false)] {
                let index = try outlinedTailIndex(hop: hop, hints: hints, depth: depth,
                                                 poisonLast: poison, cycle: cycle)
                #expect(index.funclets[0x2000]?.parent == nil)
                #expect(index.suspension(into: 0x2000) == nil)
            }
        }
    }
}

@Test func outlinedTerminalRequiresWholeDeclaredFragments() throws {
    for hints in [true, false] {
        for hop in [true, false] {
            let missing = try outlinedTailIndex(hop: hop, hints: hints, name: "OUTLINED_FUNCTION_2", missingStart: true)
            #expect(missing.funclets[0x2000]?.parent == nil)
            let undecoded = try outlinedTailIndex(hop: hop, hints: hints, name: "OUTLINED_FUNCTION_2", prefix: [0xffffffff])
            #expect(undecoded.funclets[0x2000]?.parent == nil)
            let returning = try outlinedTailIndex(hop: hop, hints: hints, returns: true)
            #expect(returning.funclets[0x2000]?.parent == nil)
            for interior in [1, 2] {
                let middle = try outlinedTailIndex(hop: hop, hints: hints, name: "ordinaryName", interior: interior)
                #expect(middle.funclets[0x2000]?.parent == nil)
                #expect(middle.suspension(into: 0x2000) == nil)
            }
            let unbound = try outlinedTailIndex(hop: hop, hints: hints, unboundTail: true)
            #expect(unbound.funclets[0x2000]?.parent == nil)
        }
    }
}

@Test func outlinedTerminalKeepsOrdinaryAsyncAndRuntimeCallees() throws {
    for hints in [true, false] {
        for hop in [true, false] {
            let index = try outlinedTailIndex(hop: hop, hints: hints, depth: 0)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
            #expect(index.funclets[0x2000]?.parent == 0x1000)
        }
    }
}

@Test func outlinedTerminalPreservesRuntimeWaitResumeArguments() throws {
    for hints in [true, false] {
        for (name, register) in [("swift_task_future_wait", 2), ("_swift_task_future_wait_throwing", 2),
                                 ("swift_taskGroup_waitAll", 3)] {
            let index = try outlinedTailIndex(hop: true, hints: hints, waitName: name, waitRegister: register)
            #expect(index.chains[0x1000] == [0x1000, 0x2000])
            #expect(index.funclets[0x2000]?.kind == .continuation)
            #expect(index.suspension(into: 0x2000)?.suspension.isExecutorHop == false)
            #expect(index.suspension(into: 0x2000)?.suspension.callee == 0x5000)
        }
    }
}

@Test func outlinedTerminalKeepsDeclaredAsyncEntryBoundaries() throws {
    // A real nine-argument async entry loads its incoming stack argument,
    // stores arguments in its own context and pops the incoming argument
    // area. Those effects do not make it a machine-outliner fragment.
    let incomingStack: [UInt32] = [0xf94003e8, 0xa90622c7, 0x910043ff]
    for name: String? in [nil, "Ordinary.nineArguments() async -> Swift.Int", "OUTLINED_FUNCTION_2"] {
        let index = try outlinedTailIndex(hop: false, hints: true, name: name,
                                         prefix: incomingStack, declaredEntry: true)
        #expect(index.chains[0x1000] == [0x1000, 0x2000])
        #expect(index.suspension(into: 0x2000)?.suspension.callee == 0x3000)
    }
    let invalid = try outlinedTailIndex(hop: false, hints: true, name: "OUTLINED_FUNCTION_2",
                                       missingStart: true, declaredEntry: true)
    #expect(invalid.funclets[0x2000]?.parent == nil)
}
