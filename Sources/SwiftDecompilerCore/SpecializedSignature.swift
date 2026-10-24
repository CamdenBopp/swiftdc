import Demangling

/// The signature a generic specialization is called with.
///
/// The demangler prints a specialization as the unspecialized declaration,
/// so `generic specialization <Swift.Double> of Spec.bump<A where A:
/// Swift.Numeric>(A) -> A` reads as taking an `A`, a type whose register
/// bank the name does not say. The specialization takes a `Swift.Double`,
/// in d0, and returns one there. Its substitution list names the
/// replacement of each canonical generic parameter, in depth and index
/// order (see `specializationBindsThrownTypeToNever`), so the specialized
/// signature is the declaration's function type with each parameter
/// replaced, printed as a plain function: `Spec.bump(Swift.Double) ->
/// Swift.Double`. Declined (nil) unless every link holds:
///
/// - the symbol is one generic specialization of a function, static or not,
///   with no function signature specialization (which drops and explodes
///   arguments) and no closure;
/// - the tree prints exactly the name the call was given;
/// - the function's generic signature has one depth, its parameter count is
///   the substitution count, and its requirements are conformances or
///   layouts only, so every parameter is canonical;
/// - every generic parameter in the function type is a depth-0 parameter by
///   itself (no member type such as `A.Element`, no nested generic type).
extension DisassembledFunction {
    static func specializedSignature(symbol: String, printedName: String) -> String? {
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_$s") { mangled = mangled.dropFirst() }
        guard mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)),
              global.kind == .global, global.print(using: .default) == printedName
        else { return nil }
        let parts = Array(global.children)
        guard parts.count == 2, parts[0].kind == .genericSpecialization else { return nil }

        var substitutions: [Node] = []
        for child in parts[0].children {
            switch child.kind {
            case .isSerialized, .specializationPassID:
                continue
            case .genericSpecializationParam:
                guard child.children.count == 1, let type = child.children.first, type.kind == .type else { return nil }
                substitutions.append(type)
            default:
                return nil
            }
        }

        let isStatic = parts[1].kind == .static
        guard let function = isStatic ? parts[1].children.first : parts[1], function.kind == .function,
              !isStatic || parts[1].children.count == 1,
              let typeNode = function.children.last, typeNode.kind == .type,
              let generic = unwrappingType(typeNode), generic.kind == .dependentGenericType,
              generic.children.count == 2,
              let signature = generic.children.first, signature.kind == .dependentGenericSignature,
              let functionType = unwrappingType(generic.children[1]), functionType.kind == .functionType
        else { return nil }

        var parameterCount: UInt64?
        for child in signature.children {
            switch child.kind {
            case .dependentGenericParamCount:
                guard parameterCount == nil, let count = child.index else { return nil }
                parameterCount = count
            case .dependentGenericConformanceRequirement, .dependentGenericLayoutRequirement,
                 .dependentGenericInverseConformanceRequirement:
                continue
            default:
                return nil
            }
        }
        guard let parameterCount, parameterCount == UInt64(substitutions.count),
              let substituted = substituting(functionType, with: substitutions)
        else { return nil }

        let specialized = Node.create(
            kind: .function,
            children: Array(function.children.dropLast()) + [Node.create(kind: .type, child: substituted)]
        )
        let entity = isStatic ? Node.create(kind: .static, child: specialized) : specialized
        return Node.create(kind: .global, child: entity).print(using: .default)
    }

    /// `node` with each depth-0 generic parameter replaced by its
    /// substitution, or nil when a parameter is anything else.
    private static func substituting(_ node: Node, with substitutions: [Node]) -> Node? {
        if node.kind == .type, node.children.count == 1, let only = node.children.first,
           only.kind == .dependentGenericParamType {
            guard let parameter = genericParameter(node), parameter.depth == 0,
                  parameter.index < UInt64(substitutions.count)
            else { return nil }
            return substitutions[Int(parameter.index)]
        }
        switch node.kind {
        case .dependentGenericParamType, .dependentMemberType, .dependentGenericType,
             .dependentGenericSignature:
            return nil
        default:
            break
        }
        guard !node.children.isEmpty else { return node }
        var children: [Node] = []
        for child in node.children {
            guard let replaced = substituting(child, with: substitutions) else { return nil }
            children.append(replaced)
        }
        return Node.create(kind: node.kind, children: children)
    }
}
