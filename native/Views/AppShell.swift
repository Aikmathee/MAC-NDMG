import SwiftUI
import AppKit

extension RootView {
    func persistMainFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === NSApp.mainWindow, window.sheetParent == nil else { return }
        window.saveFrame(usingName: "NetworkDrives.main")
    }
    var pageTitle: String {
        if store.selectedServerIDs.count > 1 { return "Selected servers" }
        if store.showingConnected { return "Connected" }
        if store.showingGroups { return "Groups" }
        return store.selected?.name ?? "Overview"
    }
    @ToolbarContentBuilder var appToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { store.showingHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
                .help("Help")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if store.showingGroups {
                Button { store.editGroup() } label: { Label("New group", systemImage: "plus.rectangle.on.folder") }
                    .disabled(store.working || store.rememberedDrives.isEmpty)
                    .help("New group")
            }
            if store.showingConnected {
                Button { Task { await store.ejectVolumes(store.mountedVolumes) } } label: { Label("Eject all", systemImage: "eject") }
                    .disabled(store.working || store.mountedVolumes.isEmpty).help("Eject all connected drives")
            }
            Button {
                Task { if store.showingConnected || store.showingGroups { await store.refreshMounted() } else { await store.scan() } }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(store.scanning || store.refreshingMounted).help("Refresh").keyboardShortcut("r", modifiers: .command)
            Button { store.showingAdd = true } label: { Label("Add server", systemImage: "plus") }
                .disabled(store.working || store.loading).help("Add server").keyboardShortcut("k", modifiers: .command)
        }
    }
    var overviewGroups: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Groups").font(.headline)
                Spacer()
                Button(store.groups.isEmpty ? "New group" : "View all") {
                    if store.groups.isEmpty { store.editGroup() } else { store.showGroups() }
                }.buttonStyle(FramedButtonStyle()).disabled(store.rememberedDrives.isEmpty || store.working)
            }
            if store.groups.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No groups").font(.headline)
                    }
                    Spacer()
                }.padding(20).modifier(ContentCard())
            } else {
                ForEach(Array(store.groups.prefix(2))) { group in overviewGroupRow(group) }
            }
        }
    }
    func overviewGroupRow(_ group: DriveGroup) -> some View {
        let drives = store.drivesForGroup(group)
        let connected = drives.filter { store.isConnected($0) }.count
        return HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(group.name).font(.headline).lineLimit(1)
                Text("\(connected) of \(drives.count) connected").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(connected == drives.count ? "Connected" : "Connect group") {
                Task { await store.connectSaved(drives, label: group.name) }
            }.buttonStyle(PillStyle(primary: connected != drives.count))
                .disabled(store.working || drives.isEmpty || connected == drives.count)
        }.padding(18).modifier(ContentCard(radius: DesignTokens.rowRadius))
    }

}


/// Remember a normal, resizable window instead of inheriting a full-screen-sized frame.
struct WindowFrameAnchor: NSViewRepresentable {
    final class Anchor: NSView {
        static var configured = Set<ObjectIdentifier>()
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, Self.configured.insert(ObjectIdentifier(window)).inserted else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                let restored = window.setFrameUsingName("main.RootView-1-AppWindow-1")
                    || window.setFrameUsingName("NetworkDrives.main")
                if !restored {
                    window.setContentSize(NSSize(width: 1100, height: 780))
                    window.center()
                }
                window.setFrameAutosaveName("NetworkDrives.main")
                window.saveFrame(usingName: "NetworkDrives.main")
            }
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}
