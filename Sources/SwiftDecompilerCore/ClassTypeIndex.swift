import Foundation
import MachOKit
import MachOSwiftSection
import Demangling

/// Small facts retained from an already-demangled tree; the tree itself is
/// released. Fully qualified identities keep imported structs out of class ABI.
struct NominalTypeEvidence: Sendable {
    var classes: Set<String> = []
    var values: Set<String> = []

    mutating func collect(from root: Node, options: DemangleOptions) {
        var work = [root]
        while let node = work.popLast() {
            switch node.kind {
            case .class, .boundGenericClass:
                classes.insert(node.print(using: options))
            case .structure, .enum, .boundGenericStructure, .boundGenericEnum:
                values.insert(node.print(using: options))
            case .extension:
                // Swift extends only nominal types, so an extension of a C
                // typedef (`(extension in os):__C.os_log_type_t`) extends one
                // the importer made a struct; its node is a TypeAlias.
                let parts = Array(node.children)
                if parts.count >= 2, parts[1].kind == .typeAlias,
                   let module = Array(parts[1].children).first, module.kind == .module, module.text == "__C" {
                    values.insert(parts[1].print(using: options))
                }
            default: break
            }
            work.append(contentsOf: node.children)
        }
    }

    mutating func formUnion(_ other: Self) {
        classes.formUnion(other.classes)
        values.formUnion(other.values)
    }
}

/// Swift **class** (reference) types proved by metadata, Objective-C symbols,
/// or nominal-kind nodes in the image's mangled signatures.
///
/// This is what makes `Optional<SomeClass>` recoverable: a reference-typed
/// optional is a single register with `nil == 0` (unlike a value-typed
/// `Optional<Int>`, which is a payload plus a separate tag byte). So a class
/// optional seeds like a scalar and its `!= nil` / `?? default` reconstruct,
/// while a tagged optional must still decline.
///
/// A simple name shared by a class AND a struct/enum is treated as **not** a
/// class — the conservative choice, so a value-typed optional is never
/// mis-seeded as single-register. Class metadata; survives stripping.
public struct ClassTypeIndex: Sendable {
    /// Simple names that are unambiguously a class in this image.
    private let classNames: Set<String>
    /// Full names proved to be a class by a descriptor or a nominal-kind node.
    private let qualifiedClassNames: Set<String>
    private let qualifiedNonClassNames: Set<String>

    public init(classNames: Set<String> = [], qualifiedClassNames: Set<String> = [],
                qualifiedNonClassNames: Set<String> = []) {
        self.classNames = classNames
        self.qualifiedClassNames = qualifiedClassNames.subtracting(qualifiedNonClassNames)
        self.qualifiedNonClassNames = qualifiedNonClassNames
    }

    /// Whether `typeName` (possibly module-qualified, e.g. `Module.Ref`) names a
    /// class proved unambiguously by the index's evidence.
    public func isClass(_ typeName: String) -> Bool {
        // A qualified name may refer to a different module's struct or enum.
        // Only matching qualified evidence proves reference layout.
        if typeName.contains(".") { return qualifiedClassNames.contains(typeName) }
        return classNames.contains(typeName)
    }

    /// Whether a module-qualified `typeName` is a struct or enum by the
    /// index's evidence (a descriptor or a nominal-kind node).
    public func isValueType(_ typeName: String) -> Bool {
        qualifiedNonClassNames.contains(typeName)
    }

    /// The inner type of `Optional<Inner>` when `Inner` is a single-register
    /// reference (a class), else nil. `Swift.Optional<Module.Ref>` → `Module.Ref`.
    public func referenceOptionalInner(_ type: String) -> String? {
        guard type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") else { return nil }
        let inner = String(type.dropFirst("Swift.Optional<".count).dropLast())
        return isClass(inner) ? inner : nil
    }

    public var count: Int { classNames.count }

    func adding(_ evidence: NominalTypeEvidence) -> ClassTypeIndex {
        let nonClasses = qualifiedNonClassNames.union(evidence.values)
        // A simplified signature can erase the module. A foreign value type
        // sharing a local class's simple name must not seed it as a reference.
        let simpleNonClasses = Set(evidence.values.compactMap { $0.split(separator: ".").last.map(String.init) })
        return ClassTypeIndex(classNames: classNames.subtracting(simpleNonClasses),
            qualifiedClassNames: qualifiedClassNames.union(evidence.classes),
            qualifiedNonClassNames: nonClasses)
    }

    public static func build(in machO: MachOFile) -> ClassTypeIndex {
        var classes: Set<String> = []
        var nonClasses: Set<String> = []
        var qualifiedClasses: Set<String> = []
        var qualifiedNonClasses: Set<String> = []
        for type in (try? machO.swift.types) ?? [] {
            switch type {
            case .class(let model):
                if let name = try? model.descriptor.name(in: machO) { classes.insert(name) }
                if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) {
                    qualifiedClasses.insert(qualified)
                }
            case .struct(let model):
                if let name = try? model.descriptor.name(in: machO) { nonClasses.insert(name) }
                if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) {
                    qualifiedNonClasses.insert(qualified)
                }
            case .enum(let model):
                if let name = try? model.descriptor.name(in: machO) { nonClasses.insert(name) }
                if let qualified = FieldMapBuilder.qualifiedName(of: type, in: machO) {
                    qualifiedNonClasses.insert(qualified)
                }
            }
        }
        // An Objective-C class this image defines or imports has an
        // `_OBJC_CLASS_$_Name` symbol, which only a class has, and Swift names
        // it `__C.Name`. Without this a parameter of type `__C.NSObject` was not
        // known to fit one register, and the seed of every incoming argument
        // was abandoned: `withObject(k, o)` rendered `note(?)` for `note(k)`.
        // Swift classes exported to Objective-C (`_TtC…`) are indexed above.
        let prefix = "_OBJC_CLASS_$_"
        for symbol in machO.symbols where symbol.name.hasPrefix(prefix) {
            let name = symbol.name.dropFirst(prefix.count)
            guard !name.isEmpty, !name.hasPrefix("_Tt"),
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { continue }
            qualifiedClasses.insert("__C." + name)
        }
        // A name shared with a struct/enum is ambiguous → not treated as a class.
        return ClassTypeIndex(
            classNames: classes.subtracting(nonClasses),
            qualifiedClassNames: qualifiedClasses.subtracting(qualifiedNonClasses),
            qualifiedNonClassNames: qualifiedNonClasses
        )
    }
}
