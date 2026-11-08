import Foundation
import Testing

@Test func auditMemoryGuardPreservesChildExitStatus() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (script, code) in [("exit 0", 0), ("exit 1", 1), ("exit 23", 23), ("kill -TERM $$", 143)] {
        let out = directory.appendingPathComponent(String(code))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["Tools/audit/guard.sh", out.path, "100", "--", "/bin/zsh", "-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == Int32(code))
        let log = try String(contentsOf: out.appendingPathComponent("mem.log"), encoding: .utf8)
        #expect(log.contains("exit \(code) after"))
    }
}
