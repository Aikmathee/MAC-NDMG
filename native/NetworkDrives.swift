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
    enum CodingKeys: String, CodingKey {
        case id, name, address, share, filesystem
        case serverName = "server_name"
        case mountPoint = "mount_point"
    }
    func hostKey(_ value: String) -> String {
        var key = (value.removingPercentEncoding ?? value).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for suffix in ["._smb._tcp.local", "._afpovertcp._tcp.local", ".local"] {
            if key.hasSuffix(suffix) { key = String(key.dropLast(suffix.count)); break }
        }
        return key
    }
    func matches(_ server: Server, share name: String) -> Bool {
        filesystem == "smbfs" && share == name && !Set([hostKey(server.address), hostKey(server.name)]).isDisjoint(with: [hostKey(address), hostKey(serverName)])
    }
}

struct SavedDrive: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var serverName: String
    var share: String
    enum CodingKeys: String, CodingKey {
        case id, name, address, share
        case serverName = "server_name"
    }
    func matches(_ volume: MountedVolume) -> Bool {
        volume.filesystem == "smbfs" && volume.share == share && volume.hostKey(volume.address) == volume.hostKey(address)
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
    enum CodingKeys: String, CodingKey {
        case ok, error, hosts, drives, volumes, remembered, groups
        case connectionState = "connection_state"
        case storageError = "storage_error"
    }
}

/// Resolves the actual system glass class at runtime so the same binary also runs on macOS 13–15.
/// Native material is the fallback on systems predating Liquid Glass.
struct GlassSurface: NSViewRepresentable {
    var radius: CGFloat = 24
    var sidebar = false
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init(frame: .zero)
            if glass.responds(to: NSSelectorFromString("setCornerRadius:")) {
                glass.setValue(radius, forKey: "cornerRadius")
            }
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = sidebar ? .sidebar : .contentBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.masksToBounds = true
        return effect
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
    }
}

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .background(GlassSurface(radius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.4), lineWidth: 0.7).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 14, y: 5)
    }
}

struct PillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(primary ? Color.white : Color.primary)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.20, green: 0.51, blue: 1), .blue], startPoint: .top, endPoint: .bottom))
                } else {
                    GlassSurface(radius: 20)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(primary ? 0.22 : 0.45), lineWidth: 0.8))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
        groupFromSaved(rememberedDrives.filter { drive in volumes.contains { drive.matches($0) } })
    }
    func ejectVolumes(_ volumes: [MountedVolume]) async {
        guard !working && !loading && !volumes.isEmpty else { return }
        working = true; stopConnecting = false; connectingLabel = "Ejecting drives"
        defer { working = false; ejectingVolumeID = nil; connectingLabel = nil; Task { await refreshMounted() } }
        var success = 0, failed = 0
        for (index, volume) in volumes.enumerated() {
            if stopConnecting { break }
            ejectingVolumeID = volume.id
            note("Ejecting \(index + 1) of \(volumes.count)…")
            do {
                let response = try await Service.request(["action": "eject_volume", "volume_id": volume.id])
                if let values = response.volumes { applyMounted(values) }
                applyLibrary(response)
                if response.ok { success += 1 }
                else { failed += 1; note("\(volume.name): \(response.error ?? "Could not eject drive")") }
            } catch { failed += 1; note("\(volume.name): \(error.localizedDescription)") }
        }
        note("Ejected \(success) of \(volumes.count) drives" + (stopConnecting ? " · stopped" : ""))
        if failed > 0 { error = "\(failed) drives could not be ejected. Close their open files and try again. See Activity for details." }
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
        guard rememberedAccountIDs.contains(server.id) else { return }
        do {
            let response = try await Service.request(["action": "mounted"])
            if let volumes = response.volumes { applyMounted(volumes) }
            try await persistAccount(credentials, server: server, remember: true)
        } catch { note("Connected, but saved account aliases could not be updated.") }
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
        username = credentials?.username ?? ""
        password = forcePrompt ? credentials?.password ?? "" : ""
        rememberAccount = rememberedAccountIDs.contains(server.id)
        authError = message
        authServer = server
        return await withCheckedContinuation { authContinuation = $0 }
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
        authSubmitting = true; authError = nil
        defer { authSubmitting = false }
        let credentials = ServerCredentials(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        do {
            let response = try await Service.request(["action": "shares", "address": server.address, "name": server.name,
                                                     "username": credentials.username, "password": credentials.password])
            guard response.ok else { authError = response.error ?? "Check your username and password."; return }
            let remember = rememberAccount
            do {
                try await persistAccount(credentials, server: server, remember: remember)
                if remember { rememberedAccountIDs.insert(server.id) } else { rememberedAccountIDs.remove(server.id) }
            } catch { note("Signed in, but the saved account could not be updated in Keychain.") }
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
                if let credentials = try? await Task.detached(operation: { try CredentialVault.load(drive.address) }).value {
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
            if let index = servers.firstIndex(where: { $0.address == server.address }) {
                if server.saved { servers[index].saved = true }
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
                merge(response.hosts ?? [])
                note("\(response.hosts?.count ?? 0) servers found")
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
        return !address.isEmpty && address.count <= 253 && address.rangeOfCharacter(from: CharacterSet(charactersIn: "/@?#\\ \n\r\t")) == nil
    }
    func add() {
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
    @AppStorage("appearance") private var appearance = "system"
    private var chosenColorScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    private var appearanceName: String {
        appearance == "dark" ? "Dark" : appearance == "light" ? "Light" : "System"
    }
    private var appearanceIcon: String {
        appearance == "dark" ? "moon.fill" : appearance == "light" ? "sun.max.fill" : "circle.lefthalf.filled"
    }
    private func applyAppearance() {
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua)
            : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    @StateObject private var store = DriveStore()
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 246)
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [Color.blue.opacity(0.055), .clear, Color.teal.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    if store.selectedServerIDs.count > 1 { multiServerPage } else if store.showingGroups { groupsPage } else if store.showingConnected { connectedPage } else if let server = store.selected { detail(server) } else { home }
                    statusBar
                }
            }
        }
        .frame(minWidth: 920, minHeight: 650)
        .tint(.blue)
        .preferredColorScheme(chosenColorScheme)
        .onAppear { applyAppearance() }
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
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
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
                            Text(server.address).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if server.saved { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }.padding(.vertical, 7).tag(server.id)
                }
            }
        }.listStyle(.sidebar).scrollContentBackground(.hidden)
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
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(store.selectedServerIDs.count) servers selected").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Connect their shared drives together, or eject their connected drives.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
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
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.selectedServers(store.selectedServerIDs)) { server in
                        HStack(spacing: 14) {
                            Image(systemName: server.symbol).font(.system(size: 25)).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(server.name).font(.system(size: 15, weight: .semibold))
                                Text(server.address).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(store.volumesForServers([server.id]).count) connected").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(20).modifier(GlassCard(radius: 18))
                            .contextMenu { serverContext(store.selectedServerIDs) }
                    }
                }
            }
            Text("⌘-click to add a server · Shift-click to select a range · Control-click for actions")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(30)
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

    func authenticationSheet(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 30, weight: .light)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 7) {
                Text("Connect to \(server.name)").font(.system(size: 22, weight: .bold, design: .rounded))
                Text(server.address).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            field("Username") { TextField("Username", text: $store.username).textContentType(.username) }
            field("Password") {
                SecureField("Password", text: $store.password).textContentType(.password)
                    .onSubmit { Task { await store.submitAuthentication() } }
            }
            Toggle("Remember this server", isOn: $store.rememberAccount).toggleStyle(.checkbox)
            Text("Your account is saved securely in this Mac’s Keychain.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let message = store.authError {
                Text(message).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { store.cancelAuthentication() }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                if store.authSubmitting { ProgressView().controlSize(.small) }
                Button(store.authSubmitting ? "Connecting…" : "Continue") { Task { await store.submitAuthentication() } }
                    .buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 420).disabled(store.authSubmitting)
            .interactiveDismissDisabled(store.authSubmitting)
    }
    var sidebar: some View {
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
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search servers", text: $store.search).textFieldStyle(.plain)
            }.font(.system(size: 12)).padding(10)
                .background(.quaternary.opacity(0.45), in: Capsule())
            serverSidebarList
            Button { store.showingAdd = true } label: {
                Label("Add server", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(PillStyle()).disabled(store.working || store.loading).keyboardShortcut("k", modifiers: .command)
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
        }.padding(.horizontal, 16).padding(.bottom, 18)
            .background(GlassSurface(radius: 0, sidebar: true))
    }

    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Overview").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await store.scan() } } label: {
                        Label(store.scanning ? "Searching…" : "Refresh", systemImage: "arrow.clockwise")
                    }.buttonStyle(PillStyle()).disabled(store.scanning).keyboardShortcut("r", modifiers: .command)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 23).fill(LinearGradient(colors: [.blue.opacity(0.14), .cyan.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 35, weight: .light)).foregroundStyle(.blue)
                    }.frame(width: 70, height: 70).modifier(GlassCard(radius: 23))
                    Text("Connect to your drives").font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-0.8)
                    Text("Choose a server to get started.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label("\(store.servers.count) servers", systemImage: "desktopcomputer")
                        if store.connectedCount > 0 {
                            Text("·")
                            Label("\(store.connectedCount) connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                if !store.mountedVolumes.isEmpty { connectedPreview }
                HStack {
                    Text("Servers").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    if store.scanning { ProgressView().controlSize(.small) }
                    Button { store.showingAdd = true } label: {
                        Label("Add server", systemImage: "plus")
                    }.buttonStyle(.borderless)
                }
                if store.visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: store.scanning ? "wifi" : "network").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text(store.scanning ? "Looking for servers…" : store.search.isEmpty ? "No servers found" : "No matching servers").font(.headline)
                        Text(store.scanning ? "This usually takes a few seconds." : "Connect to your network, or add a server address.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(30).modifier(GlassCard())
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(store.visible) { server in
                            Button { store.serverClicked(server) } label: { serverCard(server) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(server.name), \(server.address)")
                                .contextMenu { serverContext(store.selectedServerIDs.contains(server.id) ? store.selectedServerIDs : [server.id]) }
                        }
                    }
                }
            }.padding(34)
        }
    }

    var groupsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Groups & saved drives").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("⌘-click to combine groups or drives · Control-click for actions")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.editGroup() } label: { Label("New group", systemImage: "plus") }
                    .buttonStyle(PillStyle(primary: true)).disabled(store.working || store.rememberedDrives.isEmpty)
            }
            if let message = store.libraryError { Text(message).font(.system(size: 12)).foregroundStyle(.orange) }
            List(selection: $store.librarySelection) {
                Section("Groups") {
                    if store.groups.isEmpty {
                        Text("Create a group to connect a saved set of drives.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                    ForEach(store.groups) { group in
                        groupCard(group).tag("group:" + group.id).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                }
                Section("Saved drives") {
                    ForEach(store.rememberedDrives.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { drive in
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive").font(.system(size: 22)).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(drive.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(drive.serverName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if store.isConnected(drive) {
                                Label("Connected", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
                            } else {
                                Button("Connect") { Task { await store.connectSaved([drive], label: drive.name) } }
                                    .buttonStyle(PillStyle()).disabled(store.working)
                            }
                        }.padding(16).modifier(GlassCard(radius: 18)).tag("drive:" + drive.id)
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).disabled(store.working)
                .contextMenu(forSelectionType: String.self) { ids in libraryContext(ids) }
            if !store.librarySelection.isEmpty {
                HStack {
                    Text("\(store.savedForLibrary(store.librarySelection).count) selected").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save as group…") { store.groupFromSaved(store.savedForLibrary(store.librarySelection)) }.buttonStyle(PillStyle())
                    Button("Eject") { Task { await store.ejectVolumes(store.volumesForSaved(store.savedForLibrary(store.librarySelection))) } }
                        .buttonStyle(PillStyle()).disabled(store.working || store.volumesForSaved(store.savedForLibrary(store.librarySelection)).isEmpty)
                    Button("Connect") { Task { await store.connectSaved(store.savedForLibrary(store.librarySelection), label: "Selection") } }
                        .buttonStyle(PillStyle(primary: true)).disabled(store.working)
                }
            }
        }.padding(30)
    }
    func groupCard(_ group: DriveGroup) -> some View {
        let drives = store.drivesForGroup(group)
        let connected = drives.filter { store.isConnected($0) }.count
        return VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 23)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text("\(connected) of \(drives.count) connected").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Connect group") { Task { await store.connectSaved(store.drivesForGroup(group), label: group.name) } }
                    Button("Eject group") { Task { await store.ejectVolumes(store.volumesForSaved(store.drivesForGroup(group))) } }
                        .disabled(store.volumesForSaved(store.drivesForGroup(group)).isEmpty)
                    Divider()
                    Button("Edit group") { store.editGroup(group) }
                    Button("Delete group", role: .destructive) { store.pendingDeleteGroup = group }
                } label: { Image(systemName: "ellipsis").padding(8) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(store.working)
                    .accessibilityLabel("Options for \(group.name)")
            }
            Text(drives.prefix(4).map { "\($0.name) · \($0.serverName)" }.joined(separator: "\n") + (drives.count > 4 ? "\n+\(drives.count - 4) more" : ""))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            HStack {
                if connected > 0 {
                    Button("Eject group") { Task { await store.ejectVolumes(store.volumesForSaved(drives)) } }
                        .buttonStyle(PillStyle()).disabled(store.working)
                }
                Spacer()
                Button {
                    Task { await store.connectSaved(drives, label: group.name) }
                } label: {
                    Label(connected == drives.count ? "Connected" : "Connect group", systemImage: connected == drives.count ? "checkmark" : "link")
                }.buttonStyle(PillStyle(primary: connected != drives.count))
                    .disabled(drives.isEmpty || connected == drives.count || store.working || store.loading)
            }
        }.padding(22).modifier(GlassCard())
    }

    var groupEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(store.editingGroupID == nil ? "New group" : "Edit group")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "square.stack.3d.up").font(.system(size: 25)).foregroundStyle(.blue)
            }
            field("Group name") { TextField("Editing room", text: $store.newGroupName) }
            HStack {
                Text("Choose drives").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Select connected") {
                    store.newGroupDriveIDs = Set(store.rememberedDrives.filter { store.isConnected($0) }.map(\.id))
                }.buttonStyle(.borderless)
                Button("Clear") { store.newGroupDriveIDs = [] }.buttonStyle(.borderless)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.rememberedDrives) { drive in
                        Toggle(isOn: Binding(get: { store.newGroupDriveIDs.contains(drive.id) }, set: { selected in
                            if selected { store.newGroupDriveIDs.insert(drive.id) } else { store.newGroupDriveIDs.remove(drive.id) }
                        })) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(drive.name).font(.system(size: 13, weight: .medium))
                                    Text(drive.serverName).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.isConnected(drive) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12)) }
                            }
                        }.toggleStyle(.checkbox).padding(.vertical, 4)
                    }
                }.padding(4)
            }.frame(maxHeight: .infinity)
            if let message = store.groupEditorError { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { store.showingGroupEditor = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
                Text("\(store.newGroupDriveIDs.count) selected").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(store.savingGroup ? "Saving…" : "Save group") { Task { await store.saveGroup() } }
                    .buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(store.newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.newGroupName.count > 80 || store.newGroupDriveIDs.isEmpty || store.savingGroup)
            }
        }.padding(28).frame(width: 490, height: 560).disabled(store.savingGroup)
    }

    var connectedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Connected drives").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("⌘-click to select multiple · Shift-click for a range")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Eject all") { Task { await store.ejectVolumes(store.mountedVolumes) } }
                    .buttonStyle(PillStyle()).disabled(store.mountedVolumes.isEmpty || store.working)
                Button { Task { await store.refreshMounted() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(PillStyle()).disabled(store.refreshingMounted || store.working).help("Refresh")
            }
            HStack(spacing: 9) {
                Circle().fill(store.mountedError == nil ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(store.mountedError ?? "\(store.mountedVolumes.count) connected").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Select all") { store.selectedMountedIDs = Set(store.mountedVolumes.map(\.id)) }.buttonStyle(.borderless)
                Button("Deselect all") { store.selectedMountedIDs = [] }.buttonStyle(.borderless)
            }
            List(selection: $store.selectedMountedIDs) {
                ForEach(store.mountedVolumes) { volume in
                    mountedRow(volume).tag(volume.id)
                        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(store.selectedMountedIDs.contains(volume.id) ? Color.blue.opacity(0.75) : .clear, lineWidth: 1.5))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if store.mountedVolumes.isEmpty {
                    Text(store.refreshingMounted ? "Checking connected drives…" : "No network drives connected")
                        .foregroundStyle(.secondary).padding(30)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).disabled(store.working)
                .contextMenu(forSelectionType: String.self) { ids in mountedContext(ids) }
            if !store.selectedMountedIDs.isEmpty {
                HStack {
                    Text("\(store.selectedMountedIDs.count) selected").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save as group…") { store.groupFromMounted(store.selectedMountedIDs) }.buttonStyle(PillStyle())
                    Button("Eject selected") {
                        Task { await store.ejectVolumes(store.mountedVolumes.filter { store.selectedMountedIDs.contains($0.id) }) }
                    }.buttonStyle(PillStyle()).disabled(store.working)
                }
            }
        }.padding(30)
    }
    func mountedRow(_ volume: MountedVolume) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "externaldrive.fill").font(.system(size: 25)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(volume.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(volume.serverName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(volume.mountPoint).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Open") { Task { await store.openMounted(volume) } }
                .buttonStyle(PillStyle()).disabled(store.working)
            Button { Task { await store.ejectMounted(volume) } } label: {
                Label(store.ejectingVolumeID == volume.id ? "Ejecting…" : "Eject", systemImage: "eject")
            }.buttonStyle(PillStyle()).disabled(store.working || store.loading)
                .accessibilityLabel("Eject \(volume.name) from \(volume.serverName) at \(volume.mountPoint)")
        }.padding(16).modifier(GlassCard(radius: 19))
    }

    var connectedPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connected").font(.system(size: 17, weight: .semibold))
                Text("\(store.mountedVolumes.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("View all") { store.showConnected() }.buttonStyle(.borderless)
            }
            if let warning = store.mountedError {
                Text(warning).font(.system(size: 11)).foregroundStyle(.orange)
            }
            ForEach(Array(store.mountedVolumes.prefix(2))) { volume in mountedRow(volume) }
        }
    }

    func serverCard(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: server.symbol).font(.system(size: 23, weight: .regular)).foregroundStyle(.blue)
                Spacer()
                if server.saved { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.secondary) }
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(server.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(server.address).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).modifier(GlassCard(radius: 20))
    }

    func detail(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: server.symbol).font(.system(size: 26)).foregroundStyle(.blue)
                    .frame(width: 60, height: 60).modifier(GlassCard(radius: 18))
                VStack(alignment: .leading, spacing: 5) {
                    Text(server.name).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(2)
                    Text(server.address).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Save server") { Task { await store.save() } }
                    Button("Change account…") { Task { await store.browseServer(forcePrompt: true) } }
                    Button("Forget saved account") { Task { await store.forgetAccount(server) } }
                    Button("Use Finder") { Task { await store.finder() } }
                } label: { Image(systemName: "ellipsis").padding(10) }.menuStyle(.borderlessButton).fixedSize().disabled(store.working)
            }
            HStack(spacing: 12) {
                Button { Task { await store.load() } } label: {
                    Label(store.loadedServers.contains(server.id) ? "Refresh drives" : "Load drives…", systemImage: "externaldrive")
                }.buttonStyle(PillStyle(primary: true)).disabled(store.working)
                Button("Connect all") { Task { await store.connectServers([server.id]) } }.buttonStyle(PillStyle()).disabled(store.working)
                Button("Eject all") { Task { await store.ejectVolumes(store.volumesForServers([server.id])) } }
                    .buttonStyle(PillStyle()).disabled(store.working || store.volumesForServers([server.id]).isEmpty)
            }
            HStack {
                Text("Shared drives · \(server.drives.count)").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Select all") { store.selectedDrives = Set(server.drives.map(\.id)) }.buttonStyle(.borderless).disabled(store.working)
                Button("Deselect all") { store.selectedDrives = [] }.buttonStyle(.borderless).disabled(store.working)
            }
            List(selection: $store.selectedDrives) {
                ForEach(server.drives) { drive in
                    driveRow(drive).tag(drive.id).listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if server.drives.isEmpty {
                    Text("Choose Load drives to sign in and see shared drives.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 40)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).disabled(store.working)
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Connect selected") { store.selectedDrives = ids; Task { await store.batch("mount") } }.disabled(ids.isEmpty)
                    Button("Eject selected") { store.selectedDrives = ids; Task { await store.batch("eject") } }.disabled(ids.isEmpty)
                    Divider()
                    Button("Connect all") { Task { await store.connectServers([server.id]) } }
                    Button("Eject all") { Task { await store.ejectVolumes(store.volumesForServers([server.id])) } }
                }
            HStack {
                Text("\(store.selectedDrives.count) selected").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Eject selected") { Task { await store.batch("eject") } }
                    .buttonStyle(PillStyle()).disabled(!store.connectedSelection || store.working)
                Button("Connect selected") { Task { await store.batch("mount") } }
                    .buttonStyle(PillStyle(primary: true)).disabled(store.selectedDrives.isEmpty || store.working)
            }
        }.padding(30)
    }
    func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.plain).font(.system(size: 13))
                .padding(11).background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.primary.opacity(0.08), lineWidth: 0.8))
        }
    }

    func driveRow(_ drive: Drive) -> some View {
        HStack(spacing: 13) {
            Image(systemName: store.selectedDrives.contains(drive.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(store.selectedDrives.contains(drive.id) ? Color.blue : Color.secondary)
            Image(systemName: "externaldrive.fill").font(.system(size: 23)).foregroundStyle(drive.connected ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(drive.name).font(.system(size: 13, weight: .medium))
                HStack(spacing: 5) {
                    if drive.connected { Circle().fill(.green).frame(width: 5, height: 5) }
                    Text(drive.connected ? "Connected" : drive.status == "error" ? "Could not connect" : "Not connected")
                        .font(.system(size: 11)).foregroundStyle(drive.status == "error" ? .red : .secondary)
                }
            }
            Spacer()
            if drive.connected {
                Button("Open") { Task { await store.finder(drive) } }.buttonStyle(PillStyle())
            }
        }.padding(15).modifier(GlassCard(radius: 17))
    }

    var statusBar: some View {
        HStack(spacing: 7) {
            if store.scanning || store.working || store.loading { ProgressView().controlSize(.mini) }
            else { Circle().fill(Color.green.opacity(0.7)).frame(width: 5, height: 5) }
            Text(store.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if store.connectingLabel != nil {
                Button("Stop") { store.stopConnecting = true }.buttonStyle(.borderless).font(.system(size: 11))
            }
            Button { store.showingActivity = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Activity")
                .accessibilityLabel("Activity")
        }.padding(.horizontal, 30).padding(.vertical, 12)
    }

    var addSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "plus.circle.fill").font(.system(size: 32)).foregroundStyle(.blue)
            Text("Add a server").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Enter its IP address or hostname.").foregroundStyle(.secondary)
            field("Address") { TextField("192.168.1.100 or studio.local", text: $store.newAddress) }
            field("Name (optional)") { TextField("Studio NAS", text: $store.newName) }
            HStack {
                Button("Cancel") { store.showingAdd = false }.keyboardShortcut(.cancelAction).buttonStyle(PillStyle())
                Spacer()
                Button("Add server") { store.add() }.keyboardShortcut(.defaultAction).buttonStyle(PillStyle(primary: true))
                    .disabled(!store.validNewAddress)
            }
        }.padding(32).frame(width: 380)
    }

    var activitySheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Activity").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { store.showingActivity = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.history.isEmpty { Text("No recent activity.").foregroundStyle(.secondary) }
                    ForEach(Array(store.history.enumerated()), id: \.offset) { _, message in
                        Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.textSelection(.enabled)
            }
        }.padding(28).frame(width: 480, height: 340)
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
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
            }
    }
}
