import SwiftUI
import AppKit

struct Drive: Codable, Identifiable, Equatable {
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

struct Response: Decodable {
    var ok: Bool
    var error: String?
    var hosts: [Server]?
    var drives: [Drive]?
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
    func updateNSView(_ view: NSView, context: Context) {}
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .background(GlassSurface(radius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.4), lineWidth: 0.7).allowsHitTesting(false))
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

@MainActor final class DriveStore: ObservableObject {
    @Published var servers: [Server] = []
    @Published var selectedID: String?
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
    var connectedCount: Int { servers.flatMap(\.drives).filter(\.connected).count }
    var connectedSelection: Bool { selected?.drives.contains { selectedDrives.contains($0.id) && $0.connected } ?? false }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let response = try await Service.request(["action": "saved"])
            if response.ok { merge(response.hosts ?? []) }
            else { report(response.error ?? "Could not load saved servers.") }
        } catch { report(error.localizedDescription) }
        await scan()
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
        selectedID = server?.id
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
    func load() async {
        guard let server = selected, !loading && !working else { return }
        loading = true; error = nil
        note("Loading drives…")
        defer { loading = false }
        do {
            let response = try await Service.request(["action": "shares", "address": server.address, "username": username, "password": password])
            guard response.ok else { report(response.error ?? "Check your sign-in details."); return }
            if let index = servers.firstIndex(where: { $0.id == server.id }) {
                servers[index].drives = response.drives ?? []
                loadedServers.insert(server.id)
                selectedDrives = Set((response.drives ?? []).filter { !$0.connected }.map(\.id))
                note("\(response.drives?.count ?? 0) drives available")
            }
        } catch { report(error.localizedDescription) }
    }
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
        let targets = server.drives.filter { selectedDrives.contains($0.id) && (action != "eject" || $0.connected) }
        guard !targets.isEmpty else { return }
        working = true; error = nil
        defer { working = false; password = "" }
        let user = username, secret = password
        var success = 0
        for (offset, drive) in targets.enumerated() {
            note("\(action == "eject" ? "Ejecting" : "Connecting") \(offset + 1) of \(targets.count)…")
            do {
                let response = try await Service.request(["action": action, "address": server.address, "share": drive.name, "username": user, "password": secret])
                if let updated = response.drives?.first, let index = servers.firstIndex(where: { $0.id == server.id }), let row = servers[index].drives.firstIndex(where: { $0.id == drive.id }) {
                    servers[index].drives[row] = updated
                }
                if response.ok { success += 1 }
                else { report(response.error?.isEmpty == false ? response.error! : "Could not \(action == "mount" ? "connect to" : "eject") \(drive.name).") }
            } catch { report(error.localizedDescription) }
        }
        note("\(action == "eject" ? "Ejected" : "Connected") \(success) of \(targets.count) drives")
    }
    func finder(_ drive: Drive? = nil) async {
        guard let server = selected else { return }
        do {
            var payload: [String: Any] = ["action": drive == nil ? "finder" : "reveal", "address": server.address]
            if let drive { payload["share"] = drive.name }
            // Finder handles authentication itself, so no password is needed here.
            let response = try await Service.request(payload)
            if !response.ok { report("Could not open Finder.") }
        } catch { report(error.localizedDescription) }
    }
}

struct RootView: View {
    @StateObject private var store = DriveStore()
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 246)
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [Color.blue.opacity(0.055), .clear, Color.teal.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    if let server = store.selected { detail(server) } else { home }
                    statusBar
                }
            }
        }
        .frame(minWidth: 920, minHeight: 650)
        .tint(.blue)
        .task { await store.start() }
        .sheet(isPresented: $store.showingAdd) { addSheet }
        .sheet(isPresented: $store.showingActivity) { activitySheet }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
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
                    .background(store.selectedID == nil ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(store.working || store.loading)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search servers", text: $store.search).textFieldStyle(.plain)
            }.font(.system(size: 12)).padding(10)
                .background(.quaternary.opacity(0.45), in: Capsule())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    Text("SERVERS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 6)
                    ForEach(store.visible) { server in
                        Button { store.choose(server) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: server.symbol).font(.system(size: 18)).foregroundStyle(store.selectedID == server.id ? .blue : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text(server.address).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if server.saved { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(store.selectedID == server.id ? Color.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(store.working || store.loading)
                    }
                    if store.visible.isEmpty {
                        Text(store.search.isEmpty ? "Servers appear here." : "No matching servers.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(10)
                    }
                }
            }
            Button { store.showingAdd = true } label: {
                Label("Add server", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(PillStyle()).disabled(store.working || store.loading).keyboardShortcut("k", modifiers: .command)
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
                            Button { store.choose(server) } label: { serverCard(server) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(server.name), \(server.address)")
                        }
                    }
                }
            }.padding(34)
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: server.symbol).font(.system(size: 26)).foregroundStyle(.blue)
                    .frame(width: 60, height: 60).modifier(GlassCard(radius: 18))
                VStack(alignment: .leading, spacing: 5) {
                    Text(server.name).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(2)
                    Text(server.address).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.save() } } label: {
                    Label(server.saved ? "Saved" : "Save", systemImage: server.saved ? "star.fill" : "star")
                }.buttonStyle(PillStyle()).disabled(store.working || store.loading)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sign in").font(.system(size: 15, weight: .semibold))
                        Text("Use your account on this server.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.shield").font(.system(size: 21, weight: .light)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    field("Username") { TextField("Username", text: $store.username) }
                    field("Password") { SecureField("Password", text: $store.password).onSubmit { Task { await store.load() } } }
                }
                HStack(spacing: 12) {
                    Button { Task { await store.load() } } label: {
                        HStack(spacing: 8) {
                            if store.loading { ProgressView().controlSize(.mini) }
                            Text(store.loading ? "Loading…" : "Load drives")
                            if !store.loading { Image(systemName: "arrow.right") }
                        }
                    }.buttonStyle(PillStyle(primary: true)).disabled(store.loading || store.working)
                    Button("Use Finder") { Task { await store.finder() } }
                        .buttonStyle(.borderless).disabled(store.working)
                    Spacer()
                }
            }.padding(22).modifier(GlassCard())
                .disabled(store.working)
            HStack {
                Text("Shared drives").font(.system(size: 16, weight: .semibold))
                Text("\(server.drives.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                Spacer()
                if !server.drives.isEmpty {
                    Button(store.selectedDrives.count == server.drives.count ? "Deselect all" : "Select all") {
                        store.selectedDrives = store.selectedDrives.count == server.drives.count ? [] : Set(server.drives.map(\.id))
                    }.buttonStyle(.borderless).font(.system(size: 12)).disabled(store.working)
                }
            }
            ScrollView {
                if server.drives.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.tertiary)
                        Text(store.loadedServers.contains(server.id) ? "No shared drives" : "Your drives will appear here")
                            .font(.system(size: 14, weight: .medium))
                        Text(store.loadedServers.contains(server.id) ? "This server has no available disk shares." : "Sign in above, then choose Load drives.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 42)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(server.drives) { drive in driveRow(drive) }
                    }
                }
            }.frame(maxHeight: .infinity)
            HStack {
                Text(store.selectedDrives.isEmpty ? "Select drives to connect" : "\(store.selectedDrives.count) selected")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if store.connectedSelection {
                    Button("Eject") { Task { await store.batch("eject") } }
                        .buttonStyle(PillStyle()).disabled(store.working)
                }
                Button { Task { await store.batch("mount") } } label: {
                    Label(store.working ? "Working…" : "Connect", systemImage: "link")
                }.buttonStyle(PillStyle(primary: true))
                    .disabled(store.selectedDrives.isEmpty || store.working || store.loading)
                    
            }.padding(14).modifier(GlassCard(radius: 24))
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
            Toggle(isOn: Binding(get: { store.selectedDrives.contains(drive.id) }, set: { value in
                if value { store.selectedDrives.insert(drive.id) } else { store.selectedDrives.remove(drive.id) }
            })) { EmptyView() }.labelsHidden().toggleStyle(.checkbox).disabled(store.working)
                .accessibilityLabel("Select \(drive.name)")
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
