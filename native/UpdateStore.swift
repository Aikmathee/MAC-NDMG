import Foundation
import SwiftUI

@MainActor final class UpdateStore: ObservableObject {
    @Published var available: AvailableUpdate?
    @Published var showBanner = false
    @Published var checking = false
    @Published var status = ""
    @Published var intervalDays: Int {
        didSet {
            defaults.set(intervalDays, forKey: UpdatePolicy.intervalKey)
            if intervalDays == 0 { showBanner = false }
        }
    }
    private let defaults: UserDefaults
    private let installed: ReleaseVersion?
    private let fetch: () async throws -> GitHubRelease

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
         fetch: @escaping () async throws -> GitHubRelease = UpdateStore.fetchLatest) {
        self.defaults = defaults
        installed = ReleaseVersion(currentVersion)
        intervalDays = UpdatePolicy.intervalDays(defaults)
        self.fetch = fetch
    }

    static func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Aikmathee/MAC-NDMG/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacNDMG-UpdateCheck", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func check(manual: Bool = false, now: Date = Date()) async {
        guard !checking else { return }
        guard manual || UpdatePolicy.due(last: defaults.object(forKey: UpdatePolicy.attemptKey) as? Date,
                                        now: now, days: intervalDays) else { return }
        guard let installed else { status = "Could not read the installed version."; return }
        checking = true
        // Persist before networking: offline, rate-limited and failed checks cannot spam retries.
        defaults.set(now, forKey: UpdatePolicy.attemptKey)
        defer { checking = false }
        do {
            let release = try await fetch()
            guard let remote = release.installableVersion else {
                status = "No complete stable release is available yet."
                return
            }
            if remote > installed {
                available = AvailableUpdate(version: remote.text)
                status = "MacNDMG \(remote.text) is available."
                if manual || UpdatePolicy.due(last: defaults.object(forKey: UpdatePolicy.noticeKey) as? Date,
                                              now: now, days: intervalDays) {
                    defaults.set(now, forKey: UpdatePolicy.noticeKey)
                    showBanner = true
                }
            } else {
                available = nil
                showBanner = false
                status = "You’re up to date."
            }
        } catch {
            // Automatic failures stay quiet; the connection UI remains available offline.
            status = "Could not check for updates. Try again when you’re online."
        }
    }

    func monitor() async {
        while !Task.isCancelled {
            await check()
            do { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
            catch { return }
        }
    }
}
