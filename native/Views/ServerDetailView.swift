import SwiftUI

extension RootView {
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
        }.padding(20).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).modifier(ContentCard(radius: 20))
    }

    func detail(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: server.symbol).font(.system(size: 26)).foregroundStyle(.blue)
                    .frame(width: 60, height: 60).modifier(ContentCard(radius: 18))
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
            GlassControlGroup {
            HStack(spacing: 12) {
                Button { Task { await store.load() } } label: {
                    Label(store.loadedServers.contains(server.id) ? "Refresh drives" : "Load drives…", systemImage: "externaldrive")
                }.buttonStyle(PillStyle(primary: true)).disabled(store.working)
                Button("Connect all") { Task { await store.connectServers([server.id]) } }.buttonStyle(PillStyle()).disabled(store.working)
                Button("Eject all") { Task { await store.ejectVolumes(store.volumesForServers([server.id])) } }
                    .buttonStyle(PillStyle()).disabled(store.working || store.volumesForServers([server.id]).isEmpty)
            }
            }
            HStack {
                Text("Shared drives · \(server.drives.count)").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Select all") { store.selectedDrives = Set(server.drives.map(\.id)) }.buttonStyle(.borderless).disabled(store.working)
                Button("Deselect all") { store.selectedDrives = [] }.buttonStyle(.borderless).disabled(store.working)
            }
            List(selection: $store.selectedDrives) {
                ForEach(server.drives) { drive in
                    driveRow(drive).modifier(CardSelection(selected: store.selectedDrives.contains(drive.id), radius: 17))
                        .tag(drive.id).listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if server.drives.isEmpty {
                    Text("Choose Load drives to sign in and see shared drives.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 40)
                }
            }.listStyle(.inset(alternatesRowBackgrounds: false)).scrollContentBackground(.hidden)
                .modifier(ScrollBoundaryTreatment(depth: 20)).disabled(store.working)
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
            }.modifier(SelectionActionBar())
        }.padding(30)
    }
    func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder).font(.body).controlSize(.large)
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
        }.padding(15).modifier(ContentCard(radius: 17))
    }

}
