import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `Shell.run` read stdout to its end, then stderr. A tool that writes more to
/// stderr than its pipe holds waits for a reader, stdout stays open, and
/// swiftdc hangs. `/usr/bin/time -l` did this to a suite under memory pressure,
/// which shrinks a pipe's buffer to 16 KB, and llvm-objdump's warnings go there.
@Test func aToolThatFillsStderrFinishes() throws {
    let result = try Shell.run("/bin/sh", ["-c", "head -c 1000000 /dev/zero >&2; echo done"])
    #expect(result.status == 0)
    #expect(result.stdout == "done\n")
    #expect(result.stderr.utf8.count == 1_000_000)
}

@Test func aToolThatFillsBothPipesFinishes() throws {
    let result = try Shell.run("/bin/sh", ["-c", "head -c 1000000 /dev/zero; head -c 1000000 /dev/zero >&2"])
    #expect(result.stdout.utf8.count == 1_000_000)
    #expect(result.stderr.utf8.count == 1_000_000)
}
