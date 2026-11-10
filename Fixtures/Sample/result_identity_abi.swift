// Compiler ABI oracles only: emit LLVM, never link these definitions.
// The assembly entries have the same zero-argument integer convention.
@inline(never) public func run() -> Int { 701 }
@inline(never) public func twice() -> Int { 702 }
@inline(never) public func immediate() -> Int { 703 }

// Returning a borrowed Array as owned requires its real bridge-object retain.
// Its actual runtime declaration/call, including returned-argument semantics,
// is checked before the assembly invokes that runtime entry point.
@inline(never) public func bridgeABI(_ value: [Int]) -> [Int] { value }
