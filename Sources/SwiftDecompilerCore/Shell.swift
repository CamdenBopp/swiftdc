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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [tool] + args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        // Read before waiting to avoid deadlock on large output.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
