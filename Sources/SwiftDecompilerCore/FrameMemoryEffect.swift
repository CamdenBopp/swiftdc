/// A tracked fact's bytes, relative to this function's entry stack pointer.
/// Width validation belongs to the fact producer; legacy consumers can carry
/// zero widths or wrapped addresses, which this first slice does not reinterpret.
struct FrameMemoryExtent: Sendable, Equatable {
    let start: Int64
    let bytes: Int64
}

/// MAY reach of an unknown or unmodelled frame write. Durable escape state and
/// pointer provenance remain with the analyses; this value is their common
/// invalidation decision, not a new value store or allocation identity.
struct FrameMemoryEffect: Sendable, Equatable {
    enum FactEndArithmetic: Sendable, Equatable {
        /// The tracer historically compares `start &+ bytes`.
        case wrapping
        /// Preservation rejects a fact whose eight-byte end overflows.
        case checked
    }

    enum Region: Sendable, Hashable {
        /// Both bounds are finite, including Int64.min/max sentinels. Do not
        /// normalize reversed/wrapped bounds: legacy comparisons still apply.
        case finite(lower: Int64, upper: Int64)
        /// No upper comparison: legacy unknown-width writes and caller-owned
        /// reach ask whether the fact's end is above this bound.
        case atOrAbove(Int64)
        /// Legacy dynamic-allocation writes compare only the fact's start.
        /// This is deliberately distinct from a finite sentinel interval.
        case startsBelow(Int64)
    }

    let arithmetic: FactEndArithmetic
    private let everything: Bool
    private let regions: Set<Region>

    init(_ regions: Set<Region> = [], arithmetic: FactEndArithmetic, everything: Bool = false) {
        self.arithmetic = arithmetic
        self.everything = everything
        self.regions = regions
    }

    var isEmpty: Bool { !everything && regions.isEmpty }
    var isWholeFrame: Bool { everything }

    /// MAY joins retain every disjoint region; no hull, intersection, clearing
    /// or arbitrary cap may narrow what an escaped address can reach.
    func union(_ other: FrameMemoryEffect) -> FrameMemoryEffect {
        precondition(arithmetic == other.arithmetic, "Frame effect arithmetic must match its consumer")
        return FrameMemoryEffect(regions.union(other.regions), arithmetic: arithmetic,
                                 everything: everything || other.everything)
    }

    func mayInvalidate(_ fact: FrameMemoryExtent) -> Bool {
        if everything { return true }
        return regions.contains { region in
            switch region {
            case .finite(let lower, let upper):
                guard let end = factEnd(fact) else { return true }
                return lower < end && fact.start < upper
            case .atOrAbove(let lower):
                guard let end = factEnd(fact) else { return true }
                return lower < end
            case .startsBelow(let upper):
                return fact.start < upper
            }
        }
    }

    private func factEnd(_ fact: FrameMemoryExtent) -> Int64? {
        switch arithmetic {
        case .wrapping:
            return fact.start &+ fact.bytes
        case .checked:
            let (end, overflow) = fact.start.addingReportingOverflow(fact.bytes)
            return overflow ? nil : end
        }
    }
}
