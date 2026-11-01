import MachOKit
import MachOSwiftSection

/// Types whose descriptors the image holds but no type metadata record
/// lists.
///
/// IRGen adds a type to `__swift5_types` (or `__swift5_types2`, for a
/// noncopyable type) when it emits the type's metadata, and an optimized
/// build emits metadata lazily. A type whose metadata nothing needed keeps
/// its context descriptor and its field descriptor, but no record:
/// `ASTGenVisitor.DeclAttributesResult` in Xcode's LLDB has a descriptor
/// (`$s…DeclAttributesResultVMn`) and field metadata, and reading only the
/// records missed it. Its field descriptor names it, so each field
/// descriptor whose type is a direct reference to a descriptor no record
/// lists adds that type.
enum UnrecordedTypes {
    /// A `T` at `offset` (a file offset, or a cache offset for a cache
    /// image), or nil. Bound as `let x: UInt8 = try? readElement(at:)`, the
    /// read's `T` can be inferred as `Optional<UInt8>`, which decodes a tag
    /// byte from the next byte of the file: on LLDB that dropped every
    /// field descriptor, and no unrecorded type was found.
    static func read<T: FixedWidthInteger>(_ offset: Int, as _: T.Type, in machO: MachOFile) -> T? {
        do {
            let value: T = try machO.context.readElement(at: offset)
            return value
        } catch {
            return nil
        }
    }

    static func types(in machO: MachOFile, recorded: [TypeContextWrapper]) -> [TypeContextWrapper] {
        guard let section = machO.sections.first(where: { $0.segmentName == "__TEXT" && $0.sectionName == "__swift5_fieldmd" })
        else { return [] }
        let start: Int
        if let cache = machO.cache {
            start = section.address - Int(cache.mainCacheHeader.sharedRegionStart)
        } else {
            start = section.offset
        }
        let end = start + section.size
        let known = Set(recorded.map { SwiftDeclarationDumper.descriptorOffset(of: $0) })
        var found: [Int: TypeContextWrapper] = [:]
        let context = machO.context
        func read<T: FixedWidthInteger>(_ offset: Int, as type: T.Type) -> T? {
            Self.read(offset, as: type, in: machO)
        }
        var offset = start
        // A field descriptor: a relative pointer to the type's mangled name,
        // the superclass's, then kind (2), record size (2) and record count
        // (4), then the records.
        while offset + 16 <= end {
            guard let nameRelative = read(offset, as: Int32.self),
                  let recordSize = read(offset + 10, as: UInt16.self),
                  let count = read(offset + 12, as: UInt32.self)
            else { break }
            let next = offset + 16 + Int(recordSize) * Int(count)
            // A descriptor with no records may say its records are 0 bytes.
            guard recordSize == 12 || count == 0, next <= end else { break }
            defer { offset = next }
            let name = offset + Int(nameRelative)
            // Exactly a direct context reference and its terminator.
            guard read(name, as: UInt8.self) == 0x01, read(name + 5, as: UInt8.self) == 0,
                  let targetRelative = read(name + 1, as: Int32.self)
            else { continue }
            let target = name + 1 + Int(targetRelative)
            guard !known.contains(target), found[target] == nil,
                  let pointer = try? RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: targetRelative)
                      .resolve(at: name + 1, in: context),
                  let descriptor = pointer.typeContextDescriptorWrapper,
                  let type = try? TypeContextWrapper.forTypeContextDescriptorWrapper(descriptor, in: context),
                  SwiftDeclarationDumper.descriptorOffset(of: type) == target
            else { continue }
            found[target] = type
        }
        return found.keys.sorted().compactMap { found[$0] }
    }
}
