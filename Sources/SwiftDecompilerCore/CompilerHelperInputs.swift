import Demangling

extension DisassembledFunction {
    /// The first two inputs of IRGen's copy-address helpers are pointers,
    /// followed only by metadata pointers (Outlining.cpp). This is a prefix
    /// contract, never a complete count. A merged/specialized helper may have
    /// a changed signature and is deliberately outside this proof.
    static func compilerHelperGPInputPrefix(symbol: String, printedName: String) -> Int? {
        // Most symbols are unrelated. Avoid parsing their demangling trees.
        let copyPrefixes = ["outlined init with copy of ", "outlined init with take of ",
                            "outlined assign with copy of ", "outlined assign with take of "]
        guard copyPrefixes.contains(where: printedName.hasPrefix)
                || printedName.hasPrefix("__swift_assign_boxed_opaque_existential_")
                || printedName == "swift_willThrowTyped" else { return nil }
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_") { mangled = mangled.dropFirst() }
        if mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)),
           global.kind == .global, global.children.count == 1,
           global.print(using: .default) == printedName,
           let helper = global.children.first {
            switch helper.kind {
            case .outlinedInitializeWithCopy, .outlinedInitializeWithTake,
                 .outlinedAssignWithCopy, .outlinedAssignWithTake,
                 .outlinedInitializeWithCopyNoValueWitness, .outlinedInitializeWithTakeNoValueWitness,
                 .outlinedAssignWithCopyNoValueWitness, .outlinedAssignWithTakeNoValueWitness:
                return 2
            default: return nil
            }
        }
        // ErrorType.swift's generic E: Error entry takes an indirect E,
        // its metadata and its Error witness table, all in the GP bank.
        // This is the un-specialized Swift entry, not a C arity declaration.
        if mangled == "swift_willThrowTyped", printedName == "swift_willThrowTyped" { return 3 }
        // IRGen/GenExistential.cpp's reserved per-module helper has exactly
        // (destination, source), regardless of its witness-table count.
        let prefix = "__swift_assign_boxed_opaque_existential_"
        guard mangled.hasPrefix(prefix), String(mangled) == printedName else { return nil }
        let count = mangled.dropFirst(prefix.count)
        guard !count.isEmpty, count.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return 2
    }
}
