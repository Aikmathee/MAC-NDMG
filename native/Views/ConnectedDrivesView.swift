import SwiftUI

extension RootView {
    var connectedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Connected drives").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("⌘-click to select multiple · Shift-click for a range")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
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
                        .modifier(CardSelection(selected: store.selectedMountedIDs.contains(volume.id), radius: 19))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if store.mountedVolumes.isEmpty {
                    Text(store.refreshingMounted ? "Checking connected drives…" : "No network drives connected")
                        .foregroundStyle(.secondary).padding(30)
                }
            }.listStyle(.inset(alternatesRowBackgrounds: false)).scrollContentBackground(.hidden)
                .modifier(ScrollBoundaryTreatment(depth: 20)).disabled(store.working)
                .contextMenu(forSelectionType: String.self) { ids in mountedContext(ids) }
            if !store.selectedMountedIDs.isEmpty {
                HStack {
                    Text("\(store.selectedMountedIDs.count) selected").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save as group…") { store.groupFromMounted(store.selectedMountedIDs) }.buttonStyle(PillStyle())
                    Button("Eject selected") {
                        Task { await store.ejectVolumes(store.mountedVolumes.filter { store.selectedMountedIDs.contains($0.id) }) }
                    }.buttonStyle(PillStyle()).disabled(store.working)
                }.modifier(SelectionActionBar())
            }
        }.padding(24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.selectedMountedIDs.isEmpty)
    }
    func mountedRow(_ volume: MountedVolume) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "externaldrive.fill").font(.system(size: 25)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(volume.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(volume.serverName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(volume.mountPoint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { Task { await store.openMounted(volume) } } label: {
                Text("Open").padding(.horizontal, 8).padding(.vertical, 7)
            }.buttonStyle(.borderless).disabled(store.working)
            Button { Task { await store.ejectMounted(volume) } } label: {
                Label(store.ejectingVolumeID == volume.id ? "Ejecting…" : "Eject", systemImage: "eject")
                    .padding(.horizontal, 8).padding(.vertical, 7)
            }.buttonStyle(.borderless).disabled(store.working || store.loading)
                .accessibilityLabel("Eject \(volume.name) from \(volume.serverName) at \(volume.mountPoint)")
        }.padding(.horizontal, 16).padding(.vertical, 12).modifier(ContentCard(radius: 19))
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

}
