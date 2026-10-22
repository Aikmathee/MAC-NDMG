import SwiftUI
import AppKit

struct Drive: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var status: String
    var error: String
    var connected: Bool { status == "connected" }
}

struct Server: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var saved: Bool
    var drives: [Drive]
    var ip: String? = nil
    var discovered: Bool? = nil
    var source: String? = nil
    var addressLabel: String { address.lowercased().contains("._smb._tcp.local") ? "SMB server" : address }
    var symbol: String { name.localizedCaseInsensitiveContains("nas") || name.localizedCaseInsensitiveContains("storage") ? "externaldrive.connected.to.line.below" : "desktopcomputer" }
}

struct MountedVolume: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var serverName: String
    var share: String
    var mountPoint: String
    var filesystem: String
    var url: String?
    enum CodingKeys: String, CodingKey {
        case id, name, address, share, filesystem, url
        case serverName = "server_name"
        case mountPoint = "mount_point"
    }
    static func hostKey(_ value: String) -> String {
        var key = (value.removingPercentEncoding ?? value).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for suffix in ["._smb._tcp.local", "._afpovertcp._tcp.local", ".local"] {
            if key.hasSuffix(suffix) { key = String(key.dropLast(suffix.count)); break }
        }
        return key
    }
    func matches(_ server: Server, share name: String) -> Bool {
        filesystem == "smbfs" && share == name && !Set([Self.hostKey(server.address), Self.hostKey(server.name), Self.hostKey(server.ip ?? "")]).isDisjoint(with: [Self.hostKey(address), Self.hostKey(serverName)])
    }
}

struct SavedDrive: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var serverName: String
    var share: String
    var url: String?
    var connectionProtocol: String?
    var mountedIDs: [String]?
    var usesIPAddress: Bool {
        address.contains(":") || (address.split(separator: ".").count == 4 && address.split(separator: ".").allSatisfy { UInt8($0) != nil })
    }
    enum CodingKeys: String, CodingKey {
        case id, name, address, share, url
        case connectionProtocol = "protocol"
        case mountedIDs = "mounted_ids"
        case serverName = "server_name"
    }
    func matches(_ volume: MountedVolume) -> Bool {
        if mountedIDs?.contains(volume.id) == true { return true }
        if connectionProtocol == "webdav" { return volume.filesystem == "webdav" && volume.url == url }
        return volume.filesystem == "smbfs" && volume.share == share && MountedVolume.hostKey(volume.address) == MountedVolume.hostKey(address)
    }
}

struct DriveGroup: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var driveIDs: [String]
    enum CodingKeys: String, CodingKey {
        case id, name
        case driveIDs = "drive_ids"
    }
}

struct EjectProcess: Decodable, Identifiable {
    var pid: Int32
    var name: String
    var id: Int32 { pid }
    var displayName: String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? name
    }
}
struct EjectFailure: Decodable, Identifiable {
    var id: String
    var name: String
    var message: String
    var processes: [EjectProcess]
    var limited: Bool
    var summary: String {
        let text = message.lowercased()
        if text.contains("busy") || text.contains("in use") || text.contains("dissent") { return "Drive is in use." }
        if text.contains("timed out") || text.contains("did not finish") { return "Eject timed out." }
        if text.contains("permission") || text.contains("not permitted") { return "macOS denied the eject request." }
        if text.contains("not responding") || text.contains("connection") { return "Check the server connection." }
        return "macOS could not eject this drive."
    }
}
struct EjectProblem: Identifiable {
    let id = UUID()
    var failures: [EjectFailure]
}

struct Response: Decodable {
    var ok: Bool
    var error: String?
    var hosts: [Server]?
    var drives: [Drive]?
    var volumes: [MountedVolume]?
    var remembered: [SavedDrive]?
    var groups: [DriveGroup]?
    var connectionState: String?
    var storageError: String?
    var ejectFailure: EjectFailure?
    enum CodingKeys: String, CodingKey {
        case ok, error, hosts, drives, volumes, remembered, groups
        case connectionState = "connection_state"
        case storageError = "storage_error"
        case ejectFailure = "eject_failure"
    }
}

struct Service {
    static func request(_ payload: [String: Any]) async throws -> Response {
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let root = Bundle.main.resourceURL else { throw ServiceError.missing }
                    let executable = root.appendingPathComponent("service/ndmg-service")
                    let process = Process()
                    process.executableURL = executable
                    let input = Pipe(), output = Pipe()
                    process.standardInput = input
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    input.fileHandleForWriting.write(encoded + Data([10]))
                    try input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let result = try JSONDecoder().decode(Response.self, from: data)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    enum ServiceError: LocalizedError {
        case missing
        var errorDescription: String? { "The app’s connection service is missing. Reinstall the app." }
    }
}

struct AuthenticatedServer {
    var credentials: ServerCredentials
    var drives: [Drive]
}

@MainActor final class DriveStore: ObservableObject {
    @Published var finderSignInPending = false
    @Published var showingEjectConfirmation = false
    @Published var pendingEjectVolumes: [MountedVolume]?
    @Published var showingHelp = false
    @Published var ejectProblem: EjectProblem?
    var pendingEjectIDs = Set<String>()
    @Published var servers: [Server] = []
    @Published var mountedVolumes: [MountedVolume] = []
    @Published var showingConnected = false
    @Published var showingGroups = false
    @Published var rememberedDrives: [SavedDrive] = []
    @Published var groups: [DriveGroup] = []
    @Published var showingGroupEditor = false
    @Published var editingGroupID: String?
    @Published var newGroupName = ""
    @Published var newGroupDriveIDs = Set<String>()
    @Published var groupEditorError: String?
    @Published var libraryError: String?
    @Published var savingGroup = false
    @Published var pendingDeleteGroup: DriveGroup?
    @Published var connectingLabel: String?
    @Published var stopConnecting = false
    @Published var refreshingMounted = false
    @Published var mountedError: String?
    @Published var ejectingVolumeID: String?
    @Published var selectedID: String?
    @Published var selectedServerIDs = Set<String>()
    @Published var selectedMountedIDs = Set<String>()
    @Published var librarySelection = Set<String>()
    @Published var authServer: Server?
    @Published var authSubmitting = false
    @Published var authError: String?
    @Published var rememberAccount = false
    @Published var rememberedAccountIDs = Set<String>()
    private var sessionCredentials: [String: ServerCredentials] = [:]
    private var authContinuation: CheckedContinuation<AuthenticatedServer?, Never>?
    private var completedAuthentication: AuthenticatedServer?
    @Published var search = ""
    @Published var username = ""
    @Published var password = ""
    @Published var selectedDrives = Set<String>()
    @Published var scanning = false
    @Published var loading = false
    @Published var working = false
    @Published var status = "Ready"
    @Published var error: String?
    @Published var history: [String] = []
    @Published var showingAdd = false
    @Published var showingActivity = false
    @Published var newAddress = ""
    @Published var newName = ""
    @Published var hasScanned = false
    @Published var loadedServers = Set<String>()
    private var started = false

    var selected: Server? { servers.first { $0.id == selectedID } }
    var visible: [Server] {
        servers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) }
            .sorted { $0.saved != $1.saved ? $0.saved : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var connectedCount: Int { mountedVolumes.count }
    var connectedSelection: Bool { selected?.drives.contains { selectedDrives.contains($0.id) && $0.connected } ?? false }

    func selectServers(_ ids: Set<String>) {
        guard !working && !loading else { return }
        selectedServerIDs = ids
        selectedID = ids.count == 1 ? ids.first : nil
        showingConnected = false; showingGroups = false
        username = ""; password = ""; selectedDrives = []; error = nil
    }
    func serverClicked(_ server: Server) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            var next = selectedServerIDs
            if next.contains(server.id) { next.remove(server.id) } else { next.insert(server.id) }
            selectServers(next)
        } else if flags.contains(.shift), let anchor = selectedServerIDs.first,
                  let a = visible.firstIndex(where: { $0.id == anchor }), let b = visible.firstIndex(where: { $0.id == server.id }) {
            selectServers(Set(visible[min(a,b)...max(a,b)].map(\.id)))
        } else { choose(server) }
    }
    func selectedServers(_ ids: Set<String>) -> [Server] { visible.filter { ids.contains($0.id) } }
    func volumesForServers(_ ids: Set<String>) -> [MountedVolume] {
        let targets = servers.filter { ids.contains($0.id) }
        return mountedVolumes.filter { volume in targets.contains { volume.matches($0, share: volume.share) } }
    }
    func savedForServers(_ ids: Set<String>) -> [SavedDrive] {
        let targets = servers.filter { ids.contains($0.id) }
        return rememberedDrives.filter { drive in targets.contains { server in
            drive.address.lowercased() == server.address.lowercased() ||
            drive.serverName.lowercased() == server.name.lowercased()
        } }
    }
    func savedForLibrary(_ ids: Set<String>) -> [SavedDrive] {
        var driveIDs = Set(ids.filter { $0.hasPrefix("drive:") }.map { String($0.dropFirst(6)) })
        for group in groups where ids.contains("group:" + group.id) { driveIDs.formUnion(group.driveIDs) }
        return rememberedDrives.filter { driveIDs.contains($0.id) }
    }
    func volumesForSaved(_ drives: [SavedDrive]) -> [MountedVolume] {
        mountedVolumes.filter { volume in drives.contains { $0.matches(volume) } }
    }
    func groupFromSaved(_ drives: [SavedDrive]) {
        editGroup()
        newGroupDriveIDs = Set(drives.map(\.id))
    }
    func groupFromMounted(_ ids: Set<String>) {
        let volumes = mountedVolumes.filter { ids.contains($0.id) }
        let preferred = Set(volumes.compactMap { volume -> String? in
            let matches = rememberedDrives.filter { $0.matches(volume) }
            return (matches.first { !$0.usesIPAddress } ?? matches.first)?.id
        })
        groupFromSaved(rememberedDrives.filter { preferred.contains($0.id) })
    }
    func ejectVolumes(_ volumes: [MountedVolume], confirmed: Bool = false) async {
        guard !working && !loading && !volumes.isEmpty else { return }
        if volumes.count > 1 && !confirmed {
            pendingEjectVolumes = volumes; showingEjectConfirmation = true; return
        }
        working = true; stopConnecting = false; connectingLabel = "Ejecting drives"
        defer { working = false; ejectingVolumeID = nil; connectingLabel = nil; Task { await refreshMounted() } }
        var success = 0, failed = 0
        var failures: [EjectFailure] = []
        for (index, volume) in volumes.enumerated() {
            if stopConnecting { break }
            ejectingVolumeID = volume.id
            note("Ejecting \(index + 1) of \(volumes.count)…")
            do {
                let response = try await Service.request(["action": "eject_volume", "volume_id": volume.id])
                if let values = response.volumes { applyMounted(values) }
                applyLibrary(response)
                if response.ok { success += 1 }
                else {
                    failed += 1
                    let message = response.error ?? "macOS could not eject this drive."
                    failures.append(response.ejectFailure ?? EjectFailure(id: volume.id, name: volume.name, message: message, processes: [], limited: true))
                    note("\(volume.name): \(message)")
                }
            } catch {
                failed += 1
                failures.append(EjectFailure(id: volume.id, name: volume.name, message: error.localizedDescription, processes: [], limited: true))
                note("\(volume.name): \(error.localizedDescription)")
            }
        }
        note("Ejected \(success) of \(volumes.count) drives" + (stopConnecting ? " · stopped" : ""))
        if failed > 0 { ejectProblem = EjectProblem(failures: failures) }
    }
    func ejectProblemDismissed() {
        let ids = pendingEjectIDs
        pendingEjectIDs = []
        guard !ids.isEmpty else { return }
        Task {
            await refreshMounted()
            await ejectVolumes(mountedVolumes.filter { ids.contains($0.id) }, confirmed: true)
        }
    }
    func credentialAddresses(_ server: Server) -> [String] {
        Array(Set([server.address] + mountedVolumes.filter { $0.matches(server, share: $0.share) }.map(\.address)))
    }
    func persistAccount(_ credentials: ServerCredentials, server: Server, remember: Bool) async throws {
        let current = credentialAddresses(server)
        try await Task.detached {
            let old = try CredentialVault.load(server.address)
            let addresses = Array(Set(current + (old?.aliases ?? [])))
            var stored = credentials
            stored.aliases = addresses
            for address in addresses {
                if remember { try CredentialVault.save(stored, address: address) }
                else { try CredentialVault.remove(address) }
            }
        }.value
    }
    func syncAccountAliases(_ server: Server, credentials: ServerCredentials) async {
        guard rememberedAccountIDs.contains(server.id), !credentials.username.isEmpty else { return }
        do {
            let response = try await Service.request(["action": "mounted"])
            if let volumes = response.volumes { applyMounted(volumes) }
            try await persistAccount(credentials, server: server, remember: true)
        } catch { note("Connected. Couldn’t update the saved account.") }
    }
    func forgetAccount(_ server: Server) async {
        do {
            try await persistAccount(ServerCredentials(username: "", password: ""), server: server, remember: false)
            sessionCredentials.removeValue(forKey: server.id)
            rememberedAccountIDs.remove(server.id)
            note("Saved account removed")
        } catch { report(error.localizedDescription) }
    }
    func authenticate(_ server: Server, forcePrompt: Bool = false) async -> AuthenticatedServer? {
        var credentials = sessionCredentials[server.id]
        var message: String?
        if credentials == nil {
            do {
                credentials = try await Task.detached { try CredentialVault.load(server.address) }.value
                if credentials != nil { rememberedAccountIDs.insert(server.id) }
            } catch { message = "Saved account is unavailable. Sign in again." }
        }
        if !forcePrompt, let credentials {
            do {
                let response = try await Service.request(["action": "shares", "address": server.address, "name": server.name,
                                                         "username": credentials.username, "password": credentials.password])
                if response.ok {
                    sessionCredentials[server.id] = credentials
                    return AuthenticatedServer(credentials: credentials, drives: response.drives ?? [])
                }
                message = response.error ?? "Sign in again to this server."
            } catch { message = "Could not reach this server. Check the network and try again." }
        }
        if !forcePrompt && credentials == nil {
            // Let macOS reuse an existing Finder SMB session without asking for a password.
            if let response = try? await Service.request(["action": "shares", "address": server.address, "name": server.name]), response.ok {
                let system = ServerCredentials(username: "", password: "")
                sessionCredentials[server.id] = system
                return AuthenticatedServer(credentials: system, drives: response.drives ?? [])
            }
        }
        username = credentials?.username ?? ""
        password = forcePrompt ? credentials?.password ?? "" : ""
        rememberAccount = rememberedAccountIDs.contains(server.id)
        authError = message
        finderSignInPending = false
        authServer = server
        return await withCheckedContinuation { authContinuation = $0 }
    }
    func useFinderSignIn() async {
        guard let server = authServer else { return }
        username = ""; password = ""; rememberAccount = false
        do {
            let response = try await Service.request(["action": "finder", "address": server.address])
            finderSignInPending = response.ok
            authError = response.ok ? "Connect in Finder, then click Sign in." : "Finder could not open this server."
        } catch { authError = "Finder could not open this server." }
    }
    func cancelAuthentication() {
        completedAuthentication = nil
        authServer = nil
    }
    func authenticationDismissed() {
        let continuation = authContinuation
        let result = completedAuthentication
        authContinuation = nil; completedAuthentication = nil
        password = ""; authError = nil
        continuation?.resume(returning: result)
    }
    func submitAuthentication() async {
        guard let server = authServer, !authSubmitting else { return }
        authSubmitting = true; authError = nil; finderSignInPending = false
        defer { authSubmitting = false }
        let credentials = ServerCredentials(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        do {
            let response = try await Service.request(["action": "shares", "address": server.address, "name": server.name,
                                                     "username": credentials.username, "password": credentials.password])
            guard response.ok else { authError = response.error ?? "Check your username and password."; return }
            let remember = rememberAccount && !credentials.username.isEmpty
            do {
                if !credentials.username.isEmpty {
                    try await persistAccount(credentials, server: server, remember: remember)
                }
                if remember { rememberedAccountIDs.insert(server.id) } else { rememberedAccountIDs.remove(server.id) }
            } catch { note("Signed in. Couldn’t save the account.") }
            sessionCredentials[server.id] = credentials
            completedAuthentication = AuthenticatedServer(credentials: credentials, drives: response.drives ?? [])
            authServer = nil; password = ""
        } catch { authError = "Could not reach this server. Check the network and try again." }
    }
    func browseServer(forcePrompt: Bool = false) async {
        guard let server = selected, !working && !loading else { return }
        working = true
        defer { working = false }
        guard let result = await authenticate(server, forcePrompt: forcePrompt) else { return }
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].drives = result.drives
            loadedServers.insert(server.id)
            selectedDrives = Set(result.drives.filter { !$0.connected }.map(\.id))
            note("\(result.drives.count) drives available")
        }
    }
    func connectServers(_ ids: Set<String>) async {
        let targets = servers.filter { ids.contains($0.id) }
        guard !working && !loading && !targets.isEmpty else { return }
        working = true; stopConnecting = false; connectingLabel = "Connecting servers"
        defer { working = false; connectingLabel = nil; Task { await refreshMounted() } }
        var succeeded = 0, failed = 0
        for server in targets {
            if stopConnecting { break }
            note("Connecting to \(server.name)…")
            guard let result = await authenticate(server) else { stopConnecting = true; break }
            if let index = servers.firstIndex(where: { $0.id == server.id }) {
                servers[index].drives = result.drives
                loadedServers.insert(server.id)
            }
            for drive in result.drives {
                if stopConnecting { break }
                if drive.connected { succeeded += 1; continue }
                do {
                    let response = try await Service.request(["action": "mount", "address": server.address, "name": server.name,
                        "share": drive.name, "username": result.credentials.username, "password": result.credentials.password])
                    if response.ok { succeeded += 1 }
                    else { failed += 1; note("\(server.name) · \(drive.name): \(response.error ?? "Could not connect")") }
                } catch { failed += 1; note("\(drive.name): \(error.localizedDescription)") }
            }
            await syncAccountAliases(server, credentials: result.credentials)
        }
        note("\(succeeded) connected · \(failed) failed" + (stopConnecting ? " · stopped" : ""))
        if failed > 0 { error = "Some drives could not be connected. See Activity for details." }
    }
    func start() async {
        guard !started else { return }
        started = true
        do {
            let response = try await Service.request(["action": "saved"])
            if response.ok { merge(response.hosts ?? []) }
            else { report(response.error ?? "Could not load saved servers.") }
        } catch { report(error.localizedDescription) }
        await loadConnections()
        await scan()
    }
    func applyLibrary(_ response: Response) {
        libraryError = response.storageError
        if let values = response.remembered { rememberedDrives = values }
        if let values = response.groups { groups = values }
    }
    func loadConnections() async {
        do {
            let response = try await Service.request(["action": "connections"])
            if response.ok { applyLibrary(response) }
            else { report(response.error ?? "Could not load saved connections.") }
        } catch { report(error.localizedDescription) }
    }
    func isConnected(_ drive: SavedDrive) -> Bool { mountedVolumes.contains { drive.matches($0) } }
    func drivesForGroup(_ group: DriveGroup) -> [SavedDrive] {
        group.driveIDs.compactMap { id in rememberedDrives.first { $0.id == id } }
    }
    func showGroups() {
        guard !working && !loading else { return }
        choose(nil)
        showingGroups = true
    }
    func editGroup(_ group: DriveGroup? = nil) {
        editingGroupID = group?.id
        newGroupName = group?.name ?? ""
        newGroupDriveIDs = Set(group?.driveIDs ?? [])
        groupEditorError = nil
        showingGroupEditor = true
    }
    func saveGroup() async {
        guard !savingGroup else { return }
        savingGroup = true; groupEditorError = nil
        defer { savingGroup = false }
        do {
            var payload: [String: Any] = ["action": "save_group", "name": newGroupName, "drive_ids": Array(newGroupDriveIDs).sorted()]
            if let id = editingGroupID { payload["group_id"] = id }
            let response = try await Service.request(payload)
            if response.ok {
                applyLibrary(response)
                showingGroupEditor = false
                showGroups()
                note("Group saved")
            } else { groupEditorError = response.error ?? "Could not save group." }
        } catch { groupEditorError = error.localizedDescription }
    }
    func deleteGroup(_ group: DriveGroup) async {
        guard !savingGroup else { return }
        savingGroup = true
        defer { savingGroup = false }
        do {
            let response = try await Service.request(["action": "delete_group", "group_id": group.id])
            if response.ok { applyLibrary(response); note("Group deleted") }
            else { report(response.error ?? "Could not delete group.") }
        } catch { report(error.localizedDescription) }
    }
    func connectSaved(_ drives: [SavedDrive], label: String) async {
        guard !working && !loading else { return }
        let pending = drives.filter { !isConnected($0) }
        guard !pending.isEmpty else { note("Already connected"); return }
        working = true
        connectingLabel = label
        stopConnecting = false
        defer {
            working = false
            connectingLabel = nil
            Task { await refreshMounted() }
        }
        var connected = 0, waiting = 0, failed = 0, processed = 0
        for drive in pending {
            if stopConnecting { break }
            note("\(label): \(processed + 1) of \(pending.count)…")
            do {
                var payload: [String: Any] = ["action": "reconnect", "drive_id": drive.id]
                if drive.connectionProtocol != "webdav", let credentials = try? await Task.detached(operation: { try CredentialVault.load(drive.address) }).value {
                    payload["username"] = credentials.username; payload["password"] = credentials.password
                }
                let response = try await Service.request(payload)
                if let volumes = response.volumes { applyMounted(volumes) }
                if response.ok && response.connectionState == "connected" { connected += 1 }
                else if response.ok && response.connectionState == "waiting" { waiting += 1 }
                else {
                    failed += 1
                    note("Could not connect to \(drive.name): \(response.error ?? "Unknown error")")
                }
            } catch {
                failed += 1
                note("Could not connect to \(drive.name): \(error.localizedDescription)")
            }
            processed += 1
        }
        let result = "\(connected) connected" + (waiting > 0 ? " · \(waiting) waiting in Finder" : "") + (failed > 0 ? " · \(failed) failed" : "")
        note((stopConnecting ? "Stopped · " : "") + result)
        if failed > 0 { error = "Some drives could not be opened. Check the network and see Activity for details." }
    }
    func monitorMounts() async {
        while !Task.isCancelled {
            await refreshMounted()
            do { try await Task.sleep(nanoseconds: 3_000_000_000) }
            catch { return }
        }
    }
    func refreshMounted() async {
        guard !refreshingMounted && !working && !savingGroup else { return }
        refreshingMounted = true
        defer { refreshingMounted = false }
        do {
            let response = try await Service.request(["action": "mounted"])
            guard response.ok else { mountedError = response.error ?? "Could not refresh connected drives."; return }
            guard !working && !savingGroup else { return }
            applyLibrary(response)
            merge(response.hosts ?? [])
            mountedError = nil
            applyMounted(response.volumes ?? [])
        } catch { mountedError = "Could not refresh connected drives. Showing the last known list." }
    }
    func applyMounted(_ volumes: [MountedVolume]) {
        mountedVolumes = volumes
        selectedMountedIDs.formIntersection(Set(volumes.map(\.id)))
        for index in servers.indices {
            for row in servers[index].drives.indices {
                let found = volumes.contains { $0.matches(servers[index], share: servers[index].drives[row].name) }
                if found { servers[index].drives[row].status = "connected" }
                else if servers[index].drives[row].status == "connected" { servers[index].drives[row].status = "disconnected" }
            }
        }
    }
    func showConnected() {
        guard !working && !loading else { return }
        choose(nil)
        showingConnected = true
    }
    func ejectMounted(_ volume: MountedVolume) async { await ejectVolumes([volume]) }
    func openMounted(_ volume: MountedVolume) async {
        do {
            let response = try await Service.request(["action": "reveal_volume", "volume_id": volume.id])
            if !response.ok { report(response.error ?? "Could not open drive.") }
            if let volumes = response.volumes { applyMounted(volumes) }
        } catch { report(error.localizedDescription) }
    }
    func note(_ message: String) {
        status = message
        history.append(message)
        if history.count > 100 { history.removeFirst(history.count - 100) }
    }
    func report(_ message: String) {
        error = message
        note(message)
    }
    func merge(_ incoming: [Server]) {
        for server in incoming {
            if let index = servers.firstIndex(where: { existing in
                let sameEndpoint = MountedVolume.hostKey(existing.address) == MountedVolume.hostKey(server.address)
                let sameServiceName = existing.name.caseInsensitiveCompare(server.name) == .orderedSame &&
                    ((server.source == "bonjour" && existing.address.contains("._smb._tcp.local")) ||
                     (existing.source == "bonjour" && server.address.contains("._smb._tcp.local")))
                return sameEndpoint || sameServiceName
            }) {
                if server.saved { servers[index].saved = true }
                if server.discovered == true {
                    if server.source != "connected" {
                        if server.source == "bonjour" && servers[index].address.contains("._smb._tcp.local") {
                            servers[index].address = server.address
                        }
                        servers[index].source = server.source
                        servers[index].ip = server.ip
                        if !servers[index].saved { servers[index].name = server.name }
                    }
                    servers[index].discovered = true
                }
                if servers[index].drives.isEmpty { servers[index].drives = server.drives }
            } else { servers.append(server) }
        }
    }
    func scan() async {
        guard !scanning else { return }
        scanning = true
        note("Looking for servers…")
        defer { scanning = false; hasScanned = true }
        do {
            let response = try await Service.request(["action": "scan"])
            if response.ok {
                let hosts = response.hosts ?? []
                let found = Set(hosts.map { MountedVolume.hostKey($0.address) })
                let names = Set(hosts.map { $0.name.lowercased() })
                servers.removeAll {
                    $0.discovered == true && !$0.saved && !found.contains(MountedVolume.hostKey($0.address)) &&
                    !($0.address.contains("._smb._tcp.local") && names.contains($0.name.lowercased()))
                }
                merge(hosts)
                selectedServerIDs.formIntersection(Set(servers.map(\.id)))
                if let id = selectedID, !servers.contains(where: { $0.id == id }) { selectedID = nil }
                note("\(hosts.count) servers found")
            } else { report(response.error ?? "Could not search the network.") }
        } catch { report(error.localizedDescription) }
    }
    func choose(_ server: Server?) {
        guard !working && !loading else { return }
        showingConnected = false
        showingGroups = false
        selectedID = server?.id
        selectedServerIDs = server.map { [$0.id] } ?? []
        password = ""
        username = ""
        selectedDrives = []
        error = nil
        status = "Ready"
    }
    var validNewAddress: Bool {
        let address = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.contains("://") { return URLComponents(string: address)?.host != nil }
        return !address.isEmpty && address.count <= 253 && address.rangeOfCharacter(from: CharacterSet(charactersIn: "/@?#\\ \n\r\t")) == nil
    }
    func add() async {
        if newAddress.contains("://") {
            do {
                let response = try await Service.request(["action": "save_endpoint", "url": newAddress.trimmingCharacters(in: .whitespacesAndNewlines), "name": newName])
                guard response.ok else { report(response.error ?? "Could not add drive."); return }
                applyLibrary(response)
                showingAdd = false
                newName = ""; newAddress = ""
                showGroups()
                note("Drive saved · select Connect when your VPN is ready")
            } catch { report(error.localizedDescription) }
            return
        }
        let address = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.count <= 253,
              address.rangeOfCharacter(from: CharacterSet(charactersIn: "/@?#\\ \n\r\t")) == nil else {
            report("Enter an IP address or hostname, such as studio.local.")
            return
        }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = Server(id: address, name: name.isEmpty ? address : name, address: address, saved: false, drives: [])
        merge([server])
        choose(servers.first { $0.address == address })
        showingAdd = false
        newName = ""; newAddress = ""
    }
    func load() async { await browseServer() }
    func save() async {
        guard let server = selected else { return }
        do {
            let response = try await Service.request(["action": "save", "address": server.address, "name": server.name, "shares": server.drives.map(\.name)])
            if response.ok { merge(response.hosts ?? []); note("Server saved") }
            else { report(response.error ?? "Could not save server.") }
        } catch { report(error.localizedDescription) }
    }
    func batch(_ action: String) async {
        guard let server = selected, !working && !loading else { return }
        let targets = server.drives.filter { selectedDrives.contains($0.id) }
        if action == "eject" {
            await ejectVolumes(mountedVolumes.filter { volume in targets.contains { volume.matches(server, share: $0.name) } })
            return
        }
        guard !targets.isEmpty else { return }
        working = true; connectingLabel = "Connecting drives"; stopConnecting = false
        defer { working = false; connectingLabel = nil; Task { await refreshMounted() } }
        guard let auth = await authenticate(server) else { return }
        var success = 0
        for drive in targets {
            if stopConnecting { break }
            note("Connecting \(drive.name)…")
            do {
                let response = try await Service.request(["action": "mount", "address": server.address, "name": server.name,
                    "share": drive.name, "username": auth.credentials.username, "password": auth.credentials.password])
                if response.ok { success += 1 }
                else { note("\(drive.name): \(response.error ?? "Could not connect")") }
            } catch { note("\(drive.name): \(error.localizedDescription)") }
        }
        await syncAccountAliases(server, credentials: auth.credentials)
        note("Connected \(success) of \(targets.count) drives")
    }
    func finder(_ drive: Drive? = nil) async {
        guard let server = selected else { return }
        do {
            var payload: [String: Any] = ["action": drive == nil ? "finder" : "reveal", "address": server.address, "name": server.name]
            if let drive { payload["share"] = drive.name }
            // Finder handles authentication itself, so no password is needed here.
            let response = try await Service.request(payload)
            if !response.ok { report("Could not open Finder.") }
        } catch { report(error.localizedDescription) }
    }
}

struct RootView: View {
    @AppStorage("appearance") var appearance = "system"
    var chosenColorScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    var appearanceName: String {
        appearance == "dark" ? "Dark" : appearance == "light" ? "Light" : "System"
    }
    var appearanceIcon: String {
        appearance == "dark" ? "moon.fill" : appearance == "light" ? "sun.max.fill" : "circle.lefthalf.filled"
    }
    func applyAppearance() {
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua)
            : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    @StateObject var store = DriveStore()
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var expandedGroupIDs = Set<String>()
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if store.selectedServerIDs.count > 1 { multiServerPage }
                else if store.showingGroups { groupsPage }
                else if store.showingConnected { connectedPage }
                else if let server = store.selected { detail(server) }
                else { home }
            }
            .modifier(NativeSafeAreaBar(edge: .bottom) { statusBar })
            .modifier(NativeScrollEdges())
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
            .navigationTitle(pageTitle)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar { appToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowFrameAnchor().frame(width: 0, height: 0))
        .frame(minWidth: 800, minHeight: 620)
        .tint(.accentColor)
        .preferredColorScheme(chosenColorScheme)
        .onAppear { applyAppearance() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { persistMainFrame($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { persistMainFrame($0) }
        .onChange(of: appearance) { _ in applyAppearance() }
        .task { await store.start() }
        .task { await store.monitorMounts() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshMounted() }
        }
        .sheet(item: $store.authServer, onDismiss: { store.authenticationDismissed() }) { server in authenticationSheet(server) }
        .sheet(isPresented: $store.showingGroupEditor) { groupEditor }
        .confirmationDialog("Delete group?", isPresented: Binding(get: { store.pendingDeleteGroup != nil }, set: { if !$0 { store.pendingDeleteGroup = nil } })) {
            if let group = store.pendingDeleteGroup {
                Button("Delete \(group.name)", role: .destructive) {
                    store.pendingDeleteGroup = nil
                    Task { await store.deleteGroup(group) }
                }
            }
            Button("Cancel", role: .cancel) { store.pendingDeleteGroup = nil }
        } message: { Text("This removes the saved group. Its drives stay connected.") }
        .sheet(isPresented: $store.showingAdd) { addSheet }
        .sheet(isPresented: $store.showingActivity) { activitySheet }
        .sheet(isPresented: $store.showingHelp) { appHelp }
        .confirmationDialog("Eject \(store.pendingEjectVolumes?.count ?? 0) drives?", isPresented: $store.showingEjectConfirmation) {
            Button("Eject") {
                let volumes = store.pendingEjectVolumes ?? []
                store.pendingEjectVolumes = nil
                Task { await store.ejectVolumes(volumes, confirmed: true) }
            }
            Button("Cancel", role: .cancel) { store.pendingEjectVolumes = nil }
        } message: { Text("Drives in use will stay connected.") }
        .sheet(item: $store.ejectProblem, onDismiss: { store.ejectProblemDismissed() }) { ejectProblemSheet($0) }
        .alert("Couldn’t complete action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    var serverSidebarList: some View {
        List(selection: Binding(get: { store.selectedServerIDs }, set: { store.selectServers($0) })) {
            Section("Servers") {
                ForEach(store.visible) { server in
                    HStack(spacing: 9) {
                        Image(systemName: server.symbol).font(.system(size: 18)).foregroundStyle(.blue).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(server.addressLabel).help(server.address.removingPercentEncoding ?? server.address).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if server.saved { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }.padding(.vertical, 7).tag(server.id)
                }
            }
        }.listStyle(.sidebar).scrollContentBackground(.hidden)
            .modifier(NativeScrollEdges())
            .disabled(store.working || store.loading)
            .contextMenu(forSelectionType: String.self) { ids in serverContext(ids) }
    }

    @ViewBuilder func serverContext(_ ids: Set<String>) -> some View {
        Button("Connect selected servers (\(ids.count))") { Task { await store.connectServers(ids) } }
            .disabled(ids.isEmpty || store.working)
        Button("Eject drives on selected servers (\(store.volumesForServers(ids).count))") {
            Task { await store.ejectVolumes(store.volumesForServers(ids)) }
        }.disabled(store.volumesForServers(ids).isEmpty || store.working)
        Button("Save selection as group…") { store.groupFromSaved(store.savedForServers(ids)) }
            .disabled(store.savedForServers(ids).isEmpty || store.working)
        Divider()
        Button("Select all servers") { store.selectServers(Set(store.visible.map(\.id))) }
        Button("Connect all servers…") { Task { await store.connectServers(Set(store.visible.map(\.id))) } }
            .disabled(store.working || store.visible.isEmpty)
        Button("Eject all connected drives (\(store.mountedVolumes.count))") {
            Task { await store.ejectVolumes(store.mountedVolumes) }
        }.disabled(store.mountedVolumes.isEmpty || store.working)
    }

    var multiServerPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.selectedServers(store.selectedServerIDs)) { server in
                    HStack(spacing: 14) {
                        Image(systemName: server.symbol).font(.system(size: 25)).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(server.name).font(.system(size: 15, weight: .semibold))
                            Text(server.addressLabel).help(server.address.removingPercentEncoding ?? server.address).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(store.volumesForServers([server.id]).count) connected").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(20).modifier(ContentCard(radius: 18))
                        .contextMenu { serverContext(store.selectedServerIDs) }
                }
            }
            }
            .modifier(NativeScrollEdges())
            .modifier(NativeSafeAreaBar(edge: .top) { multiServerHeader })
            .padding(30)
    }

    var multiServerHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(store.selectedServerIDs.count) servers selected").font(.system(size: 26, weight: .bold, design: .rounded))
                }
                Spacer()
            }
            HStack {
                Button { Task { await store.connectServers(store.selectedServerIDs) } } label: {
                    Label("Connect all", systemImage: "link")
                }.buttonStyle(PillStyle(primary: true)).disabled(store.working)
                Button("Eject all") { Task { await store.ejectVolumes(store.volumesForServers(store.selectedServerIDs)) } }
                    .buttonStyle(PillStyle()).disabled(store.working || store.volumesForServers(store.selectedServerIDs).isEmpty)
                Button("Save as group…") { store.groupFromSaved(store.savedForServers(store.selectedServerIDs)) }
                    .buttonStyle(PillStyle()).disabled(store.working || store.savedForServers(store.selectedServerIDs).isEmpty)
            }
        }.padding(.bottom, 18)
    }


    @ViewBuilder func mountedContext(_ ids: Set<String>) -> some View {
        Button("Eject selected (\(ids.count))") {
            Task { await store.ejectVolumes(store.mountedVolumes.filter { ids.contains($0.id) }) }
        }.disabled(ids.isEmpty || store.working)
        Button("Save selection as group…") { store.groupFromMounted(ids) }.disabled(ids.isEmpty || store.working)
        Divider()
        Button("Select all") { store.selectedMountedIDs = Set(store.mountedVolumes.map(\.id)) }
        Button("Deselect all") { store.selectedMountedIDs = [] }
        Divider()
        Button("Eject all (\(store.mountedVolumes.count))") { Task { await store.ejectVolumes(store.mountedVolumes) } }
            .disabled(store.mountedVolumes.isEmpty || store.working)
    }

    @ViewBuilder func libraryContext(_ ids: Set<String>) -> some View {
        Button("Connect selection") { Task { await store.connectSaved(store.savedForLibrary(ids), label: "Selected drives") } }
            .disabled(store.savedForLibrary(ids).isEmpty || store.working)
        Button("Eject selection") { Task { await store.ejectVolumes(store.volumesForSaved(store.savedForLibrary(ids))) } }
            .disabled(store.volumesForSaved(store.savedForLibrary(ids)).isEmpty || store.working)
        Button("Save selection as new group…") { store.groupFromSaved(store.savedForLibrary(ids)) }
            .disabled(store.savedForLibrary(ids).isEmpty || store.working)
        Divider()
        Button("Select all saved drives") { store.librarySelection = Set(store.rememberedDrives.map { "drive:" + $0.id }) }
        Button("Deselect all") { store.librarySelection = [] }
        Button("Connect all saved drives") { Task { await store.connectSaved(store.rememberedDrives, label: "All saved drives") } }
            .disabled(store.rememberedDrives.isEmpty || store.working)
        Button("Eject all connected drives") { Task { await store.ejectVolumes(store.mountedVolumes) } }
            .disabled(store.mountedVolumes.isEmpty || store.working)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            sidebarNavigation
            serverSidebarList
                .modifier(NativeSafeAreaBar(edge: .top, showsBackground: false) { sidebarSearch })
                .modifier(NativeSafeAreaBar(edge: .bottom, showsBackground: false) { sidebarFooter })
        }
    }

    var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(.blue)
                Text("Network Drives").font(.system(size: 15, weight: .semibold))
            }.padding(.top, 20)
            Button { store.choose(nil) } label: {
                Label("Overview", systemImage: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(store.selectedServerIDs.isEmpty && !store.showingConnected && !store.showingGroups ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(store.working || store.loading)
            Button { store.showConnected() } label: {
                HStack {
                    Label("Connected", systemImage: "externaldrive.badge.checkmark")
                    Spacer()
                    Text("\(store.mountedVolumes.count)").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
                }.font(.system(size: 13, weight: .medium)).padding(12)
                    .background(store.showingConnected ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(store.working || store.loading)
            Button { store.showGroups() } label: {
                HStack {
                    Label("Groups", systemImage: "square.stack.3d.up")
                    Spacer()
                    if !store.groups.isEmpty { Text("\(store.groups.count)").font(.system(size: 11)) }
                }.font(.system(size: 13, weight: .medium)).padding(12)
                    .background(store.showingGroups ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(store.working || store.loading)
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }

    var sidebarSearch: some View {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search servers", text: $store.search).textFieldStyle(.plain)
            }.font(.system(size: 12)).padding(10)
                .background(.quaternary.opacity(0.45), in: Capsule())
            .padding(.horizontal, 16).padding(.bottom, 12)
    }

    var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { store.showingAdd = true } label: {
                Label("Add server", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(PillStyle()).disabled(store.working || store.loading)
            Menu {
                Picker("Appearance", selection: $appearance) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }.pickerStyle(.inline)
            } label: {
                HStack {
                    Label("Appearance", systemImage: appearanceIcon)
                    Spacer()
                    Text(appearanceName).foregroundStyle(.secondary)
                }.font(.system(size: 11)).padding(.horizontal, 4)
            }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Appearance, \(appearanceName)")
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 18)
    }

    var statusBar: some View {
        HStack(spacing: 7) {
            if store.scanning || store.working || store.loading { ProgressView().controlSize(.mini) }
            else { Circle().fill(Color.green.opacity(0.7)).frame(width: 5, height: 5) }
            Text(store.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if store.connectingLabel != nil {
                Button("Stop") { store.stopConnecting = true }.buttonStyle(FramedButtonStyle()).font(.system(size: 11))
            }
            Button { store.showingActivity = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(FramedButtonStyle()).help("Activity")
                .accessibilityLabel("Activity")
        }.padding(.horizontal, 24).padding(.vertical, 8)
    }


}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.title = "Network Drives"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .windowBackgroundColor
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct NetworkDrivesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Network Drives") { RootView() }
            .defaultSize(width: 1060, height: 780)
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified)
            .commands {
                CommandGroup(replacing: .newItem) {}
            }
    }
}
