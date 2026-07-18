import Foundation
import MachOKit
import MachOSwiftSection

/// The set of Swift **class** (reference) type names an image defines.
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

    public init(classNames: Set<String> = []) { self.classNames = classNames }

    /// Whether `typeName` (possibly module-qualified, e.g. `Module.Ref`) names a
    /// class this image defines unambiguously.
    public func isClass(_ typeName: String) -> Bool {
        let simple = typeName.split(separator: ".").last.map(String.init) ?? typeName
        return classNames.contains(simple)
    }

    /// The inner type of `Optional<Inner>` when `Inner` is a single-register
    /// reference (a class), else nil. `Swift.Optional<Module.Ref>` → `Module.Ref`.
    public func referenceOptionalInner(_ type: String) -> String? {
        guard type.hasPrefix("Swift.Optional<"), type.hasSuffix(">") else { return nil }
        let inner = String(type.dropFirst("Swift.Optional<".count).dropLast())
        return isClass(inner) ? inner : nil
    }

    public var count: Int { classNames.count }

    public static func build(in machO: MachOFile) -> ClassTypeIndex {
        var classes: Set<String> = []
        var nonClasses: Set<String> = []
        for type in (try? machO.swift.types) ?? [] {
            switch type {
            case .class(let model):
                if let name = try? model.descriptor.name(in: machO) { classes.insert(name) }
            case .struct(let model):
                if let name = try? model.descriptor.name(in: machO) { nonClasses.insert(name) }
            case .enum(let model):
                if let name = try? model.descriptor.name(in: machO) { nonClasses.insert(name) }
            }
        }
        // A name shared with a struct/enum is ambiguous → not treated as a class.
        return ClassTypeIndex(classNames: classes.subtracting(nonClasses))
    }
}
