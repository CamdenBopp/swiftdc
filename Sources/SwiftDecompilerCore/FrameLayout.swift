/// Immutable evidence discovered for one function's current frame. An address
/// calculation identifies a coordinate, not the extent of an object there:
/// two calculations can address different words of the same local.
struct FrameLayout: Sendable {
    let addressTakenOffsets: [Int64]
    let saveSlots: Set<Int64>
    let escapeEvidence: TraceLayoutEvidence

    init(addressTakenOffsets: [Int64] = [], saveSlots: Set<Int64> = []) {
        self.addressTakenOffsets = addressTakenOffsets
        self.saveSlots = saveSlots
        self.escapeEvidence = TraceLayoutEvidence(prologueSaveSlots: saveSlots)
    }
}
