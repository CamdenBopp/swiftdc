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

/// `clz`, `cls` and `rbit` on the low `bits` (32 or 64) of a value, shared
/// by constant folding and the independent-value evaluator.
enum BitCounting {
    static func apply(_ op: AbstractUnaryOperator, _ value: UInt64) -> UInt64? {
        switch op {
        case .leadingZeros(let bits): return leadingZeros(value, bits: bits)
        case .leadingSignBits(let bits): return leadingSignBits(value, bits: bits)
        case .bitReverse(let bits): return reversed(value, bits: bits)
        default: return nil
        }
    }

    /// Leading zeros of the low `bits`: `clz`.
    static func leadingZeros(_ value: UInt64, bits: Int) -> UInt64? {
        switch bits {
        case 64: return UInt64(value.leadingZeroBitCount)
        case 32: return UInt64(UInt32(truncatingIfNeeded: value).leadingZeroBitCount)
        default: return nil
        }
    }

    /// The bits after the sign bit that equal it, in the low `bits`: `cls`.
    static func leadingSignBits(_ value: UInt64, bits: Int) -> UInt64? {
        switch bits {
        case 64:
            let signed = Int64(bitPattern: value)
            return UInt64((signed ^ (signed >> 63)).leadingZeroBitCount - 1)
        case 32:
            let signed = Int32(truncatingIfNeeded: value)
            return UInt64((signed ^ (signed >> 31)).leadingZeroBitCount - 1)
        default: return nil
        }
    }

    /// The low `bits` in reverse order: `rbit`.
    static func reversed(_ value: UInt64, bits: Int) -> UInt64? {
        guard bits == 32 || bits == 64 else { return nil }
        var result: UInt64 = 0
        for bit in 0 ..< bits where value & (1 << UInt64(bit)) != 0 {
            result |= 1 << UInt64(bits - 1 - bit)
        }
        return result
    }
}
