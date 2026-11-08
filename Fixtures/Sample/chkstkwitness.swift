// A synthesized Decodable init for an enum with payloads (-O) keeps each
// keyed container in a dynamic stack buffer: `ldur x8, [meta, #-0x8];
// ldr x8, [x8, #0x40]; mov x9, x8; blr x16` (___chkstk_darwin) then `mov
// x9, sp; sub x8, x9, x8; mov sp, x8`. The probe writes only x9 and the
// flags, so x8 still holds the size and the buffer is a bounded allocation
// below the frame. Read as an ordinary call it forgot x8, the buffer
// became an unknown frame offset, and every later call forgot every frame
// slot, so a container's value-witness table spilled to the frame and
// reloaded for its destroy was lost.
public enum Message: Decodable {
    case ping(id: Int)
    case named(title: String, count: Int)
    case flag(on: Bool)
}
