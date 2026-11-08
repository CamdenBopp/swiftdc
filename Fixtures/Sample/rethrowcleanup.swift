// After `try await store.apply(ops)`, the await-return funclet tests the
// callee's error in x20. On the error path it releases `ops`
// (`bl swift_release`) and branches to its own ResumeParent with x20
// untouched. x20 is callee-saved under AAPCS64, so that exit rethrows the
// callee's error.
public protocol Store2: Sendable { func apply(_ ops: [Int]) async throws }

public actor A2 {
    let store: any Store2
    var pending: [Int] = []
    var published = 0
    public init(store: any Store2) { self.store = store }
    public func persist() async throws {
        let ops = pending.map { $0 &* 2 }
        try await store.apply(ops)
        pending.removeAll()
        published &+= ops.count
    }
}
