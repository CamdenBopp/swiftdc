import Foundation

extension FileHandle {
    /// `read(upToCount:)` without leaving its `NSData` in the calling
    /// thread's autorelease pool. Foundation returns the bytes autoreleased,
    /// and a Swift Concurrency thread drains no pool until its task ends, so
    /// every read stayed alive for the whole run: preflight's conformance
    /// reads held 148,225 objects (22 MB) through a GoodLinks `xrefs`, and a
    /// probe trace read in 64 KB chunks would have held the whole file.
    func readDrained(upToCount count: Int) throws -> Data? {
        try autoreleasepool { try read(upToCount: count) }
    }
}
