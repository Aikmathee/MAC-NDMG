import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let numbers: [Int]
    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0).map { $0 <= 999999 } == true }) else { return nil }
        numbers = parts.map { Int($0)! }
    }
    var text: String { numbers.map(String.init).joined(separator: ".") }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
    }
    var name: String? = nil
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var installableVersion: ReleaseVersion? {
        guard !draft, !prerelease, let version = ReleaseVersion(tag_name), tag_name == "v" + version.text else { return nil }
        // A notification must never lead to a release without installers.
        let required = ["Apple-Silicon", "Intel"].flatMap { architecture in
            ["dmg", "zip"].map { "Network-Drive-Manager-macOS-\(architecture).\($0)" }
        }
        guard required.allSatisfy({ name in assets.contains { $0.name == name && $0.state == "uploaded" && $0.size > 0 } }) else { return nil }
        return version
    }
}

struct AvailableUpdate: Equatable {
    let version: String
    var displayName: String? = nil
    var title: String { displayName ?? "MacNDMG \(version)" }
    var releaseURL: URL { URL(string: "https://github.com/Aikmathee/MAC-NDMG/releases/tag/v\(version)")! }
}

enum UpdatePolicy {
    static let intervalKey = "updates.intervalDays"
    static let attemptKey = "updates.lastAttempt"
    static let noticeKey = "updates.lastNotice"
    static func intervalDays(_ defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: intervalKey) != nil else { return 1 }
        let value = defaults.integer(forKey: intervalKey)
        return [0, 1, 2].contains(value) ? value : 1
    }
    static func due(last: Date?, now: Date, days: Int) -> Bool {
        guard days > 0 else { return false }
        guard let last else { return true }
        return now < last || now.timeIntervalSince(last) >= Double(days) * 86400
    }
}
