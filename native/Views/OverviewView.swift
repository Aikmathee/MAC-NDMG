import SwiftUI

extension RootView {
    var home: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28, pinnedViews: [.sectionHeaders]) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your workspace").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(store.mountedVolumes.isEmpty ? "Connect a drive to get started." : "\(store.mountedVolumes.count) drives connected · Ready to work")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !store.mountedVolumes.isEmpty { connectedPreview }
                overviewGroups
                Section {
                    if store.visible.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: store.scanning ? "wifi" : "network").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text(store.scanning ? "Looking for servers…" : store.search.isEmpty ? "No servers found" : "No matching servers").font(.headline)
                            Text(store.scanning ? "This usually takes a few seconds." : "Connect to your network, or add a server address.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(30).modifier(ContentCard())
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                            ForEach(store.visible) { server in
                                Button { store.serverClicked(server) } label: { serverCard(server) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(server.name), \(server.address)")
                                    .contextMenu { serverContext(store.selectedServerIDs.contains(server.id) ? store.selectedServerIDs : [server.id]) }
                            }
                        }
                    }
                } header: { overviewServersHeader }
            }.padding(34)
        }.modifier(ScrollBoundaryTreatment())
    }

    var overviewServersHeader: some View {
        HStack {
            Text("Servers").font(.system(size: 17, weight: .semibold))
            Spacer()
            if store.scanning { ProgressView().controlSize(.small) }
            Button { store.showingAdd = true } label: {
                Label("Add server", systemImage: "plus")
            }.buttonStyle(.borderless)
        }
        .padding(.vertical, 14)
        .background {
            Rectangle().fill(.regularMaterial)
                .padding(.horizontal, -34)
                .padding(.bottom, -16)
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.65),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
    }
}
