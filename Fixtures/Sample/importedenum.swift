// Imported C enums and option sets pass as their raw integer, one register.
// The image proves the width: each foreign type's metadata candidate starts
// with its value witness table, bound to the builtin integer's
// (`_$sBi64_WV`). True behaviour: `describe` returns its argument (the
// switch maps -1, 0, 1 to themselves) after checking `r + 1 <u 3`;
// `rawOptions` returns its argument's raw value.
import Foundation

@inline(never) public func describe(_ r: ComparisonResult) -> Int {
    switch r {
    case .orderedAscending: return -1
    case .orderedSame: return 0
    case .orderedDescending: return 1
    }
}
@inline(never) public func rawOptions(_ o: NSString.CompareOptions) -> UInt { o.rawValue }
@inline(never) public func optionsType() -> Any.Type { NSString.CompareOptions.self }
