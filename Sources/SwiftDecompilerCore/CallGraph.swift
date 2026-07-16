import Foundation

/// One edge of the call graph: a call instruction and where it goes.
public struct CallEdge: Sendable, Hashable {
    /// Address of the calling instruction.
    public let site: UInt64
    /// Start address of the calling function.
    public let caller: UInt64
    /// Resolved call target.
    public let callee: UInt64
}

/// Caller/callee relationships across a set of disassembled functions.
///
/// Built from resolved direct-branch targets only. Indirect dispatch — a
/// `blr` through a vtable, witness table, or block pointer — has no static
/// target, so those edges are genuinely absent rather than merely unrecovered;
/// `unresolvedCallSites` counts them so callers can say so instead of implying
/// the graph is complete.
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

    private let calleesByCaller: [UInt64: [CallEdge]]
    private let callersByCallee: [UInt64: [CallEdge]]

    public init(functions: [DisassembledFunction], externalNames: [UInt64: String] = [:]) {
        var names: [UInt64: String] = externalNames
        for function in functions { names[function.startAddress] = function.displayName }

        var edges: [CallEdge] = []
        var unresolved = 0
        for function in functions {
            for insn in function.instructions where insn.controlFlow == .call {
                guard let target = insn.branchTarget else {
                    unresolved += 1
                    continue
                }
                // Calls into a stub (an import, or an ObjC selector stub) target
                // an address that is not itself a recovered function, so it has
                // no entry above — but the call site knows the name.
                if names[target] == nil, let name = DisassembledFunction.calleeName(of: insn) {
                    names[target] = name
                }
                edges.append(CallEdge(site: insn.address, caller: function.startAddress, callee: target))
            }
        }

        self.names = names
        self.functionAddresses = Set(functions.map(\.startAddress))
        self.edges = edges
        self.unresolvedCallSites = unresolved
        self.calleesByCaller = Dictionary(grouping: edges, by: \.caller)
        self.callersByCallee = Dictionary(grouping: edges, by: \.callee)
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
