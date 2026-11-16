// A class field of an imported C struct type (`timespec`), read and written
// through its C member: `stamp.tv_nsec` is the word at +8 of the field. The
// image's field record for `__C.timespec` names it (`tv_nsec` at +0x8), so
// the access reads as the member, not a byte range of the Swift field.
// True behaviour: nanos() returns stamp.tv_nsec; setNanos(n) stores n there.
import Darwin

public final class Clock {
    public var stamp = timespec(tv_sec: 0, tv_nsec: 0)
    public init() {}
    @inline(never) public func nanos() -> Int { stamp.tv_nsec }
    @inline(never) public func setNanos(_ n: Int) { stamp.tv_nsec = n }
}
