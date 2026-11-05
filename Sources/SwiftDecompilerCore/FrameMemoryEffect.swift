/// A tracked fact's bytes, relative to this function's entry stack pointer.
/// Width validation belongs to the fact producer; legacy consumers can carry
/// zero widths or wrapped addresses, which this slice does not reinterpret.
struct FrameMemoryExtent: Sendable, Equatable {
    let start: Int64
    let bytes: Int64
}

/// MAY-write footprints shared by frame-fact consumers. Durable escape state,
/// provenance and value installation remain with the analyses. An exact write
/// replaces bytes; forgetting knowledge after an unknown write does not.
struct FrameMemoryEffect: Sendable, Equatable {
    enum FactEndArithmetic: Sendable, Equatable {
        /// Unknown-write tracer facts historically compare `start &+ bytes`.
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
        case startsBelow(Int64)
        /// Exact storeStack compatibility: endpoint additions trap, are deferred
        /// until a query, and the write end is tested before the fact end.
        /// This region's explicit policy overrides FactEndArithmetic.
        case legacyTracerExactWrite(start: Int64, bytes: Int64)
    }

    /// Canonical 0/1/many storage. Direct exact-store construction has no Set;
    /// existing Set callers still canonicalize to the same equality value.
    private enum Regions: Sendable, Equatable {
        case empty
        case single(Region)
        case multiple(Set<Region>)

        init(_ regions: Set<Region>) {
            if regions.isEmpty { self = .empty }
            else if regions.count == 1, let region = regions.first { self = .single(region) }
            else { self = .multiple(regions) }
        }

        var isEmpty: Bool {
            if case .empty = self { return true }
            return false
        }

        func contains(where predicate: (Region) -> Bool) -> Bool {
            switch self {
            case .empty: return false
            case .single(let region): return predicate(region)
            case .multiple(let regions): return regions.contains(where: predicate)
            }
        }

        func union(_ other: Regions) -> Regions {
            switch (self, other) {
            case (.empty, _): return other
            case (_, .empty): return self
            case (.single(let a), .single(let b)):
                return a == b ? self : .multiple([a, b])
            case (.multiple(let regions), .single(let region)), (.single(let region), .multiple(let regions)):
                return .multiple(regions.union([region]))
            case (.multiple(let a), .multiple(let b)):
                return .multiple(a.union(b))
            }
        }
    }

    let arithmetic: FactEndArithmetic
    private let everything: Bool
    private let regions: Regions

    init(_ regions: Set<Region> = [], arithmetic: FactEndArithmetic, everything: Bool = false) {
        self.init(regions: Regions(regions), arithmetic: arithmetic, everything: everything)
    }

    /// No temporary singleton Set is needed by an exact-store consumer.
    init(_ region: Region, arithmetic: FactEndArithmetic, everything: Bool = false) {
        self.init(regions: .single(region), arithmetic: arithmetic, everything: everything)
    }

    private init(regions: Regions, arithmetic: FactEndArithmetic, everything: Bool) {
        self.arithmetic = arithmetic
        self.everything = everything
        self.regions = regions
    }

    /// Deliberately performs no endpoint arithmetic. With no old facts,
    /// storeStack makes no query and has never evaluated an overlap endpoint.
    static func legacyTracerExactWrite(start: Int64, bytes: Int64) -> FrameMemoryEffect {
        FrameMemoryEffect(.legacyTracerExactWrite(start: start, bytes: bytes), arithmetic: .wrapping)
    }

    var isEmpty: Bool { !everything && regions.isEmpty }
    var isWholeFrame: Bool { everything }

    /// MAY joins retain every disjoint region; no hull, intersection, clearing
    /// or arbitrary cap may narrow what an escaped address can reach.
    func union(_ other: FrameMemoryEffect) -> FrameMemoryEffect {
        precondition(arithmetic == other.arithmetic, "Frame effect arithmetic must match its consumer")
        return FrameMemoryEffect(regions: regions.union(other.regions), arithmetic: arithmetic,
                                 everything: everything || other.everything)
    }

    func mayInvalidate(_ fact: FrameMemoryExtent) -> Bool {
        if everything { return true }
        return regions.contains { region in
            switch region {
            case .finite(let lower, let upper):
                // Preserve checked overflow's unconditional invalidation,
                // even when a later upper-bound test would be false.
                guard let end = factEnd(fact) else { return true }
                return Self.strictlyOverlaps(lower: lower, upper: upper,
                    factStart: fact.start, factEnd: end, order: .lowerFirst)
            case .atOrAbove(let lower):
                guard let end = factEnd(fact) else { return true }
                return lower < end
            case .startsBelow(let upper):
                return fact.start < upper
            case .legacyTracerExactWrite(let start, let bytes):
                return Self.strictlyOverlaps(lower: start, upper: start + bytes,
                    factStart: fact.start, factEnd: fact.start + fact.bytes, order: .upperFirst)
            }
        }
    }

    enum ComparisonOrder: Sendable {
        case lowerFirst
        case upperFirst
    }

    /// The common strict half-open comparison. Autoclosures keep the legacy
    /// exact tracer's potentially trapping endpoints in their original order.
    /// Internal visibility permits direct order assertions without test hooks.
    static func strictlyOverlaps(
        lower: Int64, upper: @autoclosure () -> Int64,
        factStart: Int64, factEnd: @autoclosure () -> Int64,
        order: ComparisonOrder
    ) -> Bool {
        switch order {
        case .lowerFirst:
            return lowerBoundary(lower, factEnd: factEnd()) && upperBoundary(factStart, upper: upper())
        case .upperFirst:
            return upperBoundary(factStart, upper: upper()) && lowerBoundary(lower, factEnd: factEnd())
        }
    }

    private static func lowerBoundary(_ lower: Int64, factEnd: Int64) -> Bool {
        lower < factEnd
    }

    private static func upperBoundary(_ factStart: Int64, upper: Int64) -> Bool {
        factStart < upper
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
