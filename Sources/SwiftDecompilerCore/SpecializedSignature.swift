import Demangling
import Synchronization

/// The signature a specialization is called with, as far as its mangled
/// clauses prove it.
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
/// Swift.Double`.
///
/// Arguments can then leave the list, and nothing printed says so: a `Tt`
/// clause drops a metatype (NodePrinter skips `DroppedArgument`, so
/// `generic specialization <Swift.Int8> of P.meta<A>(A.Type, Swift.Int)`
/// takes one Int in x0), and a closure-propagated clause drops the closure
/// and appends its captures after every argument left. The tree says both.
///
/// Proven only when every link holds:
///
/// - the symbol is function signature specializations over at most one
///   generic specialization of a function;
/// - the tree prints exactly the name it was given;
/// - the function's generic signature has one depth, its parameter count is
///   the substitution count, and its requirements are conformances or
///   layouts only, so every parameter is canonical;
/// - every generic parameter in the function type is a depth-0 parameter by
///   itself (no member type such as `A.Element`, no nested generic type);
/// - a tuple result has no generic element, since a buffer then stays in x0;
/// - a clause that removes arguments is on a synchronous function with no
///   tuple formal, every index it names is accounted for (`survivors`), and
///   a function signature specialization has one entry per parameter, so
///   no `self` is among its arguments (`applying`). It may re-own or remove
///   a closure; anything else, `Arg[0] = Dead` included, is left to the
///   printed name.
struct SpecializedLayout: Equatable, Sendable {
    /// `P.apply(Swift.Int, Swift.Int) -> Swift.Int`.
    let signature: String
    /// False when a capture the mangling cannot place follows the parameters
    /// `signature` lists (`isPlacedCapture`). The listed ones are still in
    /// their registers, so a body can be seeded from them. A call cannot be
    /// laid out from them: it passes more.
    let isComplete: Bool
}

/// What a symbol's mangled clauses say about the printed name.
enum SpecializationClause: Equatable, Sendable {
    /// No clause this reads, or none that removes an argument: what the
    /// printed name says stands (`signatureSpecializationKeepsLayout`).
    case absent
    case proven(SpecializedLayout)
    /// The clause drops arguments and could not be followed. The printed
    /// signature lists a parameter that is not there, so a call is bounded
    /// by its body. No body is seeded either: what a clause drops is a
    /// metatype or a value of generic type, and the printed list places no
    /// parameter once it reaches one (`aDeclinedClauseSeedsNothing`).
    case declined
}

/// One parameter of a specialization, as a tuple element.
private struct SpecializedParameter {
    let element: Node
    let isCapture: Bool
}

extension DisassembledFunction {
    static func specializedSignature(symbol: String, printedName: String) -> String? {
        guard case .proven(let layout) = specializationClause(symbol: symbol, printedName: printedName),
              layout.isComplete
        else { return nil }
        return layout.signature
    }

    /// What the mangled clauses of `symbol` prove, parsed once per symbol: a
    /// name is read many times, by entry seeding, the result register and
    /// each parameter-type query. `printedName` must be what the tree
    /// prints.
    static func specializationClause(symbol: String, printedName: String) -> SpecializationClause {
        guard isSpecializationName(printedName) else { return .absent }
        if let known = parsedClauses.withLock({ $0[symbol] }) {
            return known.printed == printedName ? known.clause : .absent
        }
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_$s") { mangled = mangled.dropFirst() }
        guard mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)), global.kind == .global
        else { return .absent }
        let parsed = (printed: global.print(using: .default), clause: parseClause(of: global))
        parsedClauses.withLock { $0[symbol] = parsed }
        return parsed.printed == printedName ? parsed.clause : .absent
    }

    /// Whether a name opens with a clause this reads, cheaply: every
    /// function's name comes through here. The merged and `Tt` forms print
    /// `generic` first too.
    static func isSpecializationName(_ name: String) -> Bool {
        name.hasPrefix("generic ") || name.hasPrefix("function signature specialization <")
            || name.hasPrefix("merged ")
    }

    private static let parsedClauses = Mutex<[String: (printed: String, clause: SpecializationClause)]>([:])

    private static func parseClause(of global: Node) -> SpecializationClause {
        let parts = Array(global.children)
        guard parts.count >= 2, let entity = parts.last else { return .absent }
        let clauses = Array(parts.dropLast())
        if let layout = layout(of: entity, under: clauses) { return .proven(layout) }
        guard clauses.contains(where: { $0.children.contains { $0.kind == .droppedArgument } }) else { return .absent }
        // A dropped argument prints nothing, so the printed signature of a
        // clause this parse cannot read lists a parameter that is not there,
        // unless what went was never in that list.
        return dropsOnlyPastFormals(of: entity, under: clauses) ? .absent : .declined
    }

    /// Whether every argument a lone clause drops is past the formals, where
    /// a `self` or a capture is: `_ContiguousArrayBuffer.init(_uninitializedCount:
    /// minimumCapacity:)`'s `Tt1` is its thin metatype, and a closure's its
    /// captured one. Each formal stays where the name prints it. This parse
    /// reads only functions, but the check needs no more than the function
    /// type.
    private static func dropsOnlyPastFormals(of entity: Node, under clauses: [Node]) -> Bool {
        let isStatic = entity.kind == .static
        guard clauses.count == 1, let clause = clauses.first,
              let declaration = isStatic ? entity.children.first : entity,
              !isFreeFunction(declaration, isStatic: isStatic),
              let typeNode = declaration.children.first(where: { $0.kind == .type }),
              var functionType = unwrappingType(typeNode)
        else { return false }
        if functionType.kind == .dependentGenericType {
            guard let inner = functionType.children.last.flatMap(unwrappingType) else { return false }
            functionType = inner
        }
        guard functionType.kind == .functionType, !isUnmeasured(functionType),
              // An indirect typed error is a SIL argument too.
              !functionType.children.contains(where: { $0.kind == .typedThrowsAnnotation }),
              let declared = formals(of: functionType), !hasTupleFormal(declared),
              let result = resultType(of: functionType)
        else { return false }
        let results = indirectResultCount(of: result)
        return clause.children.allSatisfy { child in
            guard child.kind == .droppedArgument else { return true }
            guard let index = child.index.map({ Int($0) }) else { return false }
            if let results { return index >= results + declared.count }
            // Any result but a tuple is at most one `@out`, which would make
            // this the formal before: `Pack<A>.init(count:scale:)`'s index 2
            // would be `scale`, an Int the compiler never drops.
            guard unwrappingType(result)?.kind != .tuple, index >= declared.count else { return false }
            return index > declared.count || !isDroppable(declared[index - 1])
        }
    }

    /// Nothing follows a free function's formals, and a clause that says
    /// otherwise is not read.
    private static func isFreeFunction(_ function: Node, isStatic: Bool) -> Bool {
        !isStatic && function.kind == .function && function.children.first?.kind == .module
    }

    /// An async function's context is laid out apart from its formals, and no
    /// measurement covers its specializations.
    private static func isUnmeasured(_ functionType: Node) -> Bool {
        functionType.children.contains { $0.kind == .asyncAnnotation }
    }

    /// A clause counts SIL arguments, and a tuple formal explodes into one
    /// per element (`tup((Int, Int), A.Type, Int)` drops index 2).
    private static func hasTupleFormal(_ declared: [Node]) -> Bool {
        declared.contains { formalType($0).flatMap(unwrappingType)?.kind == .tuple }
    }

    private static func layout(of entity: Node, under clauses: [Node]) -> SpecializedLayout? {
        var signatureClauses = clauses
        let genericClause = signatureClauses.last?.kind == .genericSpecialization ? signatureClauses.removeLast() : nil
        guard signatureClauses.allSatisfy({ $0.kind == .functionSignatureSpecialization }),
              genericClause != nil || !signatureClauses.isEmpty
        else { return nil }

        let isStatic = entity.kind == .static
        guard let function = isStatic ? entity.children.first : entity, function.kind == .function,
              !isStatic || entity.children.count == 1,
              let typeNode = function.children.last, typeNode.kind == .type
        else { return nil }

        let functionType: Node
        var substitutions: [Node] = []
        // Each dropped argument's index in the SIL argument list.
        var dropped = Set<Int>()
        if let genericClause {
            for child in genericClause.children {
                switch child.kind {
                case .isSerialized, .specializationPassID:
                    continue
                case .droppedArgument:
                    guard let index = child.index else { return nil }
                    dropped.insert(Int(index))
                case .genericSpecializationParam:
                    guard child.children.count == 1, let type = child.children.first, type.kind == .type else { return nil }
                    substitutions.append(type)
                default:
                    return nil
                }
            }
            guard let generic = unwrappingType(typeNode), generic.kind == .dependentGenericType,
                  generic.children.count == 2,
                  let signature = generic.children.first, signature.kind == .dependentGenericSignature,
                  let declared = unwrappingType(generic.children[1]), declared.kind == .functionType
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
            guard parameterCount == UInt64(substitutions.count) else { return nil }
            functionType = declared
        } else {
            // A generic function left generic takes metadata after its
            // formals, and the clause's list does not say where.
            guard let declared = unwrappingType(typeNode), declared.kind == .functionType else { return nil }
            functionType = declared
        }
        guard let substituted = substituting(functionType, with: substitutions),
              let result = resultType(of: functionType), !isGenericTuple(result)
        else { return nil }

        if dropped.isEmpty, signatureClauses.isEmpty {
            return SpecializedLayout(signature: printed(function, isStatic: isStatic, type: substituted, labels: true),
                                     isComplete: true)
        }
        // A typed error can add an indirect SIL result before the formals, and
        // whether it does turns on its resilience, which the symbol does not
        // say: a dropped index cannot be mapped (55b2248).
        guard !functionType.children.contains(where: { $0.kind == .typedThrowsAnnotation }) else { return nil }

        guard !isUnmeasured(functionType), let declared = formals(of: functionType), !hasTupleFormal(declared),
              let kept = survivors(of: declared, dropping: dropped, result: result,
                                   isFree: isFreeFunction(function, isStatic: isStatic))
        else { return nil }
        var parameters = [SpecializedParameter]()
        for formal in kept {
            guard let element = substituting(formal, with: substitutions) else { return nil }
            parameters.append(SpecializedParameter(element: element, isCapture: false))
        }

        // Mangled last, printed first: the innermost clause is the last one.
        for clause in signatureClauses.reversed() {
            guard let rewritten = applying(clause, to: parameters) else { return nil }
            parameters = rewritten
        }

        var placed: [Node] = []
        var isComplete = true
        for parameter in parameters {
            guard !parameter.isCapture || isPlacedCapture(parameter.element) else {
                isComplete = false
                break
            }
            placed.append(parameter.element)
        }
        guard let rebuilt = replacingFormals(of: substituted, with: placed) else { return nil }
        return SpecializedLayout(signature: printed(function, isStatic: isStatic, type: rebuilt, labels: false),
                                 isComplete: isComplete)
    }

    /// `function` with `type`, printed as a plain function. The label list
    /// names the declared formals, so it goes when they change.
    private static func printed(_ function: Node, isStatic: Bool, type: Node, labels: Bool) -> String {
        let name = function.children.dropLast().map { labels || $0.kind != .labelList ? $0 : Node.create(kind: .labelList) }
        let specialized = Node.create(kind: .function, children: name + [Node.create(kind: .type, child: type)])
        let entity = isStatic ? Node.create(kind: .static, child: specialized) : specialized
        return Node.create(kind: .global, child: entity).print(using: .default)
    }

    /// Each formal of a function type as a tuple element.
    private static func formals(of functionType: Node) -> [Node]? {
        guard let arguments = functionType.children.first(where: { $0.kind == .argumentTuple }),
              arguments.children.count == 1, let type = arguments.children.first, type.kind == .type,
              let inner = unwrappingType(type)
        else { return nil }
        guard inner.kind == .tuple else { return [Node.create(kind: .tupleElement, child: type)] }
        let elements = Array(inner.children)
        return elements.allSatisfy({ $0.kind == .tupleElement && formalType($0) != nil }) ? elements : nil
    }

    private static func formalType(_ element: Node) -> Node? {
        element.children.last { $0.kind == .type }
    }

    private static func resultType(of functionType: Node) -> Node? {
        guard let result = functionType.children.first(where: { $0.kind == .returnType }),
              result.children.count == 1, let type = result.children.first, type.kind == .type
        else { return nil }
        return type
    }

    /// A tuple result with a generic element: `(A, A)` and `(Swift.Int, A)`.
    /// Only a function with no direct result gets one, so its specialization
    /// keeps a buffer in x0 (`dup<Int>` is `(ptr, i64, i64)` returning i64).
    private static func isGenericTuple(_ result: Node) -> Bool {
        unwrappingType(result)?.kind == .tuple && mentionsGenericParameter(result)
    }

    private static func mentionsGenericParameter(_ node: Node) -> Bool {
        node.kind == .dependentGenericParamType || node.children.contains { mentionsGenericParameter($0) }
    }

    /// The formals a `Tt` clause leaves. Its indices count SIL arguments, an
    /// indirect result's first: `rg<Double>(A.Type, Swift.Int, A) -> A`
    /// drops index 1 for the metatype (`Tt0`), and read against the formals
    /// that was the Int. The compiler drops a metatype or an unused value of
    /// generic type (`ReabstractionInfo::createSubstitutedAndSpecializedTypes`),
    /// so an index that lands anywhere else is a mapping this does not know.
    /// Past the formals is `self`, which `Array.==`'s `Tt1` drops as a thin
    /// metatype, and the list keeps every formal.
    private static func survivors(
        of declared: [Node], dropping dropped: Set<Int>, result: Node, isFree: Bool
    ) -> [Node]? {
        guard !dropped.isEmpty else { return declared }
        guard let indirectResults = indirectResultCount(of: result) else { return nil }
        var kept = declared
        for index in dropped.sorted(by: >) {
            let formal = index - indirectResults
            if !isFree, formal >= declared.count { continue }
            guard declared.indices.contains(formal), isDroppable(declared[formal]) else { return nil }
            kept.remove(at: formal)
        }
        return kept
    }

    private static func isDroppable(_ element: Node) -> Bool {
        guard let inner = formalType(element).flatMap(unwrappingType) else { return false }
        return inner.kind == .metatype || inner.kind == .dependentGenericParamType
    }

    /// How many SIL arguments a declared result takes before the formals:
    /// one for a value of generic type, none for a type that travels in
    /// registers, nil when it is not provably either (a value type of
    /// another module may be `@out`).
    private static func indirectResultCount(of result: Node) -> Int? {
        if unwrappingType(result)?.kind == .dependentGenericParamType { return 1 }
        return SwiftLowering.of(result.print(using: .default)).isDirect ? 0 : nil
    }

    /// `parameters` after one function signature specialization, or nil when
    /// the clause does more than remove a closure or re-own an argument.
    ///
    /// The clause has one entry per SIL argument
    /// (`FunctionSignatureSpecializationMangler`'s constructor), which checks
    /// this parameter list independently: an indirect result or a `self` the
    /// list does not hold makes the counts differ. The specialization takes
    /// the arguments that are left, then each closure's captures, in clause
    /// order (ClosureSpecialization.swift, `addFunctionArgumentsForCaptures`):
    /// `capTwo`'s `Tf1cncn_n` is `(double x, i64 z, i64 a, i64 b)`.
    private static func applying(_ clause: Node, to parameters: [SpecializedParameter]) -> [SpecializedParameter]? {
        var entries: [Node] = []
        for child in clause.children {
            switch child.kind {
            case .isSerialized, .specializationPassID:
                continue
            case .functionSignatureSpecializationParam:
                entries.append(child)
            default:
                // `Return = …`, a representation change, a removed `async`.
                return nil
            }
        }
        guard entries.count == parameters.count else { return nil }
        var kept: [SpecializedParameter] = []
        var captures: [SpecializedParameter] = []
        for (entry, parameter) in zip(entries, parameters) {
            guard let kind = entry.children.first else {
                kept.append(parameter)
                continue
            }
            guard kind.kind == .functionSignatureSpecializationParamKind, let value = kind.index else { return nil }
            switch value {
            case ParameterKind.ownedToGuaranteed, ParameterKind.guaranteedToOwned:
                kept.append(parameter)
            case ParameterKind.closure, ParameterKind.escapingClosure:
                for capture in entry.children where capture.kind == .type {
                    captures.append(SpecializedParameter(element: Node.create(kind: .tupleElement, child: capture),
                                                         isCapture: true))
                }
            case ParameterKind.sameClosureAsEarlierArgument:
                continue
            default:
                return nil
            }
        }
        return kept + captures
    }

    /// The `FunctionSigSpecializationParamKind` values this reads. That enum
    /// is internal to Demangling, whose numbering is not the compiler's past
    /// `constantPropKeyPath`.
    private enum ParameterKind {
        static let closure: UInt64 = 5
        static let sameClosureAsEarlierArgument: UInt64 = 11
        static let escapingClosure: UInt64 = 12
        static let ownedToGuaranteed: UInt64 = 128
        static let guaranteedToOwned: UInt64 = 512
    }

    /// Whether a capture's registers are fixed by its mangling. The clause
    /// lists SIL value types, so a capture by address prints like one by
    /// value: `capDouble`'s and `capVar`'s `Swift.Double` are `double %1` and
    /// `ptr %1`. Only a one-integer-register type takes the same register
    /// either way. A float's bank and a String's register count are unknown,
    /// and with them the place of every capture after them.
    private static func isPlacedCapture(_ element: Node) -> Bool {
        guard let type = formalType(element), let inner = unwrappingType(type) else { return false }
        if inner.kind == .class || inner.kind == .boundGenericClass { return true }
        return SwiftLowering.of(type.print(using: .default)) == .oneInteger
    }

    /// A function type with `elements` for its formals, or nil when it has
    /// no argument list.
    private static func replacingFormals(of functionType: Node, with elements: [Node]) -> Node? {
        guard let index = functionType.children.firstIndex(where: { $0.kind == .argumentTuple }) else { return nil }
        let tuple = Node.create(kind: .tuple, children: elements)
        var children = Array(functionType.children)
        children[index] = Node.create(kind: .argumentTuple, child: Node.create(kind: .type, child: tuple))
        return Node.create(kind: functionType.kind, children: children)
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

/// A proven substitution, an ordinary unavailable result, or the specific
/// dropped-index ambiguity that must also block outgoing argument guesses.
enum SpecializedSignatureProof: Equatable, Sendable {
    case unavailable
    case signature(String)
    case unprovenDroppedTypedError
}

extension DisassembledFunction {
    /// `specializationClause` for call recovery. A clause that drops an
    /// argument of a function with a typed throw is declined, and is not an
    /// ordinary unavailable signature: the typed error can add an indirect SIL
    /// result before the formals, so neither the printed list nor a
    /// positional fallback may lay out the call
    /// (`unprovenDroppedTypedError`).
    static func specializedSignatureProof(symbol: String, printedName: String) -> SpecializedSignatureProof {
        switch specializationClause(symbol: symbol, printedName: printedName) {
        case .proven(let layout): return .signature(layout.signature)
        case .absent: return .unavailable
        case .declined: return dropsUnderTypedThrow(symbol) ? .unprovenDroppedTypedError : .unavailable
        }
    }

    private static func dropsUnderTypedThrow(_ symbol: String) -> Bool {
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_$s") { mangled = mangled.dropFirst() }
        guard mangled.hasPrefix("$s"), let global = try? demangleAsNode(String(mangled)) else { return false }
        func contains(_ node: Node, _ kind: Node.Kind) -> Bool {
            node.kind == kind || node.children.contains { contains($0, kind) }
        }
        return contains(global, .droppedArgument) && contains(global, .typedThrowsAnnotation)
    }
}
