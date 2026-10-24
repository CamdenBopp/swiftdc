import Demangling

/// A generic specialization that binds a typed-throws error parameter to
/// `Swift.Never`.
///
/// The demangler prints a specialization as the unspecialized declaration,
/// so `generic specialization <(), Swift.Never> of f<A, B>(…) throws(B) -> A`
/// reads as throwing. No value of `Never` exists, so this function cannot
/// throw and every exit is a normal return. Only the substitution list says
/// what `B` is, and it is positional: it names the replacement of each
/// canonical generic parameter of the specialized function's generic
/// signature, in depth and index order (`GenericSpecializationMangler::
/// appendSubstitutions`). The proof reads that list from the demangle tree,
/// never from the printed name, and declines (keeps the function throwing)
/// unless every link holds:
///
/// - the symbol is one generic specialization of a function, or of a closure
///   directly inside one, optionally under one function signature
///   specialization (which changes how arguments travel, not the error type);
/// - the function's own generic signature has one depth and no requirement
///   that can make a parameter non-canonical (same-type, same-shape, pack or
///   value markers), and its parameter count equals the substitution count;
/// - the thrown type is a depth-0 parameter with a `Swift.Error` conformance
///   in that signature, and its substitution is exactly `Swift.Never`.
///
/// The count and the conformance together rule out an outer generic context.
/// An outer canonical parameter would add a substitution the function's own
/// signature does not count. An outer parameter that is not canonical never
/// carries a requirement, so a depth-0 parameter with its own `Swift.Error`
/// conformance is the function's own, and the function's own parameters sit
/// at depth 0 only when the context has none.
extension DisassembledFunction {
    /// The function's own signature throws: its name says `throws` and its
    /// specialization does not bind the thrown type to `Swift.Never`.
    var signatureThrows: Bool {
        Self.splitSignature(analysisDisplayName)?.isThrowing == true && !specializationBindsThrownTypeToNever
    }

    /// See the extension's comment. False whenever the binding is not proven.
    var specializationBindsThrownTypeToNever: Bool {
        guard objcMethod == nil, source == .symbol, let name = semanticName,
              name.contains("specialization <"),
              Self.splitSignature(name)?.thrownType != nil
        else { return false }
        return Self.specializationBindsThrownTypeToNever(symbol: symbol, semanticName: name)
    }

    /// Specialization kinds whose parameters are the replacement types of
    /// the specialized function's canonical generic parameters.
    private static let substitutingSpecializations: Set<Node.Kind> = [
        .genericSpecialization, .genericSpecializationNotReAbstracted,
        .genericSpecializationInResilienceDomain, .genericSpecializationPrespecialized,
    ]

    static func specializationBindsThrownTypeToNever(symbol: String, semanticName: String) -> Bool {
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_$s") { mangled = mangled.dropFirst() }
        // The tree must be the one the analysed name was printed from.
        guard mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)),
              global.kind == .global, global.print(using: .default) == semanticName
        else { return false }
        var parts = Array(global.children)
        if parts.count == 3, parts[0].kind == .functionSignatureSpecialization { parts.removeFirst() }
        guard parts.count == 2, substitutingSpecializations.contains(parts[0].kind) else { return false }

        var substitutions: [Node] = []
        for child in parts[0].children {
            switch child.kind {
            case .isSerialized, .specializationPassID:
                continue
            case .genericSpecializationParam:
                guard child.children.count == 1, let type = child.children.first else { return false }
                substitutions.append(type)
            default:
                return false
            }
        }

        // The function that owns the generic signature, and the function type
        // whose typed-throws annotation names the thrown type.
        let entity = parts[1]
        let function: Node
        let thrownIn: Node
        switch entity.kind {
        case .function:
            guard let generic = dependentGenericType(of: entity), generic.children.count == 2,
                  let inner = unwrappingType(generic.children[1])
            else { return false }
            function = entity
            thrownIn = inner
        case .explicitClosure, .implicitClosure:
            guard let context = entity.children.first, context.kind == .function,
                  let typeNode = entity.children.last, typeNode.kind == .type,
                  let closureType = unwrappingType(typeNode), closureType.kind != .dependentGenericType
            else { return false }
            function = context
            thrownIn = closureType
        default:
            return false
        }
        guard let generic = dependentGenericType(of: function),
              let signature = generic.children.first, signature.kind == .dependentGenericSignature
        else { return false }

        var parameterCount: UInt64?
        var errorConforming = Set<UInt64>()
        for child in signature.children {
            switch child.kind {
            case .dependentGenericParamCount:
                guard parameterCount == nil, let count = child.index else { return false }
                parameterCount = count
            case .dependentGenericConformanceRequirement:
                if child.children.count == 2, let parameter = genericParameter(child.children[0]),
                   parameter.depth == 0, isSwiftType(child.children[1], kind: .protocol, named: "Error") {
                    errorConforming.insert(parameter.index)
                }
            case .dependentGenericLayoutRequirement, .dependentGenericInverseConformanceRequirement:
                continue
            default:
                return false
            }
        }
        guard let parameterCount, parameterCount == UInt64(substitutions.count),
              thrownIn.kind == .functionType || thrownIn.kind == .noEscapeFunctionType
        else { return false }
        let annotations = thrownIn.children.filter { $0.kind == .typedThrowsAnnotation }
        guard annotations.count == 1, let annotation = annotations.first, annotation.children.count == 1,
              let thrown = genericParameter(annotation.children[0]), thrown.depth == 0,
              thrown.index < parameterCount, errorConforming.contains(thrown.index)
        else { return false }
        return isSwiftType(substitutions[Int(thrown.index)], kind: .enum, named: "Never")
    }

    /// The `DependentGenericType` a generic function's type is wrapped in.
    private static func dependentGenericType(of function: Node) -> Node? {
        guard let typeNode = function.children.last, typeNode.kind == .type,
              let type = unwrappingType(typeNode), type.kind == .dependentGenericType
        else { return nil }
        return type
    }

    static func unwrappingType(_ node: Node) -> Node? {
        var node = node
        while node.kind == .type {
            guard node.children.count == 1, let inner = node.children.first else { return nil }
            node = inner
        }
        return node
    }

    static func genericParameter(_ node: Node) -> (depth: UInt64, index: UInt64)? {
        guard let node = unwrappingType(node), node.kind == .dependentGenericParamType,
              node.children.count == 2,
              node.children[0].kind == .index, let depth = node.children[0].index,
              node.children[1].kind == .index, let index = node.children[1].index
        else { return nil }
        return (depth, index)
    }

    private static func isSwiftType(_ node: Node, kind: Node.Kind, named name: String) -> Bool {
        guard let node = unwrappingType(node), node.kind == kind, node.children.count == 2 else { return false }
        return node.children[0].kind == .module && node.children[0].text == "Swift"
            && node.children[1].kind == .identifier && node.children[1].text == name
    }
}
