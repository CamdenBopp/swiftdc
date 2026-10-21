import Foundation

/// One edge of the call graph: a call instruction and where it goes.
public struct CallEdge: Sendable, Hashable {
    /// Address of the calling instruction.
    public let site: UInt64
    /// Start address of the calling function.
    public let caller: UInt64
    /// Resolved call target.
    public let callee: UInt64
    /// The site is a `b` out of the caller rather than a `bl`: the callee
    /// returns to the caller's caller.
    public let isTailCall: Bool
    /// The site dispatches through `self`'s own vtable slot. The callee is the
    /// implementation that runs when self is exactly its class; a subclass
    /// override runs instead otherwise, so the edge is possible, not proven.
    public var isSelfDispatch: Bool = false
}

/// Caller/callee relationships across a set of disassembled functions.
///
/// Built from resolved branch targets. This includes direct calls, tail calls
/// (a `b` to another function's entry or to a stub), and indirect
/// calls whose function pointer was proven from a concrete Mach-O slot (for
/// example a known witness table). Truly dynamic vtable, generic witness-table,
/// and block dispatch remains absent; `unresolvedCallSites` counts those sites
/// so callers can say so instead of implying the graph is complete.
public struct CallGraph: Sendable {
    /// Address → display name. Covers functions in this image plus stub/import
    /// targets that appear only as callees.
    public let names: [UInt64: String]
    /// Start addresses of functions defined in this image — `names` minus the
    /// stub and import targets, which are not ours to reason about.
    public let functionAddresses: Set<UInt64>
    public let edges: [CallEdge]
    /// Call instructions whose target isn't statically known (indirect dispatch).
    public let unresolvedCallSites: Int
    /// Calls with no address in this image but a proven callee: an import
    /// called through its GOT slot. Not unresolved, and not edges either,
    /// since the callee has no address here.
    public let externalCallSites: Int

    private let calleesByCaller: [UInt64: [CallEdge]]
    private let callersByCallee: [UInt64: [CallEdge]]

    public init(functions: [DisassembledFunction], externalNames: [UInt64: String] = [:]) {
        var names: [UInt64: String] = externalNames
        for function in functions { names[function.startAddress] = function.displayName }

        let starts = Set(functions.map(\.startAddress))
        let spans = functions.map { ($0.startAddress, $0.instructions.last?.address ?? $0.startAddress) }
            .sorted { $0.0 < $1.0 }
        func insideAFunction(_ address: UInt64) -> Bool {
            var low = 0, high = spans.count
            while low < high {
                let mid = (low + high) / 2
                if spans[mid].0 <= address { low = mid + 1 } else { high = mid }
            }
            return low > 0 && address <= spans[low - 1].1
        }

        var edges: [CallEdge] = []
        var unresolved = 0
        var external = 0
        for function in functions {
            let first = function.startAddress
            let last = function.instructions.last?.address ?? first
            for insn in function.instructions {
                let isTailCall: Bool
                switch insn.controlFlow {
                case .call:
                    guard insn.branchTarget != nil else {
                        // A `blr` through a bound GOT slot names its import;
                        // counted as unresolved it inflated the count (69% of
                        // one app's "unresolved" sites had a proven target).
                        if DisassembledFunction.calleeName(of: insn) != nil { external += 1 } else { unresolved += 1 }
                        continue
                    }
                    isTailCall = false
                case .branch:
                    // A `b` that leaves the function is a tail call. Without
                    // this edge a function reached only that way (14,401 of
                    // Fiery Feeds' 180,015) reads as having no caller at all.
                    // A branch inside the span, or back to the entry, is the
                    // function's own control flow; one into the middle of
                    // another function is a shared tail, not a call to it.
                    guard let target = insn.branchTarget, target < first || target > last,
                          starts.contains(target)
                            || (!insideAFunction(target) && DisassembledFunction.calleeName(of: insn) != nil)
                    else { continue }
                    isTailCall = true
                default:
                    continue
                }
                guard let target = insn.branchTarget else { continue }
                // Calls into a stub (an import, or an ObjC selector stub) target
                // an address that is not itself a recovered function, so it has
                // no entry above — but the call site knows the name.
                if names[target] == nil, let name = DisassembledFunction.calleeName(of: insn) {
                    names[target] = name
                }
                edges.append(CallEdge(
                    site: insn.address, caller: function.startAddress, callee: target, isTailCall: isTailCall,
                    isSelfDispatch: DisassembledFunction.isSelfDispatch(insn)
                ))
            }
        }

        self.names = names
        self.functionAddresses = starts
        self.edges = edges
        self.unresolvedCallSites = unresolved
        self.externalCallSites = external
        self.calleesByCaller = Dictionary(grouping: edges, by: \.caller)
        self.callersByCallee = Dictionary(grouping: edges, by: \.callee)
    }

    /// What the graph reads of `function`: its names, its call and branch
    /// sites (text and annotation, for callee names) and its last
    /// instruction (its span). Everything else, the structured detail and
    /// the recovered arguments, is dropped, so a whole-image graph built while
    /// streaming holds sites, not instructions: about 1 KB per instruction
    /// held at once put Swiftcord's 12.4M past 8 GB.
    public static func sites(of function: DisassembledFunction) -> DisassembledFunction {
        let instructions = function.instructions
        var kept: [Instruction] = []
        for (index, insn) in instructions.enumerated()
        where insn.controlFlow == .call || insn.controlFlow == .branch || index == instructions.count - 1 {
            kept.append(Instruction(
                address: insn.address, text: insn.text, annotation: insn.annotation,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget, callee: .kept(insn.callee)
            ))
        }
        return function.replacingInstructions(kept)
    }

    /// Display name for an address, or a synthesized `sub_<addr>`.
    public func name(of address: UInt64) -> String {
        names[address] ?? "sub_\(String(address, radix: 16))"
    }

    /// Edges leaving `function`, in call order.
    public func callees(of function: UInt64) -> [CallEdge] {
        (calleesByCaller[function] ?? []).sorted { $0.site < $1.site }
    }

    /// Edges arriving at `function`, in call order.
    public func callers(of function: UInt64) -> [CallEdge] {
        (callersByCallee[function] ?? []).sorted { $0.site < $1.site }
    }

    /// Addresses whose name matches `needle` (case-insensitive substring).
    /// Includes stub targets, so `--function objc_msgSend$foo` finds every site
    /// that sends that selector.
    public func addresses(matching needle: String) -> [UInt64] {
        let lowered = needle.lowercased()
        return names
            .filter { $0.value.lowercased().contains(lowered) }
            .keys
            .sorted()
    }

    /// Functions in this image that nothing in it statically calls. Never proof
    /// of dead code: an entry point, an exported symbol, or anything reached by
    /// indirect dispatch has no static caller either.
    public func unreferenced() -> [UInt64] {
        functionAddresses.filter { callersByCallee[$0] == nil }.sorted()
    }
}
