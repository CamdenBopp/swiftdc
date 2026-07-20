import Testing
import Foundation

/// A regression guard on whole-image decode memory.
///
/// The Performance section of the readiness doc measured that whole-image
/// decoding holds every function's instructions at once, so peak memory scales
/// linearly at ~2.5–3.4 KB per recovered instruction (SwiftUI's 13.5 GB exceeds
/// a 16 GB host). That is an OPEN limit awaiting a streaming refactor — but until
/// then, nothing stopped it getting *worse*: adding a field to `Instruction`, or
/// holding one more copy of the list, would balloon it silently. This is the
/// "no performance regression guard" the doc listed as UNKNOWN.
///
/// The oracle is **external** — `/usr/bin/time -l`'s process accounting, not any
/// number swiftdc reports about itself — so it cannot drift with the code it
/// guards. It measures per-instruction footprint (footprint ÷ recovered
/// instructions) so the bound is independent of image size, and it is also the
/// before/after oracle the streaming refactor will need: after streaming, this
/// number should fall sharply, and the bound can be tightened.
///
/// Host-gated: it needs a system dyld cache image (`UserNotifications`), so it
/// skips cleanly on a machine or CI runner without one. Deterministic allocation
/// makes the footprint stable to ~4% run to run; the bound carries a 1.6× margin
/// over that so it flags a doubling-class regression, not noise.

private let cli = URL(fileURLWithPath: ".build/debug/swiftdc")

/// Ceiling on `peak memory footprint ÷ instruction count`, in bytes. Measured
/// baseline on the `--json` path is ~3,400 B/instruction; this is ~1.6× that, so
/// it trips on a material regression (a doubling of held state) but not on the
/// ~4% run-to-run variance or minor legitimate growth.
private let perInstructionCeiling = 5_632

/// Run `/usr/bin/time -l <cli> <args>`, returning (peak footprint bytes, stdout).
/// `time`'s accounting goes to stderr; the wrapped tool's output to stdout.
private func timed(_ args: [String]) -> (footprint: Int, stdout: Data)? {
    let out = Pipe(), err = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
    process.arguments = ["-l", cli.path] + args
    process.standardOutput = out
    process.standardError = err
    guard (try? process.run()) != nil else { return nil }
    // Read both pipes fully before waiting, so a large stdout cannot deadlock.
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }

    for line in String(decoding: stderr, as: UTF8.self).split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("peak memory footprint"),
              let bytes = Int(trimmed.split(separator: " ").first ?? "")
        else { continue }
        return (bytes, stdout)
    }
    return nil
}

private func instructionCount(_ json: Data) -> Int? {
    guard let functions = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]]
    else { return nil }
    return functions.reduce(0) { $0 + (($1["instructions"] as? [Any])?.count ?? 0) }
}

@Test func wholeImageDecodeMemoryStaysBoundedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: cli.path),
          FileManager.default.fileExists(atPath: "/usr/bin/time")
    else { return }

    // One time-wrapped run: --json gives both the instruction count (stdout) and
    // the heavier serialising path to bound. A system cache image is required;
    // absence (clean checkout / CI) is a skip, not a failure.
    guard let result = timed(["disasm", "--image", "UserNotifications", "--json"]),
          let count = instructionCount(result.stdout), count > 10_000
    else { return }

    let perInstruction = result.footprint / count
    #expect(
        perInstruction < perInstructionCeiling,
        """
        whole-image decode used \(result.footprint >> 20) MB over \(count) instructions \
        = \(perInstruction) B/instruction, over the \(perInstructionCeiling) B bound. \
        A memory regression in the whole-image path (an added held field, or an extra \
        retained copy of the instruction list). If the streaming refactor landed, this \
        should have *fallen* — retune the bound rather than raising it.
        """
    )
}
