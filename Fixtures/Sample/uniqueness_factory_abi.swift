// Compiler oracle for the actual runtime query ABI. Built at -O only to
// expose the runtime import; native wrappers must not run unless its emitted
// declaration proves C/default-cc i1(ptr), and the emitted call survives.
public final class ABIProbeBox { public init() {} }
@inline(never)
public func runtimeQueryABIProbe(_ box: inout ABIProbeBox) -> Bool {
    isKnownUniquelyReferenced(&box)
}
