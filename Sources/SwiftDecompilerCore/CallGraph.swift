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
        self.init(sites: functions.map(Self.callSites(of:)), externalNames: externalNames)
    }

    /// The graph over each function's call sites alone (`callSites(of:)`),
    /// which is all `init(functions:)` reads.
    public init(sites functions: [FunctionCallSites], externalNames: [UInt64: String] = [:]) {
        var names: [UInt64: String] = externalNames
        for function in functions { names[function.function.startAddress] = function.function.displayName }

        let starts = Set(functions.map(\.function.startAddress))
        let spans = functions.map { ($0.function.startAddress, $0.lastAddress) }
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
            let first = function.function.startAddress
            let last = function.lastAddress
            for site in function.sites {
                let isTailCall: Bool
                if site.isCall {
                    guard site.target != nil else {
                        // A `blr` through a bound GOT slot names its import;
                        // counted as unresolved it inflated the count (69% of
                        // one app's "unresolved" sites had a proven target).
                        if site.callee != nil { external += 1 } else { unresolved += 1 }
                        continue
                    }
                    isTailCall = false
                } else {
                    // A `b` that leaves the function is a tail call. Without
                    // this edge a function reached only that way (14,401 of
                    // Fiery Feeds' 180,015) reads as having no caller at all.
                    // A branch inside the span, or back to the entry, is the
                    // function's own control flow; one into the middle of
                    // another function is a shared tail, not a call to it.
                    guard let target = site.target, target < first || target > last,
                          starts.contains(target) || (!insideAFunction(target) && site.callee != nil)
                    else { continue }
                    isTailCall = true
                }
                guard let target = site.target else { continue }
                // Calls into a stub (an import, or an ObjC selector stub) target
                // an address that is not itself a recovered function, so it has
                // no entry above — but the call site knows the name.
                if names[target] == nil, let name = site.callee {
                    names[target] = name
                }
                edges.append(CallEdge(
                    site: site.address, caller: first, callee: target, isTailCall: isTailCall,
                    isSelfDispatch: site.isSelfDispatch
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

    /// Everything the graph reads of `function`, in the least memory: the
    /// function without its instructions (its names), its last address
    /// (its span) and one `GraphSite` per call or branch. `xrefs` streams
    /// the image and holds these for every function at once; holding each
    /// site as an `Instruction` (176 bytes) was 139 MB of a GoodLinks run.
    /// A site rewritten to what its outlined fragment does is, in the
    /// binary, a `bl` or `b` to the fragment, and is kept as that.
    public static func callSites(of function: DisassembledFunction) -> FunctionCallSites {
        var sites: [GraphSite] = []
        for insn in function.instructions {
            if let origin = insn.inlinedFragment {
                sites.append(GraphSite(address: insn.address, callee: nil, target: origin.address,
                                      isCall: origin.reachedByCall, isSelfDispatch: false))
            } else if insn.controlFlow == .call || insn.controlFlow == .branch {
                sites.append(GraphSite(address: insn.address, callee: insn.callee, target: insn.branchTarget,
                                      isCall: insn.controlFlow == .call, isSelfDispatch: insn.isSelfDispatch))
            }
        }
        return FunctionCallSites(
            function: function.replacingInstructions([]),
            lastAddress: function.instructions.last?.address ?? function.startAddress,
            sites: sites)
    }

    /// What the graph reads of `function`: its names, its call and branch
    /// sites (their typed callee, target and the two facts `init` reads) and
    /// its last instruction (its span). Everything else, the structured
    /// detail, the recovered arguments, the annotation and every other fact,
    /// is dropped, so a whole-image graph built while streaming holds sites,
    /// not instructions: about 1 KB per instruction held at once put
    /// Swiftcord's 12.4M past 8 GB. A site's annotation and facts alone held
    /// most of GoodLinks' `xrefs` peak, since `init` names a callee by its
    /// typed `callee`, never its notes.
    public static func sites(of function: DisassembledFunction) -> DisassembledFunction {
        let instructions = function.instructions
        var kept: [Instruction] = []
        for (index, insn) in instructions.enumerated()
        where insn.controlFlow == .call || insn.controlFlow == .branch || insn.inlinedFragment != nil
            || index == instructions.count - 1 {
            var facts = Instruction.Facts()
            facts.isSelfDispatch = insn.isSelfDispatch
            facts.inlinedFragment = insn.inlinedFragment
            kept.append(Instruction(
                address: insn.address, text: insn.text, annotation: nil,
                controlFlow: insn.controlFlow, branchTarget: insn.branchTarget, callee: .kept(insn.callee),
                facts: facts
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

/// One call or branch site, as a call graph reads it.
public struct GraphSite: Sendable, Equatable {
    /// Address of the `bl`, `blr`, `b` or `br`.
    public let address: UInt64
    /// The typed callee name of the instruction (`Instruction.callee`).
    public let callee: String?
    /// The proven target, when there is one.
    public let target: UInt64?
    /// A call (`bl`, `blr`) rather than a branch.
    public let isCall: Bool
    /// `Instruction.isSelfDispatch`.
    public let isSelfDispatch: Bool
}

/// A function as a call graph reads it (`CallGraph.callSites(of:)`).
public struct FunctionCallSites: Sendable {
    /// The function's names and identity, without its instructions.
    public let function: DisassembledFunction
    /// Its last instruction's address: the end of its span.
    public let lastAddress: UInt64
    public let sites: [GraphSite]
}
