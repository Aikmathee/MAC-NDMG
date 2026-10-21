import SwiftUI

extension RootView {
    var pageTitle: String {
        if store.selectedServerIDs.count > 1 { return "Selected servers" }
        if store.showingConnected { return "Connected" }
        if store.showingGroups { return "Groups" }
        return store.selected?.name ?? "Overview"
    }
    @ToolbarContentBuilder var appToolbar: some ToolbarContent {
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
                }.buttonStyle(.borderless).disabled(store.rememberedDrives.isEmpty || store.working)
            }
            if store.groups.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your drives, together").font(.headline)
                        Text("Save a group to reconnect your workspace in one step.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20).modifier(ContentCard())
            } else {
                ForEach(Array(store.groups.prefix(2))) { group in groupCard(group) }
            }
        }
    }
}
