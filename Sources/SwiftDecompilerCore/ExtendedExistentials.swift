import Demangling

/// Resolves a constrained existential (`any Source<String>`, Swift 5.7) that
/// a field record mangles through an extended existential shape: a symbolic
/// reference (0x0A unique, 0x0B non-unique) to the shape, then the shape's
/// generic arguments, then `Xj`.
///
/// The symbolic demangler reads the shape and hangs its existential type,
/// written over the generalization signature's parameters (`any Source<τ_0_0>`,
/// as `Self.Element == τ_0_0`), under the reference node. The printer ignores
/// that subtree, as the toolchain's does, and prints `symbolic existential type
/// (non-unique) 0x0 <Swift.String>`: no protocol, a meaningless address, and
/// several arguments run together (`<Swift.IntSwift.String>`). Resolving
/// substitutes each argument for its parameter, which is the type the
/// accessor symbols of the same field demangle to.
enum ExtendedExistentials {
    struct Unresolved: Error, CustomStringConvertible {
        let reason: String
        var description: String { "constrained existential not resolved: \(reason)" }
    }

    /// `node` with every extended existential replaced by its existential
    /// type. Throws when a shape's type is missing or names a parameter its
    /// arguments do not supply: printing it unresolved would read as a type.
    static func resolve(_ node: Node) throws -> Node {
        guard node.contains(where: { $0.kind == .symbolicExtendedExistentialType }) else { return node }
        let rewriter = ShapeRewriter()
        let result = rewriter.rewrite(node)
        if let failure = rewriter.failure { throw failure }
        return result
    }

    private final class ShapeRewriter: Node.Rewriter {
        var failure: Unresolved?

        override func visit(_ node: Node) -> Node {
            guard node.kind == .symbolicExtendedExistentialType else { return node }
            let children = Array(node.children)
            guard children.count == 2,
                  [.uniqueExtendedExistentialTypeShapeSymbolicReference,
                   .nonUniqueExtendedExistentialTypeShapeSymbolicReference].contains(children[0].kind),
                  children[0].children.count == 1,
                  children[1].kind == .typeList
            else {
                failure = Unresolved(reason: "unexpected shape node")
                return node
            }
            let substituter = ParameterSubstituter(arguments: Array(children[1].children))
            let existential = substituter.rewrite(children[0].children[0])
            if let missing = substituter.failure {
                failure = Unresolved(reason: missing)
                return node
            }
            return existential
        }
    }

    /// Replaces `τ_0_i` with the i-th argument. The generalization signature
    /// is the shape's only generic signature, so every parameter is at depth
    /// 0; any other parameter, or an index past the arguments, fails.
    private final class ParameterSubstituter: Node.Rewriter {
        let arguments: [Node]
        var failure: String?

        init(arguments: [Node]) {
            self.arguments = arguments
        }

        override func visit(_ node: Node) -> Node {
            guard node.kind == .type, node.children.count == 1,
                  let parameter = node.children.first, parameter.kind == .dependentGenericParamType
            else { return node }
            let indices = Array(parameter.children)
            guard indices.count == 2, let depth = indices[0].index, let index = indices[1].index,
                  depth == 0, index < arguments.count
            else {
                failure = "parameter \(parameter.children.compactMap(\.index)) of \(arguments.count) arguments"
                return node
            }
            return arguments[Int(index)]
        }
    }
}
