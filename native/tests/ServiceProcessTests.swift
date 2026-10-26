import Foundation

@main struct ServiceProcessTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macndmg-runner-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        func script(_ name: String, _ body: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }
        let echo = try script("echo", "read value\nprintf '%s' \"$value\"\n")
        let data = try ServiceProcess.run(executable: echo, input: Data("{\"ok\":true}\n".utf8), timeout: 2)
        precondition(String(data: data, encoding: .utf8) == "{\"ok\":true}")
        let empty = try script("empty", "exit 1\n")
        do {
            _ = try ServiceProcess.run(executable: empty, input: Data(), timeout: 1)
            fatalError("Expected incomplete-response error")
        } catch ServiceProcess.Failure.invalidResponse { }
        let stalled = try script("stall", "sleep 2\n")
        let start = Date()
        do {
            _ = try ServiceProcess.run(executable: stalled, input: Data(), timeout: 0.15)
            fatalError("Expected timeout")
        } catch ServiceProcess.Failure.timedOut { }
        precondition(Date().timeIntervalSince(start) < 1, "Must not wait for descendant stdout to close")
        print("Passed service success, incomplete response and bounded timeout checks")
    }
}
