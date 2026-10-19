import Foundation

/// Minimal subprocess runner with a hard timeout. Used for `osascript` and `security`.
enum Shell {
    struct Result {
        let status: Int32
        let out: String
        let err: String
    }

    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 8) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Result(status: -1, out: "", err: error.localizedDescription) }

        let group = DispatchGroup()
        var outData = Data(), errData = Data()
        group.enter()
        DispatchQueue.global(qos: .utility).async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global(qos: .utility).async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
        p.waitUntilExit()
        group.wait()
        return Result(status: p.terminationStatus,
                      out: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                      err: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func osascript(_ script: String, timeout: TimeInterval = 5) -> Result {
        run("/usr/bin/osascript", ["-e", script], timeout: timeout)
    }
}
