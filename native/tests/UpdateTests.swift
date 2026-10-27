import Foundation

@main struct UpdateTests {
    @MainActor static func main() async throws {
        precondition(ReleaseVersion("2.10.0")! > ReleaseVersion("2.9.9")!)
        precondition(ReleaseVersion("v2.3.7") == ReleaseVersion("2.3.7"))
        for invalid in ["2.4.0-beta", "main", "2.4", "2.4.0.1", "2.-1.0", "2.0.99999999999999999999999"] {
            precondition(ReleaseVersion(invalid) == nil)
        }
        let assets = ["Apple-Silicon", "Intel"].flatMap { a in ["dmg", "zip"].map { GitHubRelease.Asset(name: "Network-Drive-Manager-macOS-\(a).\($0)", state: "uploaded", size: 10) } }
        let release = GitHubRelease(tag_name: "v2.4.0", draft: false, prerelease: false, assets: assets)
        precondition(release.installableVersion == ReleaseVersion("2.4.0"))
        precondition(GitHubRelease(tag_name: "v2.4.0", draft: true, prerelease: false, assets: assets).installableVersion == nil)
        precondition(GitHubRelease(tag_name: "v2.4.0", draft: false, prerelease: true, assets: assets).installableVersion == nil)
        precondition(GitHubRelease(tag_name: "v2.4.0", draft: false, prerelease: false, assets: Array(assets.prefix(1))).installableVersion == nil)
        precondition(GitHubRelease(tag_name: "2.4.0", draft: false, prerelease: false, assets: assets).installableVersion == nil)
        precondition(AvailableUpdate(version: "2.4.0").releaseURL.absoluteString == "https://github.com/Aikmathee/MAC-NDMG/releases/tag/v2.4.0")

        let suite = "macndmg-update-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 100000)
        var calls = 0
        let store = UpdateStore(defaults: defaults, currentVersion: "2.3.7", fetch: { calls += 1; return release })
        precondition(store.intervalDays == 1)
        await store.check(now: start)
        precondition(calls == 1 && store.available?.version == "2.4.0" && store.showBanner)
        store.showBanner = false
        await store.check(now: start.addingTimeInterval(86399))
        precondition(calls == 1 && !store.showBanner)
        await store.check(now: start.addingTimeInterval(86400))
        precondition(calls == 2 && store.showBanner)
        // Restart retains cadence and cannot re-notify immediately.
        let restarted = UpdateStore(defaults: defaults, currentVersion: "2.3.7", fetch: { calls += 1; return release })
        await restarted.check(now: start.addingTimeInterval(86401))
        precondition(calls == 2 && !restarted.showBanner)
        restarted.intervalDays = 2
        await restarted.check(now: start.addingTimeInterval(86400 * 3 - 1))
        precondition(calls == 2)
        await restarted.check(now: start.addingTimeInterval(86400 * 3))
        precondition(calls == 3 && restarted.showBanner)
        restarted.intervalDays = 0
        await restarted.check(now: start.addingTimeInterval(86400 * 10))
        precondition(calls == 3 && !restarted.showBanner)
        await restarted.check(manual: true, now: start.addingTimeInterval(86400 * 10))
        precondition(calls == 4 && restarted.showBanner)
        defaults.removePersistentDomain(forName: suite)
        var failures = 0
        let offline = UpdateStore(defaults: defaults, currentVersion: "2.3.7", fetch: {
            failures += 1
            throw URLError(.notConnectedToInternet)
        })
        await offline.check(now: start)
        await offline.check(now: start.addingTimeInterval(100))
        precondition(failures == 1 && !offline.showBanner && !offline.checking)
        defaults.removePersistentDomain(forName: suite)
        let current = UpdateStore(defaults: defaults, currentVersion: "2.4.0", fetch: { release })
        await current.check(now: start)
        precondition(current.available == nil && !current.showBanner)
        defaults.removePersistentDomain(forName: suite)
        var preview = GitHubRelease(tag_name: "v2.3.9", draft: false, prerelease: false, assets: assets)
        preview.name = "MacNDMG Preview 1"
        let previewStore = UpdateStore(defaults: defaults, currentVersion: "2.3.8", fetch: { preview })
        await previewStore.check(now: start)
        precondition(previewStore.available?.version == "2.3.9")
        precondition(previewStore.available?.title == "MacNDMG Preview 1")
        print("Passed update version, complete-release, daily/48h cadence, restart, off/manual, offline and current-version checks")
    }
}
