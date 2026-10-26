import Foundation

/// Bound service requests without a blocking read on a subprocess pipe.
/// Output is private and temporary; credentials are sent only through stdin.
enum ServiceProcess {
    enum Failure: LocalizedError {
        case timedOut, unavailable, invalidResponse
        var errorDescription: String? {
            switch self {
            case .timedOut: return "The connection request timed out. Check the network, then try again."
            case .unavailable: return "The connection service could not start. Reopen MacNDMG and try again."
            case .invalidResponse: return "The connection service returned an incomplete response. Try again."
            }
        }
    }

    static func run(executable: URL, input: Data, timeout: TimeInterval) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macndmg-request-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("response")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else { throw Failure.unavailable }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let process = Process()
        let pipe = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.standardInput = pipe
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? pipe.fileHandleForWriting.close() }
            try? pipe.fileHandleForWriting.write(contentsOf: input)
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            // Only terminate the service process created for this request.
            // Do not wait on descendants that may still hold an output handle.
            if process.isRunning { process.terminate() }
            throw Failure.timedOut
        }
        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else { throw Failure.invalidResponse }
        return data
    }
}
