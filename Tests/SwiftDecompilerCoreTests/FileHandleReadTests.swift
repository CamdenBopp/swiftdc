import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private func physicalFootprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
}

/// A read on a Swift Concurrency thread leaves nothing behind once its
/// bytes are dropped. `read(upToCount:)` autoreleases its NSData and such a
/// thread drains no pool until its task ends: 2,000 reads of 64 KB held
/// 128 MB.
@Test func aDrainedReadKeepsNothingAliveIfPresent() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftdc-drained-\(getpid())")
    try Data(repeating: 7, count: 65536).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let before = physicalFootprint()
    try #require(before > 0)
    var total = 0
    for _ in 0..<2000 {
        try handle.seek(toOffset: 0)
        total += try handle.readDrained(upToCount: 65536)?.count ?? 0
    }
    #expect(total == 2000 * 65536)
    let grown = physicalFootprint() - before
    #expect(grown < 32 << 20, "footprint grew \(grown >> 20) MB")
}

/// Every repeated file read goes through `readDrained`: a raw
/// `read(upToCount:)` in the sources brings the leak back.
@Test func noSourceReadsAFileHandleUndrainedIfPresent() throws {
    let root = URL(fileURLWithPath: "Sources")
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
    var offenders: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "FileHandleReads.swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        if text.contains(".read(upToCount:") { offenders.append(url.lastPathComponent) }
    }
    #expect(offenders.isEmpty, "\(offenders)")
}
