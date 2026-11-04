import Foundation

/// Minimal subprocess runner for invoking toolchain binaries (llvm-objdump).
enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Run `xcrun <tool> <args...>` and capture output.
    static func xcrun(_ tool: String, _ args: [String]) throws -> Result {
        try run("/usr/bin/xcrun", [tool] + args)
    }

    /// Everything two pipes carry, read at once. Reading one to its end first
    /// stops for good when the process fills the other: it waits for a reader
    /// while the first pipe stays open. A `Thread`, not a dispatch queue: this
    /// blocks its caller, and callers on the cooperative pool would starve the
    /// queue that had to finish the read (12 of them hung a suite).
    static func drain(_ out: Pipe, _ err: Pipe) -> (out: Data, err: Data) {
        nonisolated(unsafe) var errData = Data()
        let done = DispatchSemaphore(value: 0)
        let errHandle = err.fileHandleForReading
        Thread.detachNewThread {
            errData = errHandle.readDataToEndOfFile()
            done.signal()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        return (outData, errData)
    }

    /// Run an executable at an absolute path with `args` and capture output.
    static func run(_ executable: String, _ args: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        // Read before waiting to avoid deadlock on large output.
        let (outData, errData) = drain(outPipe, errPipe)
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
