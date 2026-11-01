// Types fetched through `__swift_instantiateConcreteTypeFromMangledNameV2`:
// each call passes a `{relative offset, length}` pair whose symbol,
// `…MR`, demangles to "mangled name ref for type metadata for T". Built -O,
// and stripped (libMangledTypes.stripped.dylib) to leave the helper unnamed.
// True behaviour: every pair names the type its MR symbol does.
import Foundation

public struct Box<T> { var v: T }
public final class Node<Key: Hashable> { var key: Key; init(_ k: Key) { key = k } }
public enum Choice: Hashable { case a, b(Int) }

@inline(never) public func types() -> [Any.Type] {
    [Box<Int>.self, Box<String>.self, [Box<Int>].self, Box<Int>?.self, (Int, String).self,
     Node<String>.self, [String: Box<Double>].self, Box<URL>.self, ((Int) -> String).self,
     Set<Choice?>.self, [Node<Int>].self]
}
@inline(never) public func make() -> Any { [Box(v: 1), Box(v: 2)] as [Box<Int>] }
