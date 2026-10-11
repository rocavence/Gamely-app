import Foundation

enum Shell {
    /// Runs a command to completion off the main actor and returns its stdout,
    /// or nil if it couldn't be launched.
    @concurrent
    static func run(_ path: String, _ arguments: [String]) async -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return data
    }
}
