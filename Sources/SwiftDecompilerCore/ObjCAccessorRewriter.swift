import Foundation
import MachOKit
import ObjCDump

extension ObjCDumper {
    /// A property's accessor: the object type the method encoding drops (an
    /// accessor's return/argument is encoded only as `@`/`id`), and whether this
    /// selector is the setter.
    struct PropertyAccessor {
        let type: String
        let isSetter: Bool
    }

    /// Rewrite a class header so property-backed accessors read like a real
    /// header. A declared `@property` already implies its getter and setter, so a
    /// *synthesized* accessor (a trivial ivar load/store) is redundant and
    /// dropped; a *custom* accessor is genuine code, so it is kept and given the
    /// object type recovered from the property.
    ///
    /// `isSynthesized(imp)` is the disassembly-backed oracle: `true` = trivial
    /// (suppress), `false` = custom (keep + type), `nil` = unknown — no disasm on
    /// this architecture, so treat every property-backed accessor as synthesized,
    /// which is class-dump's metadata-only behaviour.
    static func rewritingPropertyAccessors(
        _ header: String,
        class info: ObjCClassInfo,
        isSynthesized: (UInt64) -> Bool?
    ) -> String {
        guard !info.properties.isEmpty, !info.methods.isEmpty else { return header }
        let accessors = propertyAccessors(info.properties)
        guard !accessors.isEmpty else { return header }

        var suppress: Set<String> = []      // exact header lines to drop
        var retype: [String: String] = [:]  // old line → typed line

        for method in info.methods where !method.isClassMethod {
            guard let accessor = accessors[method.name] else { continue }
            let line = method.headerString
            if isSynthesized(method.imp) == false {
                let typed = retyping(line, accessor: accessor)
                if typed != line { retype[line] = typed }
            } else {
                suppress.insert(line)
            }
        }
        guard !suppress.isEmpty || !retype.isEmpty else { return header }

        // Each method renders as its own `headerString` line, so whole-line
        // matching rewrites exactly the accessor lines and nothing else.
        let lines = header.components(separatedBy: "\n").compactMap { line -> String? in
            if suppress.contains(line) { return nil }
            return retype[line] ?? line
        }
        return lines.joined(separator: "\n")
    }

    /// Selector → accessor descriptor for every getter and setter a property
    /// declares, honouring `getter=`/`setter=` and `readonly`.
    private static func propertyAccessors(_ properties: [ObjCPropertyInfo]) -> [String: PropertyAccessor] {
        var result: [String: PropertyAccessor] = [:]
        for property in properties {
            let attributes = property.attributes
            let type = attributes.compactMap { attribute -> String? in
                if case let .type(type) = attribute, let type { return type.decodedStringForArgument }
                return nil
            }.first
            guard let type else { continue }

            let customGetter = attributes.compactMap { attribute -> String? in
                if case let .getter(name) = attribute { return name } else { return nil }
            }.first
            result[customGetter ?? property.name] = PropertyAccessor(type: type, isSetter: false)

            guard !attributes.contains(.readonly) else { continue }
            let customSetter = attributes.compactMap { attribute -> String? in
                if case let .setter(name) = attribute { return name } else { return nil }
            }.first
            let setter = customSetter ?? "set\(capitalizingFirst(property.name)):"
            result[setter] = PropertyAccessor(type: type, isSetter: true)
        }
        return result
    }

    private static func capitalizingFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }

    /// Give a kept custom accessor the object type its encoding dropped:
    /// `- (id)name;` → `- (NSString *)name;`,
    /// `- (void)setName:(id)arg0;` → `- (void)setName:(NSString *)arg0;`.
    /// Only the untyped `id` is substituted; an accessor whose type the encoding
    /// already carries (a scalar like `int`) is left as-is.
    private static func retyping(_ line: String, accessor: PropertyAccessor) -> String {
        guard accessor.type != "id" else { return line }
        if accessor.isSetter {
            return line.replacingOccurrences(of: "(id)arg0", with: "(\(accessor.type))arg0")
        }
        return line.replacingOccurrences(of: "- (id)", with: "- (\(accessor.type))")
    }

    /// Disassemble every property-backed accessor and classify it: `true` =
    /// synthesized (a trivial ivar load/store its @property already covers),
    /// `false` = custom (real code, keep and type it). Keyed by the raw
    /// `ObjCMethodInfo.imp` so `rewritingPropertyAccessors` can look it up.
    static func classifyAccessors(
        _ snapshot: ObjCMetadataSnapshot,
        in machO: MachOFile,
        disassembler: Disassembler
    ) async -> [UInt64: Bool] {
        var rawToRuntime: [UInt64: UInt64] = [:]
        for cls in snapshot.classes {
            let accessors = propertyAccessors(cls.properties)
            guard !accessors.isEmpty else { continue }
            for method in cls.methods
            where !method.isClassMethod && accessors[method.name] != nil {
                if let runtime = ObjCMetadataIndex.implementationAddress(of: method.imp, in: machO) {
                    rawToRuntime[method.imp] = runtime
                }
            }
        }
        guard !rawToRuntime.isEmpty else { return [:] }

        let functions = await disassembler.disassembleFunctions(at: Set(rawToRuntime.values), in: machO)
        let byAddress = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { first, _ in first })

        var result: [UInt64: Bool] = [:]
        for (raw, runtime) in rawToRuntime {
            if let function = byAddress[runtime] {
                result[raw] = isSynthesizedAccessor(function)
            }
        }
        return result
    }

    /// Whether a disassembled accessor body is synthesized: a single basic block
    /// (no branches or loops) whose only calls are ARC / property-storage runtime
    /// helpers. Anything that sends a message, calls another function, or has
    /// control flow is custom and worth keeping.
    static func isSynthesizedAccessor(_ function: DisassembledFunction) -> Bool {
        guard function.basicBlocks().count <= 1 else { return false }
        for insn in function.instructions
        where insn.controlFlow == .call || insn.controlFlow == .branch {
            guard let callee = DisassembledFunction.calleeName(of: insn) else {
                // An unresolved call is not provably a helper — treat as custom.
                if insn.controlFlow == .call { return false }
                continue
            }
            guard isAccessorRuntimeHelper(callee) else { return false }
        }
        return true
    }

    /// ARC and property-storage helpers a synthesized accessor may call: the
    /// retain/release/autorelease bookkeeping `isRuntimeNoise` already knows,
    /// plus the atomic/copy accessor primitives.
    private static func isAccessorRuntimeHelper(_ callee: String) -> Bool {
        if DisassembledFunction.isRuntimeNoise(callee) { return true }
        let helpers = [
            "objc_storeStrong", "objc_storeWeak", "objc_loadWeakRetained",
            "objc_getProperty", "objc_setProperty", "objc_copyStruct",
            "objc_copyCppObjectAtomic", "objc_initWeak", "objc_destroyWeak",
        ]
        return helpers.contains { callee.hasPrefix($0) }
    }
}
