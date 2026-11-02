import MachOKit

/// Where a method descriptor's or witness table slot's implementation field
/// leads, read as the runtime reads it.
///
/// `TargetMethodDescriptor::getImpl` (swift/include/swift/ABI/Metadata.h)
/// reads the field three ways. For a synchronous method it is code. When
/// `MethodDescriptorFlags::isAsync()` holds (`IsAsyncMask = 0x40`,
/// swift/include/swift/ABI/MetadataValues.h) it is `AsyncImpl`, a relative
/// pointer to an async function pointer; when `isCalleeAllocatedCoroutine()`
/// holds it is `CoroImpl`, a relative pointer to a coroutine function pointer.
/// An override descriptor (`TargetMethodOverrideDescriptor::getImpl`) takes
/// the base method's flags. A witness table slot for a requirement with
/// `ProtocolRequirementFlags::isAsync()` (`IsAsyncMask = 0x20`) holds the
/// witness's async function pointer (`IGM.getAddrOfAsyncFunctionPointer` in
/// swift/lib/IRGen/GenProto.cpp).
///
/// Both records are data and begin with a 32-bit relative pointer to the
/// function: `AsyncFunctionPointer { TargetCompactFunctionPointer<…, int32_t>
/// Function; uint32_t ExpectedContextSize; }` (swift/include/swift/ABI/
/// Executor.h; IRGen's `swift.async_func_pointer` is `{ i32 relative, i32 }`)
/// and `swift.coro_func_pointer` is `{ i32 relative, i32, i64 }`
/// (swift/lib/IRGen/IRGenModule.cpp). Naming the record as the method put a
/// function's name on data and left the real entry `sub_`.
struct MethodImplementation {
    private let machO: MachOFile
    private let base: UInt64
    /// The `__TEXT` sections the linker marks as instructions, other than
    /// stubs (`CodeSection.of` without its function-starts test, which
    /// metadata readers do not have). Read once: `sections` parses the load
    /// commands on every access.
    private let codeRanges: [Range<UInt64>]

    init(_ machO: MachOFile) {
        self.machO = machO
        base = machO.address(forOffset: 0)
        var ranges: [Range<UInt64>] = []
        for section in machO.sections where section.segmentName == "__TEXT" && section.size > 0 {
            let start = UInt64(section.address)
            let attributes = section.flags.attributes
            guard section.sectionName == "__text"
                || (attributes.contains(.pure_instructions) || attributes.contains(.some_instructions))
                && section.flags.type != .symbol_stubs
                && !["__stub_helper", "__objc_stubs"].contains(section.sectionName)
            else { continue }
            ranges.append(start ..< start + UInt64(section.size))
        }
        codeRanges = ranges
    }

    /// The code address an implementation field leads to, or nil when it
    /// cannot be shown to be code. `address` is where the field points;
    /// `isData` says the runtime reads it as a function pointer record.
    func code(at address: UInt64, isData: Bool) -> UInt64? {
        guard isData else { return isCode(address) ? address : nil }
        // Wrapping arithmetic: an address below the image wraps past
        // `Int.max` and is not read, and a target that wraps is not code.
        guard let recordOffset = Int(exactly: address &- base),
              let relative = UnrecordedTypes.read(recordOffset, as: Int32.self, in: machO)
        else { return nil }
        let function = address &+ UInt64(bitPattern: Int64(relative))
        // Where the record leads must be code; anywhere else, the field was
        // not what its flags say, and nothing is named.
        return isCode(function) ? function : nil
    }

    /// Whether `address` lies in one of the image's code sections.
    func isCode(_ address: UInt64) -> Bool {
        codeRanges.contains { $0.contains(address) }
    }
}

