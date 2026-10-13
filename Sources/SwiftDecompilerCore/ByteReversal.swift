/// Integer bit semantics shared by constant folding and the independent-value
/// evaluator. Native CPU fixtures validate this against the ARM instructions.
enum ByteReversal {
    static func apply(_ value: UInt64, bits: Int) -> UInt64? {
        switch bits {
        case 64: return value.byteSwapped
        case 32:
            return UInt64(UInt32(truncatingIfNeeded: value).byteSwapped)
                | (UInt64(UInt32(truncatingIfNeeded: value >> 32).byteSwapped) << 32)
        case 16:
            return ((value & 0x00ff00ff00ff00ff) << 8) | ((value & 0xff00ff00ff00ff00) >> 8)
        default: return nil
        }
    }
}
