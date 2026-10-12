/// The magic reciprocals LLVM chooses for division by a 64-bit constant,
/// ported from `llvm/lib/Support/DivisionByConstantInfo.cpp` (Hacker's Delight
/// 10-1 for signed, the Granlund-Montgomery variant with an add indicator and
/// even-divisor pre-shift for unsigned). Their derivations prove the resulting
/// sequence equals `x / D` for every 64-bit input, which is what lets
/// `MagicDivision` call a fold proven rather than sampled.
enum MagicConstants {
    struct Signed: Equatable {
        let magic: UInt64
        let shift: Int
    }

    struct Unsigned: Equatable {
        let magic: UInt64
        let preShift: Int
        let postShift: Int
        let isAdd: Bool
    }

    /// `SignedDivisionByConstantInfo::get`. Nil for |D| < 2.
    static func signed(_ divisor: Int64) -> Signed? {
        guard divisor != 0, divisor != 1, divisor != -1, divisor != .min else { return nil }
        let d = UInt64(bitPattern: divisor)
        let signedMin: UInt64 = 1 << 63
        let ad = divisor.magnitude
        let t = signedMin &+ (d >> 63)
        let anc = t &- 1 &- t % ad
        var p = 63
        var q1 = signedMin / anc, r1 = signedMin &- q1 &* anc
        var q2 = signedMin / ad, r2 = signedMin &- q2 &* ad
        var delta: UInt64
        repeat {
            p += 1
            q1 = q1 &<< 1; r1 = r1 &<< 1
            if r1 >= anc { q1 &+= 1; r1 &-= anc }
            q2 = q2 &<< 1; r2 = r2 &<< 1
            if r2 >= ad { q2 &+= 1; r2 &-= ad }
            delta = ad &- r2
        } while q1 < delta || (q1 == delta && r1 == 0)
        var magic = q2 &+ 1
        if divisor < 0 { magic = 0 &- magic }
        return Signed(magic: magic, shift: p - 64)
    }

    /// `UnsignedDivisionByConstantInfo::get`, with the even-divisor pre-shift.
    /// Nil for D < 2.
    static func unsigned(_ divisor: UInt64, leadingZeros: Int = 0, allowEvenPreShift: Bool = true) -> Unsigned? {
        guard divisor > 1 else { return nil }
        let allOnes: UInt64 = leadingZeros == 0 ? .max : (UInt64.max >> UInt64(leadingZeros))
        let signedMin: UInt64 = 1 << 63
        let signedMax: UInt64 = signedMin - 1
        let nc = allOnes &- (allOnes &+ 1 &- divisor) % divisor
        var p = 63
        var q1 = signedMin / nc, r1 = signedMin % nc
        var q2 = signedMax / divisor, r2 = signedMax % divisor
        var isAdd = false
        var delta: UInt64
        repeat {
            p += 1
            if r1 >= nc &- r1 {
                q1 = (q1 &<< 1) &+ 1
                r1 = (r1 &<< 1) &- nc
            } else {
                q1 = q1 &<< 1
                r1 = r1 &<< 1
            }
            if r2 &+ 1 >= divisor &- r2 {
                if q2 >= signedMax { isAdd = true }
                q2 = (q2 &<< 1) &+ 1
                r2 = (r2 &<< 1) &+ 1 &- divisor
            } else {
                if q2 >= signedMin { isAdd = true }
                q2 = q2 &<< 1
                r2 = (r2 &<< 1) &+ 1
            }
            delta = divisor &- 1 &- r2
        } while p < 128 && (q1 < delta || (q1 == delta && r1 == 0))

        if isAdd, divisor & 1 == 0, allowEvenPreShift {
            let preShift = divisor.trailingZeroBitCount
            guard let shifted = unsigned(divisor >> UInt64(preShift),
                                         leadingZeros: leadingZeros + preShift,
                                         allowEvenPreShift: false),
                  !shifted.isAdd, shifted.preShift == 0
            else { return nil }
            return Unsigned(magic: shifted.magic, preShift: preShift,
                            postShift: shifted.postShift, isAdd: false)
        }
        let postShift = p - 64 - (isAdd ? 1 : 0)
        return Unsigned(magic: q2 &+ 1, preShift: 0, postShift: postShift, isAdd: isAdd)
    }
}
